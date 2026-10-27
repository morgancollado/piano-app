import PianoCore
import SwiftUI

struct RootView: View {
    @Environment(PlaySession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false

    var body: some View {
        @Bindable var session = session

        // Using the system navigation bar means iPhone Duo moves these controls to the
        // vertical side bar automatically. Every item has a symbol and a title.
        NavigationStack {
            PlayScreen()
                .navigationTitle("Piano")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("Octave Down", systemImage: "chevron.left.2") {
                            session.shiftOctave(by: -1)
                        }
                        .disabled(!session.canShiftOctave(by: -1))

                        Button("Octave Up", systemImage: "chevron.right.2") {
                            session.shiftOctave(by: 1)
                        }
                        .disabled(!session.canShiftOctave(by: 1))
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Toggle(isOn: $session.sustainOn) {
                            Label("Sustain", systemImage: "waveform")
                        }
                        .toggleStyle(.button)

                        Button("Settings", systemImage: "gearshape") {
                            showingSettings = true
                        }
                    }
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsScreen()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: session.engine.start()
            case .background: session.engine.pause()
            default: break
            }
        }
    }
}
