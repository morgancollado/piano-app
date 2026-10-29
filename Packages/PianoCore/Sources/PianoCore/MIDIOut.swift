import Foundation

// MIDI out: what the app sends to a DAW or other recording app. Everything here is plain
// data, so it's tested on any platform. The app's `MIDIOutput` hands the words to CoreMIDI.

/// A MIDI channel. Stored as 0–15, shown to people as 1–16.
public struct MIDIChannel: Hashable, Comparable, Sendable, Identifiable, CustomStringConvertible {
    /// 0–15, as it goes into the status byte.
    public let index: UInt8

    /// - Parameter number: 1–16, as people count channels.
    public init?(number: Int) {
        guard (1...16).contains(number) else { return nil }
        index = UInt8(number - 1)
    }

    /// 1–16.
    public var number: Int { Int(index) + 1 }
    public var id: Int { number }
    public var description: String { String(number) }

    public static func < (lhs: MIDIChannel, rhs: MIDIChannel) -> Bool { lhs.index < rhs.index }

    /// Channel 1, where notes go unless the player picks another.
    public static let defaultNotes = MIDIChannel(number: 1)!
    /// Channel 16 carries the Record, Play and Stop buttons, so a DAW track that listens to
    /// the notes' channel never records a button press.
    public static let transport = MIDIChannel(number: 16)!
    /// The channels notes can use: every channel except the buttons' one.
    public static let noteChoices: [MIDIChannel] = (1...15).compactMap(MIDIChannel.init(number:))
}

/// MIDI Machine Control commands, the standard transport messages some DAWs accept.
public enum MachineControlCommand: UInt8, Sendable, CaseIterable {
    case stop = 0x01
    case play = 0x02
    /// "Record strobe": start recording.
    case record = 0x06
}

/// One MIDI 1.0 message.
public enum MIDIMessage: Equatable, Sendable {
    case noteOn(Note, velocity: UInt8, channel: MIDIChannel)
    case noteOff(Note, channel: MIDIChannel)
    case controlChange(UInt8, value: UInt8, channel: MIDIChannel)
    /// Sent to every device ("all call", device ID 0x7F).
    case machineControl(MachineControlCommand)

    public static let sustainController: UInt8 = 64
    public static let allNotesOffController: UInt8 = 123

    /// The message as MIDI 1.0 bytes, the form DAW manuals and MIDI monitors show.
    public var bytes: [UInt8] {
        switch self {
        case let .noteOn(note, velocity, channel):
            // Velocity 0 would mean note off, so a note on is never quieter than 1.
            [0x90 | channel.index, note.midiByte, min(max(velocity, 1), 127)]
        case let .noteOff(note, channel):
            [0x80 | channel.index, note.midiByte, 0]
        case let .controlChange(controller, value, channel):
            [0xB0 | channel.index, min(controller, 127), min(value, 127)]
        case let .machineControl(command):
            [0xF0] + Self.machineControlData(command) + [0xF7]
        }
    }

    /// The message as Universal MIDI Packet words (MIDI 1.0 protocol, group 0), the form
    /// CoreMIDI's `MIDIEventList` takes.
    public var umpWords: [UInt32] {
        switch self {
        case .noteOn, .noteOff, .controlChange:
            // Message type 2: a MIDI 1.0 channel voice message in one 32-bit word.
            let b = bytes
            return [0x2000_0000 | UInt32(b[0]) << 16 | UInt32(b[1]) << 8 | UInt32(b[2])]
        case let .machineControl(command):
            // Message type 3: 7-bit system exclusive in one 64-bit packet. The status nibble
            // 0 means "complete in this packet". F0 and F7 are left out; the byte count says
            // how many of the six data slots are used.
            let data = Self.machineControlData(command)
            var slots = [UInt8](repeating: 0, count: 6)
            for (i, byte) in data.enumerated() { slots[i] = byte }
            let first = 0x3000_0000 | UInt32(data.count) << 16 | UInt32(slots[0]) << 8 | UInt32(slots[1])
            let second = UInt32(slots[2]) << 24 | UInt32(slots[3]) << 16 | UInt32(slots[4]) << 8 | UInt32(slots[5])
            return [first, second]
        }
    }

    private static func machineControlData(_ command: MachineControlCommand) -> [UInt8] {
        // Real-time universal SysEx, all devices, MMC command.
        [0x7F, 0x7F, 0x06, command.rawValue]
    }
}

// MARK: - Transport buttons

/// The app's Record, Play and Stop buttons.
public enum TransportCommand: String, CaseIterable, Sendable, Identifiable {
    case record, play, stop

    public var id: String { rawValue }

    /// The control change each button sends in learnable mode. 117–119 are in the range MIDI
    /// leaves unassigned (102–119), so no DAW gives them a meaning of its own.
    public var learnableController: UInt8 {
        switch self {
        case .record: 117
        case .play: 118
        case .stop: 119
        }
    }

    var machineControl: MachineControlCommand {
        switch self {
        case .record: .record
        case .play: .play
        case .stop: .stop
        }
    }
}

/// Which messages the transport buttons send. Only one kind at a time: a DAW that answered
/// both would act twice, and a doubled Record can start and stop recording at once.
public enum TransportMode: String, CaseIterable, Sendable, Identifiable {
    /// Control changes on channel 16 that the player links to the DAW's commands once, with
    /// the DAW's MIDI learn. Works with most DAWs.
    case learnable
    /// MIDI Machine Control. No setup in DAWs that accept it.
    case machineControl

    public var id: String { rawValue }

    /// What one tap of a button sends.
    public func messages(for command: TransportCommand) -> [MIDIMessage] {
        switch self {
        case .learnable:
            // Press then release, like a quick tap on a hardware button.
            let controller = command.learnableController
            return [
                .controlChange(controller, value: 127, channel: .transport),
                .controlChange(controller, value: 0, channel: .transport),
            ]
        case .machineControl:
            return [.machineControl(command.machineControl)]
        }
    }
}

/// When the transport buttons are shown.
public enum TransportVisibility: String, CaseIterable, Sendable, Identifiable {
    /// While a computer or other device is connected over Wi-Fi, a cable or Bluetooth.
    case whenConnected
    /// Also useful for a DAW on the same iPhone, which iOS doesn't report as a connection.
    case always
    case never

    public var id: String { rawValue }

    public func showsButtons(isConnected: Bool) -> Bool {
        switch self {
        case .whenConnected: isConnected
        case .always: true
        case .never: false
        }
    }
}

// MARK: - Notes

/// Turns the keyboard's note events into MIDI messages and remembers which notes the DAW
/// thinks are down, so a recording never ends up with overlapping or stuck notes.
public struct MIDIOutLedger: Sendable {
    public private(set) var channel: MIDIChannel
    /// Notes the DAW has had a note on for and no note off yet.
    public private(set) var notesDown: Set<Note> = []
    /// Whether the DAW last heard the sustain pedal go down.
    public private(set) var sustainDown = false

    public init(channel: MIDIChannel = .defaultNotes) {
        self.channel = channel
    }

    public mutating func messages(for events: [NoteEvent]) -> [MIDIMessage] {
        var messages: [MIDIMessage] = []
        for event in events {
            switch event.kind {
            case .on:
                // A second finger on a key that's already down re-strikes it. The keyboard
                // sends on, on, off for that, which a DAW can record as two overlapping notes
                // with one left hanging. End the first note before starting the second.
                if notesDown.contains(event.note) {
                    messages.append(.noteOff(event.note, channel: channel))
                }
                messages.append(.noteOn(event.note, velocity: event.velocity, channel: channel))
                notesDown.insert(event.note)
            case .off:
                if notesDown.remove(event.note) != nil {
                    messages.append(.noteOff(event.note, channel: channel))
                }
            }
        }
        return messages
    }

    public mutating func sustain(_ down: Bool) -> [MIDIMessage] {
        sustainDown = down
        return [.controlChange(MIDIMessage.sustainController, value: down ? 127 : 0, channel: channel)]
    }

    /// Ends every note: a note off for each note down, then pedal up and All Notes Off as a
    /// safety net. Always sends the last two, so it also clears a note some earlier
    /// connection left hanging.
    public mutating func releaseAll() -> [MIDIMessage] {
        var messages: [MIDIMessage] = notesDown.sorted().map { .noteOff($0, channel: channel) }
        messages.append(.controlChange(MIDIMessage.sustainController, value: 0, channel: channel))
        messages.append(.controlChange(MIDIMessage.allNotesOffController, value: 0, channel: channel))
        notesDown.removeAll()
        sustainDown = false
        return messages
    }

    /// Moves to another channel. Notes and the pedal are released on the old channel first,
    /// and the pedal goes down again on the new one if it was down.
    public mutating func setChannel(_ newChannel: MIDIChannel) -> [MIDIMessage] {
        guard newChannel != channel else { return [] }
        let wasSustained = sustainDown
        var messages = releaseAll()
        channel = newChannel
        if wasSustained {
            messages += sustain(true)
        }
        return messages
    }
}

// MARK: - Timing

/// Places notes in a recording where the finger landed rather than when the app got round to
/// sending them.
public enum MIDIEventTiming {
    /// Older touches than this are sent as "now". Bounds the damage if a clock is ever off.
    public static let maximumAge: TimeInterval = 0.05

    /// How long ago an event happened, in seconds, given its time and the current time on
    /// the same clock (seconds since the device started, as touch events and
    /// `ProcessInfo.systemUptime` use). Returns 0, meaning "send as now", when the event
    /// time is missing, in the future, or older than `maximumAge`.
    public static func age(eventUptime: TimeInterval?, nowUptime: TimeInterval) -> TimeInterval {
        guard let eventUptime else { return 0 }
        let age = nowUptime - eventUptime
        guard age > 0, age <= maximumAge else { return 0 }
        return age
    }

    /// Converts an age in seconds to host-clock ticks, given the host clock's timebase
    /// (ticks × numerator / denominator = nanoseconds).
    public static func hostTicks(forSeconds seconds: TimeInterval, numerator: UInt32, denominator: UInt32) -> UInt64 {
        guard seconds > 0, numerator > 0, denominator > 0 else { return 0 }
        let nanoseconds = seconds * 1_000_000_000
        return UInt64((nanoseconds * Double(denominator) / Double(numerator)).rounded())
    }
}
