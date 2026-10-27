import AVFoundation
import AudioToolbox
import Observation
import PianoCore

/// Plays piano notes with low latency.
///
/// Signal chain: sampler → EQ (tone / "lid") → reverb → output.
/// The sampler loads `Piano.sf2` from the app bundle. Until that file is added,
/// it plays the sampler's built-in placeholder tone so everything else can be tested.
@MainActor
@Observable
final class PianoEngine {
    private(set) var isReady = false
    private(set) var hasPianoSamples = false
    private(set) var lastError: String? = nil

    var sustainOn = false {
        didSet { sampler.sendController(Self.sustainController, withValue: sustainOn ? 127 : 0, onChannel: 0) }
    }

    /// 0 is dark and soft, 1 is fully bright.
    var brightness: Double = 1 {
        didSet { applyTone() }
    }

    /// 0 is dry, 1 is all reverb.
    var reverbMix: Double = 0.15 {
        didSet { reverb.wetDryMix = Float(min(max(reverbMix, 0), 1) * 100) }
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let sampler = AVAudioUnitSampler()
    @ObservationIgnored private let tone = AVAudioUnitEQ(numberOfBands: 1)
    @ObservationIgnored private let reverb = AVAudioUnitReverb()
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    private static let sustainController: UInt8 = 64
    /// Requested hardware buffer. 5 ms keeps touch-to-sound delay low.
    private static let preferredBufferDuration: TimeInterval = 0.005

    init() {
        buildGraph()
        loadPianoSound()
        applyTone()
        reverb.wetDryMix = Float(reverbMix * 100)
        observeSystemEvents()
    }

    // MARK: - Lifecycle

    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback keeps playing with the silent switch on.
            // .mixWithOthers lets the piano play over a video lesson in Split View.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(Self.preferredBufferDuration)
            try session.setActive(true)
            if !engine.isRunning {
                try engine.start()
            }
            isReady = true
            lastError = nil
        } catch {
            isReady = false
            lastError = error.localizedDescription
        }
    }

    func pause() {
        allNotesOff()
        engine.pause()
        isReady = false
    }

    // MARK: - Notes

    func noteOn(_ note: Note, velocity: UInt8) {
        sampler.startNote(note.midiByte, withVelocity: velocity, onChannel: 0)
    }

    func noteOff(_ note: Note) {
        sampler.stopNote(note.midiByte, onChannel: 0)
    }

    func allNotesOff() {
        for number in UInt8(0)...UInt8(127) {
            sampler.stopNote(number, onChannel: 0)
        }
    }

    // MARK: - Setup

    private func buildGraph() {
        engine.attach(sampler)
        engine.attach(tone)
        engine.attach(reverb)
        engine.connect(sampler, to: tone, format: nil)
        engine.connect(tone, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        reverb.loadFactoryPreset(.mediumHall)
    }

    private func loadPianoSound() {
        guard let url = Bundle.main.url(forResource: "Piano", withExtension: "sf2") else {
            hasPianoSamples = false
            return
        }
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            hasPianoSamples = true
        } catch {
            hasPianoSamples = false
            lastError = "Couldn't load Piano.sf2: \(error.localizedDescription)"
        }
    }

    private func applyTone() {
        let value = min(max(brightness, 0), 1)
        let band = tone.bands[0]
        band.filterType = .lowPass
        // 1.2 kHz when dark, up to 20 kHz when bright.
        band.frequency = Float(1_200 * pow(20_000.0 / 1_200.0, value))
        band.bypass = value >= 0.999
        tone.globalGain = Float(-6 * (1 - value))
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(rawType: rawType) }
        })

        // Headphones plugged in or removed, Bluetooth changes, and similar.
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterChange() }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterChange() }
        })
    }

    private func handleInterruption(rawType: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            allNotesOff()
            isReady = false
        case .ended:
            start()
        @unknown default:
            break
        }
    }

    private func restartAfterChange() {
        allNotesOff()
        start()
    }
}
