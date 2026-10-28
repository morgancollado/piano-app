import Foundation

/// A piano note, identified by its MIDI note number. Middle C is 60 (C4).
public struct Note: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let midiNumber: Int

    public init(midiNumber: Int) {
        precondition((0...127).contains(midiNumber), "MIDI note numbers run from 0 to 127")
        self.midiNumber = midiNumber
    }

    public static let middleC = Note(midiNumber: 60)

    /// The lowest and highest keys of an 88-key piano: A0 and C8.
    public static let pianoRange: ClosedRange<Note> = Note(midiNumber: 21)...Note(midiNumber: 108)

    /// 0 for C, 1 for C♯, … 11 for B.
    public var pitchClass: Int { midiNumber % 12 }

    /// Scientific pitch octave, where middle C is in octave 4.
    public var octave: Int { midiNumber / 12 - 1 }

    public var isBlack: Bool { Self.blackPitchClasses.contains(pitchClass) }
    public var isWhite: Bool { !isBlack }

    /// Whether a black key sits just above this white key. E and B have none.
    public var hasBlackKeyAbove: Bool { isWhite && pitchClass != 4 && pitchClass != 11 }

    public var name: String { Self.names[pitchClass] + String(octave) }
    public var description: String { name }

    /// The MIDI note number as a byte, for audio and MIDI APIs.
    public var midiByte: UInt8 { UInt8(midiNumber) }

    public func transposed(by semitones: Int) -> Note? {
        let number = midiNumber + semitones
        return (0...127).contains(number) ? Note(midiNumber: number) : nil
    }

    /// The white key `steps` white keys away. Negative steps move down.
    /// A black note counts from the white key just below it.
    public func whiteKey(offsetBy steps: Int) -> Note? {
        var current = isWhite ? midiNumber : midiNumber - 1
        var remaining = steps
        while remaining != 0 {
            current += remaining > 0 ? 1 : -1
            guard (0...127).contains(current) else { return nil }
            if !Self.blackPitchClasses.contains(current % 12) {
                remaining += remaining > 0 ? -1 : 1
            }
        }
        return Note(midiNumber: current)
    }

    public static func < (lhs: Note, rhs: Note) -> Bool { lhs.midiNumber < rhs.midiNumber }

    private static let blackPitchClasses: Set<Int> = [1, 3, 6, 8, 10]
    private static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
}
