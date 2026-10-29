# Plan: send the notes you play to a recording app (MIDI out)

Status: planned, 2026-10-29. Nothing is built yet.

Goal: notes played on the app's keys reach a DAW or other recording app (GarageBand,
Logic Pro, Ableton Live, Cubase, FL Studio, Reaper and others) so that app can record them.
The piano becomes a MIDI controller, the same job a USB keyboard does in a studio.

## What MIDI out means here

A recording app does not record the app's sound. It records **MIDI messages**, small
instructions like "note C4 on, velocity 96" and "note C4 off". The recording app then plays
those notes with any instrument it has, and the notes can be edited afterwards. So the app
has to send three kinds of message:

| Message | When | Bytes (channel 1) |
| --- | --- | --- |
| Note on | A key goes down | `0x90 note velocity` |
| Note off | A key comes up | `0x80 note 0` |
| Sustain pedal (CC 64) | The Sustain button changes | `0xB0 64 127` or `0xB0 64 0` |

On iOS, all of this goes through **CoreMIDI**, which is part of iOS (no third-party library,
no extra cost). iOS 18, the app's minimum, has every API this plan uses.

## Assumptions

1. **"Control a DAW" means sending notes (and the pedal) for recording.** Starting and stopping
   the DAW's transport (play, record) from the app is a different feature. It is listed under
   "Later" below.
2. **The recording app could be on the iPhone itself, on a Mac, or on a Windows PC.** You
   didn't say which, so the plan covers all three. The Mac route matters most because you have
   one.
3. **The app keeps its own piano sound by default**, with a setting to mute it. When a DAW
   plays the notes through its own instrument you'd otherwise hear two pianos.
4. **Free Personal Team signing is enough.** None of the routes below needs an entitlement
   that requires the paid Developer Program. Only Info.plist permission text is needed.

## Ways to connect, and which ones to build

| Route | Where the DAW is | How it works | Latency | Build it? |
| --- | --- | --- | --- | --- |
| **A. Virtual MIDI source** | Same iPhone (GarageBand for iPhone, Cubasis, AUM) | The app creates a MIDI source called "Piano". Other apps list it as a MIDI input. | Lowest, under 1 ms | Yes, first |
| **B. Send to every MIDI destination** | Anything CoreMIDI can see: USB MIDI interfaces plugged into the iPhone, a Mac over a USB-C cable (see below), Bluetooth and Wi-Fi sessions once connected | The app sends each message to all destinations. | Depends on the link | Yes, with A (same code) |
| **C. Wi-Fi to a Mac or PC** | Mac (Logic, Ableton, any DAW), Windows with the free rtpMIDI driver | Apple's network MIDI session (`MIDINetworkSession`). The Mac connects to the iPhone in Audio MIDI Setup; the DAW then sees an input called "Network Session 1". | Usually a few ms, with some jitter on busy Wi-Fi | Yes, second |
| **D. Bluetooth to a Mac** | Mac, or anything that hosts Bluetooth LE MIDI | Apple's `CABTMIDILocalPeripheralViewController` makes the iPhone advertise as a Bluetooth MIDI device. The Mac connects in Audio MIDI Setup → MIDI Studio → Bluetooth. | Around 10–15 ms, more jitter than Wi-Fi | Yes, third |
| **E. USB-C cable to a Mac** | Mac | Plug the iPhone into the Mac, open Audio MIDI Setup → Audio Devices, click **Enable** under the iPhone (Apple calls this IDAM). The app sees a destination called "IDAM MIDI Host"; route B already sends to it. | Lowest of the computer routes | Free with B. Needs a test: third-party reports say it must be re-enabled after unplugging or sleep, and it turns off the iPhone-as-camera mode while on. |
| F. Audio Unit MIDI plug-in (AUv3) | Inside an iPhone DAW, as a plug-in | A separate app extension target that a DAW loads | Lowest | No, not now. Large separate project; see "Later". |

Why this order: A and B are one small class and let you test with GarageBand on the same
iPhone straight away. C is the most useful for a Mac and needs no cable. D covers places
without shared Wi-Fi. E costs nothing extra to support.

### iPhone Duo bonus

On the open iPhone Duo, Split View puts two apps side by side at 50/50 (see
[IPHONE_DUO_REFERENCE.md](IPHONE_DUO_REFERENCE.md), "Audio, scenes, and multitasking"). With
route A you can have GarageBand in one half recording and this piano in the other. Both apps
stay in the foreground, so no background-mode work is needed for that. The audio session
already uses `.mixWithOthers`, so both apps can make sound. This is worth showing in App
Store screenshots.

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
sustain and pause/background are forwarded the same way. Nothing in the keyboard view
changes, so the existing "every touch path ends its notes" guarantee carries over.

## Design

### Pure logic in PianoCore (testable on Linux)

New file `Packages/PianoCore/Sources/PianoCore/MIDIOut.swift`, no CoreMIDI import:

- `MIDIChannel`: 0–15 inside, shown to people as 1–16.
- `MIDIMessage`: `.noteOn(Note, velocity, channel)`, `.noteOff(Note, channel)`,
  `.controlChange(controller, value, channel)`, with a `bytes: [UInt8]` property.
- `MIDIOutLedger`: a struct that turns `[NoteEvent]` into `[MIDIMessage]` and remembers which
  notes the DAW currently thinks are down. It handles three cases the sampler doesn't care
  about but a recording does:
  1. **Re-strike.** `TouchTracker` sends note on, note on, note off when a second finger hits
     a key that's already down (see `TouchTracker.begin`). The sampler copes, but a DAW can
     record two overlapping notes with one left hanging. The ledger sends note off then note
     on for a re-strike, so the DAW records two clean notes.
  2. **Panic.** `releaseAll()` returns a note off for every note it thinks is down, then
     CC 64 = 0 (pedal up) and CC 123 (All Notes Off). Used when the app goes to the
     background, when MIDI out is turned off, and when the channel changes. A stuck note in a
     recording becomes a note that lasts until the end of the take, which is worse than a
     stuck note in the speaker.
  3. **Channel change while playing.** Releases held notes on the old channel before using
     the new one.
- Unit tests in `Tests/PianoCoreTests/MIDIOutTests.swift`: byte encoding for each message,
  velocity clamping, re-strike order, panic contents, channel change, and that a note off for
  a note that isn't down sends nothing.

### App side (`PianoApp/MIDI/`, Xcode build only)

- `MIDIOutput.swift`, `@MainActor @Observable`:
  - `MIDIClientCreateWithBlock` for the client. Its notify block runs on a CoreMIDI thread,
    so it hops to the main actor to refresh the list of connected destinations (Swift 6).
  - `MIDISourceCreateWithProtocol(client, "Piano", ._1_0, …)` for the virtual source
    (route A), and `MIDIOutputPortCreate` for route B.
  - `send(_ messages: [MIDIMessage])` builds one `MIDIEventList` (MIDI 1.0 words from
    `MIDI1UPNoteOn`, `MIDI1UPNoteOff` and `MIDI1UPControlChange`, added with
    `MIDIEventListInit`/`MIDIEventListAdd`), calls `MIDIReceivedEventList` on the virtual source,
    and `MIDISendEventList` to each destination. The app's own virtual source is skipped as a
    destination so notes don't loop back.
  - `isEnabled`, `channel`, `connectedNames` (for the settings screen), and `panic()`.
  - Rebuilds its client after `AVAudioSession.mediaServicesWereResetNotification`, the same
    way `PianoEngine` rebuilds its audio graph.
- `NetworkMIDI.swift` (route C): turns `MIDINetworkSession.default()` on with
  `connectionPolicy = .anyone` only when the person turns on "Wi-Fi" in settings, because
  that's what triggers iOS's local network permission prompt. Lists connected computers from
  `session.connections()`.
- `BluetoothMIDIView.swift` (route D): a `UIViewControllerRepresentable` around
  `CABTMIDILocalPeripheralViewController` (import CoreAudioKit), shown as a sheet from settings.
- `PlaySession` changes:
  - owns `let midi = MIDIOutput()`;
  - `handle(_:)` sends events to `midi` as well as the engine;
  - a new saved setting `playsSoundLocally` (default on). When off, `handle(_:)` skips
    `engine.noteOn` but still updates the keys and trails;
  - `sustainOn` setter also sends CC 64;
  - saved settings `midiEnabled` (default on: a virtual source costs nothing and shows no
    prompt), `midiChannel` (default 1), `networkMIDIEnabled` (default off).
- `RootView`: on `.background`, call `session.midi.panic()` next to `engine.pause()`; on
  `.active`, send the current sustain state again.
- `SettingsScreen`: a new section "Send to recording apps":
  - Toggle "Send notes as MIDI"
  - Picker "MIDI channel" (1–16)
  - Toggle "Play sound in this app"
  - Toggle "Allow Wi-Fi connections" with a footer: "On your Mac, open Audio MIDI Setup →
    Window → Show MIDI Studio → Network, select this iPhone and click Connect."
  - Button "Connect over Bluetooth…" (opens the Bluetooth sheet)
  - "Connected" list showing what's connected, or "Nothing connected"
  - Button "Stop all notes" (panic), for when a DAW somewhere is left holding a note.
  Buttons use a title and an SF Symbol, per the project rules.

### Info.plist and project changes (do on the Mac)

| Key | Value | Needed for |
| --- | --- | --- |
| `NSLocalNetworkUsageDescription` | "Piano sends the notes you play to music apps on your Mac or PC over Wi-Fi." | Route C |
| `NSBonjourServices` | `["_apple-midi._udp"]` | Route C (advertising the session) |
| `NSBluetoothAlwaysUsageDescription` | "Piano can connect to your Mac over Bluetooth to send the notes you play." | Route D |

The first and third can be build settings (`INFOPLIST_KEY_…`) because the project generates
its Info.plist. `NSBonjourServices` is an array, which build settings can't express, so it
needs a small Info.plist file merged with the generated one (set `INFOPLIST_FILE` and keep
`GENERATE_INFOPLIST_FILE = YES`). Put that file **outside** `PianoApp/`, for example
`Config/Info.plist`: files inside the folder-synced group are copied into the bundle
automatically, which makes Xcode fail with "Multiple commands produce Info.plist".

No background mode is added. The app only sends MIDI while someone is touching its keys, and
that only happens in the foreground. A DAW on the same iPhone needs its own background audio
setting to keep recording while you switch to the piano; GarageBand has one.

## Steps

Each step ends with something you can try.

1. **PianoCore MIDI logic and tests** (about half a day, can be done in a cloud session).
   Done when `swift test` passes on Linux with the new tests.
2. **Virtual source and send to all destinations, settings section without Wi-Fi/Bluetooth,
   panic on background** (1–2 days). Test with GarageBand on the iPhone: add a Keyboard
   track, record, play the app's keys. On iPhone Duo, try it in Split View. Also try the
   USB-C cable route (E) with Logic on the Mac.
   Done when GarageBand records what you play, chords included, and backgrounding mid-chord
   leaves no note hanging in the recording.
3. **Wi-Fi** (1 day). Test with Logic Pro and, if you have it, Ableton Live (in Ableton turn
   on "Track" for the "Network Session 1" input under Settings → Link, Tempo & MIDI). Done
   when a Mac records over Wi-Fi and the settings screen shows the Mac as connected.
4. **Bluetooth** (half a day to 1 day). Done when a Mac records over Bluetooth with Wi-Fi
   off on the iPhone.
5. **Better timing in recordings** (half a day, optional but recommended). Today a note is
   sent when the main thread gets to it, which can be a few ms after the finger landed. Each
   `UITouch` has a `timestamp` (seconds since boot); converting it to host time and putting it
   on the MIDI message lets the DAW place the note where the finger actually landed. This
   needs a timestamp field on `NoteEvent` and a check on device that the clocks line up.

Rough total: 4–6 days part-time, plus testing.

## Later (not in this plan)

- **Hinge as a controller on iPhone Duo.** Send the hinge angle as a MIDI control (mod wheel,
  expression, or pitch bend, which is Apple's own whammy-bar demo). The angle is already in
  `PlaySession.hinge`. Off by default, same reasoning as the hinge lid.
- **Transport buttons** (record, play, stop) using MIDI Machine Control. Support varies a lot
  between DAWs (Logic and Reaper have settings for it; others don't), so it needs research first.
- **Audio Unit MIDI plug-in (route F).** Lets an iPhone DAW load the keyboard as a plug-in.
  It's a separate app extension with its own UI and size limits, so it's a project of its own.
- **Receive MIDI** (light up keys from an external keyboard) is already in Phase 5 of
  [PLAN.md](PLAN.md) and shares the `MIDIOutput` client code.

## Risks and things to test on hardware

| Item | Why it matters | How to resolve |
| --- | --- | --- |
| Hearing two pianos | The app's sound and the DAW's instrument play at once, slightly out of time | "Play sound in this app" toggle. Mention it in the settings footer. |
| Fixed velocity | Every recorded note has the same loudness by default | Point people to "Lower on the key is louder". It already exists. |
| Wi-Fi jitter | Notes can land a few ms early or late in the recording | Step 5 timestamps help. Recommend USB-C for serious takes. |
| IDAM (USB to Mac) still working in macOS 27 | Only third-party reports, some old | Test in step 2. If it doesn't work, drop it from the help text. |
| `MIDINetworkSession` permission prompt | When exactly iOS asks isn't documented | Test in step 3. Turn the session on only from the settings toggle. |
| GarageBand for iPhone listing other apps' virtual sources | Route A depends on it | Test in step 2. If it doesn't, Cubasis and AUM do. |
| Windows | Needs the free rtpMIDI driver for Wi-Fi; no USB route | Mention in help text. Test only if Windows users matter for launch. |
