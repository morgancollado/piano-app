import PianoCore
import SwiftUI

/// Soft light trails rising from each played key. Animates only while there are trails.
///
/// With Reduce Motion on, nothing rises: a held key shows a still glow above it, which
/// fades out when the key is released.
struct NoteTrailsView: View {
    let trails: NoteTrails
    /// Each key's frame in this view's coordinates (only the horizontal position is used).
    let keyFrames: [Note: CGRect]
    var speed = NoteTrails.defaultSpeed

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Above this many trails the blurred glow is skipped to keep drawing light.
    private let glowLimit = 16
    /// Reduce Motion: how long a released key's glow takes to fade.
    nonisolated static let reducedMotionFadeSeconds = 0.35

    /// How far a released trail must rise before it can be removed: the height of the trail
    /// area, or with Reduce Motion, however far it would have risen while it fades.
    static func clearDistance(areaHeight: Double, reduceMotion: Bool,
                              speed: Double = NoteTrails.defaultSpeed) -> Double {
        reduceMotion ? reducedMotionFadeSeconds * speed : max(0, areaHeight)
    }

    private var isStill: Bool {
        // With Reduce Motion, held glows don't change, so there's nothing to animate until a
        // key is released.
        trails.isEmpty || (reduceMotion && trails.trails.allSatisfy { $0.end == nil })
    }

    var body: some View {
        // Plain values for the drawing closure.
        let trails = self.trails
        let keyFrames = self.keyFrames
        let speed = self.speed
        let reduceMotion = self.reduceMotion
        let drawGlow = trails.trails.count <= glowLimit

        TimelineView(.animation(minimumInterval: nil, paused: isStill)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                for trail in trails.trails {
                    guard let key = keyFrames[trail.note] else { continue }
                    let width = key.width * (trail.note.isBlack ? 0.8 : 0.6)
                    // Louder notes glow brighter.
                    let strength = 0.45 + 0.55 * Double(trail.velocity) / 127

                    let rect: CGRect
                    let alpha: Double
                    if reduceMotion {
                        let fade = trail.end.map { 1 - (now - $0) / Self.reducedMotionFadeSeconds } ?? 1
                        guard fade > 0 else { continue }
                        let height = min(size.height, max(60, size.height * 0.45))
                        rect = CGRect(x: key.midX - width / 2, y: size.height - height, width: width, height: height)
                        alpha = 0.9 * strength * min(fade, 1)
                    } else {
                        let extent = trail.extent(at: now, speed: speed)
                        let bottom = size.height - extent.bottom
                        let top = max(size.height - extent.top, -40)
                        guard bottom > 0, bottom > top else { continue }
                        rect = CGRect(x: key.midX - width / 2, y: top, width: width, height: bottom - top)
                        // Trails fade as they rise.
                        alpha = 0.9 * strength * min(max(bottom / size.height, 0), 1)
                    }
                    Self.draw(rect, width: width, color: PianoTheme.trailColor(for: trail.note.midiNumber),
                              alpha: alpha, glow: drawGlow, in: &context)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    nonisolated private static func draw(_ rect: CGRect, width: CGFloat, color: Color, alpha: Double,
                                         glow: Bool, in context: inout GraphicsContext) {
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [color.opacity(0), color.opacity(alpha)]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
        )
        if glow {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: width * 0.6))
                layer.fill(Path(roundedRect: rect.insetBy(dx: -width * 0.35, dy: 0),
                                cornerRadius: width), with: shading)
            }
        }
        context.fill(Path(roundedRect: rect, cornerRadius: min(width / 2, 8)), with: shading)
    }
}
