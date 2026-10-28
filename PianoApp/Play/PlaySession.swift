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
    /// Taller than any trail area, so a pruned trail is always off screen.
    private static let trailHeight = 1_200.0

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
        trails.prune(at: now, height: Self.trailHeight)
        // While a note is held there's nothing to schedule; its release calls this again.
        guard let wait = trails.secondsUntilClear(at: now, height: Self.trailHeight) else { return }
        pruneTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait + 0.05))
            guard !Task.isCancelled, let self else { return }
            self.trails.prune(at: Date.timeIntervalSinceReferenceDate, height: Self.trailHeight)
        }
    }

    func canShiftOctave(by octaves: Int) -> Bool {
        guard let shifted = preferredLowestNote.transposed(by: 12 * octaves) else { return false }
        return shifted >= Note.pianoRange.lowerBound && shifted.midiNumber <= Self.highestStart
    }

    func shiftOctave(by octaves: Int) {
        guard canShiftOctave(by: octaves),
              let shifted = preferredLowestNote.transposed(by: 12 * octaves) else { return }
        preferredLowestNote = shifted
    }

    private func applyTone() {
        engine.brightness = PianoLid.effectiveBrightness(
            manual: toneBrightness, hinge: hinge, enabled: hingeControlsTone
        )
    }

    /// C7: the highest start that still leaves room for an octave on an 88-key piano.
    private static let highestStart = 96

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
