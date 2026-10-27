// swift-tools-version: 6.0
import PackageDescription

// Pure Swift logic for the piano app: notes, key geometry, fold alignment, touch tracking.
// No UIKit or AVFoundation, so it builds and tests anywhere (`swift test`).
let package = Package(
    name: "PianoCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PianoCore", targets: ["PianoCore"]),
    ],
    targets: [
        .target(name: "PianoCore"),
        .testTarget(name: "PianoCoreTests", dependencies: ["PianoCore"]),
    ]
)
