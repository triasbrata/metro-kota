#!/usr/bin/env python3
"""Synthesizes the cozy SNES-style background loops into assets/music/.

Pure standard library synthesis (plus ffmpeg to encode OGG Vorbis):
    python3 tool/gen_music.py
One song, written out below as chords and melody, in two arrangements:
- cozy.ogg (in game): 16 bars in F major at 108 BPM. Pulse-wave lead, e-piano chords, a
  bouncing triangle bass, kick, snare and shaker, all through an SNES-style echo.
- menu.ogg (welcome / city picker): the same tune at 96 BPM on a music box an octave up,
  with chord stabs, a walking bass and a light kick and shaker.
Each file loops seamlessly: note tails and the echo wrap around from the end to the start.
"""
import math
import random
import struct
import subprocess
import wave
from pathlib import Path

RATE = 22050
BARS = 16
OUT = Path(__file__).resolve().parent.parent / "assets" / "music"
BEAT = N = 0  # set per arrangement by render()


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def add(buf, start_beat, samples, gain):
    """Mixes samples in at a beat position, wrapping past the end (seamless loop)."""
    i0 = int(start_beat * BEAT * RATE)
    for k, s in enumerate(samples):
        buf[(i0 + k) % N] += s * gain


def voice(freq, beats, kind, attack=0.01, release=0.08, decay=0.0, vib=0.0, duty=0.5, bell=0.0):
    """One note: kind = pulse | tri | sine. Held for `beats`, then released."""
    held = beats * BEAT
    n = int((held + release) * RATE)
    out, ph = [], 0.0
    for i in range(n):
        t = i / RATE
        f = freq * (1 + vib * math.sin(2 * math.pi * 5.2 * t) * min(1, t / 0.25))
        ph = (ph + f / RATE) % 1.0
        if kind == "pulse":
            s = 0.5 if ph < duty else -0.5
        elif kind == "tri":
            s = 4 * abs(ph - 0.5) - 1
        else:
            s = math.sin(2 * math.pi * ph) + bell * math.sin(2 * math.pi * ph * 3.0) * math.exp(-6 * t)
        env = min(1.0, t / attack) * math.exp(-decay * t)
        if t > held:
            env *= max(0.0, 1 - (t - held) / release)
        out.append(s * env)
    return out


def lowpass(buf, a):
    """One-pole low-pass run twice round the loop so the wrap point is seamless."""
    y = 0.0
    out = [0.0] * N
    for _ in range(2):
        for i in range(N):
            y += a * (buf[i] - y)
            out[i] = y
    return out


def echo(buf, delay_beats=0.75, feedback=0.38, mix=0.32):
    """SNES-style echo: feedback delay line, settled over a few loops for a seamless wrap."""
    d = int(delay_beats * BEAT * RATE)
    line = [0.0] * N
    for _ in range(4):
        for i in range(N):
            line[i] = buf[i] + feedback * line[i - d]  # i - d wraps to the loop's end
    return [buf[i] + mix * (line[i - d]) for i in range(N)]


# ---- the song ----
F3, G3, A3, Bb3, C4, D4, E4, F4, G4, A4, Bb4, C5, D5, E5, F5 = 53, 55, 57, 58, 60, 62, 64, 65, 67, 69, 70, 72, 74, 76, 77
CHORDS = {  # voicing, bass root
    "Fmaj7": ([F3, A3, C4, E4], 41),
    "Dm7": ([D4 - 12, F3, A3, C4], 38),
    "Gm7": ([G3, Bb3, D4, F4], 43),
    "C7": ([Bb3, C4, E4, G4], 36),
    "Am7": ([A3, C4, E4, G4], 45),
    "Bbmaj7": ([Bb3, D4, F4, A4], 46),
}
PROGRESSION = [
    "Fmaj7", "Dm7", "Gm7", "C7", "Fmaj7", "Am7", "Bbmaj7", "C7",  # A
    "Bbmaj7", "Am7", "Gm7", "Fmaj7", "Bbmaj7", "Am7", "Gm7", "C7",  # B
]
R = None  # rest
MELODY = [  # (note, beats) per bar, 4 beats each
    [(A4, 1), (C5, 1), (E5, 1.5), (D5, .5)],
    [(C5, 1), (A4, 1), (F4, 2)],
    [(G4, 1), (Bb4, 1), (D5, 1), (C5, 1)],
    [(Bb4, 1.5), (A4, .5), (G4, 2)],
    [(A4, 1), (C5, 1), (F5, 1.5), (E5, .5)],
    [(E5, 1), (C5, 1), (A4, 2)],
    [(D5, 1), (C5, 1), (Bb4, 1), (A4, 1)],
    [(G4, 3), (R, 1)],
    [(F5, 2), (D5, 1), (Bb4, 1)],
    [(C5, 2), (E5, 1), (C5, 1)],
    [(D5, 1.5), (C5, .5), (Bb4, 1), (G4, 1)],
    [(A4, 3), (R, 1)],
    [(D5, 1), (F5, 1), (E5, 1), (D5, 1)],
    [(C5, 1), (A4, 1), (C5, 2)],
    [(Bb4, 1), (A4, 1), (G4, 1), (Bb4, 1)],
    [(C5, 2), (R, 2)],
]


def render(name, bpm, menu):
    """Plays the song in one arrangement and writes assets/music/<name>.ogg."""
    global BEAT, N
    BEAT = 60 / bpm
    N = int(round(BARS * 4 * BEAT * RATE))
    random.seed(7)
    lead, keys, bass, drums = ([0.0] * N for _ in range(4))
    for bar, chord in enumerate(PROGRESSION):
        b0 = bar * 4
        notes, root = CHORDS[chord]
        if menu:
            # keys: two warm chord stabs a bar (not a sleepy held pad)
            for at, g in ((0, 0.08), (2, 0.06)):
                for m in notes:
                    add(keys, b0 + at, voice(hz(m), 1.6, "sine", attack=0.04, release=0.4, decay=0.9, bell=0.2), g)
            # bass: root and fifth on the beat
            for at, m, length in ((0, root, 1), (1.5, root + 7, .5), (2, root, 1), (3, root + 7, .9)):
                add(bass, b0 + at, voice(hz(m), length, "tri", attack=0.01, release=0.1), 0.24)
            # a light beat: soft kick on 1 and 3, shaker on the offbeats
            for at in (0, 2):
                add(drums, b0 + at, voice(80, 0.2, "sine", attack=0.002, release=0.05, decay=16), 0.3)
            for e in range(8):
                hit = [random.uniform(-1, 1) * math.exp(-70 * i / RATE) for i in range(int(0.04 * RATE))]
                add(drums, b0 + e / 2, hit, 0.035 if e % 2 else 0.015)
        else:
            # e-piano: a chord on the downbeat and a push on the "and" of 2
            for at, length, g in ((0, 1.2, 0.11), (2.5, 1.2, 0.09)):
                for m in notes:
                    add(keys, b0 + at, voice(hz(m), length, "sine", attack=0.005, release=0.2, decay=2.2, bell=0.35), g)
            # bass: bouncing eighths around the root
            for e, step in enumerate((0, 12, 7, 12, 0, 12, 7, 10)):
                add(bass, b0 + e / 2, voice(hz(root + step), 0.42, "tri", attack=0.004, release=0.05), 0.26)
            # drums: kick on 1 and 3, snare on 2 and 4, shaker on the eighths
            for at in (0, 2):
                add(drums, b0 + at, voice(90, 0.25, "sine", attack=0.002, release=0.05, decay=14), 0.5)
            for at in (1, 3):
                snare = [(random.uniform(-1, 1) * 0.7 + math.sin(2 * math.pi * 190 * i / RATE) * 0.5) * math.exp(-28 * i / RATE)
                         for i in range(int(0.14 * RATE))]
                add(drums, b0 + at, snare, 0.14)
            for e in range(8):
                hit = [random.uniform(-1, 1) * math.exp(-60 * i / RATE) for i in range(int(0.05 * RATE))]
                add(drums, b0 + e / 2, hit, 0.05 if e % 2 else 0.03)
        # lead: the same melody; a music box an octave up on the menu, the pulse lead in game
        at = b0
        for m, length in MELODY[bar]:
            if m is not None:
                if menu:
                    add(lead, at, voice(hz(m + 12), length, "sine", attack=0.003, release=0.35, decay=2.6, bell=0.6), 0.2)
                else:
                    add(lead, at, voice(hz(m), length * 0.8, "pulse", attack=0.01, release=0.08, vib=0.004, duty=0.25), 0.16)
            at += length

    dry = [l + k * 0.6 for l, k in zip(lead, keys)]
    wet = echo(dry, delay_beats=0.75, feedback=0.35, mix=0.3) if menu else echo(dry, feedback=0.3, mix=0.25)
    mix = lowpass([w + b + d for w, b, d in zip(wet, bass, drums)], 0.3 if menu else 0.35)  # warm like the SNES DSP
    peak = max(abs(s) for s in mix)

    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / f"{name}.wav"
    with wave.open(str(tmp), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * 0.85 * 32767)) for s in mix))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp), "-c:a", "libvorbis", "-q:a", "4",
                    str(OUT / f"{name}.ogg")], check=True)
    tmp.unlink()
    print(f"wrote {OUT / name}.ogg ({N / RATE:.1f} s loop)")


render("cozy", 108, menu=False)
render("menu", 96, menu=True)
