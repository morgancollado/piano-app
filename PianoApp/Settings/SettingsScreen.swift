import PianoCore
import SwiftUI

struct SettingsScreen: View {
    @Environment(PlaySession.self) private var session
    @Environment(\.dismiss) private var dismiss

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
        }
    }
}
