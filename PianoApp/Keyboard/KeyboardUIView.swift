import PianoCore
import UIKit

/// The playable keyboard. UIKit is used here because each finger needs its own
/// touch tracking (chords, glissando, cancelled touches), which SwiftUI gestures handle poorly.
final class KeyboardUIView: UIView {
    var layout: KeyboardLayout? {
        didSet { if layout != oldValue { setNeedsDisplay() } }
    }
    var velocityMode: VelocityMode = .fixed
    var showsNoteLabels = true {
        didSet { if showsNoteLabels != oldValue { setNeedsDisplay() } }
    }
    var onNoteEvents: (([NoteEvent]) -> Void)?

    private var tracker = TouchTracker<ObjectIdentifier>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = .black
        contentMode = .redraw

        // Lets VoiceOver users play the keys directly.
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
        accessibilityLabel = String(localized: "Piano keyboard")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        var events: [NoteEvent] = []
        for touch in touches {
            let (note, velocity) = noteAndVelocity(for: touch)
            events += tracker.begin(ObjectIdentifier(touch), on: note, velocity: velocity)
        }
        send(events)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var events: [NoteEvent] = []
        for touch in touches {
            let (note, velocity) = noteAndVelocity(for: touch)
            events += tracker.move(ObjectIdentifier(touch), to: note, velocity: velocity)
        }
        send(events)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        send(touches.flatMap { tracker.end(ObjectIdentifier($0)) })
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Cancelled touches (folding mid-note, a system gesture) must still stop their notes.
        send(touches.flatMap { tracker.end(ObjectIdentifier($0)) })
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            send(tracker.endAll())
        }
    }

    private func noteAndVelocity(for touch: UITouch) -> (Note?, UInt8) {
        guard let layout else { return (nil, Velocity.defaultFixed) }
        let point = touch.location(in: self)
        guard let key = layout.key(at: point) else { return (nil, Velocity.defaultFixed) }
        let velocity = Velocity.value(mode: velocityMode, depth: layout.depth(of: point, in: key))
        return (key.note, velocity)
    }

    private func send(_ events: [NoteEvent]) {
        guard !events.isEmpty else { return }
        onNoteEvents?(events)
        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        UIColor.black.setFill()
        UIRectFill(bounds)
        guard let layout else { return }

        let held = tracker.heldNotes
        let pressedTint = tintColor.withAlphaComponent(0.45)
        let corner = CGSize(width: 6, height: 6)

        for key in layout.whiteKeys {
            let shape = UIBezierPath(
                roundedRect: key.frame.insetBy(dx: 0.75, dy: 0),
                byRoundingCorners: [.bottomLeft, .bottomRight],
                cornerRadii: corner
            )
            UIColor.white.setFill()
            shape.fill()
            if held.contains(key.note) {
                pressedTint.setFill()
                shape.fill()
            }
            if showsNoteLabels, key.note.pitchClass == 0 {
                drawLabel(key.note.name, in: key.frame)
            }
        }

        for key in layout.blackKeys {
            let shape = UIBezierPath(
                roundedRect: key.frame,
                byRoundingCorners: [.bottomLeft, .bottomRight],
                cornerRadii: CGSize(width: 4, height: 4)
            )
            (held.contains(key.note) ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 0.08, alpha: 1)).setFill()
            shape.fill()
            if held.contains(key.note) {
                pressedTint.setFill()
                shape.fill()
            }
        }
    }

    private func drawLabel(_ text: String, in frame: CGRect) {
        let fontSize = min(14, max(9, frame.width * 0.26))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: UIColor(white: 0.45, alpha: 1),
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 8))
    }
}
