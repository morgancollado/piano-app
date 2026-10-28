import PianoCore
import SwiftUI

/// The main playing surface: a note display and the keyboard.
///
/// Sizes come only from the space this view is given (never the screen or device model),
/// so it adapts to every iPhone, both iPhone Duo displays, every pose, and Split View.
struct PlayScreen: View {
    @Environment(PlaySession.self) private var session

    var body: some View {
        GeometryReader { proxy in
            let surface = PlaySurfaceLayout(size: proxy.size, division: proxy.pianoDivision())
            let layout = KeyboardLayout(
                size: surface.keyboardRect.size,
                fold: surface.keyboardFold,
                targetWhiteKeyWidth: CGFloat(session.keyWidth),
                preferredLowestNote: session.preferredLowestNote
            )

            ZStack {
                if let content = surface.contentRect {
                    NoteDisplay(
                        notes: session.soundingNotes,
                        range: layout.noteRange,
                        soundStatus: session.engine.statusMessage
                    )
                        .frame(width: content.width, height: content.height)
                        .position(x: content.midX, y: content.midY)
                }

                KeyboardView(
                    layout: layout,
                    velocityMode: session.velocityMode,
                    showsNoteLabels: session.showsNoteLabels,
                    onNoteEvents: { session.handle($0) }
                )
                .frame(width: surface.keyboardRect.width, height: surface.keyboardRect.height)
                .position(x: surface.keyboardRect.midX, y: surface.keyboardRect.midY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // A piano always runs low notes on the left.
        .environment(\.layoutDirection, .leftToRight)
        // Swipes along the bottom edge should play keys before they open the Home Screen.
        .defersSystemGestures(on: .bottom)
        .persistentSystemOverlays(.hidden)
        .onHingeReading { session.hinge = $0 }
    }
}
