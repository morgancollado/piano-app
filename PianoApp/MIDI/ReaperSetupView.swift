import PianoCore
import SwiftUI

/// Step-by-step help for recording into Reaper on a Mac.
struct ReaperSetupView: View {
    @Environment(PlaySession.self) private var session

    var body: some View {
        Form {
            Section("1. Connect the iPhone") {
                step("Wi-Fi", "Turn on Allow Wi-Fi connections in Settings. On the Mac, open Audio MIDI Setup → Window → Show MIDI Studio → Network (globe button). Add a session under My Sessions and tick Enabled, then select this iPhone under Directory and click Connect.")
                step("Cable", "Connect the iPhone to the Mac with a USB-C cable. In Audio MIDI Setup → Audio Devices, click Enable under the iPhone.")
                step("Bluetooth", "Tap Connect over Bluetooth in Settings and keep it open. On the Mac: Audio MIDI Setup → Window → Show MIDI Studio → Bluetooth button → Connect.")
            }

            Section("2. Turn on the input in Reaper") {
                Text("Reaper → Settings (⌘,) → Audio → MIDI Inputs (MIDI Devices in older versions). Right-click the iPhone's input (\"Network Session 1\" for Wi-Fi) and choose Enable input. Right-click it again and choose Enable input for control messages, so the Record, Play and Stop buttons work. If it isn't listed, close and reopen Settings.")
            }

            Section("3. Record notes") {
                Text("Add a track and arm it. Set its input to the iPhone's MIDI input, channel \(session.midiChannel.number). Picking that one channel keeps the button presses, sent on channel \(MIDIChannel.transport.number), out of your take. Add an instrument to the track to hear it.")
            }

            Section("4. Link the buttons") {
                switch session.transportMode {
                case .learnable:
                    Text("Actions → Show action list. Find Transport: Record, click Add…, tap Record in this app, then OK. Do the same for Transport: Play and Transport: Stop. Reaper keeps these for every project.")
                case .machineControl:
                    Text("The buttons send MIDI Machine Control. Reaper only reacts to it on an input with control messages turned on (step 2), and may need you to press Play in Reaper once first. If the buttons don't work, switch Button messages to Learnable in Settings and follow the steps shown here.")
                }
            }

            Section {
                Toggle("Play sound in this app", isOn: Bindable(session).playsSoundLocally)
            } header: {
                Text("5. Listen through Reaper")
            } footer: {
                Text("Turn this off when Reaper plays the notes, so you don't hear two pianos.")
            }
        }
        .navigationTitle("Set Up Reaper")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text)
        }
    }
}
