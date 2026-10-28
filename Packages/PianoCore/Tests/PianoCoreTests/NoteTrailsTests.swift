import Testing
@testable import PianoCore

struct NoteTrailsTests {
    let c4 = Note.middleC
    let e4 = Note(midiNumber: 64)

    @Test func heldTrailGrowsFromTheKey() throws {
        var trails = NoteTrails()
        trails.noteOn(c4, velocity: 90, at: 10)
        let trail = try #require(trails.trails.first)
        let extent = trail.extent(at: 11, speed: 100)
        #expect(extent.bottom == 0)
        #expect(extent.top == 100)
    }

    @Test func releasedTrailRisesAwayKeepingItsLength() throws {
        var trails = NoteTrails()
        trails.noteOn(c4, velocity: 90, at: 0)
        trails.noteOff(c4, at: 0.5)
        let trail = try #require(trails.trails.first)
        let extent = trail.extent(at: 2, speed: 100)
        #expect(extent.top == 200)
        #expect(extent.bottom == 150)
    }

    @Test func restrikingEndsThePreviousTrail() {
        var trails = NoteTrails()
        trails.noteOn(c4, velocity: 90, at: 0)
        trails.noteOn(c4, velocity: 90, at: 1)
        #expect(trails.trails.count == 2)
        #expect(trails.trails[0].end == 1)
        #expect(trails.trails[1].end == nil)
    }

    @Test func pruneRemovesOnlyTrailsThatLeftTheView() {
        var trails = NoteTrails()
        trails.noteOn(c4, velocity: 90, at: 0)
        trails.noteOff(c4, at: 0.1)
        trails.noteOn(e4, velocity: 90, at: 0)
        trails.prune(at: 5, height: 300, speed: 100)
        #expect(trails.trails.map(\.note) == [e4])
    }

    @Test func secondsUntilClear() {
        var trails = NoteTrails()
        #expect(trails.secondsUntilClear(at: 0, height: 300, speed: 100) == 0)
        trails.noteOn(c4, velocity: 90, at: 0)
        #expect(trails.secondsUntilClear(at: 0, height: 300, speed: 100) == nil)
        trails.noteOff(c4, at: 1)
        #expect(trails.secondsUntilClear(at: 2, height: 300, speed: 100) == 2)
        trails.endAll(at: 3)
    }
}
