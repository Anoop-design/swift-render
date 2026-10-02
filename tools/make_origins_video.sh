#!/usr/bin/env bash
#
# Build the narrated OriginsOfWokeness editorial film:
# Kokoro VO → synthesized score → ducked mix → Swift Render MP4.
#
# Usage:
#   bash tools/make_origins_video.sh
#   VOICE=af_heart bash tools/make_origins_video.sh
#   SKIP_VO=1 bash tools/make_origins_video.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

VOICE="${VOICE:-am_michael}"
PY=".venv-kokoro/bin/python"
MUSIC="out/origins-music.wav"
MIX="out/origins-mix.wav"
TSV="out/origins-vo.tsv"
VODIR="out/vo-origins"
OUT="${OUT:-out/origins-of-wokeness.mp4}"

if [[ "${SKIP_VO:-0}" != "1" ]]; then
  echo "[origins] 1/4  Kokoro TTS (voice '$VOICE')"
  "$PY" tools/origins_vo.py "$VOICE"
else
  echo "[origins] 1/4  reusing existing VO in $VODIR"
fi

echo "[origins] 2/4  exporting score → $MUSIC"
swift run swift-render audio OriginsOfWokeness --out "$MUSIC"

echo "[origins] 3/4  ducking score under VO → $MIX"
"$PY" tools/mix_vo.py "$MUSIC" "$TSV" "$VODIR" "$MIX"

echo "[origins] 4/4  rendering film → $OUT"
swift run swift-render render OriginsOfWokeness --audio "$MIX" --out "$OUT"

echo "[origins] done → $OUT"
