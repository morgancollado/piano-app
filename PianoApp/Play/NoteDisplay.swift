import PianoCore
import SwiftUI

/// Shows the notes being played, and the keyboard's range when nothing is playing.
struct NoteDisplay: View {
    let notes: Set<Note>
    let range: ClosedRange<Note>?
    /// Shown when sound isn't working, so a silent keyboard is never a mystery.
    var soundStatus: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Text(notes.isEmpty ? " " : notes.sorted().map(\.name).joined(separator: "  "))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            if let range {
                Text("\(range.lowerBound.name) – \(range.upperBound.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let soundStatus {
                Label(soundStatus, systemImage: "speaker.slash")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NoteDisplay(
        notes: [.middleC, Note(midiNumber: 64)],
        range: Note.middleC...Note(midiNumber: 83),
        soundStatus: "Sound isn't working: example"
    )
}
