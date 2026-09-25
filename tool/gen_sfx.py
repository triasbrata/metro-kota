#!/usr/bin/env python3
"""Synthesizes the game's sound effects into assets/sfx/*.wav (22.05 kHz, 16-bit mono).

Pure standard library, so the sounds can be tweaked here and regenerated:
    python3 tool/gen_sfx.py
File names must match the `Sfx` enum in lib/game.dart.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "sfx"


def note(freq, dur, shape="sine", attack=0.005, decay=6.0, vol=1.0, slide=None, partials=((1, 1.0),)):
    """One note. decay: exponential fade rate per second. slide: end frequency (glide)."""
    n = int(dur * RATE)
    out, phase = [], [0.0] * len(partials)
    for i in range(n):
        t = i / RATE
        f = freq if slide is None else freq + (slide - freq) * (i / n)
        env = min(1.0, t / attack) * math.exp(-decay * t) * min(1.0, (n - i) / (0.004 * RATE))
        s = 0.0
        for k, (mult, amp) in enumerate(partials):
            phase[k] += 2 * math.pi * f * mult / RATE
            p = phase[k]
            if shape == "sine":
                s += amp * math.sin(p)
            elif shape == "square":
                s += amp * (0.6 if math.sin(p) >= 0 else -0.6)
            elif shape == "tri":
                s += amp * (2 / math.pi) * math.asin(math.sin(p))
        out.append(s * env * vol)
    return out


def noise(dur, vol=1.0, decay=30.0, smooth=0.5):
    """Filtered noise burst (one-pole low-pass; smooth 0..1, higher = duller)."""
    out, y = [], 0.0
    for i in range(int(dur * RATE)):
        y = smooth * y + (1 - smooth) * random.uniform(-1, 1)
        out.append(y * vol * math.exp(-decay * i / RATE))
    return out


def rest(dur):
    return [0.0] * int(dur * RATE)


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def seq(*parts):
    return [s for p in parts for s in p]


def save(name, samples, peak=0.8):
    top = max(1e-9, max(abs(s) for s in samples))
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / top * peak * 32767)) for s in samples))


C5, E5, G5, C6, E6, G6 = 523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0
bell = ((1, 1.0), (2.0, 0.35), (2.76, 0.2))

random.seed(1)
SOUNDS = {
    # fare paid: tiny two-step coin ding
    "deliver": seq(note(1318.5, 0.05, decay=30, partials=bell), note(1760, 0.14, decay=22, partials=bell)),
    # track laid: wooden clack with a low thump
    "build": mix(noise(0.05, vol=0.8, decay=60, smooth=0.3), note(110, 0.12, decay=25, vol=0.9)),
    # train on the rails: soft two-tone horn
    "train": mix(note(440, 0.28, "tri", attack=0.02, decay=4), note(554.4, 0.28, "tri", attack=0.02, decay=4, vol=0.8)),
    # carriage coupled: metallic clank
    "car": seq(mix(noise(0.03, vol=0.7, decay=90, smooth=0.1), note(820, 0.12, decay=30, partials=((1, 1.0), (1.47, 0.6)))),
               note(1230, 0.08, decay=40, vol=0.5)),
    # new station: rising pop
    "station": note(500, 0.09, decay=20, slide=950),
    # a rider walks out: falling "bwoop"
    "leave": note(420, 0.25, "tri", decay=7, slide=210),
    # festival: bright arpeggio
    "festival": seq(*(note(f, 0.09, "tri", decay=12) for f in (C5, E5, G5)), note(C6, 0.35, "tri", decay=5)),
    # accident: crash then a two-tone alarm
    "accident": seq(noise(0.12, vol=1.0, decay=20, smooth=0.2),
                    *(note(f, 0.13, "square", decay=2, vol=0.5) for f in (880, 660, 880, 660))),
    # permit zone: two low warning thuds
    "zone": seq(note(196, 0.16, "tri", decay=10), rest(0.05), note(165, 0.22, "tri", decay=8)),
    # bridge finished: bell
    "bridge": note(988, 0.8, decay=5, partials=bell),
    # goal reached: quick rising chime
    "goal": seq(note(G5, 0.08, decay=14, partials=bell), note(C6, 0.08, decay=14, partials=bell),
                note(E6, 0.3, decay=6, partials=bell)),
    # not enough money: low double buzz
    "error": seq(note(150, 0.09, "square", decay=8, vol=0.5), rest(0.04), note(150, 0.12, "square", decay=8, vol=0.5)),
    # city cleared: fanfare ending on a chord
    "win": seq(*(note(f, 0.12, "tri", decay=6) for f in (C5, E5, G5)),
               mix(note(C6, 0.9, "tri", decay=3), note(E6, 0.9, "tri", decay=3, vol=0.6),
                   note(G6, 0.9, "tri", decay=3, vol=0.4))),
    # game over: slow descending minor line
    "lose": seq(note(G5 / 2, 0.3, "tri", decay=3), note(311.1, 0.3, "tri", decay=3), note(261.6, 0.7, "tri", decay=2.5)),
}

for name, samples in SOUNDS.items():
    save(name, samples)
print(f"wrote {len(SOUNDS)} sounds to {OUT}")
