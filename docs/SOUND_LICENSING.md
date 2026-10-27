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
