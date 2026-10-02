#!/usr/bin/env bash
#
# make_billion_audio.sh — build the full narrated soundtrack for the
# "BillionDollars" explainer (Paul Graham's "How to Earn a Billion Dollars")
# and render the finished video. Uses Kokoro TTS, not macOS `say`.
#
# Pipeline (needs swift, the .venv-kokoro python env, numpy+soundfile):
#   1. Kokoro TTS → out/vo-billion/NN.wav (44.1k mono) + out/billion-vo.tsv
#      (tools/billion_vo.py also prints the `durs` array — keep BillionDollars.swift in sync)
#   2. export the scene's synthesized ambient score → out/billion-music.wav
#   3. duck the music under each VO line and mix      → out/billion-mix.wav (tools/mix_vo.py)
#   4. render the scene with the mixed track as --audio → out/billion-dollars.mp4
#
# Usage:
#   bash tools/make_billion_audio.sh                 # defaults (af_heart voice)
#   VOICE=am_michael bash tools/make_billion_audio.sh
#   SKIP_VO=1 bash tools/make_billion_audio.sh        # reuse existing VO clips
#
set -euo pipefail
cd "$(dirname "$0")/.."

VOICE="${VOICE:-af_heart}"
PY=".venv-kokoro/bin/python"
MUSIC="out/billion-music.wav"
MIX="out/billion-mix.wav"
TSV="out/billion-vo.tsv"
VODIR="out/vo-billion"
OUT="${OUT:-out/billion-dollars.mp4}"

if [[ "${SKIP_VO:-0}" != "1" ]]; then
  echo "[billion] 1/4  Kokoro TTS (voice '$VOICE')"
  "$PY" tools/billion_vo.py "$VOICE"
else
  echo "[billion] 1/4  reusing existing VO in $VODIR"
fi

echo "[billion] 2/4  exporting ambient score → $MUSIC"
swift run swift-render audio BillionDollars --out "$MUSIC"

echo "[billion] 3/4  ducking music under VO → $MIX"
"$PY" tools/mix_vo.py "$MUSIC" "$TSV" "$VODIR" "$MIX"

echo "[billion] 4/4  rendering video → $OUT"
swift run swift-render render BillionDollars --audio "$MIX" --out "$OUT"

echo "[billion] done → $OUT"
