#!/usr/bin/env python3
"""Build the app's piano SoundFont (Piano.sf2) from the Salamander Grand Piano V3 recordings.

Source: Salamander Grand Piano V3 by Alexander Holm, 44.1 kHz / 16-bit SFZ version,
https://freepats.zenvoid.org/Piano/ (public domain since 2022, see docs/SOUND_LICENSING.md).

What it does to fit on a phone (the full set is ~1.2 GB of audio):
  * Keeps a few of the 16 velocity layers and re-spreads them over velocities 1-127.
  * Trims the silence before each note (2-15 ms in the originals), which lowers latency.
  * Keeps the first few seconds of each note as recorded, then loops a short stretch of the
    tail. The loop is level-flattened and crossfaded so the seam is smooth, and the SoundFont
    volume envelope continues the decay at the rate measured from that recording. Held notes
    therefore fade out naturally instead of stopping when the sample ends.
  * Writes a standard SoundFont 2.01 file with stereo-linked samples.

Usage:
  python3 build_salamander_sf2.py <SalamanderGrandPianoV3_44.1khz16bit folder> <output.sf2>
      [--layers 4,9,13,16] [--mono]

Needs Python 3.9+ and numpy.
"""

from __future__ import annotations

import argparse
import math
import os
import re
import struct
import sys
import wave
from dataclasses import dataclass

import numpy as np

SAMPLE_RATE = 44100

# Original Salamander velocity layer -> centre of the velocity range it was mapped to.
# Taken from SalamanderGrandPianoV3.sfz (lovel/hivel per layer).
LAYER_RANGES = {
    1: (1, 26), 2: (27, 34), 3: (35, 36), 4: (37, 43), 5: (44, 46), 6: (47, 50),
    7: (51, 56), 8: (57, 64), 9: (65, 72), 10: (73, 80), 11: (81, 88), 12: (89, 96),
    13: (97, 104), 14: (105, 112), 15: (113, 120), 16: (121, 127),
}

# Keys from F#6 (MIDI 89) up have no dampers on a grand piano, so they ring after release.
# Matches the "Notes without dampers" group in the original SFZ.
FIRST_UNDAMPED_KEY = 89

NOTE_OFFSETS = {"C": 0, "D#": 3, "F#": 6, "A": 9}

# Share of the natural loudness difference between kept velocity layers that is preserved.
LAYER_STEP_KEPT = 0.15


@dataclass
class Region:
    file: str
    lokey: int
    hikey: int
    root: int
    layer: int


@dataclass
class Prepared:
    name: str
    channels: list[np.ndarray]  # one array per channel (float while building, int16 when written)
    loop_start: int
    loop_end: int
    hold_seconds: float
    decay_db_per_second: float
    level_db: float


def register_settings(key: int) -> tuple[float, float]:
    """(seconds kept before the loop, loop length in seconds) by register."""
    if key <= 45:   # up to A2
        return 3.0, 1.2
    if key <= 69:   # up to A4
        return 2.4, 1.0
    if key <= 84:   # up to C6
        return 1.8, 0.8
    return 1.2, 0.5


def minimum_decay(key: int) -> float:
    """Slowest fade allowed after the loop starts, in dB per second.

    1.2 dB/s up to A2, then doubling every 18 semitones (about 3 dB/s at A4, 13 dB/s at C8),
    a smooth curve so neighbouring notes fade alike.
    """
    return 1.2 * 2 ** (max(key - 45, 0) / 18)


def fit_slope(env: np.ndarray, first: int, stop: int, window: int) -> float:
    """Slope in dB per second of a straight-line fit to env[first:stop]."""
    stop = min(stop, len(env))
    if stop - first < 2:
        return 0.0
    times = np.arange(first, stop) * window / SAMPLE_RATE
    slope, _ = np.polyfit(times, env[first:stop], 1)
    return float(slope)


def parse_sfz(path: str) -> list[Region]:
    """Note regions from the two sustained-note groups. Release and pedal groups are skipped."""
    regions: list[Region] = []
    in_notes = False
    with open(path, encoding="latin-1") as handle:
        for line in handle:
            line = line.strip()
            if line.startswith("<group>"):
                in_notes = "trigger=release" not in line and "on_locc64" not in line and "on_hicc64" not in line
                continue
            if not in_notes or not line.startswith("<region>"):
                continue
            fields = dict(re.findall(r"(\w+)=(\S+)", line))
            sample = fields["sample"].replace("\\", "/")
            match = re.search(r"([A-G]#?)(\d)v(\d+)\.wav$", sample)
            if not match:
                continue
            # The file name is the reliable source of the pitch: some regions (the C4 ones)
            # leave out pitch_keycenter and rely on the SFZ default of 60.
            root = 12 * (int(match.group(2)) + 1) + NOTE_OFFSETS[match.group(1)]
            listed = int(fields.get("pitch_keycenter", 60))
            if listed != root:
                raise ValueError(f"{sample}: pitch_keycenter {listed} doesn't match file name ({root})")
            regions.append(Region(
                file=sample,
                lokey=int(fields["lokey"]),
                hikey=int(fields["hikey"]),
                root=root,
                layer=int(match.group(3)),
            ))
    return regions


def velocity_ranges(layers: list[int]) -> dict[int, tuple[int, int]]:
    """Spread the chosen layers over 1-127, splitting halfway between their original centres."""
    centres = [sum(LAYER_RANGES[layer]) / 2 for layer in layers]
    bounds = [1]
    for low, high in zip(centres, centres[1:]):
        bounds.append(int(math.floor((low + high) / 2)) + 1)
    bounds.append(128)
    return {layer: (bounds[i], bounds[i + 1] - 1) for i, layer in enumerate(layers)}


def load_wav(path: str) -> np.ndarray:
    with wave.open(path) as handle:
        if handle.getframerate() != SAMPLE_RATE or handle.getsampwidth() != 2:
            raise ValueError(f"{path}: expected 44.1 kHz 16-bit audio")
        frames = handle.readframes(handle.getnframes())
        channels = handle.getnchannels()
    return np.frombuffer(frames, dtype="<i2").reshape(-1, channels).astype(np.float64) / 32768.0


def envelope_db(mono: np.ndarray, window: int) -> np.ndarray:
    count = len(mono) // window
    frames = mono[: count * window].reshape(count, window)
    rms = np.sqrt(np.mean(frames ** 2, axis=1))
    return 20 * np.log10(rms + 1e-12)


def prepare(region: Region, folder: str, mono_output: bool) -> Prepared:
    audio = load_wav(os.path.join(folder, region.file))
    mono = audio.mean(axis=1)
    peak = np.abs(mono).max()

    # 1. Trim silence before the hammer strike, keeping 1 ms of lead-in.
    onset = int(np.argmax(np.abs(mono) > peak * 0.01))
    onset = max(0, onset - SAMPLE_RATE // 1000)
    audio = audio[onset:]
    mono = mono[onset:]

    hold_s, loop_s = register_settings(region.root)
    loop_start = int(hold_s * SAMPLE_RATE)
    loop_len = int(loop_s * SAMPLE_RATE)
    # Short, soft treble notes may end early: pull the loop in if needed.
    available = len(mono) - SAMPLE_RATE // 10
    if loop_start + loop_len > available:
        scale = available / (loop_start + loop_len)
        loop_start = int(loop_start * scale)
        loop_len = int(loop_len * scale)

    # 2. Measure how fast the note fades after the loop start (dB per second), from 50 ms RMS
    #    windows, stopping where it sinks into the recording's background noise.
    #    Piano notes fade in two stages (a fast drop, then a long quiet aftersound). Treble
    #    aftersound sits close to the noise floor, so each register gets a minimum fade speed;
    #    otherwise a quiet looped tail would hang around as hiss.
    window = SAMPLE_RATE // 20
    env = envelope_db(mono, window)
    first = loop_start // window
    noise_db = float(np.percentile(env[env > -200], 5))
    above = np.nonzero(env[first:] > noise_db + 10)[0]
    stop = first + (int(above[-1]) + 1 if len(above) else 0)
    stop = min(stop, first + int(20 * SAMPLE_RATE / window))
    measured = -fit_slope(env, first, stop, window) if stop - first >= 8 else 0.0
    decay = float(min(max(measured, minimum_decay(region.root)), 40.0))

    # 3. Pick the loop end: near the target length, where the waveform best matches the
    #    waveform at the loop start (searched over about three periods of the fundamental).
    f0 = 440.0 * 2 ** ((region.root - 69) / 12)
    period = SAMPLE_RATE / f0
    search = int(period * 1.5) + 1
    w = 1024
    reference = mono[loop_start - w // 2: loop_start + w // 2]
    target_end = loop_start + loop_len
    best_end, best_score = target_end, -2.0
    for candidate in range(target_end - search, target_end + search + 1):
        segment = mono[candidate - w // 2: candidate + w // 2]
        if len(segment) != w:
            continue
        score = float(np.dot(reference, segment) /
                      (np.linalg.norm(reference) * np.linalg.norm(segment) + 1e-12))
        if score > best_score:
            best_end, best_score = candidate, score
    loop_end = best_end

    # 4. Flatten the level inside the loop, using the fade measured inside the loop itself,
    #    so the loop doesn't swell or dip each time it repeats. The envelope adds the fade back.
    loop_first = loop_start // window
    loop_stop = max(loop_first + 2, loop_end // window)
    local = min(max(-fit_slope(env, loop_first, loop_stop, window), 0.0), 40.0)
    t = (np.arange(len(audio)) - loop_start) / SAMPLE_RATE
    gain = np.where(t > 0, 10 ** (local * t / 20), 1.0)
    shaped = audio * gain[:, None]

    # 5. Crossfade the end of the loop into the audio just before the loop start,
    #    so jumping from loop end back to loop start is seamless.
    fade = min(int(0.4 * (loop_end - loop_start)), loop_start)
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0, math.pi, fade))[:, None]
    tail = shaped[loop_end - fade: loop_end]
    lead = shaped[loop_start - fade: loop_start]
    shaped[loop_end - fade: loop_end] = tail * (1 - ramp) + lead * ramp

    # Keep the note up to the loop end, plus 16 samples of loop continuation for interpolation.
    body = np.concatenate([shaped[:loop_end], shaped[loop_start: loop_start + 16]])
    channels = [body.mean(axis=1)] if mono_output else [body[:, 0], body[:, 1]]

    # Loudness of the attack (first 300 ms), used to even out the velocity layers.
    head = mono[: int(0.3 * SAMPLE_RATE)]
    level_db = float(20 * np.log10(np.sqrt(np.mean(head ** 2)) + 1e-12))

    name = os.path.basename(region.file)[:-4]
    return Prepared(name, channels, loop_start, loop_end, loop_start / SAMPLE_RATE, decay, level_db)


def match_layer_levels(group: list[Prepared]) -> None:
    """Bring the softer layers of one note closer in loudness to the loudest layer.

    Only 4 of the 16 recorded layers are kept, so their natural loudness steps (about 5 dB)
    would be heard as jumps between neighbouring velocities. Each softer layer is raised to keep
    only LAYER_STEP_KEPT of its natural difference; the sampler's velocity curve then provides
    the loudness, and the layers mostly provide the change in tone. The loudest layer is left
    as recorded so the balance between low and high notes doesn't change.
    """
    loudest = max(group, key=lambda p: p.level_db)
    for prepared in group:
        difference = loudest.level_db - prepared.level_db
        gain_db = difference * (1 - LAYER_STEP_KEPT)
        peak = max(float(np.abs(c).max()) for c in prepared.channels)
        headroom_db = -20 * np.log10(peak / 10 ** (-0.5 / 20))  # keep peaks below -0.5 dBFS
        gain = 10 ** (min(gain_db, headroom_db) / 20)
        prepared.channels = [c * gain for c in prepared.channels]


def to_int16(channels: list[np.ndarray]) -> list[np.ndarray]:
    return [np.clip(np.round(c * 32767), -32768, 32767).astype("<i2") for c in channels]


# ---------------------------------------------------------------------------
# SoundFont 2.01 writer
# ---------------------------------------------------------------------------

GEN_PAN = 17
GEN_ATTACK_VOL = 34
GEN_HOLD_VOL = 35
GEN_DECAY_VOL = 36
GEN_SUSTAIN_VOL = 37
GEN_RELEASE_VOL = 38
GEN_INSTRUMENT = 41
GEN_KEY_RANGE = 43
GEN_VEL_RANGE = 44
GEN_SAMPLE_ID = 53
GEN_SAMPLE_MODES = 54
GEN_ROOT_KEY = 58

TYPE_MONO, TYPE_RIGHT, TYPE_LEFT = 1, 2, 4


def timecents(seconds: float) -> int:
    return int(round(1200 * math.log2(max(seconds, 0.001))))


def chunk(tag: bytes, data: bytes) -> bytes:
    padded = data + (b"\0" if len(data) % 2 else b"")
    return tag + struct.pack("<I", len(data)) + padded


def list_chunk(kind: bytes, body: bytes) -> bytes:
    return b"LIST" + struct.pack("<I", len(body) + 4) + kind + body


def zstr(text: str, length: int | None = None) -> bytes:
    raw = text.encode("ascii", "replace")
    if length is not None:
        return raw[: length - 1].ljust(length, b"\0")
    raw += b"\0"
    return raw + (b"\0" if len(raw) % 2 else b"")


def gen(oper: int, amount: int) -> bytes:
    return struct.pack("<Hh", oper, amount)


def gen_range(oper: int, low: int, high: int) -> bytes:
    return struct.pack("<HBB", oper, low, high)


def write_sf2(path: str, zones: list[tuple[Region, tuple[int, int], Prepared]], mono_output: bool) -> None:
    sample_data = bytearray()
    headers = bytearray()
    sample_ids: dict[str, list[int]] = {}
    index = 0
    padding = np.zeros(46, dtype="<i2").tobytes()

    for _, _, prepared in zones:
        if prepared.name in sample_ids:
            continue
        ids = []
        start_index = index
        for channel_number, data in enumerate(prepared.channels):
            start = len(sample_data) // 2
            sample_data += data.tobytes() + padding
            if mono_output:
                kind, link, suffix = TYPE_MONO, 0, ""
            elif channel_number == 0:
                kind, link, suffix = TYPE_LEFT, start_index + 1, "L"
            else:
                kind, link, suffix = TYPE_RIGHT, start_index, "R"
            headers += struct.pack(
                "<20sIIIIIBbHH",
                zstr(prepared.name + suffix, 20),
                start, start + len(data),
                start + prepared.loop_start, start + prepared.loop_end,
                SAMPLE_RATE, 0, 0, link, kind,
            )
            ids.append(index)
            index += 1
        sample_ids[prepared.name] = ids
    headers += struct.pack("<20sIIIIIBbHH", zstr("EOS", 20), 0, 0, 0, 0, 0, 0, 0, 0, 0)

    # Instrument: a global zone (velocity curve), then one zone per sample channel.
    igen = bytearray()
    imod = bytearray()
    ibag = bytearray()
    gen_count = mod_count = 0

    ibag += struct.pack("<HH", gen_count, mod_count)
    igen += gen(GEN_ATTACK_VOL, -12000)
    gen_count += 1
    # No modulators: players apply the standard SoundFont velocity-to-volume curve.

    for region, (vel_low, vel_high), prepared in zones:
        release = 5.0 if region.root >= FIRST_UNDAMPED_KEY else 1.0
        decay_seconds = min(100.0 / prepared.decay_db_per_second, 100.0)
        for channel_number, sample_id in enumerate(sample_ids[prepared.name]):
            pan = 0 if mono_output else (-500 if channel_number == 0 else 500)
            ibag += struct.pack("<HH", gen_count, mod_count)
            zone = [
                gen_range(GEN_KEY_RANGE, region.lokey, region.hikey),
                gen_range(GEN_VEL_RANGE, vel_low, vel_high),
                gen(GEN_PAN, pan),
                gen(GEN_HOLD_VOL, timecents(prepared.hold_seconds)),
                gen(GEN_DECAY_VOL, timecents(decay_seconds)),
                gen(GEN_SUSTAIN_VOL, 1000),
                gen(GEN_RELEASE_VOL, timecents(release)),
                gen(GEN_SAMPLE_MODES, 1),
                gen(GEN_ROOT_KEY, region.root),
                gen(GEN_SAMPLE_ID, sample_id),
            ]
            igen += b"".join(zone)
            gen_count += len(zone)
    ibag += struct.pack("<HH", gen_count, mod_count)
    igen += gen(0, 0)
    imod += struct.pack("<HHhHH", 0, 0, 0, 0, 0)

    inst = struct.pack("<20sH", zstr("Salamander Grand", 20), 0)
    inst += struct.pack("<20sH", zstr("EOI", 20), len(ibag) // 4 - 1)

    phdr = struct.pack("<20sHHHIII", zstr("Grand Piano", 20), 0, 0, 0, 0, 0, 0)
    phdr += struct.pack("<20sHHHIII", zstr("EOP", 20), 0, 0, 1, 0, 0, 0)
    pbag = struct.pack("<HH", 0, 0) + struct.pack("<HH", 1, 0)
    pmod = struct.pack("<HHhHH", 0, 0, 0, 0, 0)
    pgen = gen(GEN_INSTRUMENT, 0) + gen(0, 0)

    info = (
        chunk(b"ifil", struct.pack("<HH", 2, 1))
        + chunk(b"isng", zstr("EMU8000"))
        + chunk(b"INAM", zstr("Salamander Grand Piano (Piano app edition)"))
        + chunk(b"IENG", zstr("Alexander Holm (recording)"))
        + chunk(b"ICOP", zstr("Public domain. Salamander Grand Piano V3 by Alexander Holm."))
        + chunk(b"ICMT", zstr("Trimmed, looped edition of Salamander Grand Piano V3 (Yamaha C5)."))
        + chunk(b"ISFT", zstr("build_salamander_sf2.py"))
    )
    sdta = chunk(b"smpl", bytes(sample_data))
    pdta = (
        chunk(b"phdr", phdr) + chunk(b"pbag", pbag) + chunk(b"pmod", pmod) + chunk(b"pgen", pgen)
        + chunk(b"inst", inst) + chunk(b"ibag", bytes(ibag)) + chunk(b"imod", bytes(imod))
        + chunk(b"igen", bytes(igen)) + chunk(b"shdr", bytes(headers))
    )
    body = b"sfbk" + list_chunk(b"INFO", info) + list_chunk(b"sdta", sdta) + list_chunk(b"pdta", pdta)
    with open(path, "wb") as handle:
        handle.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", help="SalamanderGrandPianoV3_44.1khz16bit folder")
    parser.add_argument("output", help="Path of the .sf2 file to write")
    parser.add_argument("--layers", default="4,9,13,16", help="Original velocity layers to keep (1-16)")
    parser.add_argument("--mono", action="store_true", help="Mix to mono (half the size)")
    parser.add_argument("--verbose", action="store_true", help="Print per-note loop and decay values")
    args = parser.parse_args()

    layers = sorted({int(x) for x in args.layers.split(",")})
    if not layers or any(layer not in LAYER_RANGES for layer in layers):
        parser.error("layers must be numbers from 1 to 16")

    regions = parse_sfz(os.path.join(args.source, "SalamanderGrandPianoV3.sfz"))
    ranges = velocity_ranges(layers)
    chosen = sorted((r for r in regions if r.layer in ranges), key=lambda r: (r.root, r.layer))
    if not chosen:
        print("No matching regions found in the SFZ file", file=sys.stderr)
        return 1

    zones = []
    for region in chosen:
        prepared = prepare(region, args.source, args.mono)
        zones.append((region, ranges[region.layer], prepared))

    for root in sorted({region.root for region, _, _ in zones}):
        match_layer_levels([p for region, _, p in zones if region.root == root])
    for _, _, prepared in zones:
        prepared.channels = to_int16(prepared.channels)
        if args.verbose:
            print(f"{prepared.name:10s} hold {prepared.hold_seconds:4.2f} s  "
                  f"decay {prepared.decay_db_per_second:5.1f} dB/s  level {prepared.level_db:6.1f} dB")

    write_sf2(args.output, zones, args.mono)
    size = os.path.getsize(args.output) / 1e6
    print(f"Wrote {args.output}: {size:.1f} MB, {len(chosen)} notes, velocity ranges {ranges}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
