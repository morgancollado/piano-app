# Piano

A piano app for iPhone, optimized for iPhone Duo. SwiftUI app with a UIKit keyboard,
iOS 18+, with the iPhone Duo features enabled on iOS 27.1+.

- Plan and progress: [docs/PLAN.md](docs/PLAN.md)
- iPhone Duo API notes from Apple's documentation: [docs/IPHONE_DUO_REFERENCE.md](docs/IPHONE_DUO_REFERENCE.md)

## Layout

```
PianoApp.xcodeproj        Xcode project. Files in PianoApp/ are included automatically.
PianoApp/
  PianoApp.swift          App entry point
  RootView.swift          Navigation bar controls (octave, sustain, settings)
  Audio/PianoEngine       AVAudioEngine sampler, tone, reverb, audio session
  Keyboard/               UIKit multitouch keyboard + SwiftUI wrapper
  Play/                   Play screen, note display, app state and settings
  Duo/DuoSupport.swift    All iOS 27.1 iPhone Duo APIs (fold, hinge), behind availability checks
  Settings/               Settings sheet
Packages/PianoCore/       Pure Swift logic with unit tests: notes, key layout, fold alignment, touches
```

## Run it on your Mac

1. Open `PianoApp.xcodeproj` in Xcode 27.1 or later.
2. Select the **PianoApp** target → **Signing & Capabilities** → choose your team.
3. Pick a simulator (try **iPhone Duo**) or your device and press Run.

Until a piano SoundFont is added, the keys play a placeholder tone.

## Tests

```sh
cd Packages/PianoCore
swift test
```

The same tests run in Xcode if you open `Packages/PianoCore/Package.swift`.

## Adding the piano sound

Add a SoundFont named `Piano.sf2` to the `PianoApp/` folder. Xcode includes it automatically,
and `PianoEngine` loads it at launch. Check that its license allows commercial use and
add any required attribution in the app.
