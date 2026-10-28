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
                .font(.system(size: 46, weight: .medium, design: .rounded))
                .foregroundStyle(PianoTheme.noteText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .shadow(color: .black.opacity(0.6), radius: 8)

            if let range {
                Text("\(range.lowerBound.name) – \(range.upperBound.name)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(PianoTheme.noteText.opacity(0.45))
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
