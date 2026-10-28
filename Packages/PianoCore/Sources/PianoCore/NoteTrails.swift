/// Light trails that rise from each played key, like a piano roll running upward.
///
/// A trail starts at the key when the note is pressed. Its top rises at a steady speed; while
/// the key is held its bottom stays at the key, and after release the bottom rises too, so the
/// trail's length shows how long the note was held. Times are in seconds on any steady clock.
public struct NoteTrail: Sendable, Equatable, Identifiable {
    public let id: Int
    public let note: Note
    public let velocity: UInt8
    public let start: Double
    public internal(set) var end: Double?

    /// Distances risen above the key, in points: `bottom` ≤ `top`.
    public func extent(at time: Double, speed: Double) -> (bottom: Double, top: Double) {
        let top = max(0, time - start) * speed
        let bottom = end.map { max(0, time - $0) * speed } ?? 0
        return (min(bottom, top), top)
    }
}

public struct NoteTrails: Sendable, Equatable {
    /// Points per second.
    public static let defaultSpeed = 150.0

    public private(set) var trails: [NoteTrail] = []
    private var nextID = 0

    public init() {}

    public var isEmpty: Bool { trails.isEmpty }

    public mutating func noteOn(_ note: Note, velocity: UInt8, at time: Double) {
        // A re-struck note ends its previous trail, as the key was released in between.
        noteOff(note, at: time)
        trails.append(NoteTrail(id: nextID, note: note, velocity: velocity, start: time, end: nil))
        nextID += 1
    }

    public mutating func noteOff(_ note: Note, at time: Double) {
        if let index = trails.lastIndex(where: { $0.note == note && $0.end == nil }) {
            trails[index].end = time
        }
    }

    /// Ends every open trail (for example when all notes are cut off).
    public mutating func endAll(at time: Double) {
        for index in trails.indices where trails[index].end == nil {
            trails[index].end = time
        }
    }

    /// Removes trails that have fully risen past `height`.
    public mutating func prune(at time: Double, height: Double, speed: Double = defaultSpeed) {
        trails.removeAll { trail in
            guard trail.end != nil else { return false }
            return trail.extent(at: time, speed: speed).bottom > height
        }
    }

    /// Seconds until every released trail has risen past `height`, or nil while a note is held.
    public func secondsUntilClear(at time: Double, height: Double, speed: Double = defaultSpeed) -> Double? {
        var latest = 0.0
        for trail in trails {
            guard let end = trail.end else { return nil }
            latest = max(latest, end + height / speed - time)
        }
        return max(0, latest)
    }
}
