import Foundation
import Observation
import PianoCore

/// App-wide state: the sound engine, what's playing, and the player's settings.
/// Settings are saved to UserDefaults as they change.
@MainActor
@Observable
final class PlaySession {
    let engine = PianoEngine()

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
        set { engine.sustainOn = newValue }
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

        engine.reverbMix = reverbMix
        applyTone()
    }

    func handle(_ events: [NoteEvent]) {
        let now = Date.timeIntervalSinceReferenceDate
        for event in events {
            switch event.kind {
            case .on:
                engine.noteOn(event.note, velocity: event.velocity)
                soundingNotes.insert(event.note)
                trails.noteOn(event.note, velocity: event.velocity, at: now)
            case .off:
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
    }
}
