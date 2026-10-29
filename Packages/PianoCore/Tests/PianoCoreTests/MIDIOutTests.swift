import Testing
@testable import PianoCore

struct MIDIChannelTests {
    @Test func numbersRunFromOneToSixteen() {
        #expect(MIDIChannel(number: 0) == nil)
        #expect(MIDIChannel(number: 17) == nil)
        #expect(MIDIChannel(number: 1)?.index == 0)
        #expect(MIDIChannel(number: 16)?.index == 15)
        #expect(MIDIChannel.transport.number == 16)
    }

    @Test func notesNeverShareTheButtonsChannel() {
        #expect(MIDIChannel.noteChoices.count == 15)
        #expect(!MIDIChannel.noteChoices.contains(.transport))
        #expect(MIDIChannel.noteChoices.contains(.defaultNotes))
    }
}

struct MIDIMessageTests {
    let c4 = Note.middleC
    let ch1 = MIDIChannel.defaultNotes
    let ch10 = MIDIChannel(number: 10)!

    @Test func noteOnBytes() {
        #expect(MIDIMessage.noteOn(c4, velocity: 96, channel: ch1).bytes == [0x90, 60, 96])
        #expect(MIDIMessage.noteOn(c4, velocity: 96, channel: ch10).bytes == [0x99, 60, 96])
    }

    @Test func noteOnVelocityStaysInRange() {
        // Velocity 0 would turn a note on into a note off.
        #expect(MIDIMessage.noteOn(c4, velocity: 0, channel: ch1).bytes == [0x90, 60, 1])
        #expect(MIDIMessage.noteOn(c4, velocity: 200, channel: ch1).bytes == [0x90, 60, 127])
    }

    @Test func noteOffBytes() {
        #expect(MIDIMessage.noteOff(c4, channel: ch1).bytes == [0x80, 60, 0])
        #expect(MIDIMessage.noteOff(c4, channel: .transport).bytes == [0x8F, 60, 0])
    }

    @Test func controlChangeBytes() {
        #expect(MIDIMessage.controlChange(64, value: 127, channel: ch1).bytes == [0xB0, 64, 127])
        #expect(MIDIMessage.controlChange(117, value: 0, channel: .transport).bytes == [0xBF, 117, 0])
        #expect(MIDIMessage.controlChange(200, value: 200, channel: ch1).bytes == [0xB0, 127, 127])
    }

    @Test func machineControlBytes() {
        #expect(MIDIMessage.machineControl(.stop).bytes == [0xF0, 0x7F, 0x7F, 0x06, 0x01, 0xF7])
        #expect(MIDIMessage.machineControl(.play).bytes == [0xF0, 0x7F, 0x7F, 0x06, 0x02, 0xF7])
        #expect(MIDIMessage.machineControl(.record).bytes == [0xF0, 0x7F, 0x7F, 0x06, 0x06, 0xF7])
    }

    @Test func channelMessagesAreOneUMPWord() {
        // Type 2, group 0, then the three MIDI 1.0 bytes.
        #expect(MIDIMessage.noteOn(c4, velocity: 96, channel: ch1).umpWords == [0x2090_3C60])
        #expect(MIDIMessage.noteOff(c4, channel: ch10).umpWords == [0x2089_3C00])
        #expect(MIDIMessage.controlChange(64, value: 127, channel: ch1).umpWords == [0x20B0_407F])
    }

    @Test func machineControlIsOneSysExPacket() {
        // Type 3, group 0, "complete" status, 4 data bytes: 7F 7F 06 02.
        #expect(MIDIMessage.machineControl(.play).umpWords == [0x3004_7F7F, 0x0602_0000])
        #expect(MIDIMessage.machineControl(.record).umpWords == [0x3004_7F7F, 0x0606_0000])
    }
}

struct TransportTests {
    @Test func learnableButtonsTapOnChannelSixteen() {
        #expect(TransportMode.learnable.messages(for: .record) == [
            .controlChange(117, value: 127, channel: .transport),
            .controlChange(117, value: 0, channel: .transport),
        ])
        #expect(TransportMode.learnable.messages(for: .play).first == .controlChange(118, value: 127, channel: .transport))
        #expect(TransportMode.learnable.messages(for: .stop).first == .controlChange(119, value: 127, channel: .transport))
    }

    @Test func learnableControllersAreUnassignedAndDistinct() {
        let controllers = TransportCommand.allCases.map(\.learnableController)
        #expect(Set(controllers).count == controllers.count)
        #expect(controllers.allSatisfy { (102...119).contains($0) })
    }

    @Test func machineControlSendsOneMessagePerTap() {
        #expect(TransportMode.machineControl.messages(for: .record) == [.machineControl(.record)])
        #expect(TransportMode.machineControl.messages(for: .play) == [.machineControl(.play)])
        #expect(TransportMode.machineControl.messages(for: .stop) == [.machineControl(.stop)])
    }

    @Test func buttonsNeverUseANoteChannel() {
        for mode in TransportMode.allCases {
            for command in TransportCommand.allCases {
                for message in mode.messages(for: command) {
                    switch message {
                    case .noteOn, .noteOff:
                        Issue.record("A button sent a note")
                    case let .controlChange(_, _, channel):
                        #expect(!MIDIChannel.noteChoices.contains(channel))
                    case .machineControl:
                        break
                    }
                }
            }
        }
    }

    @Test func visibility() {
        #expect(TransportVisibility.whenConnected.showsButtons(isConnected: true))
        #expect(!TransportVisibility.whenConnected.showsButtons(isConnected: false))
        #expect(TransportVisibility.always.showsButtons(isConnected: false))
        #expect(!TransportVisibility.never.showsButtons(isConnected: true))
    }
}

struct MIDIOutLedgerTests {
    let c4 = Note.middleC
    let e4 = Note(midiNumber: 64)
    let ch1 = MIDIChannel.defaultNotes
    let ch2 = MIDIChannel(number: 2)!

    @Test func pressAndRelease() {
        var ledger = MIDIOutLedger()
        #expect(ledger.messages(for: [.on(c4, velocity: 90)]) == [.noteOn(c4, velocity: 90, channel: ch1)])
        #expect(ledger.notesDown == [c4])
        #expect(ledger.messages(for: [.off(c4)]) == [.noteOff(c4, channel: ch1)])
        #expect(ledger.notesDown.isEmpty)
    }

    @Test func reStrikeEndsTheFirstNoteBeforeTheSecond() {
        var ledger = MIDIOutLedger()
        _ = ledger.messages(for: [.on(c4, velocity: 90)])
        #expect(ledger.messages(for: [.on(c4, velocity: 70)]) == [
            .noteOff(c4, channel: ch1),
            .noteOn(c4, velocity: 70, channel: ch1),
        ])
        // The keyboard sends one off when the last finger lifts; that ends the second note.
        #expect(ledger.messages(for: [.off(c4)]) == [.noteOff(c4, channel: ch1)])
        #expect(ledger.notesDown.isEmpty)
    }

    @Test func reStrikeFromTheTouchTrackerGivesCleanNotes() {
        var tracker = TouchTracker<Int>()
        var ledger = MIDIOutLedger()
        var sent: [MIDIMessage] = []
        sent += ledger.messages(for: tracker.begin(1, on: c4, velocity: 80))
        sent += ledger.messages(for: tracker.begin(2, on: c4, velocity: 80))
        sent += ledger.messages(for: tracker.end(1))
        sent += ledger.messages(for: tracker.end(2))
        #expect(sent == [
            .noteOn(c4, velocity: 80, channel: ch1),
            .noteOff(c4, channel: ch1),
            .noteOn(c4, velocity: 80, channel: ch1),
            .noteOff(c4, channel: ch1),
        ])
    }

    @Test func noteOffForANoteThatIsNotDownSendsNothing() {
        var ledger = MIDIOutLedger()
        #expect(ledger.messages(for: [.off(c4)]).isEmpty)
    }

    @Test func sustain() {
        var ledger = MIDIOutLedger()
        #expect(ledger.sustain(true) == [.controlChange(64, value: 127, channel: ch1)])
        #expect(ledger.sustainDown)
        #expect(ledger.sustain(false) == [.controlChange(64, value: 0, channel: ch1)])
        #expect(!ledger.sustainDown)
    }

    @Test func releaseAllEndsEveryNoteThenLiftsThePedal() {
        var ledger = MIDIOutLedger()
        _ = ledger.messages(for: [.on(e4, velocity: 90), .on(c4, velocity: 90)])
        _ = ledger.sustain(true)
        #expect(ledger.releaseAll() == [
            .noteOff(c4, channel: ch1),
            .noteOff(e4, channel: ch1),
            .controlChange(64, value: 0, channel: ch1),
            .controlChange(123, value: 0, channel: ch1),
        ])
        #expect(ledger.notesDown.isEmpty)
        #expect(!ledger.sustainDown)
    }

    @Test func releaseAllWithNothingDownStillSendsTheSafetyNet() {
        var ledger = MIDIOutLedger()
        #expect(ledger.releaseAll() == [
            .controlChange(64, value: 0, channel: ch1),
            .controlChange(123, value: 0, channel: ch1),
        ])
    }

    @Test func changingChannelReleasesOnTheOldOne() {
        var ledger = MIDIOutLedger()
        _ = ledger.messages(for: [.on(c4, velocity: 90)])
        _ = ledger.sustain(true)
        #expect(ledger.setChannel(ch2) == [
            .noteOff(c4, channel: ch1),
            .controlChange(64, value: 0, channel: ch1),
            .controlChange(123, value: 0, channel: ch1),
            .controlChange(64, value: 127, channel: ch2),
        ])
        #expect(ledger.channel == ch2)
        #expect(ledger.messages(for: [.on(c4, velocity: 90)]) == [.noteOn(c4, velocity: 90, channel: ch2)])
    }

    @Test func changingToTheSameChannelSendsNothing() {
        var ledger = MIDIOutLedger()
        _ = ledger.messages(for: [.on(c4, velocity: 90)])
        #expect(ledger.setChannel(ch1).isEmpty)
        #expect(ledger.notesDown == [c4])
    }
}

struct MIDIEventTimingTests {
    @Test func recentEventsKeepTheirAge() {
        let age = MIDIEventTiming.age(eventUptime: 100.0, nowUptime: 100.004)
        #expect(abs(age - 0.004) < 1e-9)
    }

    @Test func missingFutureOrOldEventsCountAsNow() {
        #expect(MIDIEventTiming.age(eventUptime: nil, nowUptime: 100) == 0)
        #expect(MIDIEventTiming.age(eventUptime: 100.01, nowUptime: 100) == 0)
        #expect(MIDIEventTiming.age(eventUptime: 99, nowUptime: 100) == 0)
    }

    @Test func hostTicks() {
        // Apple silicon's timebase is 125/3: one tick is 41.67 ns.
        #expect(MIDIEventTiming.hostTicks(forSeconds: 0.001, numerator: 125, denominator: 3) == 24_000)
        // A 1/1 timebase means ticks are nanoseconds.
        #expect(MIDIEventTiming.hostTicks(forSeconds: 0.004, numerator: 1, denominator: 1) == 4_000_000)
        #expect(MIDIEventTiming.hostTicks(forSeconds: 0, numerator: 1, denominator: 1) == 0)
        #expect(MIDIEventTiming.hostTicks(forSeconds: 0.001, numerator: 0, denominator: 1) == 0)
    }
}
