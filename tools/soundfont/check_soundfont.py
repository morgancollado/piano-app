"""Check a built Piano.sf2: file structure, loop seams, pitch, key/velocity coverage, decay, velocity response.

Renders test notes with FluidSynth (brew install fluid-synth / apt install fluidsynth) and
compares them with the original Salamander recordings.

Usage:
  python3 check_soundfont.py <Piano.sf2> <SalamanderGrandPianoV3_44.1khz16bit/44.1khz16bit> <scratch folder>

FluidSynth scales SoundFont volume settings differently from the spec, so the velocity
numbers here are a guide; confirm the feel on a device.
"""
import os
import struct
import subprocess
import sys
import wave

import numpy as np

SF2, ORIG, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
SR = 44100
TPQ = 480  # ticks per quarter at 120 bpm -> 1 tick = 1/960 s


def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append(0x80 | (n & 0x7F))
        n >>= 7
    return bytes(reversed(out))


def write_midi(path, events):
    """events: list of (time_seconds, bytes)."""
    events = sorted(events, key=lambda e: e[0])
    track, last = b"", 0
    for t, msg in events:
        tick = int(round(t * 960))
        track += vlq(tick - last) + msg
        last = tick
    track += vlq(0) + b"\xff\x2f\x00"
    header = b"MThd" + struct.pack(">IHHH", 6, 0, 1, TPQ)
    with open(path, "wb") as f:
        f.write(header + b"MTrk" + struct.pack(">I", len(track)) + track)


def note(t, key, vel, dur):
    return [(t, bytes([0x90, key, vel])), (t + dur, bytes([0x80, key, 0]))]


def render(name, events, seconds):
    mid = os.path.join(OUT, name + ".mid")
    wav = os.path.join(OUT, name + ".wav")
    events = events + [(seconds, bytes([0xB0, 123, 0]))]
    write_midi(mid, events)
    subprocess.run(["fluidsynth", "-ni", "-q", "-R", "0", "-C", "0", "-g", "0.8", "-r", str(SR),
                    "-F", wav, SF2, mid], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with wave.open(wav) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, w.getnchannels())
    return x.astype(float).mean(axis=1) / 32768


def env_db(x, win):
    n = len(x) // win
    return 20 * np.log10(np.sqrt((x[: n * win].reshape(n, win) ** 2).mean(axis=1)) + 1e-12)


def f0_estimate(seg, expected):
    """Pitch from the strongest spectral peak within ±1 semitone of the expected frequency."""
    seg = (seg - seg.mean()) * np.hanning(len(seg))
    n = 1 << 20
    spec = np.abs(np.fft.rfft(seg, n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    band = (freqs > expected / 1.06) & (freqs < expected * 1.06)
    return freqs[band][np.argmax(spec[band])]


def read_wav_mono(path):
    with wave.open(path) as w:
        o = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, w.getnchannels())
    return o.astype(float).mean(axis=1) / 32768


def parse_sf2(path):
    """Independent SoundFont reader: returns sample headers and sample data."""
    data = open(path, "rb").read()
    assert data[:4] == b"RIFF" and data[8:12] == b"sfbk", "not a SoundFont"
    assert struct.unpack("<I", data[4:8])[0] + 8 == len(data), "RIFF size mismatch"
    chunks, pos = {}, 12
    while pos < len(data):
        tag, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        if tag == b"LIST":
            inner, end = pos + 12, pos + 8 + size
            while inner < end:
                t, sz = data[inner:inner + 4], struct.unpack("<I", data[inner + 4:inner + 8])[0]
                chunks[t] = data[inner + 8: inner + 8 + sz]
                inner += 8 + sz + (sz & 1)
        pos += 8 + size + (size & 1)
    smpl = np.frombuffer(chunks[b"smpl"], dtype="<i2").astype(float) / 32768
    headers = []
    shdr = chunks[b"shdr"]
    for i in range(len(shdr) // 46 - 1):
        name, start, end, ls, le, rate, pitch, corr, link, kind = struct.unpack("<20sIIIIIBbHH", shdr[i * 46:(i + 1) * 46])
        headers.append((name.rstrip(b"\0").decode(), start, end, ls, le, rate, pitch, link, kind))
    for key in (b"phdr", b"pbag", b"pmod", b"pgen", b"inst", b"ibag", b"imod", b"igen"):
        assert key in chunks, f"missing {key}"
    assert len(chunks[b"igen"]) % 4 == 0 and len(chunks[b"ibag"]) % 4 == 0
    return headers, smpl, chunks


ok = True

# 0. File structure and loop seams, read straight from the SoundFont.
headers, smpl, chunks = parse_sf2(SF2)
bad_struct, seam_ratios = [], []
for name, start, end, ls, le, rate, pitch, link, kind in headers:
    if not (start + 8 <= ls < le <= end - 8 and le - ls >= 32 and rate == SR):
        bad_struct.append(name)
    x = smpl[start:end]
    a, b = ls - start, le - start
    # Jump across the seam (last loop sample -> first loop sample) vs typical step inside the loop.
    seam = abs(x[a] - x[b - 1])
    typical = np.percentile(np.abs(np.diff(x[a:b])), 99) + 1e-9
    seam_ratios.append((seam / typical, name))
worst_seam = max(seam_ratios)
print(f"0. structure: {len(headers)} samples, {len(bad_struct)} with bad loop points; "
      f"worst seam jump = {worst_seam[0]:.2f}x the loop's 99th-percentile step ({worst_seam[1]})")
ok &= not bad_struct and worst_seam[0] < 2.0

# 1. Pitch of every key from E2 to C8, compared with the original recording of the nearest
#    sampled note shifted the same way (bass pitch is hard to measure: strings are inharmonic).
events, t = [], 0.0
keys = list(range(40, 109))
for k in keys:
    events += note(t, k, 100, 0.6)
    t += 0.8
x = render("pitch", events, t + 1)
names = {0: "C", 3: "D#", 6: "F#", 9: "A"}
worst = 0.0
for i, k in enumerate(keys):
    start = int((i * 0.8 + 0.1) * SR)
    expected = 440 * 2 ** ((k - 69) / 12)
    rendered = f0_estimate(x[start: start + 16384], expected)
    # Original sampled note this key plays from, and the shift applied to it.
    root = min((r for r in range(21, 109) if r % 12 in names), key=lambda r: (abs(r - k), r))
    ro = read_wav_mono(os.path.join(ORIG, f"{names[root % 12]}{root // 12 - 1}v13.wav"))
    onset = int(np.argmax(np.abs(ro) > np.abs(ro).max() * 0.01))
    original = f0_estimate(ro[onset + int(0.1 * SR): onset + int(0.1 * SR) + 16384], 440 * 2 ** ((root - 69) / 12))
    target = original * 2 ** ((k - root) / 12)
    cents = 1200 * np.log2(rendered / target)
    worst = max(worst, abs(cents))
    if abs(cents) > 5:
        print(f"  pitch off: key {k} {cents:+.1f} cents vs original")
        ok = False
print(f"1. pitch, keys 40-108, vs original recordings: worst difference {worst:.1f} cents")

# 2. Every key and every velocity layer produces sound (no gaps in key/velocity mapping).
events, t, slots = [], 0.0, []
for k in range(21, 109):
    for v in (20, 70, 100, 127):
        events += note(t, k, v, 0.25)
        slots.append((k, v, t))
        t += 0.3
x = render("coverage", events, t + 1)
silent = [(k, v) for k, v, t0 in slots if np.abs(x[int((t0 + 0.02) * SR): int((t0 + 0.2) * SR)]).max() < 1e-3]
print(f"2. coverage: {len(slots) - len(silent)}/{len(slots)} key/velocity pairs sound" + (f", silent: {silent[:8]}" if silent else ""))
ok &= not silent

# 3. Held notes: compare the rendered fade with the original recording, and look for loop clicks.
print("3. held notes (vel 100 -> original layer 13), level in dB at 1/2/4/8/12/16 s, rendered vs original:")
for name, k in [("A0", 21), ("C2", 36), ("C4", 60), ("A4", 69), ("C6", 84), ("A6", 93)]:
    x = render(f"held_{name}", note(0.0, k, 100, 18.0), 18.5)
    orig_path = os.path.join(ORIG, f"{name}v13.wav")
    with wave.open(orig_path) as w:
        o = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, 2).astype(float).mean(axis=1) / 32768
    o = o[int(np.argmax(np.abs(o) > np.abs(o).max() * 0.01)):]
    win = SR // 10
    er, eo = env_db(x, win), env_db(o, win)
    # Align overall level using the first 0.5 s.
    offset = er[:5].max() - eo[:5].max()
    marks = [1, 2, 4, 8, 12, 16]
    rendered = " ".join(f"{er[m * 10] - offset:6.1f}" if m * 10 < len(er) else "   n/a" for m in marks)
    original = " ".join(f"{eo[m * 10]:6.1f}" if m * 10 < len(eo) else "  (end)" for m in marks)
    print(f"   {name}: rendered {rendered}\n       original {original}")

# 4. Velocity response: louder with each step, no big jump at layer boundaries.
levels = []
for v in range(10, 128, 6):
    x = render(f"vel_{v}", note(0.0, 60, v, 0.5), 0.8)
    levels.append((v, 20 * np.log10(np.abs(x).max() + 1e-12)))
steps = [b[1] - a[1] for a, b in zip(levels, levels[1:])]
print("4. C4 peak level by velocity: " + " ".join(f"{v}:{l:.1f}" for v, l in levels))
# A step that crosses into the next velocity layer, compared with the steps either side of it.
boundaries = [55, 85, 113]
excess = []
for b in boundaries:
    i = next(i for i, (v, _) in enumerate(levels[1:]) if v >= b)
    neighbours = [steps[j] for j in (i - 1, i + 1) if 0 <= j < len(steps)]
    excess.append(steps[i] - sum(neighbours) / len(neighbours))
print(f"   layer changes: extra jump {', '.join(f'{e:+.1f}' for e in excess)} dB beyond neighbouring steps; any decrease: {min(steps) < -0.5}")
ok &= max(excess) < 1.5 and min(steps) >= -0.5

print("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED")
