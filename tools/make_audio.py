#!/usr/bin/env python3
"""Synthesise every sound in the game, so nothing needs licensing. Writes 16-bit mono WAV bytes."""
import wave
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
SR = 22050
rng = np.random.default_rng(2026)


def save(name, x):
    x = np.clip(x / max(np.abs(x).max(), 1e-6) * 0.85, -1, 1)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wavdata"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def t(sec):
    return np.arange(int(sec * SR)) / SR


def seamless(x, fade=1.0):
    """Crossfade the tail into the head so a loop has no click."""
    n = int(fade * SR)
    ramp = np.linspace(0, 1, n)
    out = x[:-n].copy()
    out[:n] = out[:n] * ramp + x[-n:] * (1 - ramp)
    return out


def lowpass(x, cutoff):
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    s = 0.0
    for i, v in enumerate(x):
        s += a * (v - s)
        y[i] = s
    return y


def noise(sec):
    return rng.normal(size=int(sec * SR))


def pad(notes, sec, drift=0.07):
    tt = t(sec)
    x = np.zeros_like(tt)
    for i, f in enumerate(notes):
        lfo = 0.5 + 0.5 * np.sin(2 * np.pi * drift * (i + 1) * 0.37 * tt + i * 1.7)
        for det in (0.997, 1.0, 1.004):
            x += np.sin(2 * np.pi * f * det * tt + i) * lfo * (0.6 + 0.4 * np.sin(2 * np.pi * 0.03 * tt + i))
        x += 0.25 * np.sin(2 * np.pi * f * 2.0 * tt) * lfo ** 2
    return x


# Ambient music: slow, sparse chords.
save("music_space", seamless(pad([65.41, 98.0, 130.81, 196.0, 246.94], 64.0) + 0.4 * lowpass(noise(64.0), 300.0), 4.0))
save("music_surface", seamless(pad([55.0, 82.41, 110.0, 164.81, 207.65], 64.0, 0.05) + 0.25 * lowpass(noise(64.0), 200.0), 4.0))

# Loops
save("wind", seamless(lowpass(noise(10.0), 500.0) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.21 * t(10.0))), 1.0))
save("engine", seamless(lowpass(noise(6.0), 700.0) + 0.5 * np.sin(2 * np.pi * 48 * t(6.0)) + 0.3 * lowpass(noise(6.0), 90.0) * 4, 0.5))
save("rover", seamless(np.sin(2 * np.pi * 90 * t(4.0)) * 0.4 + np.sin(2 * np.pi * 181 * t(4.0)) * 0.2 + lowpass(noise(4.0), 1200.0) * 0.4, 0.4))


# One-shots
def env(sec, attack=0.005, decay=6.0):
    tt = t(sec)
    return np.minimum(tt / attack, 1.0) * np.exp(-tt * decay)


save("click", np.sin(2 * np.pi * 880 * t(0.06)) * env(0.06, 0.002, 60))
save("hover", np.sin(2 * np.pi * 1320 * t(0.03)) * env(0.03, 0.002, 90) * 0.4)
save("chime", sum(np.sin(2 * np.pi * f * t(1.2)) * env(1.2, 0.01, 3 + i) for i, f in enumerate((659.25, 987.77, 1318.5))))
save("collect", sum(np.sin(2 * np.pi * f * t(0.5)) * np.roll(env(0.5, 0.005, 9), int(i * 0.07 * SR)) for i, f in enumerate((523.25, 783.99, 1046.5))))
save("alarm", np.sign(np.sin(2 * np.pi * 620 * t(0.5))) * (np.sin(2 * np.pi * 6 * t(0.5)) > 0) * 0.5)
save("touchdown", lowpass(noise(0.9), 220.0) * env(0.9, 0.003, 7) * 3 + np.sin(2 * np.pi * 60 * t(0.9)) * env(0.9, 0.005, 8))
save("crash", lowpass(noise(2.0), 900.0) * env(2.0, 0.002, 2.5) + np.sin(2 * np.pi * 40 * t(2.0)) * env(2.0, 0.002, 2.0) * 2)
save("stage", lowpass(noise(0.8), 1500.0) * env(0.8, 0.002, 6))
print("audio written to", OUT)
