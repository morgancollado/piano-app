import CoreMIDI
import Foundation
import Observation
import os
import PianoCore

private let log = Logger(subsystem: "com.morgancollado.piano", category: "midi")

/// Sends the notes you play, the sustain pedal, and the Record/Play/Stop buttons to DAWs.
///
/// Two ways out, used together:
/// - A virtual MIDI source called "Piano", for apps on the same iPhone (GarageBand,
///   Cubasis, AUM). They read it as a MIDI input.
/// - Every external destination: Wi-Fi (the network session), a USB-C cable to a Mac (IDAM),
///   Bluetooth, and USB MIDI gear. Other apps' virtual inputs are skipped, because those
///   apps already read the "Piano" source and would otherwise get every note twice.
///
/// Note bookkeeping (re-strikes, stuck notes) is done by `MIDIOutLedger` in PianoCore.
@MainActor
@Observable
final class MIDIOutput {
    /// What's connected over Wi-Fi, a cable or Bluetooth, for the settings screen.
    private(set) var connectedNames: [String] = []
    var isConnected: Bool { !connectedNames.isEmpty }
    /// Set when CoreMIDI couldn't be set up, for the settings screen.
    private(set) var setupError: String?

    /// When false nothing is sent. Turning it off releases every note first.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue, !isEnabled else { return }
            deliver(ledger.releaseAll(), timeStamp: 0)
        }
    }

    /// Lets computers connect over Wi-Fi. Turning it on is what shows iOS's local network
    /// permission prompt, so it stays off until the player asks for it.
    var allowsNetworkConnections = false {
        didSet {
            guard allowsNetworkConnections != oldValue else { return }
            applyNetworkSetting()
        }
    }

    var channel: MIDIChannel { ledger.channel }

    @ObservationIgnored private var ledger = MIDIOutLedger()
    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var outputPort = MIDIPortRef()
    @ObservationIgnored private var virtualSource = MIDIEndpointRef()
    @ObservationIgnored private var networkObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
    @ObservationIgnored private let defaults: UserDefaults

    private static let sourceName = "Piano"
    private static let uniqueIDKey = "midiSourceUniqueID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        setUp()
    }

    // MARK: - Sending

    /// Sends the keyboard's note events.
    /// - Parameter eventUptime: when the touches happened (`UIEvent.timestamp`), so the DAW
    ///   can place the notes where the finger landed. Nil means now.
    func send(_ events: [NoteEvent], eventUptime: TimeInterval? = nil) {
        guard isEnabled else { return }
        deliver(ledger.messages(for: events), timeStamp: timeStamp(forEventUptime: eventUptime))
    }

    func sendSustain(_ down: Bool) {
        guard isEnabled else { return }
        deliver(ledger.sustain(down), timeStamp: 0)
    }

    func setChannel(_ newChannel: MIDIChannel) {
        let messages = ledger.setChannel(newChannel)
        guard isEnabled else { return }
        deliver(messages, timeStamp: 0)
    }

    /// Ends every note the DAW thinks is down and lifts the pedal.
    func releaseAll() {
        let messages = ledger.releaseAll()
        guard isEnabled else { return }
        deliver(messages, timeStamp: 0)
    }

    func send(_ command: TransportCommand, mode: TransportMode) {
        guard isEnabled else { return }
        deliver(mode.messages(for: command), timeStamp: 0)
        log.notice("Sent \(command.rawValue, privacy: .public) (\(mode.rawValue, privacy: .public))")
    }

    // MARK: - CoreMIDI

    private func setUp() {
        let notify = Self.makeNotifyBlock { [weak self] in
            Task { @MainActor in self?.refreshConnections() }
        }
        var status = MIDIClientCreateWithBlock(Self.sourceName as CFString, &client, notify)
        guard status == noErr else {
            fail("Couldn't start MIDI (error \(status))")
            return
        }
        status = MIDIOutputPortCreate(client, "Piano Out" as CFString, &outputPort)
        guard status == noErr else {
            fail("Couldn't create the MIDI output (error \(status))")
            return
        }
        status = MIDISourceCreateWithProtocol(client, Self.sourceName as CFString, ._1_0, &virtualSource)
        guard status == noErr else {
            fail("Couldn't create the Piano MIDI source (error \(status))")
            return
        }
        keepUniqueID()

        networkObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(MIDINetworkNotificationSessionDidChange), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnections() }
        }
        refreshConnections()
        log.notice("MIDI ready: source \"\(Self.sourceName, privacy: .public)\"")
    }

    /// CoreMIDI calls the notify block on its own thread. Building the block outside the main
    /// actor keeps Swift from treating it as main-actor code and stopping the app when it runs.
    nonisolated private static func makeNotifyBlock(_ handler: @escaping @Sendable () -> Void) -> MIDINotifyBlock {
        { _ in handler() }
    }

    /// Gives the "Piano" source the same ID every launch, so DAWs that remember inputs by ID
    /// find it again. Apple's guidance for virtual endpoints.
    private func keepUniqueID() {
        let saved = Int32(truncatingIfNeeded: defaults.integer(forKey: Self.uniqueIDKey))
        if saved != 0, MIDIObjectSetIntegerProperty(virtualSource, kMIDIPropertyUniqueID, saved) == noErr {
            return
        }
        // Nothing saved yet, or the saved ID is taken: keep the one CoreMIDI assigned.
        var assigned: Int32 = 0
        if MIDIObjectGetIntegerProperty(virtualSource, kMIDIPropertyUniqueID, &assigned) == noErr {
            defaults.set(Int(assigned), forKey: Self.uniqueIDKey)
        }
    }

    private func fail(_ message: String) {
        setupError = message
        log.error("\(message, privacy: .public)")
    }

    private func deliver(_ messages: [MIDIMessage], timeStamp: MIDITimeStamp) {
        guard !messages.isEmpty, setupError == nil else { return }

        let wordCount = messages.reduce(0) { $0 + $1.umpWords.count }
        // Room for the list header, a packet header per message in the worst case, and the words.
        let byteCount = MemoryLayout<MIDIEventList>.size + messages.count * 16 + wordCount * 4
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { buffer.deallocate() }
        let list = buffer.bindMemory(to: MIDIEventList.self, capacity: 1)

        var packet: UnsafeMutablePointer<MIDIEventPacket>? = MIDIEventListInit(list, ._1_0)
        for message in messages {
            let words = message.umpWords
            guard let current = packet else { break }
            packet = words.withUnsafeBufferPointer { pointer in
                MIDIEventListAdd(list, byteCount, current, timeStamp, pointer.count, pointer.baseAddress!)
            }
        }
        guard packet != nil else {
            log.error("MIDI messages didn't fit in the event list; nothing sent")
            return
        }

        // Apps on this iPhone that read the "Piano" source.
        MIDIReceivedEventList(virtualSource, list)
        // Wi-Fi, cable, Bluetooth and USB MIDI gear.
        for destination in externalDestinations() {
            MIDISendEventList(outputPort, destination, list)
        }
    }

    /// A timestamp for notes played `eventUptime` ago, or 0 (now) if it's missing or odd.
    private func timeStamp(forEventUptime eventUptime: TimeInterval?) -> MIDITimeStamp {
        let now = mach_absolute_time()
        let age = MIDIEventTiming.age(eventUptime: eventUptime, nowUptime: ProcessInfo.processInfo.systemUptime)
        guard age > 0 else { return 0 }
        let ticks = MIDIEventTiming.hostTicks(forSeconds: age, numerator: timebase.numer, denominator: timebase.denom)
        return ticks < now ? now - ticks : 0
    }

    // MARK: - Destinations and connections

    /// Destinations that belong to a device (network session, IDAM, Bluetooth, USB). Other
    /// apps' virtual inputs have no device, and those apps read the "Piano" source instead.
    private func externalDestinations() -> [MIDIEndpointRef] {
        (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let destination = MIDIGetDestination(index)
            guard destination != 0, Self.belongsToDevice(destination) else { return nil }
            return destination
        }
    }

    private func refreshConnections() {
        var names: [String] = []

        let session = MIDINetworkSession.default()
        let networkDestination = session.isEnabled ? session.destinationEndpoint() : 0
        if session.isEnabled {
            names += session.connections().map { $0.host.name }
        }
        // The network session's endpoint exists whenever the session is on, connected or
        // not, so it's counted through `connections()` above instead.
        for destination in externalDestinations() where destination != networkDestination {
            guard !Self.isOffline(destination), let name = Self.displayName(of: destination) else { continue }
            names.append(name)
        }

        let sorted = names.sorted()
        if sorted != connectedNames {
            connectedNames = sorted
            let list = sorted.joined(separator: ", ")
            log.notice("MIDI connections: \(list.isEmpty ? "none" : list, privacy: .public)")
        }
    }

    private func applyNetworkSetting() {
        let session = MIDINetworkSession.default()
        session.isEnabled = allowsNetworkConnections
        if allowsNetworkConnections {
            // Any computer on the same Wi-Fi may connect, as with a hardware network MIDI device.
            session.connectionPolicy = .anyone
            log.notice("Network MIDI on as \"\(session.networkName, privacy: .public)\"")
        } else {
            log.notice("Network MIDI off")
        }
        refreshConnections()
    }

    nonisolated private static func belongsToDevice(_ endpoint: MIDIEndpointRef) -> Bool {
        var entity = MIDIEntityRef()
        return MIDIEndpointGetEntity(endpoint, &entity) == noErr && entity != 0
    }

    nonisolated private static func isOffline(_ object: MIDIObjectRef) -> Bool {
        var offline: Int32 = 0
        return MIDIObjectGetIntegerProperty(object, kMIDIPropertyOffline, &offline) == noErr && offline != 0
    }

    nonisolated private static func displayName(of object: MIDIObjectRef) -> String? {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &name) == noErr, let name else {
            return nil
        }
        return name.takeRetainedValue() as String
    }
}
