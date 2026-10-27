public struct NoteEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case on, off }

    public let kind: Kind
    public let note: Note
    /// MIDI velocity, 1–127. Zero for note-off events.
    public let velocity: UInt8

    public static func on(_ note: Note, velocity: UInt8) -> NoteEvent {
        NoteEvent(kind: .on, note: note, velocity: max(1, min(velocity, 127)))
    }

    public static func off(_ note: Note) -> NoteEvent {
        NoteEvent(kind: .off, note: note, velocity: 0)
    }
}

/// Turns finger touches into note-on and note-off events.
///
/// - Each finger plays one note at a time. Sliding onto another key releases the old note
///   and plays the new one (glissando).
/// - Two fingers on the same key re-strike it, and the note stops only when the last finger lifts.
/// - `endAll()` releases everything. Call it when touches are cancelled (for example when
///   the device folds mid-note) so no note is left stuck on.
public struct TouchTracker<TouchID: Hashable & Sendable>: Sendable {
    private var noteByTouch: [TouchID: Note] = [:]
    private var holdCount: [Note: Int] = [:]

    public init() {}

    /// Notes currently held down by at least one finger.
    public var heldNotes: Set<Note> { Set(holdCount.keys) }
    public var activeTouchCount: Int { noteByTouch.count }

    public mutating func begin(_ touch: TouchID, on note: Note?, velocity: UInt8) -> [NoteEvent] {
        var events = release(touch)
        if let note {
            hold(note, with: touch)
            events.append(.on(note, velocity: velocity))
        }
        return events
    }

    public mutating func move(_ touch: TouchID, to note: Note?, velocity: UInt8) -> [NoteEvent] {
        guard noteByTouch[touch] != note else { return [] }
        var events = release(touch)
        if let note {
            hold(note, with: touch)
            events.append(.on(note, velocity: velocity))
        }
        return events
    }

    public mutating func end(_ touch: TouchID) -> [NoteEvent] {
        release(touch)
    }

    public mutating func endAll() -> [NoteEvent] {
        let notes = holdCount.keys.sorted()
        noteByTouch.removeAll()
        holdCount.removeAll()
        return notes.map { .off($0) }
    }

    private mutating func hold(_ note: Note, with touch: TouchID) {
        noteByTouch[touch] = note
        holdCount[note, default: 0] += 1
    }

    private mutating func release(_ touch: TouchID) -> [NoteEvent] {
        guard let note = noteByTouch.removeValue(forKey: touch) else { return [] }
        let remaining = (holdCount[note] ?? 1) - 1
        if remaining > 0 {
            holdCount[note] = remaining
            return []
        }
        holdCount[note] = nil
        return [.off(note)]
    }
}
