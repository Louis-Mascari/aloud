#!/usr/bin/env bash
# <xbar.title>claude-voice</xbar.title>
# <xbar.desc>Menu-bar transport for claude-voice: per-pane state + play/stop/replay/jump/mute.</xbar.desc>
# <xbar.version>1.0</xbar.version>
#
# SwiftBar/xbar plugin. Reads the ~/.claude/voice state files and drives the
# `voice` CLI. Filename cadence (.3s.) = refresh every 3s. Install:
#   ln -s "$PWD/mac/swiftbar/claude-voice.3s.sh" ~/Library/Application\ Support/SwiftBar/Plugins/
#   chmod +x mac/swiftbar/claude-voice.3s.sh
# Override the CLI location with VOICE_BIN if the repo isn't at the default path.

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
VOICE_DIR="${VOICE_DIR:-$HOME/.claude/voice}"
STATE_DIR="$VOICE_DIR/state"; TASK_DIR="$VOICE_DIR/task"; PANEVOICE_DIR="$VOICE_DIR/panevoice"
# Resolve the repo's bin/voice from this script's own (symlink-aware) location, so
# the plugin works wherever the repo lives. Override with VOICE_BIN if needed.
SELF="${BASH_SOURCE[0]}"; [ -L "$SELF" ] && SELF="$(readlink "$SELF")"
VOICE_BIN="${VOICE_BIN:-$(cd "$(dirname "$SELF")/../../bin" 2>/dev/null && pwd)/voice}"
[ -x "$VOICE_BIN" ] || VOICE_BIN="$(command -v voice || echo "$VOICE_BIN")"

# state -> "glyph|label|color"
_meta() { case "$1" in
  working) echo "🔧|working|#7f8fa6";;
  ready)   echo "✓|finished|#76946a";;
  input)   echo "⏸|needs you|#e6c384";;
  error)   echo "✗|error|#c34043";;
  *)       echo "·|$1|#888888";;
esac; }

# Render the whole plugin to stdout. Pulled into a function so selftest can capture it.
render() {
  local mode attention title
  mode="$(cat "$VOICE_DIR/mode" 2>/dev/null || echo auto)"
  attention="$("$VOICE_BIN" attention 2>/dev/null)"
  [ "$mode" = wait ] && title="🔇" || title="🔊"
  [ -n "$attention" ] && title="$title $attention"
  echo "$title"
  echo "---"

  echo "claude-voice — $mode | color=#888888"
  echo "⏹ Stop speaking | bash=\"$VOICE_BIN\" param0=stop terminal=false refresh=true"
  echo "⤢ Jump to urgent | bash=\"$VOICE_BIN\" param0=jump terminal=false refresh=true"
  if [ "$mode" = wait ]; then
    echo "🔊 Unmute (auto) | bash=\"$VOICE_BIN\" param0=toggle terminal=false refresh=true"
  else
    echo "🔇 Mute (wait mode) | bash=\"$VOICE_BIN\" param0=toggle terminal=false refresh=true"
  fi
  echo "---"

  local any=0 f p st task g label color
  for f in "$STATE_DIR"/*; do
    [ -e "$f" ] || continue
    p="${f##*/}"; case "$p" in *[!0-9]*) continue;; esac   # numeric pane ids only
    st="$(cat "$f" 2>/dev/null)"
    task="$(cat "$TASK_DIR/$p" 2>/dev/null | tr '|\n' '  ')"; [ -n "$task" ] || task="pane $p"
    # Trim to a word boundary with an ellipsis so the row doesn't end mid-word.
    [ "${#task}" -gt 40 ] && { task="${task:0:40}"; task="${task% *}…"; }
    IFS='|' read -r g label color <<<"$(_meta "$st")"
    echo "$g $p · $task | color=$color"
    echo "-- ▶ Play pending | bash=\"$VOICE_BIN\" param0=drain param1=$p terminal=false refresh=true"
    echo "-- ↺ Replay last | bash=\"$VOICE_BIN\" param0=recap param1=$p terminal=false refresh=true"
    echo "-- 🎙 Voice"
    local vg cur; cur="$(cat "$PANEVOICE_DIR/$p" 2>/dev/null)"
    for vg in "af_heart:Heart · A" "af_bella:Bella · A-" "bf_emma:Emma · B-" "am_michael:Michael · C+" "am_puck:Puck · C+"; do
      mark=""; [ "${vg%%:*}" = "$cur" ] && mark="✓ "   # the pane's current voice
      echo "---- ${mark}${vg#*:} | bash=\"$VOICE_BIN\" param0=panevoice param1=$p param2=${vg%%:*} terminal=false refresh=true"
    done
    any=1
  done
  [ "$any" = 1 ] || echo "No active sessions | color=#888888"
  echo "---"

  echo "Speed"
  local s
  for s in 0.8 1.0 1.2 1.5; do
    echo "-- ${s}× | bash=\"$VOICE_BIN\" param0=speed param1=$s terminal=false refresh=true"
  done
  echo "Refresh | refresh=true"
}

# selftest: a temp state dir with one input pane must render that pane + its actions.
if [ "${1:-}" = selftest ]; then
  d="$(mktemp -d)"; VOICE_DIR="$d"; STATE_DIR="$d/state"; TASK_DIR="$d/task"
  VOICE_BIN="/usr/bin/true"; mkdir -p "$STATE_DIR" "$TASK_DIR"
  printf input > "$STATE_DIR/42"; printf 'fix the parser' > "$TASK_DIR/42"; echo wait > "$d/mode"
  out="$(render)"
  echo "$out" | grep -q '^🔇' || { echo "FAIL: wait mode not muted glyph"; exit 1; }
  echo "$out" | grep -q '42 · fix the parser' || { echo "FAIL: pane row missing"; exit 1; }
  echo "$out" | grep -q 'param0=drain param1=42' || { echo "FAIL: play action missing"; exit 1; }
  rm -rf "$d"; echo "ok"; exit 0
fi

render
