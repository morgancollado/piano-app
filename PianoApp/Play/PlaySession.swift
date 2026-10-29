import Foundation
import Observation
import PianoCore

/// App-wide state: the sound engine, MIDI out, what's playing, and the player's settings.
/// Settings are saved to UserDefaults as they change.
@MainActor
@Observable
final class PlaySession {
    let engine = PianoEngine()
    /// Sends what you play to DAWs and other recording apps.
    let midi: MIDIOutput

    private(set) var soundingNotes: Set<Note> = []
    /// Light trails for the notes being played, drawn above the keys.
    private(set) var trails = NoteTrails()
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    /// How far a released trail rises before it's removed, so the trail view can stop
    /// animating once nothing is visible. The play screen sets it from the trail area's
    /// measured height (see `NoteTrailsView.clearDistance`).
    @ObservationIgnored var trailClearDistance = 1_200.0 {
        didSet { if trailClearDistance != oldValue { scheduleTrailCleanup() } }
    }

    /// Where the keyboard would start after Octave Down and Octave Up, or nil when the keys
    /// can't move that way. Worked out from the keys on screen by `updateOctaveShifts(for:)`.
    private(set) var octaveDownStart: Note?
    private(set) var octaveUpStart: Note?

    /// Where the keyboard starts. The layout may move it by a few keys to line up with the fold.
    var preferredLowestNote: Note {
        didSet { defaults.set(preferredLowestNote.midiNumber, forKey: Keys.lowestNote) }
    }
    var keyWidth: Double {
        didSet { defaults.set(keyWidth, forKey: Keys.keyWidth) }
    }
    var velocityMode: VelocityMode {
        didSet { defaults.set(velocityMode.rawValue, forKey: Keys.velocityMode) }
    }
    var showsNoteLabels: Bool {
        didSet { defaults.set(showsNoteLabels, forKey: Keys.showsNoteLabels) }
    }
    /// Manual tone, 0 (dark) to 1 (bright).
    var toneBrightness: Double {
        didSet {
            defaults.set(toneBrightness, forKey: Keys.toneBrightness)
            applyTone()
        }
    }
    var reverbMix: Double {
        didSet {
            defaults.set(reverbMix, forKey: Keys.reverbMix)
            engine.reverbMix = reverbMix
        }
    }
    /// iPhone Duo only: the hinge acts like a piano lid. Off by default, because people shift
    /// the angle without thinking while they play.
    var hingeControlsTone: Bool {
        didSet {
            defaults.set(hingeControlsTone, forKey: Keys.hingeControlsTone)
            applyTone()
        }
    }
    var hinge: HingeReading? = nil {
        didSet { if hinge != oldValue { applyTone() } }
    }

    var sustainOn: Bool {
        get { engine.sustainOn }
        set {
            engine.sustainOn = newValue
            midi.sendSustain(newValue)
        }
    }

    // MARK: MIDI out settings

    /// Send notes, the pedal and the transport buttons as MIDI. On by default: the "Piano"
    /// source costs nothing and shows no permission prompt.
    var midiEnabled: Bool {
        didSet {
            defaults.set(midiEnabled, forKey: Keys.midiEnabled)
            midi.isEnabled = midiEnabled
            if midiEnabled { midi.sendSustain(sustainOn) }
        }
    }
    var midiChannel: MIDIChannel {
        didSet {
            defaults.set(midiChannel.number, forKey: Keys.midiChannel)
            midi.setChannel(midiChannel)
        }
    }
    /// Off when you listen through the DAW's own instrument, so you don't hear two pianos.
    var playsSoundLocally: Bool {
        didSet { defaults.set(playsSoundLocally, forKey: Keys.playsSoundLocally) }
    }
    /// Lets a Mac or PC connect over Wi-Fi. Off until asked for, because turning it on shows
    /// iOS's local network permission prompt.
    var allowsNetworkMIDI: Bool {
        didSet {
            defaults.set(allowsNetworkMIDI, forKey: Keys.allowsNetworkMIDI)
            midi.allowsNetworkConnections = allowsNetworkMIDI
        }
    }
    var transportMode: TransportMode {
        didSet { defaults.set(transportMode.rawValue, forKey: Keys.transportMode) }
    }
    var transportVisibility: TransportVisibility {
        didSet { defaults.set(transportVisibility.rawValue, forKey: Keys.transportVisibility) }
    }

    /// Whether the Record, Play and Stop buttons are in the toolbar.
    var showsTransportButtons: Bool {
        midiEnabled && transportVisibility.showsButtons(isConnected: midi.isConnected)
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedLowest = defaults.object(forKey: Keys.lowestNote) as? Int
        preferredLowestNote = savedLowest.flatMap { (0...127).contains($0) ? Note(midiNumber: $0) : nil } ?? .middleC
        keyWidth = defaults.object(forKey: Keys.keyWidth) as? Double ?? Double(KeyboardLayout.defaultWhiteKeyWidth)
        velocityMode = (defaults.string(forKey: Keys.velocityMode)).flatMap(VelocityMode.init(rawValue:)) ?? .fixed
        showsNoteLabels = defaults.object(forKey: Keys.showsNoteLabels) as? Bool ?? true
        toneBrightness = defaults.object(forKey: Keys.toneBrightness) as? Double ?? 1
        reverbMix = defaults.object(forKey: Keys.reverbMix) as? Double ?? 0.15
        hingeControlsTone = defaults.object(forKey: Keys.hingeControlsTone) as? Bool ?? false

        midi = MIDIOutput(defaults: defaults)
        midiEnabled = defaults.object(forKey: Keys.midiEnabled) as? Bool ?? true
        let savedChannel = (defaults.object(forKey: Keys.midiChannel) as? Int).flatMap(MIDIChannel.init(number:))
        midiChannel = savedChannel.flatMap { MIDIChannel.noteChoices.contains($0) ? $0 : nil } ?? .defaultNotes
        playsSoundLocally = defaults.object(forKey: Keys.playsSoundLocally) as? Bool ?? true
        allowsNetworkMIDI = defaults.object(forKey: Keys.allowsNetworkMIDI) as? Bool ?? false
        transportMode = defaults.string(forKey: Keys.transportMode).flatMap(TransportMode.init(rawValue:)) ?? .learnable
        transportVisibility = defaults.string(forKey: Keys.transportVisibility)
            .flatMap(TransportVisibility.init(rawValue:)) ?? .whenConnected

        engine.reverbMix = reverbMix
        applyTone()
        // didSet doesn't run during init, so hand the saved MIDI settings over here.
        midi.isEnabled = midiEnabled
        midi.setChannel(midiChannel)
        midi.allowsNetworkConnections = allowsNetworkMIDI
    }

    /// - Parameter eventUptime: when the touches happened (`UIEvent.timestamp`), so a DAW
    ///   records the notes where the finger landed.
    func handle(_ events: [NoteEvent], eventUptime: TimeInterval? = nil) {
        midi.send(events, eventUptime: eventUptime)
        let now = Date.timeIntervalSinceReferenceDate
        for event in events {
            switch event.kind {
            case .on:
                if playsSoundLocally {
                    engine.noteOn(event.note, velocity: event.velocity)
                }
                soundingNotes.insert(event.note)
                trails.noteOn(event.note, velocity: event.velocity, at: now)
            case .off:
                // Always sent, even with the app's sound off, so a note started before the
                // setting changed can't stay on.
                engine.noteOff(event.note)
                soundingNotes.remove(event.note)
                trails.noteOff(event.note, at: now)
            }
        }
        scheduleTrailCleanup()
    }

    /// Removes trails once they've risen off screen, so the trail view can stop animating.
    private func scheduleTrailCleanup() {
        pruneTask?.cancel()
        let now = Date.timeIntervalSinceReferenceDate
        let distance = trailClearDistance
        trails.prune(at: now, height: distance)
        // While a note is held there's nothing to schedule; its release calls this again.
        guard let wait = trails.secondsUntilClear(at: now, height: distance) else { return }
        pruneTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait + 0.05))
            guard !Task.isCancelled, let self else { return }
            self.trails.prune(at: Date.timeIntervalSinceReferenceDate, height: self.trailClearDistance)
        }
    }

    // MARK: - App lifecycle and MIDI

    func didBecomeActive() {
        engine.start()
        // The DAW heard the pedal go up when the app left; put it back where the toolbar is.
        if sustainOn { midi.sendSustain(true) }
    }

    func didEnterBackground() {
        engine.pause()
        // Nothing can be played in the background, so end every note the DAW is holding.
        midi.releaseAll()
    }

    /// Record, Play or Stop in the DAW.
    func sendTransport(_ command: TransportCommand) {
        midi.send(command, mode: transportMode)
    }

    /// Silences the app and tells every DAW to let go of every note.
    func stopAllNotes() {
        engine.allNotesOff()
        midi.releaseAll()
        if sustainOn { midi.sendSustain(true) }
    }

    /// Call whenever the keyboard on screen changes.
    func updateOctaveShifts(for layout: KeyboardLayout) {
        let down = layout.startNote(shiftedByOctaves: -1)
        let up = layout.startNote(shiftedByOctaves: 1)
        if down != octaveDownStart { octaveDownStart = down }
        if up != octaveUpStart { octaveUpStart = up }
    }

    func canShiftOctave(by octaves: Int) -> Bool {
        octaveStart(by: octaves) != nil
    }

    func shiftOctave(by octaves: Int) {
        guard let start = octaveStart(by: octaves) else { return }
        preferredLowestNote = start
    }

    private func octaveStart(by octaves: Int) -> Note? {
        switch octaves {
        case -1: octaveDownStart
        case 1: octaveUpStart
        default: nil
        }
    }

    private func applyTone() {
        engine.brightness = PianoLid.effectiveBrightness(
            manual: toneBrightness, hinge: hinge, enabled: hingeControlsTone
        )
    }

    private enum Keys {
        static let lowestNote = "lowestNote"
        static let keyWidth = "keyWidth"
        static let velocityMode = "velocityMode"
        static let showsNoteLabels = "showsNoteLabels"
        static let toneBrightness = "toneBrightness"
        static let reverbMix = "reverbMix"
        static let hingeControlsTone = "hingeControlsTone"
        static let midiEnabled = "midiEnabled"
        static let midiChannel = "midiChannel"
        static let playsSoundLocally = "playsSoundLocally"
        static let allowsNetworkMIDI = "allowsNetworkMIDI"
        static let transportMode = "transportMode"
        static let transportVisibility = "transportVisibility"
    }
}
