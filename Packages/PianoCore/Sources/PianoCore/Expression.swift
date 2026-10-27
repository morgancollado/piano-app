import Foundation

/// How hard a note sounds. iPhone screens don't sense pressure, so the app offers
/// a fixed level or a level based on where the finger lands on the key.
public enum VelocityMode: String, CaseIterable, Sendable, Identifiable {
    case fixed
    /// Lower on the key (nearer the player) plays louder.
    case touchPosition

    public var id: String { rawValue }
}

public enum Velocity {
    public static let defaultFixed: UInt8 = 96
    static let softest: CGFloat = 40

    /// - Parameter depth: 0 at the top of the key, 1 at the bottom.
    public static func value(mode: VelocityMode, depth: CGFloat, fixed: UInt8 = defaultFixed) -> UInt8 {
        switch mode {
        case .fixed:
            return fixed
        case .touchPosition:
            let clamped = min(max(depth, 0), 1)
            return UInt8((softest + clamped * (127 - softest)).rounded())
        }
    }
}

/// A hinge reading from iPhone Duo, in degrees.
public struct HingeReading: Sendable, Equatable {
    public var degrees: Double
    public var isPartiallyOpen: Bool

    public init(degrees: Double, isPartiallyOpen: Bool) {
        self.degrees = degrees
        self.isPartiallyOpen = isPartiallyOpen
    }
}

/// The optional "piano lid": while iPhone Duo is partly folded, closing it makes the sound
/// darker and softer, like lowering the lid of a grand piano.
///
/// Assumes 180° means flat and smaller angles mean more closed. Apple's documentation
/// doesn't say; confirm it in the iPhone Duo simulator.
public enum PianoLid {
    static let closedDegrees = 30.0
    static let openDegrees = 150.0
    /// The lid never goes fully dark, so the piano stays audible.
    static let minimumBrightness = 0.15

    public static func brightness(hingeDegrees: Double) -> Double {
        let t = (hingeDegrees - closedDegrees) / (openDegrees - closedDegrees)
        let clamped = min(max(t, 0), 1)
        return minimumBrightness + clamped * (1 - minimumBrightness)
    }

    /// Combines the manual tone setting with the hinge, when the hinge control is turned on.
    public static func effectiveBrightness(manual: Double, hinge: HingeReading?, enabled: Bool) -> Double {
        guard enabled, let hinge, hinge.isPartiallyOpen else { return manual }
        return manual * brightness(hingeDegrees: hinge.degrees)
    }
}
