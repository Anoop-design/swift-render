#!/usr/bin/env python3
"""Kokoro TTS engine for make_firm_audio.sh.

Reads a TSV of narration lines and writes one 44.1 kHz / mono / Int16 wav per
id into the given out/vo directory — drop-in replacement for the macOS `say`
path. Loads the Kokoro model ONCE for the whole batch.

Usage:
    python kokoro_tts.py <tsv_path> <out_vo_dir> [voice]

TSV format (tab-separated, matching tools/mix_vo.py):
    id<TAB>start<TAB>text

Kokoro outputs 24 kHz float32; we resample each line to 44100/mono/s16 with
ffmpeg so the downstream mixer (tools/mix_vo.py) sample-rate assertion passes.

Must be run with the project's Kokoro venv python, e.g.:
    /Users/sky/swift-render/.venv-kokoro/bin/python tools/kokoro_tts.py ...
"""

import os
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Environment setup — MUST happen before importing kokoro, which phonemizes via
# espeak-ng at import/first-call time. Derive paths from `brew --prefix
# espeak-ng`. Also set VIRTUAL_ENV (to the venv this interpreter lives in) to
# avoid a uv error inside kokoro's deps.
# ---------------------------------------------------------------------------


def _setup_env():
    try:
        prefix = subprocess.check_output(
            ["brew", "--prefix", "espeak-ng"], text=True
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        sys.exit(f"kokoro_tts: could not locate espeak-ng via brew: {exc}")

    data_path = os.path.join(prefix, "share", "espeak-ng-data")
    lib_path = os.path.join(prefix, "lib", "libespeak-ng.dylib")
    os.environ.setdefault("ESPEAK_DATA_PATH", data_path)
    os.environ.setdefault("PHONEMIZER_ESPEAK_LIBRARY", lib_path)

    # VIRTUAL_ENV = the venv containing this python interpreter
    # (…/.venv-kokoro/bin/python → …/.venv-kokoro)
    venv = os.path.dirname(os.path.dirname(os.path.abspath(sys.executable)))
    os.environ.setdefault("VIRTUAL_ENV", venv)


_setup_env()

import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402
from kokoro import KPipeline  # noqa: E402

KOKORO_SR = 24000
TARGET_SR = 44100


def synth_line(pipe, text, voice):
    """Run Kokoro over `text`, concatenating all yielded float32 chunks."""
    chunks = []
    for _, _, audio in pipe(text, voice=voice):
        if audio is None:
            continue
        arr = np.asarray(audio, dtype=np.float32)
        if arr.size:
            chunks.append(arr)
    if not chunks:
        return np.zeros(0, dtype=np.float32)
    return np.concatenate(chunks).astype(np.float32)


def resample_to_target(src_wav, dst_wav):
    """ffmpeg-resample a 24k wav to 44100 / mono / s16."""
    subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-i", src_wav,
            "-ar", str(TARGET_SR), "-ac", "1", "-sample_fmt", "s16",
            dst_wav,
        ],
        check=True,
    )


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: kokoro_tts.py <tsv_path> <out_vo_dir> [voice]")

    tsv_path = sys.argv[1]
    out_vo_dir = sys.argv[2]
    voice = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else "af_heart"

    os.makedirs(out_vo_dir, exist_ok=True)

    lines = []
    with open(tsv_path) as fh:
        for raw in fh:
            if not raw.strip():
                continue
            parts = raw.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            lid, start, text = parts[0], parts[1], parts[2]
            if not text.strip():
                continue
            lines.append((lid, start, text))

    print(f"[kokoro] loading model (voice={voice}) for {len(lines)} lines …",
          flush=True)
    pipe = KPipeline(lang_code="a")

    for lid, _start, text in lines:
        audio = synth_line(pipe, text, voice)
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp24 = tmp.name
        try:
            sf.write(tmp24, audio, KOKORO_SR, subtype="FLOAT")
            dst = os.path.join(out_vo_dir, f"{lid}.wav")
            resample_to_target(tmp24, dst)
        finally:
            try:
                os.unlink(tmp24)
            except OSError:
                pass
        dur = len(audio) / KOKORO_SR if audio.size else 0.0
        print(f"[kokoro] line {lid}  {dur:5.2f}s → {os.path.join(out_vo_dir, lid)}.wav",
              flush=True)


if __name__ == "__main__":
    main()
