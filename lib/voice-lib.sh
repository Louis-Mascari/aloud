# voice-lib.sh — shared helpers for the claude-voice hooks and CLI. Sourced, not run.

VOICE_DIR="${VOICE_DIR:-$HOME/.claude/voice}"
QUEUE_DIR="$VOICE_DIR/queue"
STATE_DIR="$VOICE_DIR/state"
MODE_FILE="$VOICE_DIR/mode"

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

# Speak without blocking the hook (Claude Code waits for the hook to exit).
voice_say()  { [ -n "$1" ] && ( say "$1" >/dev/null 2>&1 & ); }
voice_ping() { [ -n "$1" ] && ( afplay "$1" >/dev/null 2>&1 & ); }
