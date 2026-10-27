import Testing
@testable import PianoCore

struct TouchTrackerTests {
    let c4 = Note.middleC
    let d4 = Note(midiNumber: 62)
    let e4 = Note(midiNumber: 64)

    @Test func pressAndRelease() {
        var tracker = TouchTracker<Int>()
        #expect(tracker.begin(1, on: c4, velocity: 100) == [.on(c4, velocity: 100)])
        #expect(tracker.heldNotes == [c4])
        #expect(tracker.end(1) == [.off(c4)])
        #expect(tracker.heldNotes.isEmpty)
    }

    @Test func slidingAcrossKeysPlaysEachOne() {
        var tracker = TouchTracker<Int>()
        _ = tracker.begin(1, on: c4, velocity: 90)
        #expect(tracker.move(1, to: c4, velocity: 90).isEmpty)
        #expect(tracker.move(1, to: d4, velocity: 90) == [.off(c4), .on(d4, velocity: 90)])
        #expect(tracker.move(1, to: nil, velocity: 90) == [.off(d4)])
        #expect(tracker.move(1, to: e4, velocity: 90) == [.on(e4, velocity: 90)])
    }

    @Test func twoFingersOnOneKeyStopOnlyWhenBothLift() {
        var tracker = TouchTracker<Int>()
        _ = tracker.begin(1, on: c4, velocity: 80)
        #expect(tracker.begin(2, on: c4, velocity: 80) == [.on(c4, velocity: 80)])
        #expect(tracker.end(1).isEmpty)
        #expect(tracker.heldNotes == [c4])
        #expect(tracker.end(2) == [.off(c4)])
    }

    @Test func chordsAndEndAllLeaveNothingStuck() {
        var tracker = TouchTracker<Int>()
        _ = tracker.begin(1, on: c4, velocity: 80)
        _ = tracker.begin(2, on: e4, velocity: 80)
        _ = tracker.begin(3, on: nil, velocity: 80)
        #expect(tracker.activeTouchCount == 2)
        #expect(tracker.endAll() == [.off(c4), .off(e4)])
        #expect(tracker.heldNotes.isEmpty)
        #expect(tracker.end(1).isEmpty)
    }

    @Test func velocityIsClampedToMIDIRange() {
        #expect(NoteEvent.on(c4, velocity: 0).velocity == 1)
        #expect(NoteEvent.on(c4, velocity: 200).velocity == 127)
    }
}

struct ExpressionTests {
    @Test func touchPositionVelocity() {
        #expect(Velocity.value(mode: .fixed, depth: 0.9) == Velocity.defaultFixed)
        #expect(Velocity.value(mode: .touchPosition, depth: 0) == 40)
        #expect(Velocity.value(mode: .touchPosition, depth: 1) == 127)
        #expect(Velocity.value(mode: .touchPosition, depth: 5) == 127)
    }

    @Test func lidOnlyActsWhenEnabledAndPartlyOpen() {
        let half = HingeReading(degrees: 90, isPartiallyOpen: true)
        let flat = HingeReading(degrees: 180, isPartiallyOpen: false)
        #expect(PianoLid.effectiveBrightness(manual: 0.8, hinge: half, enabled: false) == 0.8)
        #expect(PianoLid.effectiveBrightness(manual: 0.8, hinge: flat, enabled: true) == 0.8)
        #expect(PianoLid.effectiveBrightness(manual: 0.8, hinge: nil, enabled: true) == 0.8)
        #expect(PianoLid.effectiveBrightness(manual: 1, hinge: half, enabled: true) < 1)
    }

    @Test func lidBrightnessRisesAsTheHingeOpens() {
        #expect(PianoLid.brightness(hingeDegrees: 0) == PianoLid.minimumBrightness)
        #expect(PianoLid.brightness(hingeDegrees: 180) == 1)
        #expect(PianoLid.brightness(hingeDegrees: 60) < PianoLid.brightness(hingeDegrees: 120))
    }
}
