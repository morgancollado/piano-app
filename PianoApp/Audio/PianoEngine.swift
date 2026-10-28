import AVFoundation
import AudioToolbox
import Observation
import os
import PianoCore

private let log = Logger(subsystem: "com.morgancollado.piano", category: "audio")

/// Plays piano notes with low latency.
///
/// Signal chain: sampler → EQ (tone / "lid") → reverb → output.
///
/// Start-up order matters: configure and activate the audio session (off the main thread,
/// because activation can block), then start the engine, then load `Piano.sf2` into the
/// running sampler. Every step logs to the Xcode console under the "audio" category, and
/// failures are shown on screen through `statusMessage`.
@MainActor
@Observable
final class PianoEngine {
    enum State: Equatable {
        case idle
        case starting
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var hasPianoSamples = false
    private(set) var soundLoadError: String? = nil

    /// A short message for the play screen when sound isn't working, otherwise nil.
    var statusMessage: String? {
        switch state {
        case .idle, .starting:
            return String(localized: "Starting sound…")
        case .failed(let reason):
            return String(localized: "Sound isn't working: \(reason)")
        case .ready:
            if let soundLoadError {
                return String(localized: "Piano sound didn't load, using a placeholder tone: \(soundLoadError)")
            }
            return nil
        }
    }

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
    @ObservationIgnored private var graphBuilt = false
    @ObservationIgnored private var soundLoaded = false

    private static let sustainController: UInt8 = 64
    /// Requested hardware buffer. 5 ms keeps touch-to-sound delay low.
    nonisolated private static let preferredBufferDuration: TimeInterval = 0.005

    init() {
        applyTone()
        reverb.wetDryMix = Float(reverbMix * 100)
        observeSystemEvents()
    }

    // MARK: - Lifecycle

    func start() {
        guard state != .starting else { return }
        if state == .ready, engine.isRunning { return }
        state = .starting

        Task {
            // Session activation can block for a while, so it runs off the main thread.
            let sessionResult = await Task.detached(priority: .userInitiated) {
                Result { try Self.configureSession() }
            }.value

            switch sessionResult {
            case .failure(let error):
                fail("audio session: \(error.localizedDescription)")
                return
            case .success(let info):
                log.notice("Audio session active: \(info, privacy: .public)")
            }

            buildGraphIfNeeded()
            do {
                if !engine.isRunning {
                    try engine.start()
                }
                let format = engine.outputNode.outputFormat(forBus: 0).description
                log.notice("Engine running, output format \(format, privacy: .public)")
            } catch {
                fail("engine: \(error.localizedDescription)")
                return
            }

            loadPianoSoundIfNeeded()
            state = .ready
        }
    }

    func pause() {
        allNotesOff()
        engine.pause()
        state = .idle
        log.notice("Engine paused")
    }

    // MARK: - Notes

    func noteOn(_ note: Note, velocity: UInt8) {
        if state != .ready {
            let current = String(describing: state)
            log.error("Note \(note.name, privacy: .public) pressed but sound isn't ready (\(current, privacy: .public))")
        }
        sampler.startNote(note.midiByte, withVelocity: velocity, onChannel: 0)
        log.debug("Note on \(note.name, privacy: .public) velocity \(velocity)")
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

    nonisolated private static func configureSession() throws -> String {
        let session = AVAudioSession.sharedInstance()
        // .playback keeps playing with the silent switch on.
        // .mixWithOthers lets the piano play over a video lesson in Split View.
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredIOBufferDuration(preferredBufferDuration)
        try session.setActive(true)
        let route = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ", ")
        return "\(Int(session.sampleRate)) Hz, buffer \(Int(session.ioBufferDuration * 1000)) ms, output \(route)"
    }

    private func buildGraphIfNeeded() {
        guard !graphBuilt else { return }
        engine.attach(sampler)
        engine.attach(tone)
        engine.attach(reverb)
        engine.connect(sampler, to: tone, format: nil)
        engine.connect(tone, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = Float(reverbMix * 100)
        graphBuilt = true
    }

    private func loadPianoSoundIfNeeded() {
        guard !soundLoaded else { return }
        soundLoaded = true
        guard let url = Bundle.main.url(forResource: "Piano", withExtension: "sf2") else {
            soundLoadError = String(localized: "Piano.sf2 isn't in the app bundle")
            log.error("Piano.sf2 not found in the app bundle")
            return
        }
        let started = Date()
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            hasPianoSamples = true
            soundLoadError = nil
            let seconds = Date().timeIntervalSince(started)
            log.notice("Loaded Piano.sf2 in \(seconds, format: .fixed(precision: 2)) s")
        } catch {
            hasPianoSamples = false
            soundLoadError = error.localizedDescription
            let details = String(describing: error)
            log.error("Couldn't load Piano.sf2: \(details, privacy: .public)")
        }
    }

    private func fail(_ reason: String) {
        state = .failed(reason)
        log.error("Sound failed: \(reason, privacy: .public)")
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
            log.notice("Audio interrupted")
            allNotesOff()
            state = .idle
        case .ended:
            log.notice("Audio interruption ended")
            start()
        @unknown default:
            break
        }
    }

    private func restartAfterChange() {
        log.notice("Audio configuration changed, restarting the engine")
        allNotesOff()
        state = .idle
        start()
    }
}
