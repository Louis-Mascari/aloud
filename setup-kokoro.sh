#!/usr/bin/env bash
# setup-kokoro.sh — install the local Kokoro neural-TTS backend (100% offline,
# no cloud, no espeak-ng). ~360MB model download into an isolated uv venv under
# ~/.claude/voice/kokoro. Re-runnable.
set -euo pipefail

command -v uv   >/dev/null || { echo "need uv: https://docs.astral.sh/uv/getting-started/installation/"; exit 1; }
command -v curl >/dev/null || { echo "need curl"; exit 1; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K="$HOME/.claude/voice/kokoro"
mkdir -p "$K"; cd "$K"

echo "==> venv + deps"
uv venv --python 3.12
uv pip install --python "$K/.venv/bin/python" -q kokoro-onnx soundfile sounddevice
# sounddevice bundles PortAudio on macOS/Windows; on Linux it needs the system lib:
#   Debian/Ubuntu: sudo apt install libportaudio2
[ "$(uname -s)" = Linux ] && ldconfig -p 2>/dev/null | grep -q portaudio \
  || { [ "$(uname -s)" = Linux ] && echo "NOTE: install libportaudio2 (e.g. sudo apt install libportaudio2)"; }

echo "==> models (~360MB, skipped if present)"
base="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
[ -f kokoro-v1.0.onnx ] || curl -fL --retry 3 -o kokoro-v1.0.onnx "$base/kokoro-v1.0.onnx"
[ -f voices-v1.0.bin ]  || curl -fL --retry 3 -o voices-v1.0.bin  "$base/voices-v1.0.bin"

cp "$REPO/kokoro/synth.py" "$K/synth.py"
cp "$REPO/kokoro/daemon.py" "$K/daemon.py"

echo
echo "Kokoro ready. Enable it in ~/.claude/voice/config.sh:"
echo "  VOICE_TTS=kokoro"
echo "  VOICE_KOKORO_VOICE=af_heart   # af_sarah, am_adam, am_michael, bf_emma, bm_george, ..."
echo "Test: $REPO/bin/kokoro-say 'Kokoro is working.'"
