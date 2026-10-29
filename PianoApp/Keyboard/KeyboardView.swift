import PianoCore
import SwiftUI

/// SwiftUI wrapper for `KeyboardUIView`. Give it the same size its layout was computed for.
struct KeyboardView: UIViewRepresentable {
    let layout: KeyboardLayout
    var velocityMode: VelocityMode = .fixed
    var showsNoteLabels = true
    /// Note events and when their touches happened (see `KeyboardUIView.onNoteEvents`).
    let onNoteEvents: ([NoteEvent], TimeInterval?) -> Void

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
