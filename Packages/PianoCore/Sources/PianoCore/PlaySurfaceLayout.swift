import Foundation
// CGRect, CGSize and CGPoint get their Equatable conformance from CoreGraphics on Apple
// platforms, so import it directly. On Linux these types come from Foundation.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The iPhone Duo fold as reported by the system, in the play surface's coordinates.
public struct Division: Sendable, Equatable {
    public var frame: CGRect
    /// True while the device is partly folded. When flat, the fold is inactive and has zero width.
    public var isActive: Bool

    public init(frame: CGRect, isActive: Bool) {
        self.frame = frame
        self.isActive = isActive
    }

    /// True when the fold runs top to bottom (held like a book), false when it runs
    /// side to side (set down like a laptop).
    public var runsVertically: Bool { frame.height > frame.width }
}

/// Splits the play screen into an optional content area (note names, later sheet music)
/// and the keyboard area.
///
/// - Laptop pose (fold active and running side to side): content on the top half,
///   keys on the bottom half, as Apple's design guidelines suggest.
/// - Everything else: keys along the bottom. If a vertical fold crosses the keyboard,
///   it is passed on so `KeyboardLayout` can align keys to it.
public struct PlaySurfaceLayout: Sendable, Equatable {
    public var contentRect: CGRect?
    public var keyboardRect: CGRect
    public var keyboardFold: FoldInfo?

    /// Share of the height given to the keys when the surface is wider than tall, and when taller.
    public static let landscapeKeyboardShare: CGFloat = 0.62
    public static let portraitKeyboardShare: CGFloat = 0.42
    public static let minimumKeyboardHeight: CGFloat = 120
    public static let minimumContentHeight: CGFloat = 44

    public init(size: CGSize, division: Division?) {
        if let division, division.isActive, !division.runsVertically,
           division.frame.minY > 0, division.frame.maxY < size.height {
            contentRect = CGRect(x: 0, y: 0, width: size.width, height: division.frame.minY)
            keyboardRect = CGRect(x: 0, y: division.frame.maxY,
                                  width: size.width, height: size.height - division.frame.maxY)
            keyboardFold = nil
            return
        }

        let share = size.width > size.height ? Self.landscapeKeyboardShare : Self.portraitKeyboardShare
        let keyboardHeight = min(size.height, max(Self.minimumKeyboardHeight, (size.height * share).rounded()))
        keyboardRect = CGRect(x: 0, y: size.height - keyboardHeight, width: size.width, height: keyboardHeight)

        let contentHeight = size.height - keyboardHeight
        var content: CGRect? = contentHeight >= Self.minimumContentHeight
            ? CGRect(x: 0, y: 0, width: size.width, height: contentHeight)
            : nil

        if let division, division.runsVertically,
           division.frame.midX > 0, division.frame.midX < size.width {
            keyboardFold = FoldInfo(centerX: division.frame.midX,
                                    width: division.isActive ? division.frame.width : 0)
            // Held like a book: keep the content on the left page, out of the fold.
            if division.isActive, let current = content {
                content = CGRect(x: 0, y: 0, width: division.frame.minX, height: current.height)
            }
        } else {
            keyboardFold = nil
        }
        contentRect = content
    }
}
