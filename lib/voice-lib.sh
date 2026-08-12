# voice-lib.sh — shared helpers for the claude-voice hooks and CLI. Sourced, not run.

_VOICE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VOICE_DIR="${VOICE_DIR:-$HOME/.claude/voice}"
QUEUE_DIR="$VOICE_DIR/queue"
STATE_DIR="$VOICE_DIR/state"
MODE_FILE="$VOICE_DIR/mode"

# Optional user overrides (voice name, rate, sounds) live here, sourced if present.
[ -f "$VOICE_DIR/config.sh" ] && . "$VOICE_DIR/config.sh"

# Spoken voice + rate. Empty = macOS system voice. Set VOICE_SAY_VOICE to a
# downloaded Premium/Enhanced voice for a far more natural sound, e.g.
# VOICE_SAY_VOICE="Ava (Premium)". Rate is words/min (e.g. 180).
VOICE_SAY_VOICE="${VOICE_SAY_VOICE:-}"
VOICE_SAY_RATE="${VOICE_SAY_RATE:-}"

# TTS backend: say (built-in, zero-install default) or kokoro (local neural voice,
# run setup-kokoro.sh once). kokoro falls back to say if its wrapper is missing.
VOICE_TTS="${VOICE_TTS:-say}"
KOKORO_SAY="${KOKORO_SAY:-$_VOICE_LIB_DIR/../bin/kokoro-say}"
VOICE_KOKORO_VOICE="${VOICE_KOKORO_VOICE:-af_heart}"
VOICE_KOKORO_SPEED="${VOICE_KOKORO_SPEED:-1.0}"

# Swappable so a fork can rebrand the cues without touching logic.
VOICE_SOUND_READY="${VOICE_SOUND_READY:-/System/Library/Sounds/Glass.aiff}"
VOICE_SOUND_INPUT="${VOICE_SOUND_INPUT:-/System/Library/Sounds/Ping.aiff}"
VOICE_SOUND_WAIT="${VOICE_SOUND_WAIT:-/System/Library/Sounds/Submarine.aiff}"

voice_init() { mkdir -p "$QUEUE_DIR" "$STATE_DIR"; }

# auto = speak the moment the focused pane is ready; wait = never speak or ping on
# its own, you ask for it (meeting-safe). Absent file = auto.
voice_mode() { cat "$MODE_FILE" 2>/dev/null || echo auto; }

# pane_id with real keyboard focus across every window and tab; empty outside WezTerm.
voice_focused_pane() {
  wezterm cli list-clients --format json 2>/dev/null \
    | jq -r 'first(.[] | .focused_pane_id) // empty' 2>/dev/null
}

# Focused when $1 == the focused pane. No pane id (not under WezTerm) counts as
# focused, so a plain-terminal user hears output instead of silence.
voice_is_focused() { [ -z "$1" ] && return 0; [ "$1" = "$(voice_focused_pane)" ]; }

# Tab-bar state (working|ready|input), read by wezterm's format-tab-title. Files,
# not OSC user vars: Claude Code hooks run without a tty and can't emit the
# SetUserVar escape that statusline.sh uses.
voice_set_state()   { [ -n "$1" ] && printf '%s' "$2" > "$STATE_DIR/$1"; }
voice_clear_state() { [ -n "$1" ] && rm -f "$STATE_DIR/$1"; }

# Speak. voice_say is async (a hook must not block Claude Code); voice_say_sync
# blocks and is for callers already backgrounded (drain/refocus). Both honor the
# configured voice/rate; the array keeps a voice name with spaces intact.
_voice_say() {
  if [ "$VOICE_TTS" = kokoro ] && [ -x "$KOKORO_SAY" ]; then
    "$KOKORO_SAY" "$1" "$VOICE_KOKORO_VOICE" "$VOICE_KOKORO_SPEED" && return 0
  fi
  local -a a=(say)
  [ -n "$VOICE_SAY_VOICE" ] && a+=(-v "$VOICE_SAY_VOICE")
  [ -n "$VOICE_SAY_RATE" ]  && a+=(-r "$VOICE_SAY_RATE")
  "${a[@]}" "$1"
}
voice_say()      { [ -n "$1" ] && ( _voice_say "$1" >/dev/null 2>&1 & ); }
voice_say_sync() { [ -n "$1" ] && _voice_say "$1"; }
voice_ping() { [ -n "$1" ] && ( afplay "$1" >/dev/null 2>&1 & ); }
