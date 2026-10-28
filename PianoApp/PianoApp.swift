import SwiftUI

@main
struct PianoApp: App {
    @State private var session = PlaySession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
