import PianoCore
import SwiftUI

/// SwiftUI wrapper for `KeyboardUIView`. Give it the same size its layout was computed for.
struct KeyboardView: UIViewRepresentable {
    let layout: KeyboardLayout
    var velocityMode: VelocityMode = .fixed
    var showsNoteLabels = true
    let onNoteEvents: ([NoteEvent]) -> Void

    func makeUIView(context: Context) -> KeyboardUIView {
        KeyboardUIView(frame: .zero)
    }

    func updateUIView(_ view: KeyboardUIView, context: Context) {
        view.layout = layout
        view.velocityMode = velocityMode
        view.showsNoteLabels = showsNoteLabels
        view.onNoteEvents = onNoteEvents
    }
}
