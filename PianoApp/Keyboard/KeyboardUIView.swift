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
        backgroundColor = PianoTheme.bodyUI
        contentMode = .redraw

        // Lets VoiceOver users play the keys directly.
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
        accessibilityLabel = String(localized: "Piano keyboard")

        // Note names follow the Dynamic Type setting, so redraw when it changes.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: KeyboardUIView, _: UITraitCollection) in
            view.setNeedsDisplay()
        }
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
        guard let context = UIGraphicsGetCurrentContext() else { return }
        PianoTheme.bodyUI.setFill()
        context.fill(bounds)
        guard let layout else { return }

        let held = tracker.heldNotes
        let metrics = KeyMetrics(whiteWidth: layout.whiteKeyWidth, height: bounds.height)

        for key in layout.whiteKeys {
            drawWhiteKey(key, pressed: held.contains(key.note), metrics: metrics, in: context)
        }
        for key in layout.blackKeys {
            drawBlackKey(key, pressed: held.contains(key.note), metrics: metrics, in: context)
        }
        drawFelt(metrics: metrics, in: context)
    }

    /// Sizes of the drawn details, scaled to the keys.
    private struct KeyMetrics {
        let gap: CGFloat
        let corner: CGFloat
        let lip: CGFloat
        let feltHeight: CGFloat
        let blackInset: CGFloat
        let blackFront: CGFloat

        init(whiteWidth: CGFloat, height: CGFloat) {
            gap = min(2, max(1, whiteWidth * 0.03))
            corner = min(7, whiteWidth * 0.11)
            lip = min(9, max(4, height * 0.028))
            feltHeight = min(7, max(4, height * 0.016))
            blackInset = max(1.5, whiteWidth * 0.06)
            blackFront = min(12, max(5, height * 0.035))
        }
    }

    private func drawWhiteKey(_ key: PianoKey, pressed: Bool, metrics: KeyMetrics, in context: CGContext) {
        let frame = key.frame.insetBy(dx: metrics.gap / 2, dy: 0)
        let corner = CGSize(width: metrics.corner, height: metrics.corner)
        let shape = UIBezierPath(roundedRect: frame, byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: corner)

        context.saveGState()
        shape.addClip()
        fillVertical(frame, with: pressed ? PianoTheme.whiteKeyPressed : PianoTheme.whiteKey, in: context)

        // The rounded front edge of the key. A pressed key shows less of it, as if it sank.
        let lip = pressed ? metrics.lip * 0.45 : metrics.lip
        fillVertical(CGRect(x: frame.minX, y: frame.maxY - lip, width: frame.width, height: lip),
                     with: PianoTheme.whiteLip, in: context)

        if pressed {
            let glowTop = frame.minY + frame.height * 0.35
            fillVertical(CGRect(x: frame.minX, y: glowTop, width: frame.width, height: frame.maxY - glowTop),
                         with: PianoTheme.keyGlow(tintColor), in: context)
        }
        context.restoreGState()

        if showsNoteLabels, key.note.pitchClass == 0 {
            drawLabel(key.note.name, in: frame, above: metrics.lip)
        }
    }

    private func drawBlackKey(_ key: PianoKey, pressed: Bool, metrics: KeyMetrics, in context: CGContext) {
        let frame = key.frame
        let radius = min(4, frame.width * 0.12)
        let corners = CGSize(width: radius, height: radius)
        let body = UIBezierPath(roundedRect: frame, byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: corners)

        // Shadow cast onto the white keys; shorter when pressed, because the key is lower.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: pressed ? 1.5 : 4),
            blur: pressed ? 3 : 7,
            color: PianoTheme.blackKeyShadowUI.cgColor
        )
        PianoTheme.blackSideUI.setFill()
        body.fill()
        context.restoreGState()

        // Top surface, inset from the sides, ending where the sloped front face starts.
        let front = pressed ? metrics.blackFront * 0.5 : metrics.blackFront
        let top = CGRect(x: frame.minX + metrics.blackInset, y: frame.minY,
                         width: max(0, frame.width - 2 * metrics.blackInset), height: max(0, frame.height - front))
        context.saveGState()
        UIBezierPath(roundedRect: top, byRoundingCorners: [.bottomLeft, .bottomRight],
                     cornerRadii: CGSize(width: radius * 0.6, height: radius * 0.6)).addClip()
        fillVertical(top, with: pressed ? PianoTheme.blackTopPressed : PianoTheme.blackTop, in: context)
        if pressed {
            let glowTop = top.minY + top.height * 0.4
            fillVertical(CGRect(x: top.minX, y: glowTop, width: top.width, height: top.maxY - glowTop),
                         with: PianoTheme.keyGlow(tintColor), in: context)
        }
        context.restoreGState()

        // Front face: a lighter sloped edge at the end of the key.
        let face = CGRect(x: frame.minX + 1, y: top.maxY, width: max(0, frame.width - 2), height: max(0, frame.maxY - top.maxY - 1))
        context.saveGState()
        UIBezierPath(roundedRect: face, byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: corners).addClip()
        fillVertical(face, with: PianoTheme.blackFront, in: context)
        context.restoreGState()
    }

    /// The red felt strip along the back of the keys, and the shadow it casts on them.
    private func drawFelt(metrics: KeyMetrics, in context: CGContext) {
        let shadow = CGRect(x: 0, y: metrics.feltHeight, width: bounds.width, height: metrics.feltHeight * 2.4)
        fillVertical(shadow, with: PianoTheme.fallboardShadow, in: context)
        let felt = CGRect(x: 0, y: 0, width: bounds.width, height: metrics.feltHeight)
        fillVertical(felt, with: PianoTheme.felt, in: context)
    }

    /// Fills `rect` with a top-to-bottom gradient.
    private func fillVertical(_ rect: CGRect, with gradient: CGGradient, in context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
        context.restoreGState()
    }

    private func drawLabel(_ text: String, in frame: CGRect, above lip: CGFloat) {
        // Sized to the key, scaled by the Dynamic Type setting, and capped so it stays on the key.
        let base = min(14, max(9, frame.width * 0.24))
        let scaled = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: base, compatibleWith: traitCollection)
        let fontSize = min(scaled, frame.width * 0.45)
        var font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        if let rounded = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: rounded, size: fontSize)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: PianoTheme.labelUI,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.maxY - lip - size.height - 6))
    }
}
