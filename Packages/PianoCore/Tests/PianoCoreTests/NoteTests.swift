import Testing
@testable import PianoCore

struct NoteTests {
    @Test func middleCIsC4() {
        #expect(Note.middleC.name == "C4")
        #expect(Note(midiNumber: 69).name == "A4")
        #expect(Note(midiNumber: 61).name == "C♯4")
        #expect(Note(midiNumber: 21).name == "A0")
    }

    @Test func blackAndWhiteKeys() {
        let blacks = (60..<72).filter { Note(midiNumber: $0).isBlack }
        #expect(blacks == [61, 63, 66, 68, 70])
    }

    @Test func onlyEAndBHaveNoBlackKeyAbove() {
        let whites = (60..<72).map(Note.init(midiNumber:)).filter(\.isWhite)
        let withoutBlack = whites.filter { !$0.hasBlackKeyAbove }.map(\.name)
        #expect(withoutBlack == ["E4", "B4"])
    }

    @Test func whiteKeyOffsets() {
        let c4 = Note.middleC
        #expect(c4.whiteKey(offsetBy: 0) == c4)
        #expect(c4.whiteKey(offsetBy: 6)?.name == "B4")
        #expect(c4.whiteKey(offsetBy: 7)?.name == "C5")
        #expect(c4.whiteKey(offsetBy: -1)?.name == "B3")
        // A black note counts from the white key below it.
        #expect(Note(midiNumber: 61).whiteKey(offsetBy: 1)?.name == "D4")
        #expect(Note(midiNumber: 0).whiteKey(offsetBy: -1) == nil)
    }
}
