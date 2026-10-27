# iPhone Duo developer reference (condensed)

Notes gathered on 2026-10-27 from Apple's official iPhone Duo material, kept here so
development sessions start with the right context. Where something comes from a
third-party source or is unverified, it is marked **(unverified)**.

## Official sources

| Source | URL |
| --- | --- |
| Get ready for iPhone Duo (hub) | https://developer.apple.com/iphone-duo/ |
| Three steps to make your app shine | https://developer.apple.com/iphone-duo/prepare/ |
| Preparing your app for iPhone Duo (Technology Overview) | https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo |
| HIG: Designing for iPhone Duo | https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo |
| `ReservedRegion` (SwiftUI) | https://developer.apple.com/documentation/swiftui/reservedregion |
| `ArrangementView` (SwiftUI) | https://developer.apple.com/documentation/swiftui/arrangementview |
| `UIHingeInteraction` / `UIHinge` (UIKit) | https://developer.apple.com/documentation/uikit/uihingeinteraction |
| Tech Talk: Design for iPhone Duo | https://developer.apple.com/videos/play/tech-talks/111466/ |
| Tech Talk: Prepare your app for iPhone Duo | https://developer.apple.com/videos/play/tech-talks/111461/ |
| Tech Talk: Raise the bar (vertical bars) | https://developer.apple.com/videos/play/tech-talks/111462/ |
| Tech Talk: Strike a pose with adaptive layouts | https://developer.apple.com/videos/play/tech-talks/111463/ |
| Tech Talk: Leverage multiple displays and scenes | https://developer.apple.com/videos/play/tech-talks/111464/ |
| Forum: Summary of the iPhone Duo Group Lab (Apple DTS Q&A) | https://developer.apple.com/forums/thread/847644 |
| Tech specs | https://support.apple.com/en-us/148588 |
| Figma / Sketch kits | https://developer.apple.com/design/resources/ |

Tip: Apple's doc pages render with JavaScript. The raw content is available as JSON at
`https://developer.apple.com/tutorials/data/<path>.json` (for example
`.../tutorials/data/documentation/swiftui/reservedregion.json`).

## Hardware facts (Apple tech specs)

- Book-style fold. Released 2026-10-23, ships with iOS 27.
- Inner display: 7.6" OLED, 1878 x 2670 px, 430 ppi, ProMotion up to 120 Hz.
- Outer display: 5.4" OLED, 1398 x 2034 px, 460 ppi, ProMotion up to 120 Hz.
- Open: 164.6 x 117.8 x 5.2 mm. Closed: 84.1 x 117.8 x 11.3 mm. 254 g.
  The 117.8 mm side is shared, so the device is wider than tall when open
  ("passport shape"), and the fold runs vertically when held that way.
- A20 Pro, stereo speakers (top and bottom per MacRumors **(unverified which play in each pose)**),
  Haptic Touch only (no pressure-sensitive touch), USB-C (USB 3), Touch ID in the side button.
- Point sizes **(unverified, assumes 3x scale)**: inner 626 x 890 pt, outer 466 x 678 pt.
  Never hardcode these: always read the size you are given.

## Tooling

- Xcode 27.1 (iOS 27.1 SDK), Apple silicon Mac on macOS 26.6 or later **(per third-party guide)**.
- Test with: the iPhone Duo simulator in Xcode 27.1 (Device Hub shows each pose and
  simulates the hinge), the resizable iOS simulator, and iPhone Mirroring on macOS 27
  (drag the window to extreme sizes).
- Camera and scene-accessory features need real hardware; layout and hinge work in the simulator.
- Xcode's coding assistant has a "get my app ready for iPhone Duo" skill. Export it for
  another agent with `xcrun agent skills export`.

## What the SDK you build with changes

| Built with | Behavior on iPhone Duo |
| --- | --- |
| iOS 26 SDK or earlier | Runs in compatibility mode at an iPhone aspect ratio, centered when open, does not adapt. |
| iOS 27 SDK | Fills most of the inner display, still avoids the status bar on the right edge. |
| iOS 27.1 SDK or later | Full display. Toolbars and tab bars move to a vertical bar on the side. |

All Duo-specific APIs (`ArrangementView`, `ReservedRegion`, `onHingeChange`,
`toolbarVerticalEdge` / `verticalBarEdge`) need **iOS 27.1+**.

## Core rules from Apple

1. **Build to resize.** The app resizes continuously when the device opens, closes, folds,
   rotates, or enters Split View. Folding is a size/trait change, not a scene teardown.
2. **Never size from the screen.** Remove `UIScreen.main`. Use `GeometryReader` /
   `onGeometryChange`, `view.bounds`, `traitCollection.displayScale`.
3. **No orientation or idiom checks for layout.** Don't use `UIDevice.current.orientation`,
   `interfaceOrientation`, or `userInterfaceIdiom`. Compare width vs height of the space you have.
   Regular width no longer means iPad.
4. **The inner display ignores supported-orientation locks.** Plan for portrait and landscape
   on the inner display. The outer display honors them like a normal iPhone.
5. **Two size classes cover every pose:** compact width (outer), regular width (inner).
   Don't build a custom layout per pose, and never tie a feature to one pose.
6. **Keep interactive elements out of the fold** when partially folded. Scrolling content is exempt.
7. **Small adjustments over rearrangement** when the device folds.
8. **Grids: prefer an even number of columns** so content divides cleanly at the fold.
9. **Games / immersive UIs:** playable in every pose; change aspect ratio rather than letterbox.
   Full-width non-scrolling UIs (Calculator is Apple's example) may skip bars, as long as nothing
   collides with the Dynamic Island or status bar.
10. **Apps cannot draw on the outer display while open.** Only system scene accessories
    (camera capture, AlarmKit) appear there, and the system can withdraw them at any time.

## Poses

| Pose | Display | Fold (division region) |
| --- | --- | --- |
| Closed | Outer, compact width | None. Outer camera occlusion always present. |
| Open flat | Inner, regular width | Inactive (zero width). Query with `.includeInactive` to know where it will be. |
| Partially folded like a book | Inner | Active, runs **vertically** at the center: content goes side by side. |
| Partially folded like a laptop (on a table) | Inner | Active, runs **horizontally**: top = content viewed at a distance, bottom = interactive controls. |
| Standing on its edges | Inner | Active. Interactive elements move to the bottom half. |

There is no single "pose" value. Infer it from the division region's direction, hinge
status, and size class together.

## Reserved regions

```swift
GeometryReader { proxy in
    let divisions = proxy.reservedRegions(kind: .division)              // active only
    let all = proxy.reservedRegions(kind: .division, options: .includeInactive)
    let cameras = proxy.reservedRegions(kind: .occlusion)
    // region.frame is in this view's coordinates, in points, margins included.
    // region.isActive, region.kind, region.id, region.margins
}
```

- Kinds: `.division` (the fold), `.occlusion` (outer camera always; inner camera only while in use).
- Only regions that overlap the queried view are returned.
- Frames are mirrored for right-to-left layouts by default. Pass
  `layoutDirectionBehavior: .fixed` for unmirrored frames.
- Division frame taller than wide = vertical fold (book). Wider than tall = horizontal fold (laptop).
- Touches inside an occlusion region may be suppressed. Keep keys out of camera regions.
- UIKit: `view.reservedRegions(kind:options:)` returning `UIView.ReservedRegion`.

## Arrangement views

```swift
ArrangementView {
    PrimaryView()
} secondary: {
    SecondaryView()
}
.arrangementViewStyle(.overlay)          // or .split, .split.axes(.horizontal), .overlay.axes(...)
```

- **split:** primary leading / secondary trailing when wider than tall; primary top /
  secondary bottom when taller. Keeps both on separate sides of the fold. If the allowed axis
  doesn't fit, only the primary is shown.
- **overlay:** primary layered above secondary (z-axis) when flat or closed. When folded:
  book = secondary leading, primary trailing; laptop = secondary top, primary bottom.
  Read `@Environment(\.overlayArrangementZIndex)` to collapse content when it is underneath.
- Sizing modifiers: `splitArrangementLayoutRatio(_:)`, `splitArrangementLayoutSize(...)`,
  `splitArrangementFixedLayoutSize(...)`, `overlayArrangementEdge(_:)`.
- Do not put an `ArrangementView` inside `ScrollView`/`List`/grids, and do not put
  `NavigationSplitView`/`TabView` inside one. Keep navigation outside it.
- UIKit: `UIArrangementViewController`, `setViewController(_:for:)`, `updateArrangement(_:)`.

## Hinge

```swift
// SwiftUI (from Apple's Tech Talk 111464, an instrument demo using the hinge as a whammy bar)
.onHingeChange { _, context in
    if let hinge = context.hinge, hinge.status == .partiallyOpen {
        pitchBend = calculatePitchBend(angle: hinge.angle)   // hinge.angle is an `Angle`
    } else {
        pitchBend = 0
    }
}

// UIKit
let interaction = UIHingeInteraction { _, update in
    guard let hinge = update.hinge else { return }   // nil = no hinge (regular iPhone)
    _ = hinge.angle    // radians
    _ = hinge.status   // .closed / .partiallyOpen / .fullyOpen (UIKit adds .unknown: treat as .fullyOpen)
}
view.addInteraction(interaction)
```

- Use the hinge for **interactions and effects**, never for layout (use regions/arrangements).
- Update rate and precision are system policy and can change. Don't depend on them.
- Which angle means closed vs flat is **not stated** in the docs read so far. Check in the simulator.

## Vertical bars

- Outer display, and inner display in landscape: nav bar + toolbar + tab bar stack vertically
  on the trailing hardware edge (same side in RTL). Inner portrait keeps horizontal bars.
- Only bars from `NavigationStack` / `NavigationSplitView` / `TabView` (or UIKit controllers)
  move automatically. Custom bars don't.
- Items need a **symbol and a title**. Text-only items stay horizontal.
- Useful modifiers: `.toolbarVerticalBehavior(.disabled)`, `.axisBehavior(.verticalPreferred)`,
  `.visibilityPriority(.high)`, `ToolbarOverflowMenu`, `.toolbarVerticalCompressionBehavior(...)`,
  `@Environment(\.toolbarVerticalEdge)`, `.backgroundExtensionEffect()`.
- Safe areas become asymmetric. Handle each edge separately.

## Audio, scenes, and multitasking (Group Lab answers)

- Audio focus goes to the most recently launched app that started playback. It is not split per window.
- Split View: a 50/50 split on the inner display. All apps participate. Each app's bars go on its outer edge.
- Multiple windows work like iPad on the inner display only. Use `UIWindowSceneActivationAction`.
- Text input and scroll position survive folding.
- Core Motion: `startDeviceMotionUpdates(using:)` with `deviceMotionBody` set to a
  `CMBodyIdentifiable` view, so attitude is correct for the half the app is on.
- Rounded corners: use `ConcentricRectangle` / `UICornerConfiguration`.
- App Store: submitting iPhone Duo screenshots adds a "Made for iPhone Duo" badge.

## Not covered by Apple's material (test on hardware)

- Audio output latency and which speakers play in each pose.
- Touch accuracy right on the crease when flat.
- Haptics behavior.
- Hinge update rate in practice.
