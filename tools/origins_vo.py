#!/usr/bin/env python3
"""Kokoro narration and measured timings for OriginsOfWokeness.

The video is an attributed visual summary of Paul Graham's January 2025 essay
"The Origins of Wokeness." Each chapter duration is derived from its rendered
voice clip, keeping narration and motion graphics on the same timing grid.

Outputs:
  out/vo-origins/NN.wav
  out/origins-vo.tsv
  a Swift `durs` literal on stdout

Usage:
  .venv-kokoro/bin/python tools/origins_vo.py [voice]
"""
import os
import sys
import warnings

warnings.filterwarnings("ignore")
import numpy as np
import soundfile as sf
from kokoro import KPipeline

VOICE = sys.argv[1] if len(sys.argv) > 1 else "am_michael"
LEAD_IN = 0.65
TAIL = 1.35
LAST_TAIL = 2.8
CROSS = 0.55

VODIR = "out/vo-origins"
TSV = "out/origins-vo.tsv"
os.makedirs(VODIR, exist_ok=True)

# Original summary narration. Claims and interpretations are explicitly
# attributed to Graham because the essay is argumentative, not a neutral
# historical account.
LINES = [
    ("01", "In The Origins of Wokeness, Paul Graham asks a historical question. "
           "Why did aggressively performative moralism take this particular form, at this particular moment?"),
    ("02", "His starting point is the prig: a self-righteously moralistic person who proves purity by enforcing rules. "
           "The personality is old, Graham argues. Only the rulebook changes."),
    ("03", "He traces two waves. Political correctness rises in universities in the late nineteen eighties, fades from public view in the late nineties, then returns through social media in the early twenty tens, peaking around twenty twenty."),
    ("04", "Graham's institutional story begins with the student radicals of the nineteen sixties. "
           "They became professors, gained tenure, and moved from protesting authority to possessing it. "
           "In fields where politics could shape the work, persuasion could become enforcement."),
    ("05", "The result, in his account, was a complicated moral etiquette. "
           "Rules changed quickly, and knowing the newest language became a visible badge of virtue. "
           "Orthodoxy could substitute for character."),
    ("06", "The second wave found its engine online. Outrage spreads unusually well; Graham says users on a forum he ran were roughly three times more likely to upvote content that angered them. "
           "Social networks turned moral enforcement into a fast, coordinated crowd."),
    ("07", "Institutions added another flywheel. Administrators were hired to detect impropriety, organizations copied new best practices, and fear moved rules faster than conviction. "
           "A small committed group could set norms for a much larger cautious one."),
    ("08", "Graham models the cycle like an epidemic. Zealots define a new offense. Early adopters signal virtue. "
           "A larger group complies to avoid trouble. That success makes everyone more anxious about the next rule, and the loop accelerates."),
    ("09", "He argues the cycle peaked around twenty twenty and has since retreated. "
           "His proposed response is pluralism: treat political doctrine like religion. People may hold and explain beliefs, but institutions should not impose an orthodoxy."),
    ("10", "His broader warning reaches beyond wokeness. Every era can invent new heresies. "
           "So put the burden of proof on anyone trying to forbid speech. "
           "The number of true things we cannot say should not increase."),
]


def resample(y, sr_in, sr_out):
    if sr_in == sr_out:
        return y
    n_out = int(round(len(y) * sr_out / sr_in))
    x_in = np.linspace(0, 1, len(y), endpoint=False)
    x_out = np.linspace(0, 1, n_out, endpoint=False)
    return np.interp(x_out, x_in, y).astype(np.float32)


def trim_silence(y, sr, thresh=0.012, pad=0.06):
    idx = np.where(np.abs(y) > thresh)[0]
    if len(idx) == 0:
        return y
    p = int(pad * sr)
    return y[max(0, idx[0] - p):min(len(y), idx[-1] + p)]


print(f"[origins] synthesizing {len(LINES)} lines with Kokoro voice '{VOICE}'",
      file=sys.stderr)
pipe = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M")

vo_durs = []
for lid, text in LINES:
    chunks = [a for _, _, a in pipe(text, voice=VOICE) if a is not None]
    y = np.concatenate(chunks).astype(np.float32)
    y = trim_silence(y, 24000)
    y = resample(y, 24000, 44100)
    peak = float(np.abs(y).max())
    if peak > 1e-6:
        y = y / peak * 0.92
    sf.write(f"{VODIR}/{lid}.wav", y, 44100, subtype="PCM_16")
    d = len(y) / 44100.0
    vo_durs.append(d)
    print(f"          line {lid}  {d:5.2f}s", file=sys.stderr)

durs = [
    round(LEAD_IN + d + (LAST_TAIL if i == len(vo_durs) - 1 else TAIL), 1)
    for i, d in enumerate(vo_durs)
]

anchors = []
cursor = 0.0
for d in durs:
    anchors.append(round(cursor, 3))
    cursor += d - CROSS
total = round(anchors[-1] + durs[-1], 1)

with open(TSV, "w") as f:
    for (lid, text), anchor in zip(LINES, anchors):
        f.write(f"{lid}\t{round(anchor + LEAD_IN, 3)}\t{text}\n")

print("\n// ---- paste into OriginsOfWokeness.swift ----")
print("static let durs: [Double] = [" + ", ".join(f"{d:g}" for d in durs) + "]")
print(f"// total = {total}s, chapters = {len(durs)}")
print(f"\n[origins] wrote clips → {VODIR}/ and {TSV}", file=sys.stderr)
print(f"[origins] TOTAL {total}s", file=sys.stderr)
