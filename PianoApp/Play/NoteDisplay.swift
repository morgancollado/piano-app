import PianoCore
import SwiftUI

/// Shows the notes being played, and the keyboard's range when nothing is playing.
struct NoteDisplay: View {
    let notes: Set<Note>
    let range: ClosedRange<Note>?
    /// Shown when sound isn't working, so a silent keyboard is never a mystery.
    var soundStatus: String? = nil

    /// Follows the Dynamic Type setting; the note line still shrinks to fit its width.
    @ScaledMetric(relativeTo: .largeTitle) private var noteSize: CGFloat = 46

    var body: some View {
        VStack(spacing: 8) {
            Text(notes.isEmpty ? " " : notes.sorted().map(\.name).joined(separator: "  "))
                .font(.system(size: noteSize, weight: .medium, design: .rounded))
                .foregroundStyle(PianoTheme.noteText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .shadow(color: PianoTheme.noteTextShadow, radius: 8)

            if let range {
                Text("\(range.lowerBound.name) – \(range.upperBound.name)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(PianoTheme.noteText.opacity(0.45))
            }

            if let soundStatus {
                Label(soundStatus, systemImage: "speaker.slash")
                    .font(.footnote)
                    .foregroundStyle(PianoTheme.soundWarning)
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
