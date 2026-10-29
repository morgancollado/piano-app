import PianoCore
import SwiftUI

struct SettingsScreen: View {
    @Environment(PlaySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showingBluetooth = false

    var body: some View {
        @Bindable var session = session

        NavigationStack {
            Form {
                Section("Keys") {
                    LabeledContent("Key size") {
                        Slider(
                            value: $session.keyWidth,
                            in: Double(KeyboardLayout.whiteKeyWidthRange.lowerBound)...Double(KeyboardLayout.whiteKeyWidthRange.upperBound),
                            step: 2
                        )
                    }
                    Picker("Touch strength", selection: $session.velocityMode) {
                        Text("Always the same").tag(VelocityMode.fixed)
                        Text("Lower on the key is louder").tag(VelocityMode.touchPosition)
                    }
                    Toggle("Show note names", isOn: $session.showsNoteLabels)
                }

                Section {
                    LabeledContent("Tone") {
                        Slider(value: $session.toneBrightness, in: 0...1) {
                            Text("Tone")
                        } minimumValueLabel: {
                            Image(systemName: "speaker.wave.1")
                        } maximumValueLabel: {
                            Image(systemName: "sparkles")
                        }
                    }
                    LabeledContent("Room") {
                        Slider(value: $session.reverbMix, in: 0...0.6)
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    if let status = session.engine.statusMessage {
                        Text(status)
                    }
                }

                midiSection(session: session)

                Section {
                    Toggle("Hinge controls tone", isOn: $session.hingeControlsTone)
                } header: {
                    Text("iPhone Duo")
                } footer: {
                    Text("When the phone is partly folded, closing it makes the sound softer and darker, like lowering a piano lid.")
                }

                Section("Credits") {
                    Text("Piano sound: Salamander Grand Piano, a Yamaha C5 recorded by Alexander Holm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .sheet(isPresented: $showingBluetooth) {
                BluetoothMIDISheet()
                    .preferredColorScheme(.dark)
            }
        }
    }

    /// Sending what you play to a DAW (Reaper, Logic, GarageBand and others).
    @ViewBuilder
    private func midiSection(session: PlaySession) -> some View {
        @Bindable var session = session

        Section {
            Toggle("Send notes as MIDI", isOn: $session.midiEnabled)

            if session.midiEnabled {
                Picker("MIDI channel", selection: $session.midiChannel) {
                    ForEach(MIDIChannel.noteChoices) { channel in
                        Text(String(channel.number)).tag(channel)
                    }
                }
                Toggle("Play sound in this app", isOn: $session.playsSoundLocally)
                Toggle("Allow Wi-Fi connections", isOn: $session.allowsNetworkMIDI)
                Button("Connect over Bluetooth…", systemImage: "dot.radiowaves.left.and.right") {
                    showingBluetooth = true
                }

                LabeledContent("Connected") {
                    if session.midi.connectedNames.isEmpty {
                        Text("Nothing connected")
                    } else {
                        Text(session.midi.connectedNames.joined(separator: ", "))
                    }
                }

                Picker("Record, Play and Stop", selection: $session.transportVisibility) {
                    Text("When connected").tag(TransportVisibility.whenConnected)
                    Text("Always").tag(TransportVisibility.always)
                    Text("Never").tag(TransportVisibility.never)
                }
                Picker("Button messages", selection: $session.transportMode) {
                    Text("Learnable (MIDI learn)").tag(TransportMode.learnable)
                    Text("MIDI Machine Control").tag(TransportMode.machineControl)
                }

                NavigationLink {
                    ReaperSetupView()
                } label: {
                    Label("Set Up Reaper", systemImage: "questionmark.circle")
                }

                Button("Stop All Notes", systemImage: "speaker.slash") {
                    session.stopAllNotes()
                }
            }
        } header: {
            Text("Recording Apps (MIDI)")
        } footer: {
            if let error = session.midi.setupError {
                Text(error)
            } else if session.midiEnabled {
                Text("Apps on this iPhone see an input called Piano. A Mac connects over Wi-Fi (Audio MIDI Setup → MIDI Studio → Network), a USB-C cable (Audio MIDI Setup → Audio Devices → Enable), or Bluetooth. Turn off Play sound in this app when your DAW plays the notes.")
            }
        }
    }
}
