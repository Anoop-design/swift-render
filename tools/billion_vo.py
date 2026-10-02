#!/usr/bin/env python3
"""billion_vo.py — Kokoro TTS for the "How to Earn a Billion Dollars" explainer.

For each narration line: synthesize with Kokoro, trim silence, resample to
44.1 kHz mono, write out/vo-billion/NN.wav. Chapter durations are derived from
the *measured* VO length (lead-in + speech + tail) so the Swift scene's `durs`
array can be generated to match exactly — audio and video share one source of
truth and cannot drift.

Emits:
  out/vo-billion/NN.wav      one clip per line (44.1k mono, 16-bit)
  out/billion-vo.tsv         id <tab> absolute_start_s <tab> text  (for mix_vo.py)
  prints the Swift `durs` literal + total duration to stdout.

Usage:  .venv-kokoro/bin/python tools/billion_vo.py [voice]
"""
import os
import sys
import warnings

warnings.filterwarnings("ignore")
import numpy as np
import soundfile as sf
from kokoro import KPipeline

VOICE = sys.argv[1] if len(sys.argv) > 1 else "af_heart"
LEAD_IN = 0.7          # silence before VO starts inside a chapter
TAIL = 1.5             # silence after VO before the crossfade
LAST_TAIL = 3.0        # the lockup holds longer
CROSS = 0.5            # crossfade overlap between chapters (matches Swift)

VODIR = "out/vo-billion"
TSV = "out/billion-vo.tsv"
os.makedirs(VODIR, exist_ok=True)

# (id, narration). Math written in words so the G2P reads it cleanly.
LINES = [
    ("01", "How to earn a billion dollars. It's hard. But it turns out, it's just math."),
    ("02", "Last month, a politician said it's impossible to earn a billion dollars without cheating. "
           "I've spent twenty-one years training founders to do exactly that. So let me show you why she's wrong."),
    ("03", "I recently asked a founder for her growth rate. Ninety-three percent, she said — last month. "
           "That means her net worth was growing ninety-three percent a month too. And she wasn't exploiting anyone. "
           "Her users just loved what she built, and told their friends."),
    ("04", "A few million growing that fast, someone objected, is radically different from a billion dollars. "
           "That sounds reasonable. It's also completely false — and false in a beautifully illuminating way."),
    ("05", "To go from two million to a billion, you have to grow five hundred times. "
           "How many months of ninety-three percent growth is that? "
           "It's the log, base one point nine three, of five hundred. About nine and a half. "
           "A couple million and a billion dollars aren't radically different. They're nine and a half months apart."),
    ("06", "Think that's cheating with big numbers? Try fifteen percent a month — startups hit that constantly. "
           "Compounded over five years, that's one point one five to the sixtieth power: more than four thousand times. "
           "Start in your early twenties, and you can be a billionaire by thirty."),
    ("07", "Exponential growth is like magic. It produces outcomes that feel impossible. "
           "And that's exactly why some politicians distrust it. They don't feel the math — "
           "so when they see impossible-looking wealth, they assume somebody cheated."),
    ("08", "But look closely. There are only two numbers here. Your growth rate, and how long it lasts. "
           "Startups grow fifteen percent a month honestly, all the time. "
           "And the second number is set by the size of the market. How could cheating possibly make a market bigger?"),
    ("09", "So how do you get that growth rate? You make something so good that people tell their friends. "
           "Which means finding a need nobody has satisfied yet — by feeling that need yourself."),
    ("10", "You're young, so your own wants are a uniquely valuable signal. They predict future demand. "
           "Whatever you and your friends start using now, everyone will be using in ten years. "
           "So build what you and your friends want."),
    ("11", "Here's the twist: the best startup ideas sound lame at first. That's what kept them hidden. "
           "A computer in every home. Paying to sleep on a stranger's airbed. "
           "We funded Airbnb convinced the idea was bad. We just liked the founders."),
    ("12", "So stop searching for startup ideas. Build projects with your friends, just because they'd be cool. "
           "One founder strapped a camera to his head and live-streamed his entire life. "
           "Today, you know it as Twitch."),
    ("13", "The key was never exploitation. It's empathy. "
           "Understand a group of people so deeply that you can build exactly what they want. "
           "That is what we look for in founders."),
    ("14", "Two numbers. Growth, and how long it lasts. "
           "Make something people love, in a big market, and the rest happens on its own. "
           "You don't have to cheat to earn a billion dollars."),
]


def resample(y, sr_in, sr_out):
    if sr_in == sr_out:
        return y
    n_out = int(round(len(y) * sr_out / sr_in))
    x_in = np.linspace(0, 1, len(y), endpoint=False)
    x_out = np.linspace(0, 1, n_out, endpoint=False)
    return np.interp(x_out, x_in, y).astype(np.float32)


def trim_silence(y, sr, thresh=0.012, pad=0.06):
    """Trim leading/trailing near-silence, keep a small pad."""
    mag = np.abs(y)
    idx = np.where(mag > thresh)[0]
    if len(idx) == 0:
        return y
    p = int(pad * sr)
    a = max(0, idx[0] - p)
    b = min(len(y), idx[-1] + p)
    return y[a:b]


print(f"[billion] synthesizing {len(LINES)} lines with Kokoro voice '{VOICE}'", file=sys.stderr)
pipe = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M")

vo_durs = []
for lid, text in LINES:
    chunks = [a for _, _, a in pipe(text, voice=VOICE)]
    y = np.concatenate(chunks).astype(np.float32)
    y = trim_silence(y, 24000)
    y = resample(y, 24000, 44100)
    peak = float(np.abs(y).max())
    if peak > 1e-6:
        y = y / peak * 0.92
    sf.write(f"{VODIR}/{lid}.wav", y, 44100, subtype="PCM_16")
    d = len(y) / 44100.0
    vo_durs.append(d)
    print(f"       line {lid}  {d:5.2f}s", file=sys.stderr)

# Derive chapter durations from measured VO, rounded to 0.1s (Swift uses the same literal).
durs = []
for i, d in enumerate(vo_durs):
    tail = LAST_TAIL if i == len(vo_durs) - 1 else TAIL
    durs.append(round(LEAD_IN + d + tail, 1))

# Anchors + VO start times via the SAME recurrence the Swift scene uses.
anchors = []
c = 0.0
for d in durs:
    anchors.append(round(c, 3))
    c += d - CROSS
total = round(anchors[-1] + durs[-1], 1)

with open(TSV, "w") as f:
    for (lid, text), a in zip(LINES, anchors):
        start = round(a + LEAD_IN, 3)
        f.write(f"{lid}\t{start}\t{text}\n")

print("\n// ---- paste into BillionDollars.swift ----")
print("static let durs: [Double] = [" + ", ".join(f"{d:g}" for d in durs) + "]")
print(f"// total = {total}s,  chapters = {len(durs)}")
print(f"\n[billion] wrote {len(LINES)} clips → {VODIR}/  and  {TSV}", file=sys.stderr)
print(f"[billion] TOTAL {total}s", file=sys.stderr)
