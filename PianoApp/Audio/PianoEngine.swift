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
///
/// The sound bank loads on the main thread. Measured on device (iOS 27.2) it takes about
/// 0.07 s, too short to notice, so a background load isn't worth the extra code or relying
/// on undocumented thread safety in `AVAudioUnitSampler`.
///
/// A start can be overtaken by a pause, an interruption or a restart. Each start carries a
/// generation number, and a start whose number is out of date stops at its next step, so an
/// old start never restarts the engine after the app has paused it.
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
        didSet { sendSustain() }
    }

    /// 0 is dark and soft, 1 is fully bright.
    var brightness: Double = 1 {
        didSet { applyTone() }
    }

    /// 0 is dry, 1 is all reverb.
    var reverbMix: Double = 0.15 {
        didSet { applyReverbMix() }
    }

    // The engine and its nodes are replaced when the system resets its media services,
    // because the reset leaves the old ones unusable.
    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var sampler = AVAudioUnitSampler()
    @ObservationIgnored private var tone = AVAudioUnitEQ(numberOfBands: 1)
    @ObservationIgnored private var reverb = AVAudioUnitReverb()
    @ObservationIgnored private var graphBuilt = false
    /// Whether `Piano.sf2` has been loaded (or tried) into the current sampler.
    @ObservationIgnored private var soundLoaded = false

    /// Bumped whenever a start in progress should give up.
    @ObservationIgnored private var startGeneration = 0
    /// True between `start()` and `pause()`. System events only restart sound while it's true,
    /// so a route change or reset in the background doesn't start the engine there.
    @ObservationIgnored private var wantsSound = false

    @ObservationIgnored private var sessionObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var engineObserver: (any NSObjectProtocol)?

    private static let sustainController: UInt8 = 64
    /// MIDI "All Sound Off": silences every voice at once, release tails included.
    private static let allSoundOffController: UInt8 = 120
    /// Requested hardware buffer. 5 ms keeps touch-to-sound delay low.
    nonisolated private static let preferredBufferDuration: TimeInterval = 0.005

    init() {
        applyTone()
        applyReverbMix()
        observeSessionEvents()
        observeEngineConfiguration()
    }

    // MARK: - Lifecycle

    func start() {
        wantsSound = true
        guard state != .starting else { return }
        if state == .ready, engine.isRunning { return }
        state = .starting
        startGeneration += 1
        let generation = startGeneration
        Task { await runStart(generation: generation) }
    }

    func pause() {
        wantsSound = false
        cancelPendingStart()
        allNotesOff()
        engine.pause()
        state = .idle
        log.notice("Engine paused")
    }

    private func runStart(generation: Int) async {
        // Session activation can block for a while, so it runs off the main thread.
        let sessionResult = await Task.detached(priority: .userInitiated) {
            Result { try Self.configureSession() }
        }.value
        guard isCurrent(generation) else { return }

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

        // Synchronous on the main actor, so nothing can pause or restart in between.
        loadPianoSoundIfNeeded()
        // A fresh sampler starts with the pedal up; match the toolbar.
        sendSustain()
        state = .ready
    }

    private func isCurrent(_ generation: Int) -> Bool {
        if generation == startGeneration { return true }
        log.notice("A newer pause or restart replaced this start; stopping it")
        return false
    }

    private func cancelPendingStart() {
        startGeneration += 1
    }

    // MARK: - Notes

    func noteOn(_ note: Note, velocity: UInt8) {
        // Until the piano sound has loaded the sampler only has a placeholder tone, and the
        // status line already says sound is starting, so presses stay silent.
        guard state == .ready else {
            let current = String(describing: state)
            log.error("Note \(note.name, privacy: .public) pressed but sound isn't ready (\(current, privacy: .public))")
            return
        }
        sampler.startNote(note.midiByte, withVelocity: velocity, onChannel: 0)
        log.debug("Note on \(note.name, privacy: .public) velocity \(velocity)")
    }

    func noteOff(_ note: Note) {
        // Always sent, whatever the state, so no note can be left on.
        sampler.stopNote(note.midiByte, onChannel: 0)
    }

    /// Silences everything, including notes held by the sustain pedal.
    func allNotesOff() {
        // The sampler ignores note-offs while the pedal is down, so lift it first.
        sampler.sendController(Self.sustainController, withValue: 0, onChannel: 0)
        for number in UInt8(0)...UInt8(127) {
            sampler.stopNote(number, onChannel: 0)
        }
        // Also cut release tails, so nothing is still sounding when the engine resumes.
        sampler.sendController(Self.allSoundOffController, withValue: 0, onChannel: 0)
        // Put the pedal back where the toolbar shows it, for the notes played next.
        sendSustain()
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
        applyReverbMix()
        graphBuilt = true
    }

    // MARK: - Piano sound

    private func loadPianoSoundIfNeeded() {
        guard !soundLoaded else { return }
        soundLoaded = true
        guard let url = Bundle.main.url(forResource: "Piano", withExtension: "sf2") else {
            soundLoadError = String(localized: "Piano.sf2 isn't in the app bundle")
            log.error("Piano.sf2 not found in the app bundle")
            return
        }
        // The sampler's loader aborts the app on some bad files instead of throwing, so check
        // the header first. A Git LFS pointer here means the clone was made without Git LFS.
        let prefix = (try? FileHandle(forReadingFrom: url).read(upToCount: SoundFontFile.prefixLength)) ?? Data()
        switch SoundFontFile.problem(withPrefix: prefix) {
        case .gitLFSPointer:
            soundLoadError = String(localized: "Piano.sf2 is a Git LFS placeholder. Install Git LFS, run git lfs pull, and build again.")
            log.error("Piano.sf2 is a Git LFS pointer, not the SoundFont")
            return
        case .notASoundFont:
            soundLoadError = String(localized: "Piano.sf2 isn't a SoundFont file")
            log.error("Piano.sf2 doesn't have a SoundFont header")
            return
        case nil:
            break
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

    private func sendSustain() {
        sampler.sendController(Self.sustainController, withValue: sustainOn ? 127 : 0, onChannel: 0)
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

    private func applyReverbMix() {
        reverb.wetDryMix = Float(min(max(reverbMix, 0), 1) * 100)
    }

    // MARK: - System events

    private func observeSessionEvents() {
        let center = NotificationCenter.default

        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(rawType: rawType) }
        })

        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildAfterMediaReset() }
        })
    }

    /// Headphones plugged in or removed, Bluetooth changes, and similar. Tied to the current
    /// engine, so it's registered again whenever the engine is replaced.
    private func observeEngineConfiguration() {
        if let engineObserver {
            NotificationCenter.default.removeObserver(engineObserver)
        }
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterConfigurationChange() }
        }
    }

    private func handleInterruption(rawType: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            log.notice("Audio interrupted")
            cancelPendingStart()
            allNotesOff()
            state = .idle
        case .ended:
            log.notice("Audio interruption ended")
            if wantsSound { start() }
        @unknown default:
            break
        }
    }

    /// The system stopped the engine because the output changed. The engine and nodes are
    /// still usable, so only a restart is needed.
    private func restartAfterConfigurationChange() {
        log.notice("Audio configuration changed")
        cancelPendingStart()
        allNotesOff()
        state = .idle
        if wantsSound { start() }
    }

    /// After a media services reset every audio object the app made is invalid. Apple's
    /// guidance is to make a new engine and nodes, reload the instrument, and configure
    /// the session again, which `start()` does from scratch.
    private func rebuildAfterMediaReset() {
        log.notice("Media services were reset, rebuilding the audio engine")
        cancelPendingStart()
        state = .idle

        engine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
        tone = AVAudioUnitEQ(numberOfBands: 1)
        reverb = AVAudioUnitReverb()
        graphBuilt = false
        soundLoaded = false
        hasPianoSamples = false
        soundLoadError = nil
        applyTone()
        applyReverbMix()
        observeEngineConfiguration()

        if wantsSound { start() }
    }
}
