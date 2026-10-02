#!/usr/bin/env bash
#
# Kokoro narration → synthesized score → ducked mix → final Swift Render film.
#
# Usage:
#   bash tools/make_autonomous_war_video.sh
#   VOICE=af_heart bash tools/make_autonomous_war_video.sh
#   SKIP_VO=1 bash tools/make_autonomous_war_video.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

VOICE="${VOICE:-am_michael}"
PY=".venv-kokoro/bin/python"
MUSIC="out/autonomous-war-music.wav"
MIX="out/autonomous-war-mix.wav"
TSV="out/autonomous-war-vo.tsv"
VODIR="out/vo-autonomous-war"
OUT="${OUT:-out/autonomous-war-india.mp4}"

if [[ "${SKIP_VO:-0}" != "1" ]]; then
  echo "[autonomous-war] 1/4  Kokoro TTS"
  "$PY" tools/autonomous_war_vo.py "$VOICE"
else
  echo "[autonomous-war] 1/4  reusing existing VO"
fi

echo "[autonomous-war] 2/4  exporting score"
swift run swift-render audio AutonomousWar --out "$MUSIC"

echo "[autonomous-war] 3/4  mixing narration"
"$PY" tools/mix_vo.py "$MUSIC" "$TSV" "$VODIR" "$MIX"

echo "[autonomous-war] 4/4  rendering film"
swift run swift-render render AutonomousWar --audio "$MIX" --out "$OUT"

echo "[autonomous-war] done → $OUT"
