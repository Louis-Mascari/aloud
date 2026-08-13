# voice-audio.sh — the portable audio layer: speak / play / stop. Backends are
# detected from PATH and overridable via VOICE_SPEAK_CMD / VOICE_PLAY_CMD in
# config.sh (override wins, detection only fills a blank). Sourced by
# voice-lib.sh; assumes VOICE_DIR, VOICE_TTS, KOKORO_*, VOICE_SAY_* are set.

_va_have()  { command -v "$1" >/dev/null 2>&1; }
_va_first() { local c; for c in "$@"; do _va_have "$c" && { printf '%s' "$c"; return; }; done; }

: "${VOICE_SPEAK_CMD:=$(_va_first say spd-say espeak-ng espeak)}"
: "${VOICE_PLAY_CMD:=$(_va_first afplay paplay pw-play aplay ffplay play)}"

_VA_PIDS="$VOICE_DIR/.pids"                 # our own speech PIDs, so barge-in kills only ours
_va_track() { [ -n "$1" ] && echo "$1" >> "$_VA_PIDS" 2>/dev/null; }
# True when no usable speech backend: neither the Kokoro daemon nor a native engine.
_va_no_speak_backend() {
  [ "$VOICE_TTS" = kokoro ] && [ -x "$KOKORO_SAY" ] && return 1
  [ -n "$VOICE_SPEAK_CMD" ] && return 1
  return 0
}

_va_warned() {  # $1 = SPEAK|PLAY — warn once to stderr, never break the hook
  local f="$VOICE_DIR/.no-${1}-warned"
  [ -f "$f" ] || { echo "claude-voice: no ${1} backend on PATH; set VOICE_${1}_CMD in config.sh" >&2; : > "$f"; }
}

# Native (non-Kokoro) TTS. `say` keeps its -v/-r; other engines take trailing text.
_va_native_speak() {
  # Track the engine PID (so voice_stop cuts only our own speech) and wait on it.
  case "${VOICE_SPEAK_CMD%% *}" in
    '') return 0 ;;   # no backend: voice_speak already warned in the foreground
    *say)
      local -a a=(say)
      [ -n "$VOICE_SAY_VOICE" ] && a+=(-v "$VOICE_SAY_VOICE")
      [ -n "$VOICE_SAY_RATE" ]  && a+=(-r "$VOICE_SAY_RATE")
      "${a[@]}" "$1" & _va_track "$!"; wait "$!" ;;
    *) local -a a; read -r -a a <<<"$VOICE_SPEAK_CMD"; "${a[@]}" "$1" & _va_track "$!"; wait "$!" ;;
  esac
}

# Speak one string. Kokoro (warm daemon) if selected, else the native engine.
_va_speak() {
  if [ "$VOICE_TTS" = kokoro ] && [ -x "$KOKORO_SAY" ]; then
    "$KOKORO_SAY" "$1" "$VOICE_KOKORO_VOICE" "$VOICE_KOKORO_SPEED" && return 0
  fi
  _va_native_speak "$1"
}

# async (hooks). Warn in the foreground so a missing backend actually surfaces.
voice_speak() {
  [ -n "$1" ] || return 0
  _va_no_speak_backend && { _va_warned SPEAK; return 0; }
  ( _va_speak "$1" >/dev/null 2>&1 & )
}
voice_speak_sync() {  # blocking (keys/CLI)
  [ -n "$1" ] || return 0
  _va_no_speak_backend && { _va_warned SPEAK; return 0; }
  _va_speak "$1"
}

voice_play() {  # cue sound file, async
  [ -n "$1" ] || return 0
  [ -n "$VOICE_PLAY_CMD" ] || { _va_warned PLAY; return 0; }
  local -a a; read -r -a a <<<"$VOICE_PLAY_CMD"
  ( "${a[@]}" "$1" >/dev/null 2>&1 & )
}

# Stop in-flight speech: only the engine processes we spawned (tracked PIDs),
# never a user's unrelated say/afplay. Kokoro plays in its daemon, cut by the flag.
voice_stop() {
  if [ -f "$_VA_PIDS" ]; then
    while read -r pid; do
      [ -n "$pid" ] || continue
      _va_have pkill && pkill -P "$pid" 2>/dev/null   # any child of our wrapper
      kill "$pid" 2>/dev/null
    done < "$_VA_PIDS"
    : > "$_VA_PIDS"
  fi
  _va_have spd-say && spd-say -C 2>/dev/null           # speech-dispatcher cancels its own queue
  touch "$KOKORO_DIR/interrupt" 2>/dev/null
}
