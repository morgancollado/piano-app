# Plan: play and record into a DAW (MIDI out and transport buttons)

Status: code written, 2026-10-29. PianoCore part tested on Linux (75 tests passing). The
app part (`PianoApp/MIDI/`, settings, toolbar) is written but **not yet compiled**: it needs
an Xcode build on the Mac, then the hardware tests in "Steps".

### Built, and where it differs from the plan below

| Plan | What was built | Why |
| --- | --- | --- |
| MIDI channel picker 1–16 | 1–15 | Channel 16 carries the buttons. Letting notes use it too would let a track set to channel 16 record the button presses. |
| Send to every destination | Every destination that belongs to a device (Wi-Fi session, cable, Bluetooth, USB gear). Other apps' virtual inputs are skipped. | Apps on the same iPhone already read the "Piano" source. Sending to their own inputs as well (AUM has one, for example) would play every note twice. |
| `MIDIOutput` rebuilds after a media services reset | Not done | That reset restarts the audio system. CoreMIDI runs in its own server and isn't affected. |
| Timestamp field on `NoteEvent` | The keyboard passes `UIEvent.timestamp` alongside the events | Same result without touching `NoteEvent` or `TouchTracker`. Ages over 50 ms, or in the future, are sent as "now", so a clock mismatch can't delay notes. |
| Transport button press and release read separately | Each tap sends 127 then 0 | Toolbar buttons don't reliably report press and release separately. |
| `NetworkMIDI.swift` | Part of `MIDIOutput.swift` | It's about 20 lines. |
| `BluetoothMIDIView.swift` | Same file name; the sheet says to keep it open until the Mac connects | Apple's screen may stop advertising when it closes. |

Files: `Packages/PianoCore/Sources/PianoCore/MIDIOut.swift` (+ tests),
`PianoApp/MIDI/MIDIOutput.swift`, `BluetoothMIDIView.swift`, `ReaperSetupView.swift`,
`Config/Info.plist`, and changes to `PlaySession`, `RootView`, `SettingsScreen`,
`KeyboardUIView`/`KeyboardView`, `PlayScreen` and `PianoTheme`.

First things to check after the first Xcode build: the cable route's "IDAM MIDI Host"
destination counts as a device (if not, the cable route sends nothing; see
`MIDIOutput.externalDestinations()`), and Reaper doesn't fire a learned button twice per tap.

Goal: the app works as a MIDI keyboard for a DAW on another device. Notes you play are
recorded by the DAW, and Record, Play and Stop buttons in the app run the DAW's transport.
Main target: **Reaper on your Mac**, connected over **Wi-Fi, a USB-C cable, or Bluetooth**
(any of the three). It should also work with any other DAW that accepts a MIDI keyboard.

## What gets sent

A DAW does not record the app's sound. It records **MIDI messages**, small instructions like
"note C4 on, velocity 96". It plays them through its own instrument, and you can edit them
afterwards. Every DAW accepts these, which is what makes "any DAW" possible.

| Message | When | Bytes |
| --- | --- | --- |
| Note on | A key goes down | `0x90 note velocity` (channel 1) |
| Note off | A key comes up | `0x80 note 0` (channel 1) |
| Sustain pedal (CC 64) | The Sustain button changes | `0xB0 64 127` or `0xB0 64 0` (channel 1) |
| Record, Play, Stop | The app's transport buttons | Two choices, see "Transport buttons" |

On iOS all of this goes through **CoreMIDI**, which is part of iOS, so there's no third-party
library or extra cost. iOS 18, the app's minimum, has every API this plan uses.

## Assumptions

1. **The DAW runs on a different device**, mainly your Mac with Reaper. A DAW on the same
   iPhone also works and costs nothing extra (route D below), so it stays in.
2. **"Any DAW" means any DAW that accepts a MIDI keyboard** for notes, and any DAW that can
   **MIDI-learn** its transport or accepts **MIDI Machine Control** for the buttons. Nearly
   every desktop DAW does one of those. A few DAWs, such as GarageBand for Mac, have
   neither, so in those only the notes work. See "DAW support" below.
3. **The buttons send commands and can't show the DAW's state.** Over a plain MIDI
   connection the DAW doesn't tell the app whether it's recording. So the Record button can't
   light up when Reaper is recording; it only flashes when you tap it. Showing the real state
   needs Mackie Control, under "Later".
4. **The app keeps its own piano sound by default**, with a setting to mute it. When Reaper
   plays the notes through its own instrument you'd otherwise hear two pianos, slightly out
   of time.
5. **Free Personal Team signing is enough.** Nothing here needs an entitlement that requires
   the paid Developer Program; only Info.plist permission text.

## Ways to connect

All three routes you asked for end up as an ordinary MIDI input in Reaper. The app sends every
message to every connected destination, so you can use whichever is handy.

| Route | How you connect it | What Reaper sees | Latency | Notes |
| --- | --- | --- | --- | --- |
| **A. Wi-Fi** | Turn on "Allow Wi-Fi connections" in the app. On the Mac: Audio MIDI Setup → Window → Show MIDI Studio → Network (globe button). Add a session under My Sessions and tick Enabled, then select the iPhone under Directory and click Connect. | An input called "Network Session 1" | A few ms, some jitter on busy Wi-Fi | Apple's network MIDI (`MIDINetworkSession`). Also works on Windows with the free rtpMIDI driver. |
| **B. USB-C cable** | Plug the iPhone into the Mac. Audio MIDI Setup → Audio Devices, click **Enable** under the iPhone. | A MIDI device named after the iPhone | Lowest and steadiest | Apple calls this IDAM. On the iPhone it shows up as a destination called "IDAM MIDI Host". Third-party reports say it has to be re-enabled after unplugging or sleep. Needs a test on macOS 27. |
| **C. Bluetooth** | Tap "Connect over Bluetooth…" in the app; it starts advertising. On the Mac: Audio MIDI Setup → MIDI Studio → Bluetooth button → Connect next to the iPhone. | A Bluetooth MIDI device named after the iPhone | Around 10–15 ms, more jitter | Apple's `CABTMIDILocalPeripheralViewController`. Useful where there's no shared Wi-Fi. |
| D. Same iPhone | Nothing to do | GarageBand for iPhone, Cubasis or AUM list an input called "Piano" | Under 1 ms | A virtual MIDI source. Same code as the rest. On the open iPhone Duo it works side by side in Split View. |

For serious takes, recommend the cable: it has the steadiest timing. Wi-Fi is the easiest
day to day.

## Transport buttons (Record, Play, Stop)

### Which messages to send

A Wi-Fi, Bluetooth or cable connection carries **one MIDI port**, shared by notes and
buttons. That rules out Mackie Control for now: a DAW takes over the whole port for a Mackie
device, and Mackie's transport buttons are notes 91–95 on channel 1, which are also G6–B6 on
the piano. So the app offers two kinds of button message, chosen in settings:

| Mode | What's sent | Setup in the DAW | Works in |
| --- | --- | --- | --- |
| **Learnable buttons** (default) | Control changes on **channel 16**, away from the notes on channel 1: Record = CC 117, Play = CC 118, Stop = CC 119 (in the range MIDI leaves unassigned). Each tap sends 127 then 0, like a quick press of a hardware button. | One-time "MIDI learn": point the DAW's Record/Play/Stop command at each button and tap it in the app. | Reaper, Logic, Ableton Live, Cubase, Studio One and most other DAWs with MIDI learn |
| **MIDI Machine Control (MMC)** | The standard transport messages: Stop `F0 7F 7F 06 01 F7`, Play `F0 7F 7F 06 02 F7`, Record `F0 7F 7F 06 06 F7` | Turn on MMC input in the DAW, no learning | Logic, Cubase and other DAWs that accept MMC. Reaper: possible, but one report says it ignores MMC until you've pressed Play in Reaper once, and record wasn't confirmed. Test before recommending. |

Why only one mode at a time: a DAW that responded to both would act twice, and Reaper's
Record command toggles, so two triggers would start and stop recording at once.

Why "learnable buttons" is the default: it works with Reaper for certain, and with any DAW
that has MIDI learn, which is more DAWs than accept MMC.

### When the buttons appear

A setting "Show Record, Play and Stop" with three choices:

- **When connected** (default): shown while a Wi-Fi, cable or Bluetooth connection is live.
  The app can see that a computer is connected. It can't tell whether Reaper is the program
  listening, so "connected to a DAW" in practice means "connected to a computer".
- **Always**: for a DAW on the same iPhone (route D), where iOS doesn't say who's listening.
- **Never**.

### Where the buttons go

In the navigation bar, like the existing controls, so iPhone Duo moves them into its side bar
automatically. Each has a title and an SF Symbol, as the project rules require: Record
(`record.circle`), Play (`play.fill`), Stop (`stop.fill`). Record is drawn in red so it's easy
to find.

The bar then holds seven controls (Octave Down, Octave Up, Sustain, Settings, plus three).
That's fine on iPhone Duo's side bar and in landscape. It may be too tight on a small iPhone in
portrait; see "Risks".

### Notes and the transport

- Pressing Stop doesn't release keys you're holding. You might stop the DAW while still playing.
- Going to the background releases everything (see "Stuck notes" below) but sends no transport
  command, so Reaper keeps recording if you switch apps.

## DAW support

How to check any DAW: notes work if it accepts a MIDI keyboard. Buttons work if it can
MIDI-learn its transport commands or accepts MMC.

| DAW (Mac) | Notes | Buttons | Setup for the buttons |
| --- | --- | --- | --- |
| **Reaper** | Yes | Yes, learnable buttons | See "Setting up Reaper" below |
| Logic Pro | Yes (takes all inputs by default) | Yes | MMC: Project Settings → Synchronization → MIDI → listen to MMC input. Or Controller Assignments / Learn for the CCs. |
| Ableton Live | Yes (turn on Track for the input) | Yes, learnable buttons | MIDI Map mode (⌘M), click Play, tap Play in the app; same for Stop and Record. Turn on Remote for the input. Live doesn't accept MMC as far as I know. |
| Cubase / Nuendo | Yes | Yes | MIDI Remote mapping assistant for the CCs, or MMC input in Project Synchronization Setup |
| Studio One, Bitwig, FL Studio, Pro Tools | Yes | Test each | All take notes. Transport learning differs; Pro Tools generally needs HUI, which is under "Later". |
| GarageBand for Mac | Yes | Probably not | No MIDI learn for the transport |

The cells marked "test" and the MMC details are from general knowledge and forum posts, not
from trying them. Step 5 checks the ones that matter for the launch.

### Setting up Reaper (the help text in the app, and your test script)

1. Connect the iPhone by Wi-Fi, cable or Bluetooth (table above).
2. Reaper → Settings (⌘,) → Audio → **MIDI Inputs** (called MIDI Devices in older versions).
   Find the input ("Network Session 1", or the iPhone's name). Right-click it and choose
   **Enable input**, then right-click again and choose **Enable input for control messages**
   (needed for the buttons). If it isn't listed, close and reopen Settings.
3. Make a track, arm it for recording, and set its input to that MIDI device, **channel 1**.
   Choosing channel 1 rather than "All channels" keeps the button presses (channel 16) out of
   the recording. Add an instrument to the track to hear it (ReaSynth, or a piano plug-in).
4. Buttons: Actions → Show action list. Find **Transport: Record**, click **Add…**, tap
   Record in the app, OK. Repeat for **Transport: Play** and **Transport: Stop**. Reaper keeps
   these shortcuts for every project.
5. In the app, turn off "Play sound in this app" if you're listening through Reaper.

## How notes flow today, and where MIDI out plugs in

Today (read from the code):

```
KeyboardUIView (touchesBegan / Moved / Ended / Cancelled)
  → TouchTracker (PianoCore) → [NoteEvent]
  → PlaySession.handle(_:)
       → PianoEngine.noteOn / noteOff     (the sound)
       → soundingNotes, trails            (the screen)
Sustain button → PlaySession.sustainOn → PianoEngine.sustainOn (CC 64 to the sampler)
App goes to background → PianoEngine.pause() → allNotesOff()
```

With MIDI out, `PlaySession.handle(_:)` also passes each event to a new `MIDIOutput`, and
sustain and pause/background are forwarded the same way. The transport buttons call
`MIDIOutput` directly. Nothing in the keyboard view changes, so the existing "every touch path
ends its notes" guarantee carries over.

## Design

### Pure logic in PianoCore (testable on Linux)

New file `Packages/PianoCore/Sources/PianoCore/MIDIOut.swift`, with no CoreMIDI import:

- `MIDIChannel`: 0–15 inside, shown to people as 1–16.
- `MIDIMessage`: `.noteOn(Note, velocity, channel)`, `.noteOff(Note, channel)`,
  `.controlChange(controller, value, channel)`, `.machineControl(MMCCommand)`.
- `TransportCommand` (`.record`, `.play`, `.stop`) and `TransportMode` (`.learnable`,
  `.machineControl`). `TransportMode.messages(for:)` returns what one tap sends: the CC at 127
  then 0 for learnable buttons, or the one MMC message.
- **Universal MIDI Packet words.** iOS's current CoreMIDI send functions take 32-bit "UMP"
  words. `MIDIMessage.umpWords` builds them here, so the bit packing is unit-tested on Linux.
  Channel messages are one word (type 2). An MMC message is one 64-bit SysEx7 packet (type 3,
  "complete in one packet", 4 data bytes `7F 7F 06 cc`).
- `MIDIOutLedger`: turns `[NoteEvent]` into `[MIDIMessage]` and remembers which notes the DAW
  thinks are down. It covers three cases the built-in sound doesn't care about but a recording
  does:
  1. **Re-strike.** `TouchTracker` sends on, on, off when a second finger hits a key that's
     already down (`TouchTracker.begin`). A DAW can record that as two overlapping notes with
     one left hanging. The ledger sends off then on, so the DAW records two clean notes.
  2. **Stuck notes.** `releaseAll()` returns a note off for every note it thinks is down, then
     pedal up (CC 64 = 0) and All Notes Off (CC 123). Used when the app goes to the background,
     when MIDI out is turned off, when the channel changes, and from a "Stop all notes" button.
     A stuck note in a recording lasts until the end of the take, which is worse than one in
     the speaker.
  3. **Channel change while playing.** Releases held notes on the old channel first.
- Tests in `Tests/PianoCoreTests/MIDIOutTests.swift`: bytes and UMP words for each message
  (checked against the byte tables above), velocity clamping, re-strike order, release-all
  contents, channel change, a note off for a note that isn't down sends nothing, transport
  taps in both modes, and transport CCs never on the notes' channel.

### App side (`PianoApp/MIDI/`, Xcode build only)

- `MIDIOutput.swift`, `@MainActor @Observable`:
  - `MIDIClientCreateWithBlock` for the client. Its notify block runs on a CoreMIDI thread, so
    it hops to the main actor to refresh the connection list (Swift 6).
  - `MIDISourceCreateWithProtocol(client, "Piano", ._1_0, …)` for the virtual source (route D)
    and `MIDIOutputPortCreate` for sending to destinations (routes A–C).
  - `send(_ messages: [MIDIMessage])` copies `umpWords` into one `MIDIEventList`
    (`MIDIEventListInit` / `MIDIEventListAdd`), calls `MIDIReceivedEventList` on the virtual
    source and `MIDISendEventList` to each destination. Its own virtual source is skipped as a
    destination so nothing loops back.
  - `send(_ command: TransportCommand)` for the buttons.
  - `isConnected` and `connectedNames` for the settings screen and for showing the buttons:
    true when the network session has a connection, or a destination other than the app's own
    is online (cable and Bluetooth appear as destinations).
  - Rebuilds its client after `AVAudioSession.mediaServicesWereResetNotification`, the same
    way `PianoEngine` rebuilds its audio graph.
- `NetworkMIDI.swift` (route A): turns `MIDINetworkSession.default()` on with
  `connectionPolicy = .anyone`, only when "Allow Wi-Fi connections" is turned on, because that's
  what triggers iOS's local network permission prompt. Lists computers from
  `session.connections()`.
- `BluetoothMIDIView.swift` (route C): a `UIViewControllerRepresentable` around
  `CABTMIDILocalPeripheralViewController` (import CoreAudioKit), shown as a sheet from settings.
- `PlaySession` changes:
  - owns `let midi = MIDIOutput()`;
  - `handle(_:)` sends events to `midi` as well as the engine;
  - `sustainOn` setter also sends CC 64;
  - new saved settings: `midiEnabled` (default on: the virtual source costs nothing and shows
    no prompt), `midiChannel` (default 1), `playsSoundLocally` (default on; when off,
    `handle(_:)` skips `engine.noteOn` but still lights the keys and trails),
    `networkMIDIEnabled` (default off), `transportMode` (default learnable),
    `transportVisibility` (default when connected).
- `RootView`:
  - on `.background`, `session.midi` releases all notes next to `engine.pause()`; on `.active`,
    sends the current sustain state again;
  - a `ToolbarItemGroup` with Record, Play and Stop, shown per `transportVisibility`. Each is a
    plain `Button` with a title and SF Symbol that calls `session.midi.send(.record)` and so on.
- `SettingsScreen`, new section **"Recording apps (MIDI)"**:
  - Toggle "Send notes as MIDI"
  - Picker "MIDI channel" (1–16)
  - Toggle "Play sound in this app"
  - Toggle "Allow Wi-Fi connections", with the Mac steps in the footer
  - Button "Connect over Bluetooth…"
  - "Connected" list, or "Nothing connected"
  - Picker "Record, Play and Stop buttons": When connected / Always / Never
  - Picker "Button messages": Learnable (MIDI learn) / MIDI Machine Control
  - Button "Stop all notes"
  - Link "Set up Reaper" → a short help page with the Reaper steps above (other DAWs later)

### Info.plist and project changes (do on the Mac)

| Key | Value | Needed for |
| --- | --- | --- |
| `NSLocalNetworkUsageDescription` | "Piano sends the notes you play to music apps on your Mac or PC over Wi-Fi." | Wi-Fi |
| `NSBonjourServices` | `["_apple-midi._udp"]` | Wi-Fi (advertising the session) |
| `NSBluetoothAlwaysUsageDescription` | "Piano can connect to your Mac over Bluetooth to send the notes you play." | Bluetooth |

The first and third can be build settings (`INFOPLIST_KEY_…`) because the project generates
its Info.plist. `NSBonjourServices` is an array, which build settings can't express, so it
needs a small Info.plist file merged with the generated one (set `INFOPLIST_FILE` and keep
`GENERATE_INFOPLIST_FILE = YES`). Put that file **outside** `PianoApp/`, for example
`Config/Info.plist`. Files inside the folder-synced group are copied into the bundle
automatically, which makes Xcode fail with "Multiple commands produce Info.plist".

No background mode is added. The app only sends MIDI while you're touching it, which only
happens in the foreground.

## Steps

Each step ends with something you can try.

1. **PianoCore MIDI logic and tests** (about 1 day, can be done in a cloud session). Messages,
   UMP words, ledger, transport modes. Done when `swift test` passes on Linux.
2. **MIDIOutput, Wi-Fi, settings section** (2 days). Done when Reaper on your Mac records what
   you play over Wi-Fi, chords and pedal included, and backgrounding the app mid-chord leaves
   no note hanging in the take.
3. **Record, Play and Stop** (1 day). Done when, after the one-time learn in Reaper, the app's
   buttons start a recording, play it back and stop, and the button presses don't appear in the
   recorded MIDI. Also check the toolbar on the smallest iPhone you can test (simulator) and on
   iPhone Duo's side bar.
4. **Cable and Bluetooth** (1 day). The cable needs no new app code, only testing (IDAM).
   Bluetooth needs the settings sheet. Done when steps 2–3 pass over each route.
5. **Other DAWs and MMC** (half a day of testing). Try MMC mode in Reaper and Logic (Logic's
   trial is free), and learnable mode in Ableton's trial if you can. Update the DAW support
   table with what actually worked.
6. **Better timing in recordings** (half a day, recommended). Today a note is sent when the
   main thread gets to it, which can be a few ms after the finger landed. Each `UITouch` has a
   `timestamp`; converting it to host time and putting it on the MIDI message lets the DAW
   place the note where the finger landed. Needs a timestamp field on `NoteEvent` and a check
   on device that the clocks line up.

Rough total: 5–7 days part-time, plus testing.

## Later (not in this plan)

- **Mackie Control.** Would light the Record button while the DAW is recording, because the DAW
  sends button lights back. Needs a second MIDI port so it doesn't clash with notes, which
  Wi-Fi and Bluetooth don't give (one port each), so it needs research first.
- **HUI** for Pro Tools transport.
- **More transport buttons**: Go to Start, Loop, Undo. Same design, more CCs.
- **Hinge as a controller on iPhone Duo.** Send the hinge angle as mod wheel, expression or
  pitch bend (Apple's own whammy-bar demo). The angle is already in `PlaySession.hinge`. Off by
  default, like the hinge lid.
- **Audio Unit MIDI plug-in** so an iPhone DAW can load the keyboard as a plug-in. A separate
  app extension, so a project of its own.
- **Receive MIDI** (light up keys from an external keyboard) is in Phase 5 of [PLAN.md](PLAN.md)
  and can share the `MIDIOutput` client.

## Risks and things to test on hardware

| Item | Why it matters | How to resolve |
| --- | --- | --- |
| Hearing two pianos | The app's sound and Reaper's instrument play together, slightly out of time | "Play sound in this app" toggle, mentioned in the Reaper help |
| Fixed velocity | Every recorded note has the same loudness by default | Point to "Lower on the key is louder", which already exists |
| Wi-Fi and Bluetooth jitter | Notes land a few ms early or late in the take | Step 6 timestamps; recommend the cable for serious takes |
| Reaper triggering an action on both the 127 and the 0 | A learned Record could toggle twice | Test in step 3. If it happens, send 127 only. |
| Button presses recorded as MIDI | Channel-16 CCs could end up in the take | Track input on channel 1 (Reaper step 3). Test in step 3. |
| Seven controls in the bar on a small iPhone in portrait | Buttons could be squeezed or cut off | Check in step 3. Fallback: combine Octave Down/Up into one control, or hide the transport buttons in portrait on narrow widths (decided by the width you're given, never by device). |
| IDAM (cable) on macOS 27 | Only third-party reports, some old | Test in step 4; drop from the help if it doesn't work |
| `MIDINetworkSession` permission prompt timing | Not documented | Test in step 2; the session only turns on from the settings toggle |
| MMC in Reaper | One report of it ignoring MMC until Play is pressed once; record unconfirmed | Learnable buttons are the default; MMC tested in step 5 |
