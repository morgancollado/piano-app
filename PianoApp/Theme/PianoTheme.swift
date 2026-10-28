import SwiftUI
import UIKit

/// Colors and gradients for the instrument: black lacquer body, red felt, ivory keys,
/// glossy black keys, and a warm amber accent for played notes.
/// Tweak the look here; the drawing code only refers to these names.
enum PianoTheme {
    // MARK: Body and music stand

    static let bodyUI = UIColor(red: 0.050, green: 0.050, blue: 0.063, alpha: 1)
    static let body = Color(uiColor: bodyUI)

    /// The area above the keys, a little lighter than the body at the top.
    static let standColors: [Color] = [
        Color(red: 0.110, green: 0.110, blue: 0.133),
        Color(uiColor: bodyUI),
    ]

    static let noteText = Color(red: 0.953, green: 0.933, blue: 0.890)

    // MARK: Felt strip above the keys

    static let felt = gradient([rgb(0x8E2236), rgb(0x5E1322)])
    /// Shadow the fallboard casts onto the back of the keys.
    static let fallboardShadow = gradient([UIColor.black.withAlphaComponent(0.38), UIColor.black.withAlphaComponent(0)])

    // MARK: White keys

    static let whiteKey = gradient(
        [rgb(0xE1DDD3), rgb(0xF5F2EB), rgb(0xFBF9F4), rgb(0xF0ECE3)],
        locations: [0, 0.12, 0.72, 1]
    )
    static let whiteKeyPressed = gradient(
        [rgb(0xD3CEC4), rgb(0xE7E3DA), rgb(0xEEEAE2)],
        locations: [0, 0.22, 1]
    )
    /// The rounded front edge of a white key.
    static let whiteLip = gradient([rgb(0xE6E1D7), rgb(0xCFC9BC)])
    static let labelUI = rgb(0x9A958C)

    // MARK: Black keys

    static let blackSideUI = rgb(0x050506)
    static let blackTop = gradient(
        [rgb(0x2A2A30), rgb(0x18181C), rgb(0x2C2C33), rgb(0x1B1B1F)],
        locations: [0, 0.55, 0.93, 1]
    )
    static let blackTopPressed = gradient([rgb(0x16161A), rgb(0x0F0F12)])
    static let blackFront = gradient([rgb(0x45454D), rgb(0x1E1E23)])

    // MARK: Played notes

    /// Glow rising from the front of a pressed key.
    static func keyGlow(_ tint: UIColor) -> CGGradient {
        gradient([tint.withAlphaComponent(0), tint.withAlphaComponent(0.55)])
    }

    /// Color of a note's light trail: amber in the bass, warming to pale gold in the treble.
    nonisolated static func trailColor(for midiNumber: Int) -> Color {
        let t = min(max(Double(midiNumber - 21) / 87, 0), 1)
        return Color(hue: 0.055 + 0.075 * t, saturation: 0.78 - 0.28 * t, brightness: 1)
    }

    // MARK: Helpers

    static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static func gradient(_ colors: [UIColor], locations: [CGFloat]? = nil) -> CGGradient {
        let space = CGColorSpaceCreateDeviceRGB()
        let cgColors = colors.map(\.cgColor) as CFArray
        if let locations {
            return CGGradient(colorsSpace: space, colors: cgColors, locations: locations)!
        }
        return CGGradient(colorsSpace: space, colors: cgColors, locations: nil)!
    }
}
