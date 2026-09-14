#!/usr/bin/env python3
"""Generate the test samples the Sampler offline checks read.

    python3 mksamples.py [outdir]        # default: the directory of this script

Writes three short 16-bit WAV files, chosen so every slicing and play mode has
something meaningful to chew on:

  beat.wav    1.6 s, 8 clear transients on a 16th grid at 120 bpm — onset and
              beat slicing, Repitch, Fragments
  line.wav    2.0 s, a monophonic line that steps through four pitches with a
              glide in the middle — pitch slicing, Analyzed Root Key, Cycles
  pad.wav     2.0 s, a slowly evolving stereo drone — Textures, Spectral

No dependencies beyond the standard library.
"""
import math, struct, sys, wave, os, random

SR = 44100

def w(path, chans, dur, fn):
    n = int(SR * dur)
    frames = bytearray()
    for i in range(n):
        t = i / SR
        vals = fn(t, i)
        if not isinstance(vals, tuple): vals = (vals,) * chans
        for v in vals[:chans]:
            v = max(-1.0, min(1.0, v))
            frames += struct.pack('<h', int(v * 32000))
    with wave.open(path, 'wb') as f:
        f.setnchannels(chans); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes(bytes(frames))
    return path

def beat(t, i):
    # 120 bpm, a hit every 16th (0.125 s); alternating kick / snare / hat
    step = int(t / 0.125)
    ph = t - step * 0.125
    kind = [0, 2, 1, 2, 0, 2, 1, 2][step % 8]
    env = math.exp(-ph * (40 if kind == 0 else 120 if kind == 1 else 400))
    if kind == 0:
        f = 120 * math.exp(-ph * 30) + 45
        return math.sin(2 * math.pi * f * ph) * env
    if kind == 1:
        return (random.uniform(-1, 1) * 0.7 + math.sin(2 * math.pi * 190 * ph) * 0.3) * env
    return random.uniform(-1, 1) * env * 0.5

def line(t, i):
    # four pitches, 0.5 s each, with a glide between the 2nd and the 3rd
    notes = [220.0, 277.18, 329.63, 246.94]
    k = min(3, int(t / 0.5))
    f = notes[k]
    if 0.95 < t < 1.05:
        f = notes[1] + (notes[2] - notes[1]) * ((t - 0.95) / 0.1)
    ph = t
    s = sum(math.sin(2 * math.pi * f * h * ph) / h for h in (1, 2, 3, 4))
    seg = t - k * 0.5
    return s * 0.3 * min(1.0, seg * 40) * math.exp(-seg * 1.2)

def pad(t, i):
    lo = math.sin(2 * math.pi * 110 * t) * 0.3
    mid = math.sin(2 * math.pi * (220 + 6 * math.sin(2 * math.pi * 0.4 * t)) * t) * 0.25
    hi = math.sin(2 * math.pi * 442 * t) * 0.12 * (0.5 + 0.5 * math.sin(2 * math.pi * 0.23 * t))
    l = lo + mid + hi * 0.6
    r = lo + mid * 0.8 + hi
    return (l * 0.8, r * 0.8)

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    random.seed(1)
    print(w(os.path.join(out, "beat.wav"), 1, 1.6, beat))
    random.seed(1)
    print(w(os.path.join(out, "line.wav"), 1, 2.0, line))
    print(w(os.path.join(out, "pad.wav"), 2, 2.0, pad))
