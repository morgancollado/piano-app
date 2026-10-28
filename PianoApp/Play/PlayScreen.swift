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
            // Reads only the layout settings. What's playing is read further down, by the
            // views that show it, so playing a note never recomputes the key geometry.
            PlaySurface(
                surface: PlaySurfaceLayout(size: proxy.size, division: proxy.pianoDivision()),
                keyWidth: session.keyWidth,
                preferredLowestNote: session.preferredLowestNote,
                velocityMode: session.velocityMode,
                showsNoteLabels: session.showsNoteLabels
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(PianoTheme.body.ignoresSafeArea())
        // A piano always runs low notes on the left.
        .environment(\.layoutDirection, .leftToRight)
        // Swipes along the bottom edge should play keys before they open the Home Screen.
        .defersSystemGestures(on: .bottom)
        .persistentSystemOverlays(.hidden)
        .onHingeReading { session.hinge = $0 }
    }
}

/// Lays out the keys, the trail area and the content area. Its body runs only when the size,
/// the fold or a layout setting changes.
private struct PlaySurface: View {
    @Environment(PlaySession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let surface: PlaySurfaceLayout
    let keyWidth: Double
    let preferredLowestNote: Note
    let velocityMode: VelocityMode
    let showsNoteLabels: Bool

    var body: some View {
        let layout = KeyboardLayout(
            size: surface.keyboardRect.size,
            fold: surface.keyboardFold,
            targetWhiteKeyWidth: CGFloat(keyWidth),
            preferredLowestNote: preferredLowestNote
        )
        let trailClearDistance = NoteTrailsView.clearDistance(
            areaHeight: Double(surface.trailsRect?.height ?? 0),
            reduceMotion: reduceMotion
        )

        ZStack {
            if let trailsArea = surface.trailsRect {
                ZStack {
                    LinearGradient(colors: PianoTheme.standColors, startPoint: .top, endPoint: .bottom)
                    LiveTrails(keyFrames: layout.keyFrames(shiftedBy: surface.keyboardRect.minX - trailsArea.minX))
                }
                .frame(width: trailsArea.width, height: trailsArea.height)
                .clipped()
                .position(x: trailsArea.midX, y: trailsArea.midY)
            }

            if let content = surface.contentRect {
                LiveNoteDisplay(range: layout.noteRange)
                    .frame(width: content.width, height: content.height)
                    .position(x: content.midX, y: content.midY)
            }

            KeyboardView(
                layout: layout,
                velocityMode: velocityMode,
                showsNoteLabels: showsNoteLabels,
                onNoteEvents: { session.handle($0) }
            )
            .frame(width: surface.keyboardRect.width, height: surface.keyboardRect.height)
            .position(x: surface.keyboardRect.midX, y: surface.keyboardRect.midY)
        }
        .onChange(of: layout, initial: true) { _, layout in
            session.updateOctaveShifts(for: layout)
        }
        .onChange(of: trailClearDistance, initial: true) { _, distance in
            session.trailClearDistance = distance
        }
    }
}

/// The light trails. Observes the session itself, so each note redraws only this layer.
private struct LiveTrails: View {
    @Environment(PlaySession.self) private var session
    let keyFrames: [Note: CGRect]

    var body: some View {
        NoteTrailsView(trails: session.trails, keyFrames: keyFrames)
    }
}

/// The note names and sound status. Observes the session itself, like `LiveTrails`.
private struct LiveNoteDisplay: View {
    @Environment(PlaySession.self) private var session
    let range: ClosedRange<Note>?

    var body: some View {
        NoteDisplay(
            notes: session.soundingNotes,
            range: range,
            soundStatus: session.engine.statusMessage
        )
    }
}
