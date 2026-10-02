#!/usr/bin/env python3
"""Lay OpenEar foley one-shots + a vinyl-crackle bed over the OpenEarLaunch score.

    swift run swift-render audio OpenEarLaunch --out out/oel_music.wav
    python3 tools/openear_launch_mix.py out/oel_music.wav out/oel_mix.wav
    swift run swift-render render OpenEarLaunch --audio out/oel_mix.wav --out out/openear_launch.mp4

The one-shots in assets/openear-foley/ were sliced from the HunyuanVideo-Foley
passes made for the OpenEar launch (~/Downloads/foley_only_*.mp4).
Cue times follow the section starts in OpenEarLaunch.swift (bar = 2.4s):
A 0 · B 4.8 · C 9.6 · D 12.0 · E 16.8 · F 21.6 · G 24.0 · H 28.8 · I 33.6 · J 38.4 · K 40.8
"""
import sys
from pathlib import Path

import numpy as np
import scipy.io.wavfile as wf

ROOT = Path(__file__).resolve().parent.parent
FOLEY = ROOT / "assets" / "openear-foley"
SR = 44100
BUS_DB = -3.0


def load(name):
    sr, x = wf.read(FOLEY / f"{name}.wav")
    assert sr == SR, (name, sr)
    x = x.astype(np.float32) / 32768.0
    return x if x.ndim == 2 else np.stack([x, x], axis=1)


def place(out, name, t, db, pan=0.0):
    s = load(name) * (10 ** ((db + BUS_DB) / 20))
    s[:, 0] *= 1 - max(0.0, pan)
    s[:, 1] *= 1 + min(0.0, pan)
    i = int(t * SR)
    n = min(len(s), len(out) - i)
    if n > 0:
        out[i:i + n] += s[:n]


def crackle(n, seed, level_db):
    rng = np.random.default_rng(seed)
    x = np.zeros(n, np.float32)
    pops = rng.random(n) < (38 / SR)
    x[pops] = rng.exponential(0.35, pops.sum()) * rng.choice([-1, 1], pops.sum())
    x = np.convolve(x, np.exp(-np.arange(24) / 4.0), mode="same")
    x = np.diff(x, prepend=0)
    x += rng.normal(0, 0.012, n).astype(np.float32)
    x /= np.abs(x).max() + 1e-9
    return x * 10 ** (level_db / 20)


def bed(out, t0, t1, seed, db=-31, fade=0.6):
    i0, i1 = int(t0 * SR), min(len(out), int(t1 * SR))
    c = crackle(i1 - i0, seed, db)
    env = np.ones_like(c)
    f = int(fade * SR)
    env[:f] = np.linspace(0, 1, f)
    env[-f:] = np.linspace(1, 0, f)
    out[i0:i1, 0] += c * env
    out[i0:i1, 1] += np.roll(c, 37) * env


def typing(out, t0, chars, cps, every, db, kind="tick", seed=0):
    rng = np.random.default_rng(seed)
    names = [f"tick_{i}" for i in range(5, 11)] if kind == "tick" else [f"key_{i}" for i in range(1, 16)]
    for c in range(0, chars, every):
        place(out, names[rng.integers(len(names))], t0 + c / cps, db + rng.uniform(-2.5, 1.5), pan=rng.uniform(-0.25, 0.25))


def main(src, dst):
    sr, music = wf.read(src)
    assert sr == SR
    out = music.astype(np.float32) / 32768.0

    # A · needle drop
    bed(out, 0.0, 4.7, seed=1)
    place(out, "click_1", 1.12, -6)
    place(out, "card_1", 1.13, -12)
    place(out, "swish_1", 4.2, -8)
    # B · the problem
    place(out, "key_1", 4.85, -9)
    place(out, "key_3", 6.0, -9)
    place(out, "key_5", 7.25, -9)
    place(out, "card_2", 7.72, -11, pan=0.3)
    place(out, "click_3", 8.55, -7)
    place(out, "key_7", 8.56, -10)
    place(out, "swish_2", 9.1, -15, pan=0.3)
    # C · logo
    place(out, "card_4", 9.6, -11)
    # D · calendar
    place(out, "swish_2", 12.0, -13, pan=0.25)
    for i, t in enumerate([12.5, 12.8, 13.1, 13.4]):
        place(out, f"card_{i + 1}", t, -10, pan=0.25)
    # E · notch
    place(out, "card_5", 17.0, -9)
    place(out, "click_2", 18.7, -4, pan=0.2)
    place(out, "card_6", 19.15, -13)
    # F · both sides
    typing(out, 21.8, 36, 40, 2, -19, seed=3)
    typing(out, 22.85, 43, 44, 2, -19, seed=4)
    # G · notes
    place(out, "click_4", 24.45, -4, pan=0.2)
    place(out, "card_3", 24.95, -11)
    place(out, "swish_1", 25.35, -15)
    typing(out, 25.65, 130, 72, 3, -21, seed=5)
    for i, t in enumerate([27.2, 27.45, 27.7]):
        place(out, f"card_{i + 4}", t, -11, pan=0.2)
    place(out, "click_5", 28.3, -7, pan=0.2)
    # H · ask
    place(out, "click_1", 29.0, -14)
    typing(out, 29.2, 34, 27, 1, -12, kind="key", seed=6)
    place(out, "card_5", 30.75, -10)
    place(out, "swish_2", 30.75, -17)
    typing(out, 30.9, 100, 62, 3, -21, seed=7)
    # I · ledger
    place(out, "swish_1", 33.75, -11, pan=0.25)
    for i in range(5):
        place(out, f"tick_{i % 4 + 1}", 34.5 + 0.3 * i, -9, pan=0.25)
    place(out, "card_6", 36.15, -9, pan=0.25)
    place(out, "tick_2", 36.45, -14, pan=0.25)
    place(out, "click_1", 36.75, -3, pan=0.25)
    place(out, "card_1", 36.76, -7, pan=0.25)
    for t in [36.6, 37.2, 37.8]:
        place(out, "key_12", t, -15, pan=-0.2)
    # J · dictation
    place(out, "key_9", 38.7, -5)
    typing(out, 38.85, 58, 58, 3, -21, seed=8)
    place(out, "key_11", 39.85, -7)
    place(out, "click_5", 39.95, -11)
    # K · end card
    place(out, "swish_1", 40.85, -11, pan=-0.2)
    place(out, "swish_2", 41.25, -13, pan=-0.3)
    place(out, "card_2", 43.15, -9, pan=-0.1)
    bed(out, 40.8, 45.6, seed=2, db=-32, fade=1.0)
    place(out, "click_3", 45.0, -15)

    out = np.tanh(out * 1.1) / np.tanh(1.1)
    out *= 0.89 / (np.abs(out).max() + 1e-9)
    wf.write(dst, SR, (out * 32767).astype(np.int16))
    print(f"wrote {dst}  ({len(out) / SR:.2f}s)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
