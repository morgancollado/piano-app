# Piano sound licensing

Checked 2026-10-27. This app is a paid App Store release, so the samples must allow
**redistribution inside a commercial app**. Permission to use samples "in your music" isn't enough.

## Choice: Salamander Grand Piano V3 (main piano)

- **Instrument:** Yamaha C5 grand, recorded by Alexander Holm (2011). 48 kHz / 24-bit,
  16 velocity layers, notes sampled every minor third from A0, plus release samples.
- **License: public domain since 4 March 2022**, stated by the creator on his own page:
  > "As of 4.3.2022, this is now public domain!"
  > "Have fun with it, it's yours and noones!"

  Source: https://rytmenpinne.wordpress.com/sounds-and-such/salamander-grandpiano/
  In a January 2026 comment on that page, asked about commercial use, he replied that
  being public domain, nothing is required ("do what your conscience tells you").
- **Before that** it was CC BY 3.0, and some mirrors still show that notice
  ([Internet Archive](https://archive.org/details/SalamanderGrandPianoV3),
  [FreePats](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html)).
  Even if the public-domain statement were ever questioned, the earlier CC BY 3.0 grant
  also allows commercial redistribution with attribution.
- **What we do:** credit "Salamander Grand Piano by Alexander Holm" on the app's credits
  screen anyway. It costs nothing and covers both readings. Keep a copy of this file and a
  saved copy of the creator's page with the release records.
- **Build our own trimmed SoundFont from the original V3 recordings.** Ready-made "light"
  versions such as Salamander C5 Light are third-party edits with their own attribution
  terms, and the full SoundFont (~296 MB) is too large to load into an iPhone's memory.
  Download the original from https://freepats.zenvoid.org/Piano/ (44.1 kHz 16-bit SFZ, ~394 MB).

## The built SoundFont: `PianoApp/Piano.sf2`

Built on 2026-10-27 with `tools/soundfont/build_salamander_sf2.py` from
`SalamanderGrandPianoV3+20161209_44khz16bit.tar.xz` (FreePats mirror).

| | |
| --- | --- |
| Size | 64.7 MB, stereo, 44.1 kHz / 16-bit |
| Notes | 30 sampled notes (every minor third, A0–C8), each covering 2–3 keys |
| Velocity layers | 4 of the original 16: layers 4, 9, 13, 16, mapped to velocities 1–54, 55–84, 85–112, 113–127 |
| Note start | Silence before the hammer strike trimmed to 1 ms (the originals had 2–15 ms) |
| Sustain | First 1.2–3 s kept as recorded, then a crossfaded loop; the volume envelope continues the fade at the measured rate (at least 1.2 dB/s in the bass, rising to ~13 dB/s at C8) |
| Release | 1 s after key-up; 5 s from F#6 up (no dampers on a real grand) |
| Not included | Release resonance, hammer-release noise, and pedal noise samples (SoundFont 2 can't trigger samples on key release) |

Checks (`tools/soundfont/check_soundfont.py`, rendered with FluidSynth 2.3.4):
pitch within 2.2 cents of the original recordings from E2 to C8; every key at 4 velocities
sounds; all 240 loop points valid, with the worst seam jump at 1.1× a normal waveform step;
held-note fades match the originals within ~1–4 dB through 16 s in the bass and middle;
loudness rises steadily with velocity, with at most 1.2 dB extra at a layer change.

To rebuild:

```sh
curl -O "https://freepats.zenvoid.org/Piano/SalamanderGrandPiano/SalamanderGrandPianoV3+20161209_44khz16bit.tar.xz"
tar xJf SalamanderGrandPianoV3+20161209_44khz16bit.tar.xz
python3 tools/soundfont/build_salamander_sf2.py SalamanderGrandPianoV3_44.1khz16bit PianoApp/Piano.sf2
```

The README bundled inside that 2016 download still says "CC-by". That predates the creator's
2022 public-domain statement quoted above.

## Optional second sound: Upright Piano KW

- Kawai upright recorded in a living room (2017). **CC0 1.0** (formal public-domain dedication).
- SF2 ~27 MB (2 velocity layers), or a 6 MB small version.
- Lower fidelity than Salamander, but a usable "upright" voice for a second instrument.
- Source: https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html

## Fallback: University of Iowa MIS Steinway

- "Free to download and use for any project … without restrictions" since 1997.
- Raw recordings at three dynamics only (pp, mf, ff), recorded in a small teaching studio.
  It would have to be built into a SoundFont by hand.
- Source: https://theremin.music.uiowa.edu/MIS.html

## Rejected

| Set | Reason |
| --- | --- |
| GeneralUser GS | Custom license, and the author says he can't be 100% sure where all the samples came from. |
| FluidR3_GM | MIT-licensed as a whole, but a general-MIDI bank: its piano is weaker than Salamander. |
| YDP Grand Piano | CC BY 3.0 only. Fine, but adds nothing over Salamander. |
| Salamander C5 Light and other edits | Third-party derivatives with their own attribution chain; build our own instead. |
| Free libraries licensed only for music production | Usually don't allow shipping the samples inside another product. Check before using any. |
