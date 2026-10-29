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
                    // Record, Play and Stop for a connected DAW. Only shown while it can
                    // reach one (see the settings), so the bar stays short otherwise.
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if session.showsTransportButtons {
                            Button("Record", systemImage: "record.circle") {
                                session.sendTransport(.record)
                            }
                            .tint(PianoTheme.recordButton)
                            .accessibilityHint("Starts recording in your music app")

                            Button("Play", systemImage: "play.fill") {
                                session.sendTransport(.play)
                            }
                            .accessibilityHint("Plays in your music app")

                            Button("Stop", systemImage: "stop.fill") {
                                session.sendTransport(.stop)
                            }
                            .accessibilityHint("Stops your music app")
                        }
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
        // The instrument is always dark, like a piano's black lacquer.
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            SettingsScreen()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: session.didBecomeActive()
            case .background: session.didEnterBackground()
            default: break
            }
        }
    }
}
