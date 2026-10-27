# Piano app for iPhone Duo: development plan

Status: in progress, 2026-10-27. Device and API facts are in
[IPHONE_DUO_REFERENCE.md](IPHONE_DUO_REFERENCE.md), with links to Apple's documentation.

## Decisions (confirmed 2026-10-27)

| Question | Answer |
| --- | --- |
| Mac and Xcode | Yes. Mac being updated to macOS 27.2. |
| Apple Developer Program | Yes, paid account. |
| iPhone Duo for testing | Yes. |
| Goal | **Paid App Store release.** |
| iOS support | **Any iPhone on iOS 18 or later**, optimized for iPhone Duo. The iPhone Duo APIs switch on only on iOS 27.1+. All of them live in `PianoApp/Duo/DuoSupport.swift`. |

Why iOS 18: it covers iPhone XS/XR and newer and includes `@Observable`, SwiftData, and
Swift Testing. Going lower would mean writing older patterns for a shrinking audience.
This overrides assumption 2 below.

### Progress

| Phase | Status |
| --- | --- |
| 0. Setup | Done in the repo: Xcode project, `PianoCore` package, `.gitignore`. Needs a first build on the Mac. |
| 1. Sound | Code written (`PianoEngine`). Uses a placeholder tone until a piano SoundFont is added. Not yet compiled. |
| 2. Keyboard | Code written. Key-layout and touch logic: 30 unit tests passing (`swift test`). The UIKit view isn't compiled yet. |
| 3. iPhone Duo layout | Fold alignment, gap, and laptop pose done and tested in `PianoCore`. Hooked to `reservedRegions` in `DuoSupport.swift`. Needs simulator and device testing. |
| 4. Hinge lid | Code written, off by default. Needs a check of the angle direction in the simulator. |

### Paid release: business setup (do any time)

- App Store Connect → Business: sign the **Paid Apps Agreement** and add tax and banking
  details. A paid app can't go on sale without these.
- Reserve the app name in App Store Connect (create the app record). "Piano" is a placeholder.
- Choose the bundle ID. The project uses `com.morgancollado.piano`; change it in Xcode
  before creating the App Store record if you want something else.
- Piano samples: Salamander Grand Piano, public domain since 2022. Details in
  [SOUND_LICENSING.md](SOUND_LICENSING.md). Credit Alexander Holm in the app anyway.

## 1. Goal

A SwiftUI piano app that is good on any iPhone and makes the most of iPhone Duo:

- a two-octave keyboard on the open inner display
- a "laptop" pose, with the device on a table, notes on the top half and keys on the bottom half
- a keyboard that bends around the fold instead of putting a key boundary in it
- an optional "piano lid" control that changes the tone as the hinge opens or closes

## 2. Assumptions

1. **You have, or will get, an Apple silicon Mac** with macOS 26.6+ and Xcode 27.1.
   iOS apps can't be built on Linux. This cloud environment can write the code but can't
   compile or run it.
2. **Minimum iOS 27.1.** All of the Duo APIs need 27.1. Because the app is new, setting
   27.1 as the minimum avoids `#available` branches everywhere. The cost is that users on
   older iOS versions are excluded. If you want to support iOS 26, keep the same plan and
   gate the Duo APIs.
3. **You may not own an iPhone Duo yet.** It costs $1,999 and pre-orders are shipping as
   late as January 2027. The Xcode 27.1 simulator covers poses, hinge, and layout. Any
   recent iPhone covers sound latency and multitouch. Real Duo hardware is only needed at the end.
4. **Scope is a playable instrument plus light learning features**, not a full course
   platform. Phases 5 and 6 can be cut or reordered.
5. **Point sizes below use a 3x scale** (inner 626 x 890 pt, outer 466 x 678 pt). This
   comes from third-party sites. The code never relies on it; it is only for sizing the design.
6. **iPhone Duo has no pressure-sensitive touch** (Apple lists Haptic Touch only), so key
   velocity has to come from something other than pressure.

## 3. Keyboard sizing in each pose

Target white-key width: about 60 pt (about 10.6 mm at 430 ppi / 3x). Apple's minimum
tap size is 44 pt. A real piano key is about 23.5 mm, so screen keys are roughly half size,
which is normal for phone pianos.

| Pose | Approx. space (pt) | White keys at ~60 pt | Layout |
| --- | --- | --- | --- |
| Closed, portrait | 466 wide, less the side bar | 7 (1 octave) | Keyboard on the bottom, note display on top |
| Closed, landscape | 678 wide, less the side bar | 10 | Full-width keyboard |
| Open flat, landscape | 890 x 626 | **14 (2 octaves)** | Keyboard with the fold aligned to a B/C boundary (below) |
| Open flat, portrait | 626 x 890 | 10 | Keyboard on the bottom, falling-notes view or a second keyboard row on top |
| Book (vertical fold) | two halves of ~445 x 626 | 7 + 7 | Same keyboard with a gap at the fold |
| Laptop (horizontal fold) | top ~626 x 440, bottom ~626 x 440 | 10 | Top: notes / visualizer. Bottom: keys. |

Rule from Apple: the inner display ignores orientation locks, so the inner display
needs to work in both portrait and landscape.

### Fold-aware keys

A two-octave keyboard from C to B has 14 white keys. Its exact center falls between B
and the next C, and **no black key sits between B and C** (the same is true of E/F).
So when the keyboard starts on C, the fold runs between two white keys and never cuts a
black key.

General rule for any even number of white keys `n`: choose the start note so that white key
number `n/2` is a B or an E. For example, 12 keys start on G: `G A B C D E | F G A B C D`.

Implementation:

- Read the fold with `reservedRegions(kind: .division, options: .includeInactive)` in the
  keyboard's own coordinates. Asymmetric safe areas (the vertical bar on one edge) mean the
  keyboard's center is not the display's center.
- Flat (fold inactive): align a B/C or E/F boundary with the fold, with no gap.
- Book pose (fold active and taller than wide): open a gap equal to the division's width
  at that boundary. The keys don't move otherwise, following Apple's "small adjustments" rule.
- Laptop pose (fold active and wider than tall): put the keyboard in the bottom region and
  content in the top region.
- Also query `.occlusion` regions and keep keys out of camera areas; touches there can be dropped.

The key-layout maths (note to frame, frame to note, fold alignment) lives in a pure Swift
module with unit tests (see section 5).

## 4. Architecture

```
PianoApp (SwiftUI app, iOS 27.1+)
├── PianoCore            local Swift package, no UIKit or AVFoundation, unit-tested
│   ├── Note, Scale, KeyboardLayout      note ↔ geometry, fold alignment, key-count rules
│   └── Recording                        timestamped note events ↔ Standard MIDI File
├── Audio
│   ├── PianoEngine      AVAudioEngine → AVAudioUnitSampler → EQ ("lid") → reverb → output
│   └── MIDIInput        CoreMIDI, USB-C and Bluetooth LE MIDI keyboards
├── Keyboard
│   └── KeyboardView     UIKit UIView (wrapped in UIViewRepresentable) for multitouch
└── Screens
    ├── PlayScreen       custom layout: keyboard + notes area, reads reserved regions
    ├── LibraryScreen    NavigationSplitView: songs and recordings
    └── SettingsScreen   standard Form
```

Why each choice:

- **UIKit for the keys.** Each finger needs its own touch: note on in `touchesBegan`,
  glissando in `touchesMoved`, and note off in `touchesEnded` **and `touchesCancelled`**.
  Folding the device mid-note can cancel touches, and missing `touchesCancelled` leaves
  notes stuck on. SwiftUI gestures are weaker at tracking ten fingers at once.
- **`AVAudioUnitSampler` with a SoundFont.** It is built in, low latency, and supports the
  sustain pedal (MIDI CC 64). iOS has no built-in piano sound, so the app ships samples.
  Candidate: Salamander Grand Piano (believed to be CC BY 3.0, so it needs attribution;
  confirm the license). Trim it to fewer velocity layers to keep the download around 30–80 MB.
- **Audio session:** `.playback`, so it plays even with the silent switch on. Add the
  `.mixWithOthers` option so the piano works next to a video tutorial in Split View.
  Request a 5 ms IO buffer. Handle interruptions and route changes (headphones).
- **Standard containers outside the play screen.** `NavigationStack`, `NavigationSplitView`,
  and toolbars give the vertical side bar, overflow menus, and fold avoidance for free.
  Every toolbar item gets both an SF Symbol and a title.
- **Custom layout for the play screen.** Apple allows full-width, non-scrolling UIs without
  bars (Calculator is its example). The keyboard must stay out of the status bar, Dynamic
  Island, and camera regions. Evaluate `ArrangementView` with `.overlay` (primary = keyboard,
  secondary = notes view) in the prototype. If it can't pin the keyboard the way we need,
  use Apple's `SplitContent` reserved-region pattern instead.
- **Swift 6 language mode**, `@Observable` models, SwiftData for saved recordings.

## 5. Phases

Each phase ends with something you can run and judge.

### Phase 0: Setup (half a day)
- Create the Xcode project on the Mac: SwiftUI app, iOS 27.1, Swift 6, plus the local `PianoCore` package.
- Commit it to this repo. After that, code can be written in a cloud session and built on the Mac.
- Export Xcode's Duo skill with `xcrun agent skills export` so other coding agents can use it.
- **Done when:** the empty app runs in the iPhone Duo simulator and on any iPhone.

### Phase 1: Sound (2–3 days)
- `PianoEngine`: load the SoundFont, start and stop notes, sustain, master volume.
- Audio session setup, interruptions, route changes.
- Measure touch-to-sound latency on a real iPhone (aim for under 20 ms).
- **Done when:** a test button plays a piano note with no audible delay.

### Phase 2: Playable keyboard (3–4 days)
- `KeyboardLayout` in `PianoCore`: white and black key frames from a width, height, and
  start note. Hit-testing gives black keys priority. Unit tests cover these.
- `KeyboardView`: multitouch, glissando, cancelled touches, pressed-key highlight.
- Number of keys comes from the width you are given, never from the device. Add pinch
  to change key size (44–90 pt) and buttons to move up or down an octave.
- Velocity: a fixed level by default, plus an optional "touch position" mode (lower on the key = louder).
- **Done when:** you can play two-handed chords and glissandos on a regular iPhone in both orientations.

### Phase 3: iPhone Duo layout (3–5 days)
- Fold-aware alignment and gap (section 3), with unit tests for the start-note rule.
- Laptop pose: notes on top, keys on the bottom. Book pose: gap at the fold.
- Outer display: one octave in portrait, vertical side bar respected.
- Resizing never resets state: held sustain, octave position, current song.
- Test every pose and rotation in the simulator's Device Hub, plus extreme sizes in the
  resizable simulator and iPhone Mirroring.
- **Done when:** folding, unfolding, and rotating mid-play never sticks a note, never puts a
  key boundary with a black key in the fold, and never jumps the keyboard around.

### Phase 4: Hinge "lid" (1–2 days, optional)
- `onHingeChange`: when `.partiallyOpen`, map the hinge angle to EQ brightness and volume,
  like opening a grand piano's lid. This follows Apple's own demo, which turns the hinge
  into a guitar whammy bar.
- Off by default. People shift the angle without thinking while they play, and an
  unexpected tone change would feel like a bug.
- Smooth the value, because Apple says the update rate isn't guaranteed.
- The same control also exists as a slider in settings. Apple says features must never
  depend on one pose.
- **Done when:** the tone changes smoothly in the simulator as the hinge moves, and nothing
  happens on a regular iPhone.

### Phase 5: Practice features (1–2 weeks)
- Record and play back (MIDI events → `.mid` file, played back through the sampler), and export to audio.
- Metronome.
- External MIDI keyboards over USB-C or Bluetooth light up the on-screen keys.
- A falling-notes view for MIDI songs (`Canvas` + `TimelineView`, smooth at 120 Hz).
  It sits in the top region in laptop pose. Use public-domain pieces you encode yourself.
- Extra sounds (electric piano, organ) if the SoundFont budget allows.

### Phase 6: Polish and release (1 week)
- Accessibility: VoiceOver labels per key, with `.allowsDirectInteraction` on the keyboard
  so VoiceOver users can play. Dynamic Type for everything except the keys. Contrast.
- App icon, onboarding, and settings.
- App Store: iPhone Duo screenshots (these add the "Made for iPhone Duo" badge) and an
  attribution screen for the sample license.
- Final check on a real iPhone Duo: speakers in each pose, touch on the crease, latency.

Rough total: 4–6 weeks part-time for phases 0–4 and 6. Phase 5 adds 1–2 weeks.

## 6. Risks and unknowns

| Item | Why it matters | How to resolve |
| --- | --- | --- |
| Which speakers play in each pose | Stereo could feel lopsided when open | Test on hardware. Consider a mono-compatible mix. |
| Touch accuracy on the crease (flat) | Keys next to the fold could misfire | Fold alignment helps. Test on hardware, add a small dead zone if needed. |
| `ArrangementView` overlay behavior | It may not pin the keyboard as needed | Prototype in Phase 3; the fallback is a custom reserved-region layout. |
| Hinge angle direction (which value is flat) | The lid mapping depends on it | Check in the simulator. Not stated in the docs read so far. |
| Sample license and size | App size, legal attribution | License settled: Salamander Grand Piano is public domain (see [SOUND_LICENSING.md](SOUND_LICENSING.md)). Still to do: build a trimmed SoundFont. |
| No pressure input | Expression is limited | Position-based velocity, MIDI keyboard support. |

## 7. Questions for you

1. Do you have a Mac with Xcode 27.1, and an Apple Developer Program membership ($99/year)
   for on-device testing and the App Store?
2. Do you own or plan to get an iPhone Duo, or should testing rely on the simulator until launch?
3. Is this a personal or hobby project, or a paid App Store release? That changes how much
   of Phases 5–6 matters.
4. Should it also support older iOS versions, which means dropping assumption 2?
