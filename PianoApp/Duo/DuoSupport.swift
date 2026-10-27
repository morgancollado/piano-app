import PianoCore
import SwiftUI

// Everything that touches the iOS 27.1 iPhone Duo APIs lives in this file.
// On older iOS versions, and on iPhones without a fold, these return nothing and the
// app behaves like a normal iPhone app.

extension GeometryProxy {
    /// The iPhone Duo fold in this view's coordinates, including when it's inactive (flat),
    /// so the keyboard can line up with it before the device folds.
    func pianoDivision() -> Division? {
        if #available(iOS 27.1, *) {
            // .fixed: the keyboard always runs low-to-high left-to-right, even in
            // right-to-left languages, so use unmirrored frames.
            let regions = reservedRegions(
                kind: .division,
                options: .includeInactive,
                layoutDirectionBehavior: .fixed
            )
            guard let region = regions.first else { return nil }
            return Division(frame: region.frame, isActive: region.isActive)
        }
        return nil
    }
}

/// Reports the hinge angle on iPhone Duo. Reports `nil` on devices without a hinge.
struct HingeObserver: ViewModifier {
    let onChange: (HingeReading?) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                guard let hinge = context.hinge else {
                    onChange(nil)
                    return
                }
                onChange(HingeReading(
                    degrees: hinge.angle.degrees,
                    isPartiallyOpen: hinge.status == .partiallyOpen
                ))
            }
        } else {
            content
        }
    }
}

extension View {
    func onHingeReading(_ action: @escaping (HingeReading?) -> Void) -> some View {
        modifier(HingeObserver(onChange: action))
    }
}
