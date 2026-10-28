import PianoCore
import SwiftUI

/// Soft light trails rising from each played key. Animates only while there are trails.
struct NoteTrailsView: View {
    let trails: NoteTrails
    /// Each key's frame in this view's coordinates (only the horizontal position is used).
    let keyFrames: [Note: CGRect]
    var speed = NoteTrails.defaultSpeed

    /// Above this many trails the blurred glow is skipped to keep drawing light.
    private let glowLimit = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: trails.isEmpty)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let drawGlow = trails.trails.count <= glowLimit
                for trail in trails.trails {
                    guard let key = keyFrames[trail.note] else { continue }
                    let extent = trail.extent(at: now, speed: speed)
                    let bottom = size.height - extent.bottom
                    let top = max(size.height - extent.top, -40)
                    guard bottom > 0, bottom > top else { continue }

                    let width = key.width * (trail.note.isBlack ? 0.8 : 0.6)
                    let rect = CGRect(x: key.midX - width / 2, y: top, width: width, height: bottom - top)
                    // Louder notes glow brighter; trails fade as they rise.
                    let strength = 0.45 + 0.55 * Double(trail.velocity) / 127
                    let fade = min(max(bottom / size.height, 0), 1)
                    let color = PianoTheme.trailColor(for: trail.note.midiNumber)
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [color.opacity(0), color.opacity(0.9 * strength * fade)]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                    )
                    if drawGlow {
                        context.drawLayer { glow in
                            glow.addFilter(.blur(radius: width * 0.6))
                            glow.fill(Path(roundedRect: rect.insetBy(dx: -width * 0.35, dy: 0),
                                           cornerRadius: width), with: shading)
                        }
                    }
                    context.fill(Path(roundedRect: rect, cornerRadius: min(width / 2, 8)), with: shading)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
