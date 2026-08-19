#!/usr/bin/env bash
# setup-kokoro.sh — install the local Kokoro neural-TTS backend (100% offline,
# no cloud, no espeak-ng). ~360MB model download into an isolated uv venv under
# ~/.claude/voice/kokoro. Re-runnable.
set -euo pipefail

command -v uv   >/dev/null || { echo "need uv: https://docs.astral.sh/uv/getting-started/installation/"; exit 1; }
command -v curl >/dev/null || { echo "need curl"; exit 1; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K="${KOKORO_DIR:-$HOME/.claude/voice/kokoro}"
mkdir -p "$K"; cd "$K"

echo "==> venv + deps"
uv venv --python 3.12
uv pip install --python "$K/.venv/bin/python" -q kokoro-onnx soundfile sounddevice pypdf
# sounddevice bundles PortAudio on macOS/Windows; on Linux it needs the system lib:
#   Debian/Ubuntu: sudo apt install libportaudio2
[ "$(uname -s)" = Linux ] && ldconfig -p 2>/dev/null | grep -q portaudio \
  || { [ "$(uname -s)" = Linux ] && echo "NOTE: install libportaudio2 (e.g. sudo apt install libportaudio2)"; }

echo "==> models (~360MB, skipped if present)"
base="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
[ -f kokoro-v1.0.onnx ] || curl -fL --retry 3 -o kokoro-v1.0.onnx "$base/kokoro-v1.0.onnx"
[ -f voices-v1.0.bin ]  || curl -fL --retry 3 -o voices-v1.0.bin  "$base/voices-v1.0.bin"

# Symlink the source (not copy) so an edit in the repo is live immediately: the
# repo is the single source of truth, no second copy to drift. The venv and
# model weights above stay as real files here. Requires the repo to keep its
# path; if you move it, re-run this.
ln -sfn "$REPO/kokoro/daemon.py"           "$K/daemon.py"
ln -sfn "$REPO/kokoro/demo-voices.py"      "$K/demo-voices.py"
# Spit It Out (PDF reader) shares this Kokoro runtime: its code lives in
# pdf-reader/ but links in here alongside the model weights and venv.
ln -sfn "$REPO/pdf-reader/reader.py"       "$K/reader.py"
ln -sfn "$REPO/pdf-reader/pdf_extract.py"  "$K/pdf_extract.py"
rm -rf "$K/weblib"; ln -sfn "$REPO/pdf-reader/weblib" "$K/weblib"

# New code is in place; a long-running daemon holds the OLD code in memory
# (Python imports once at startup), so stop both so the next use loads the new
# code fresh. pdf-read relaunches reader.py; the voice hook relaunches daemon.py.
pkill -f "$K/reader.py" 2>/dev/null || true
pkill -f "$K/daemon.py" 2>/dev/null || true

echo
echo "Kokoro ready. Enable it in ~/.claude/voice/config.sh:"
echo "  VOICE_TTS=kokoro"
echo "  VOICE_KOKORO_VOICE=af_heart   # af_sarah, am_adam, am_michael, bf_emma, bm_george, ..."
echo "Test: $REPO/bin/kokoro-say 'Kokoro is working.'"
