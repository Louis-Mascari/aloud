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
STATE_DIR="$VOICE_DIR/state"; TASK_DIR="$VOICE_DIR/task"
PANEVOICE_DIR="$VOICE_DIR/panevoice"; LAST_DIR="$VOICE_DIR/last"
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
  ''|idle) echo "·|idle|#888888";;
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

  # List every live session, not just ones with a current state glyph: a pane's
  # state is cleared once you look at it, but its last summary/task persist, so
  # key on the union of state + last so finished-but-idle tabs still show.
  local any=0 p st task g label color ids
  ids="$( { for f in "$STATE_DIR"/* "$LAST_DIR"/*; do [ -e "$f" ] && printf '%s\n' "${f##*/}"; done; } | grep -E '^[0-9]+$' | sort -un )"
  for p in $ids; do
    st="$(cat "$STATE_DIR/$p" 2>/dev/null)"
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

# selftest: an active pane and an idle pane (last summary but no current state)
# must both render with their actions.
if [ "${1:-}" = selftest ]; then
  d="$(mktemp -d)"; VOICE_DIR="$d"; STATE_DIR="$d/state"; TASK_DIR="$d/task"; LAST_DIR="$d/last"
  VOICE_BIN="/usr/bin/true"; mkdir -p "$STATE_DIR" "$TASK_DIR" "$LAST_DIR"
  printf input > "$STATE_DIR/42"; printf 'fix the parser' > "$TASK_DIR/42"; echo wait > "$d/mode"
  printf 'earlier summary' > "$LAST_DIR/7"; printf 'other tab' > "$TASK_DIR/7"   # idle: no state file
  out="$(render)"
  echo "$out" | grep -q '^🔇' || { echo "FAIL: wait mode not muted glyph"; exit 1; }
  echo "$out" | grep -q '42 · fix the parser' || { echo "FAIL: pane row missing"; exit 1; }
  echo "$out" | grep -q '7 · other tab' || { echo "FAIL: idle pane row missing"; exit 1; }
  echo "$out" | grep -q 'param0=recap param1=7' || { echo "FAIL: idle pane replay action missing"; exit 1; }
  echo "$out" | grep -q 'param0=drain param1=42' || { echo "FAIL: play action missing"; exit 1; }
  rm -rf "$d"; echo "ok"; exit 0
fi

render
