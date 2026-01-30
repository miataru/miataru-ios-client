#!/usr/bin/env python3
"""
sfxgen.py — parametrischer Kurz-SFX Generator (WAV, 16-bit PCM)

Beispiele:
  python3 sfxgen.py --preset pling --out pling.wav
  python3 sfxgen.py --wave sine --freq 1200 --sweep -800 --dur 0.18 --attack 0.002 --decay 0.08 --release 0.06 --out ui_pling.wav
  python3 sfxgen.py --preset click --out click.wav
"""

import argparse, math, wave, struct, random

def clamp(x, a=-1.0, b=1.0):
    return a if x < a else b if x > b else x

def osc(typ: str, phase: float) -> float:
    # phase in radians
    if typ == "sine":
        return math.sin(phase)
    if typ == "square":
        return 1.0 if math.sin(phase) >= 0 else -1.0
    if typ == "triangle":
        # triangle via saw folding
        t = (phase / (2.0 * math.pi)) % 1.0
        return 4.0 * abs(t - 0.5) - 1.0
    if typ == "saw":
        t = (phase / (2.0 * math.pi)) % 1.0
        return 2.0 * t - 1.0
    raise ValueError(f"unknown wave: {typ}")

def adsr(t, dur, attack, decay, sustain, release):
    # Simple ADSR with sustain level (0..1)
    if dur <= 0:
        return 0.0
    a = max(attack, 1e-6)
    d = max(decay, 1e-6)
    r = max(release, 1e-6)

    sustain_level = clamp(sustain, 0.0, 1.0)

    # Segment boundaries
    t_a = a
    t_d = t_a + d
    t_r = dur  # release starts at dur - r
    t_rs = max(0.0, dur - r)

    if t < 0:
        return 0.0
    if t < t_a:
        return t / t_a
    if t < t_d:
        # from 1.0 down to sustain_level
        return 1.0 - (1.0 - sustain_level) * ((t - t_a) / (t_d - t_a))
    if t < t_rs:
        return sustain_level
    if t < t_r:
        # release to 0
        return sustain_level * (1.0 - (t - t_rs) / (t_r - t_rs))
    return 0.0

def generate(args):
    sr = args.samplerate
    n = int(args.dur * sr)
    if n <= 0:
        raise ValueError("duration too small")

    # Bitcrush: reduce effective sample resolution
    crush_levels = max(2, args.bitcrush_levels)

    phase = 0.0
    out = []

    for i in range(n):
        t = i / sr

        # Frequency with linear sweep (Hz): f(t) = f0 + sweep * (t/dur)
        f = args.freq + args.sweep * (t / args.dur)

        # Vibrato (Hz mod)
        if args.vibrato_depth > 0 and args.vibrato_rate > 0:
            f += args.vibrato_depth * math.sin(2.0 * math.pi * args.vibrato_rate * t)

        f = max(1.0, f)

        phase += 2.0 * math.pi * f / sr

        s = osc(args.wave, phase)

        # Noise mix (0..1)
        if args.noise > 0:
            s = (1.0 - args.noise) * s + args.noise * (2.0 * random.random() - 1.0)

        env = adsr(t, args.dur, args.attack, args.decay, args.sustain, args.release)
        s *= env

        # Soft clip
        if args.softclip > 0:
            k = args.softclip
            s = math.tanh(k * s) / math.tanh(k)

        # Bitcrush (quantize)
        if args.bitcrush:
            q = round((s + 1.0) * (crush_levels - 1) / 2.0)
            s = (q * 2.0 / (crush_levels - 1)) - 1.0

        out.append(s)

    # Normalize
    if args.normalize:
        m = max(abs(x) for x in out) or 1.0
        out = [x / m for x in out]

    return out

def write_wav(path, samples, samplerate):
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # 16-bit
        wf.setframerate(samplerate)
        frames = bytearray()
        for s in samples:
            v = int(clamp(s) * 32767.0)
            frames += struct.pack("<h", v)
        wf.writeframes(frames)

def apply_preset(args):
    # Kleine, brauchbare Startpunkte
    if args.preset == "pling":
        args.wave = "sine"
        args.freq = 1400
        args.sweep = -900
        args.dur = 0.18
        args.attack = 0.002
        args.decay = 0.06
        args.sustain = 0.0
        args.release = 0.08
        args.vibrato_rate = 0.0
        args.vibrato_depth = 0.0
        args.noise = 0.02
        args.softclip = 1.5
        args.bitcrush = False
    elif args.preset == "click":
        args.wave = "square"
        args.freq = 900
        args.sweep = -600
        args.dur = 0.06
        args.attack = 0.001
        args.decay = 0.02
        args.sustain = 0.0
        args.release = 0.02
        args.noise = 0.10
        args.softclip = 2.0
        args.bitcrush = True
        args.bitcrush_levels = 32
    elif args.preset == "coin":
        args.wave = "triangle"
        args.freq = 1100
        args.sweep = 400
        args.dur = 0.14
        args.attack = 0.002
        args.decay = 0.05
        args.sustain = 0.1
        args.release = 0.06
        args.noise = 0.01
        args.softclip = 1.2
        args.bitcrush = False

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True, help="Output WAV path")
    p.add_argument("--preset", choices=["pling", "click", "coin"], default=None)

    p.add_argument("--samplerate", type=int, default=44100)
    p.add_argument("--wave", choices=["sine", "square", "triangle", "saw"], default="sine")

    p.add_argument("--freq", type=float, default=1200.0, help="Base frequency (Hz)")
    p.add_argument("--sweep", type=float, default=-600.0, help="Linear sweep over duration (Hz)")

    p.add_argument("--dur", type=float, default=0.15, help="Duration (s)")

    p.add_argument("--attack", type=float, default=0.002)
    p.add_argument("--decay", type=float, default=0.05)
    p.add_argument("--sustain", type=float, default=0.0)
    p.add_argument("--release", type=float, default=0.06)

    p.add_argument("--vibrato-rate", type=float, default=0.0, help="Hz")
    p.add_argument("--vibrato-depth", type=float, default=0.0, help="Hz")

    p.add_argument("--noise", type=float, default=0.0, help="0..1 mix")
    p.add_argument("--softclip", type=float, default=0.0, help="0=off, higher=more")

    p.add_argument("--bitcrush", action="store_true")
    p.add_argument("--bitcrush-levels", type=int, default=64)

    p.add_argument("--normalize", action="store_true", default=True)
    args = p.parse_args()

    if args.preset:
        apply_preset(args)

    samples = generate(args)
    write_wav(args.out, samples, args.samplerate)

if __name__ == "__main__":
    main()

