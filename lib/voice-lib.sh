# voice-lib.sh — shared helpers for the claude-voice hooks and CLI. Sourced, not run.

_VOICE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VOICE_DIR="${VOICE_DIR:-$HOME/.claude/voice}"
QUEUE_DIR="$VOICE_DIR/queue"   # pending spoken summary per pane
STATE_DIR="$VOICE_DIR/state"   # working|ready|input|error  -> tab glyph
TASK_DIR="$VOICE_DIR/task"     # short name of what the session is doing
LAST_DIR="$VOICE_DIR/last"     # last spoken summary, kept for on-demand recap
PANEVOICE_DIR="$VOICE_DIR/panevoice"   # per-pane Kokoro voice assignment (when enabled)
MODE_FILE="$VOICE_DIR/mode"

# Optional user overrides (voice, rate, backend, sounds), sourced if present.
[ -f "$VOICE_DIR/config.sh" ] && . "$VOICE_DIR/config.sh"

VOICE_SAY_VOICE="${VOICE_SAY_VOICE:-}"
VOICE_SAY_RATE="${VOICE_SAY_RATE:-}"

# TTS backend: say (built-in default) or kokoro (local neural; setup-kokoro.sh).
VOICE_TTS="${VOICE_TTS:-say}"
KOKORO_DIR="${KOKORO_DIR:-$VOICE_DIR/kokoro}"
KOKORO_SAY="${KOKORO_SAY:-$_VOICE_LIB_DIR/../bin/kokoro-say}"
VOICE_KOKORO_VOICE="${VOICE_KOKORO_VOICE:-af_heart}"
VOICE_KOKORO_SPEED="${VOICE_KOKORO_SPEED:-1.0}"

# Per-pane voices: give each pane its own Kokoro voice so concurrent sessions
# are distinguishable by ear. Off = every pane uses VOICE_KOKORO_VOICE.
VOICE_PANE_VOICES="${VOICE_PANE_VOICES:-false}"
# Default pool = clear, natural, easy-to-tell-apart voices (Kokoro grades A to C+);
# curate with `voice pool`. Excludes stylized ones like af_nicole (🎧 whisper).
VOICE_PANE_VOICE_POOL="${VOICE_PANE_VOICE_POOL:-af_heart af_bella bf_emma am_michael}"

# true = speak on switch/finish; false = silent (never auto-speaks; you press a key).
VOICE_AUTO_SPEAK="${VOICE_AUTO_SPEAK:-true}"

# Cue sounds. Only "needs you" states make sound; done is a soft blip.
VOICE_SOUND_READY="${VOICE_SOUND_READY:-/System/Library/Sounds/Glass.aiff}"
VOICE_SOUND_INPUT="${VOICE_SOUND_INPUT:-/System/Library/Sounds/Ping.aiff}"
VOICE_SOUND_ERROR="${VOICE_SOUND_ERROR:-/System/Library/Sounds/Basso.aiff}"
VOICE_SOUND_WAIT="${VOICE_SOUND_WAIT:-/System/Library/Sounds/Submarine.aiff}"

# The portable audio layer (speak / play / stop), detected + overridable.
. "$_VOICE_LIB_DIR/voice-audio.sh"

# Public names kept stable for the hooks/CLI; they map onto the audio layer.
voice_say()      { voice_speak "$1"; }
voice_say_sync() { voice_speak_sync "$1"; }
voice_ping()     { voice_play "$1"; }

# Kokoro voice for a pane (Kokoro only; `say` uses VOICE_SAY_VOICE). Off, or a
# non-pane caller, gets the single configured voice. On, a pane is assigned a
# voice once and keeps it for life; the assignment prefers one no other live pane
# holds, so concurrent sessions stay distinct until the pool is exhausted.
voice_pane_voice() {
  case "$1" in ''|*[!0-9]*) printf '%s' "$VOICE_KOKORO_VOICE"; return;; esac
  mkdir -p "$PANEVOICE_DIR"
  local f="$PANEVOICE_DIR/$1" v
  # An explicit assignment (manual pick in the menu-bar Voice submenu, or a prior
  # auto-pool draw) always wins, whether or not the auto-pool feature is on.
  v="$(cat "$f" 2>/dev/null)"; [ -n "$v" ] && { printf '%s' "$v"; return; }
  [ "$VOICE_PANE_VOICES" = true ] || { printf '%s' "$VOICE_KOKORO_VOICE"; return; }
  local -a pool; read -r -a pool <<<"$VOICE_PANE_VOICE_POOL"
  local n=${#pool[@]}
  [ "$n" -gt 0 ] || { printf '%s' "$VOICE_KOKORO_VOICE"; return; }
  local used=" " g id
  for g in "$PANEVOICE_DIR"/*; do
    [ -e "$g" ] || continue; id="${g##*/}"; [ "$id" = "$1" ] && continue
    [ -e "$LAST_DIR/$id" ] || { rm -f "$g"; continue; }   # dead pane: free its voice
    used="$used$(cat "$g" 2>/dev/null) "
  done
  local cand
  for cand in "${pool[@]}"; do case "$used" in *" $cand "*) ;; *) v="$cand"; break;; esac; done
  [ -n "$v" ] || v="${pool[$(( $1 % n ))]}"          # all in use: reuse deterministically
  printf '%s' "$v" > "$f"; printf '%s' "$v"
}
# Speak in a pane's voice; the subshell scopes the per-pane voice override.
voice_say_pane()      { ( VOICE_KOKORO_VOICE="$(voice_pane_voice "$1")"; voice_say "$2" ); }
voice_say_sync_pane() { ( VOICE_KOKORO_VOICE="$(voice_pane_voice "$1")"; voice_say_sync "$2" ); }

voice_init() {
  mkdir -p "$QUEUE_DIR" "$STATE_DIR" "$TASK_DIR" "$LAST_DIR" "$PANEVOICE_DIR"
  command -v jq >/dev/null || echo "claude-voice: jq not found; summaries disabled" >&2
}

# auto = speak in the focused pane; wait = silent, ask with the drain key. No file = auto.
voice_mode() { cat "$MODE_FILE" 2>/dev/null || echo auto; }

voice_focused_pane() {
  wezterm cli list-clients --format json 2>/dev/null \
    | jq -r 'first(.[] | .focused_pane_id) // empty' 2>/dev/null
}

# Focused when $1 == the focused pane. An empty pane id ("no WezTerm pane") counts
# as focused ONLY when WezTerm is not the terminal, so a pane under tmux/ssh that
# dropped $WEZTERM_PANE queues instead of blurting on whatever pane is up front.
voice_is_focused() {
  if [ -z "$1" ]; then
    [ -n "${WEZTERM_UNIX_SOCKET:-}${WEZTERM_EXECUTABLE:-}" ] && return 1
    return 0
  fi
  [ "$1" = "$(voice_focused_pane)" ]
}

# Atomic writes (tmp + rename) so a WezTerm reader never sees a torn/empty file.
_voice_put()        { [ -n "$1" ] && { printf '%s' "$3" > "$2/$1.tmp.$$" && mv "$2/$1.tmp.$$" "$2/$1"; }; }
voice_set_state()   { _voice_put "$1" "$STATE_DIR" "$2"; }
voice_set_task()    { _voice_put "$1" "$TASK_DIR" "$2"; }
voice_set_last()    { _voice_put "$1" "$LAST_DIR" "$2"; }
voice_clear_state() { [ -n "$1" ] && rm -f "$STATE_DIR/$1"; }
voice_clear_pane()  { [ -n "$1" ] && rm -f "$STATE_DIR/$1" "$QUEUE_DIR/$1" "$QUEUE_DIR/$1".speaking "$QUEUE_DIR/$1".drain.* "$TASK_DIR/$1" "$LAST_DIR/$1" "$PANEVOICE_DIR/$1"; }

# Triage rank: higher = more urgent. Drives the aggregate badge and `voice jump`.
voice_rank() { case "$1" in error) echo 3;; input) echo 2;; ready) echo 1;; *) echo 0;; esac; }
