# Notes for coding agents

Piano app for iPhone, optimized for iPhone Duo (Apple's foldable). Paid App Store release.
Read `docs/PLAN.md` (plan, decisions, progress) and `docs/IPHONE_DUO_REFERENCE.md`
(Apple's iPhone Duo APIs and rules) before making changes.

## Build and test

- Pure logic lives in `Packages/PianoCore` and must stay free of UIKit/SwiftUI/AVFoundation.
  Test it with `swift test` from that folder. It also builds on Linux.
- The app (`PianoApp/`) only builds in Xcode on a Mac. In a Linux cloud session, app code
  can be written but not compiled. Say so when handing off.
- `PianoApp.xcodeproj` uses folder-synced groups: new files under `PianoApp/` need no
  project edits.
- Info.plist entries that build settings can't hold (arrays, like `NSBonjourServices`) go in
  `Config/Info.plist`, which is merged with the generated one. Keep it outside `PianoApp/`.
- `PianoApp/Piano.sf2` is stored with Git LFS (`.gitattributes`). Keep it that way when
  committing a rebuilt SoundFont.

## Rules

- Minimum iOS 18. Anything from iOS 27.1 (iPhone Duo APIs) goes in
  `PianoApp/Duo/DuoSupport.swift` behind `if #available(iOS 27.1, *)`.
- Never size from the screen (`UIScreen.main`) and never branch on orientation, device
  model, or `userInterfaceIdiom`. Use the size you're given (`GeometryReader`, `bounds`).
- Keep keys and buttons out of the fold. Use `reservedRegions` via `pianoDivision()`.
- Every toolbar item needs a title and an SF Symbol (iPhone Duo puts bars on the side).
- Every touch path must end its notes, including `touchesCancelled`. No stuck notes.
- Swift 6 language mode; the app target defaults to MainActor isolation.
- Colors and gradients live in `PianoApp/Theme/PianoTheme.swift`. The play screen is always dark.
