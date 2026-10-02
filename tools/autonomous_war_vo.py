#!/usr/bin/env python3
"""Measured Kokoro narration for AutonomousWar.

Produces original strategic-analysis narration, one clip per chapter, and
derives the Swift timeline from measured speech duration.

Usage:
  .venv-kokoro/bin/python tools/autonomous_war_vo.py [voice]
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
LAST_TAIL = 3.0
CROSS = 0.55
VODIR = "out/vo-autonomous-war"
TSV = "out/autonomous-war-vo.tsv"
os.makedirs(VODIR, exist_ok=True)

LINES = [
    ("01", "War is becoming software-defined. Not because machines have replaced soldiers, but because sensing, coordination, navigation, and precision are increasingly mediated by autonomous systems."),
    ("02", "Autonomy is a spectrum. Most battlefield drones today are still remotely piloted. But software already stabilizes flight, fuses sensors, follows routes, and increasingly helps systems continue when communications or satellite navigation fail."),
    ("03", "Ukraine made the new economics visible. Small, replaceable drones provide persistent observation and precision at a fraction of the cost of traditional platforms. The battlefield is more transparent, and anything detected can rapidly become vulnerable."),
    ("04", "The decisive system is not one drone. It is the loop connecting sensors, software, commanders, and effects. Autonomy compresses that loop, allowing one human team to supervise more machines and act before an opponent can adapt."),
    ("05", "This changes military power from exquisite scarcity toward attritable mass. The United States Replicator initiative explicitly pursued thousands of autonomous systems across multiple domains. Quantity matters when systems are networked, replaceable, and cheap enough to risk."),
    ("06", "But the spectrum fights back. Jamming, spoofing, and broken links punish systems that depend on constant control. That pushes autonomy toward the edge: onboard perception, resilient navigation, mission-level coordination, and graceful failure."),
    ("07", "The same logic is spreading across domains. Uncrewed surface vessels can complicate sea control. Ground robots can carry supplies through exposed routes. Autonomous aircraft can extend sensing. The common advantage is moving risk away from people while multiplying reach."),
    ("08", "Autonomy also creates serious risks. Systems can behave unpredictably, proliferate quickly, and blur accountability. The International Committee of the Red Cross calls for prohibiting unpredictable autonomous weapons and systems designed to target people, while preserving meaningful human judgment."),
    ("09", "For India, geography makes autonomy unusually valuable. High-altitude borders strain logistics and communications. A vast coastline and the Indian Ocean demand persistent awareness. Autonomous sensing, resupply, maritime patrol, and counter-drone defense can create depth without placing more people in danger."),
    ("10", "India has foundations to build on: the Defence Artificial Intelligence Council, iDEX and the ADITI deep-tech scheme, an indigenous autonomous flying-wing demonstrator, and high-altitude drone trials conducted in real terrain. The challenge is turning projects into a scalable ecosystem."),
    ("11", "That requires five moves. Build a shared software and command layer. Test continuously with soldiers in realistic conditions. Secure domestic components and production. Treat electronic warfare and counter-drone defense as core capabilities. And establish clear rules for human control and accountability."),
    ("12", "The objective is not an army without people. It is a force where people set intent, judgment, and limits, while machines expand awareness, endurance, and scale. India should build the ecosystem that learns fastest, not simply buy the platform that looks most advanced."),
]


def resample(y, sr_in, sr_out):
    if sr_in == sr_out:
        return y
    n_out = int(round(len(y) * sr_out / sr_in))
    return np.interp(
        np.linspace(0, 1, n_out, endpoint=False),
        np.linspace(0, 1, len(y), endpoint=False),
        y,
    ).astype(np.float32)


def trim_silence(y, sr, thresh=0.012, pad=0.06):
    idx = np.where(np.abs(y) > thresh)[0]
    if len(idx) == 0:
        return y
    p = int(pad * sr)
    return y[max(0, idx[0] - p):min(len(y), idx[-1] + p)]


print(f"[autonomous-war] synthesizing {len(LINES)} lines with '{VOICE}'",
      file=sys.stderr)
pipe = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M")

vo_durs = []
for lid, text in LINES:
    chunks = [a for _, _, a in pipe(text, voice=VOICE) if a is not None]
    y = trim_silence(np.concatenate(chunks).astype(np.float32), 24000)
    y = resample(y, 24000, 44100)
    peak = float(np.abs(y).max())
    if peak > 1e-6:
        y = y / peak * 0.92
    sf.write(f"{VODIR}/{lid}.wav", y, 44100, subtype="PCM_16")
    duration = len(y) / 44100
    vo_durs.append(duration)
    print(f"                 line {lid}  {duration:5.2f}s", file=sys.stderr)

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

print("\n// ---- paste into AutonomousWar.swift ----")
print("static let durs: [Double] = [" + ", ".join(f"{d:g}" for d in durs) + "]")
print(f"// total = {total}s, chapters = {len(durs)}")
print(f"\n[autonomous-war] TOTAL {total}s", file=sys.stderr)
