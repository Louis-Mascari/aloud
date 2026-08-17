#!/usr/bin/env bash
# Claude Code Stop hook. Queue the 🔊 summary and flag the tab done. Focus is
# decided by WezTerm's update-status poll, not here: a hook can't reliably tell
# which pane is up front (no $WEZTERM_PANE under tmux/ssh; ambiguous across windows).
#
# Deterministic no-silent-turn contract (three layers, so a forgotten/wrapped marker
# never yields a bare "Done." or nothing):
#   1. Match 🔊 anywhere on a line, not just at line start, so a bullet/bold/blockquote
#      wrapper around the marker can't hide the summary.
#   2. If the marker is truly absent, BLOCK the stop once (exit 2) and make the model
#      re-send with the line. Guarded by a per-session flag (and stop_hook_active) so it
#      nudges at most once and can never loop. Toggle with VOICE_ENFORCE_MARKER=false.
#   3. If it is still absent after the nudge, speak a sanitized tail of the real message
#      instead of "Done." — the user always hears the actual content.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../lib/voice-lib.sh"
voice_init
pane="${WEZTERM_PANE:-}"
mode="$(voice_mode)"

# Read stdin once — jq consumes it and we need several fields off the same payload.
input="$(cat)"
body="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')"
session="$(printf '%s' "$input" | jq -r '.session_id // empty')"
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false')"

# The summary is the last line CONTAINING the 🔊 marker (prose may mention it earlier;
# tail -1 keeps last-line-wins). Match anywhere on the line — the sed strips up to the
# marker regardless of any leading bullet/emphasis/quote decoration.
msg="$(printf '%s\n' "$body" | grep '🔊' | tail -1 | sed 's/.*🔊[[:space:]]*//; s/^[[:space:]*_#>]*//')"

retry="$VOICE_DIR/.stop-retry/${session:-${pane:-default}}"
if [ -n "$msg" ]; then
  rm -f "$retry" 2>/dev/null                       # marker present: clear any pending nudge
else
  # No 🔊 marker. Recover deterministically — never a bare "Done.", never silent.
  if [ "${VOICE_ENFORCE_MARKER:-true}" = true ] && [ "$stop_active" != true ] && [ ! -f "$retry" ]; then
    # First miss for this turn: block the stop so the model re-sends WITH the line.
    mkdir -p "$(dirname "$retry")"; : > "$retry"
    echo "Your reply is missing its required final 🔊 line (one or two plain, spoken sentences for text-to-speech, on a line that begins with 🔊). Re-send your final message ending with that line." >&2
    exit 2
  fi
  # Already nudged (or enforcement off, or a hook re-entry): speak a sanitized tail of
  # the real message — code fences and heading/table lines dropped, last two prose lines
  # kept. The speak path (voice_sanitize) strips remaining markup.
  rm -f "$retry" 2>/dev/null
  msg="$(printf '%s\n' "$body" \
    | awk '/^[[:space:]]*```/{f=!f; next} !f' \
    | grep -v '^[[:space:]]*$' | grep -vE '^[[:space:]]*[#|]' \
    | tail -2 | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ *//; s/ *$//')"
  [ -z "$msg" ] && msg="Done."   # the message body itself was empty: a short cue beats silence
fi

# auto only: wait mode (meetings) must not accumulate a queue that blurts on return.
# The last summary is still recorded below, so drain/recap speaks the latest on demand.
[ -n "$pane" ] && [ "$mode" = auto ] && printf '%s\n' "$msg" >> "$QUEUE_DIR/$pane"
voice_set_last "$pane" "$msg"
voice_set_state "$pane" ready

if [ "$mode" = auto ] && [ -z "$pane" ] && voice_is_focused "" && [ "$VOICE_AUTO_SPEAK" = true ]; then
  # No WezTerm poll to drive playback (plain terminal): speak the recap right here,
  # so voice-out works without WezTerm. Under WezTerm the update-status poll speaks.
  voice_say_pane "$pane" "$msg"
elif [ "$mode" = auto ] && ! voice_is_focused "$pane"; then
  # Background finish under WezTerm: soft nudge; the poll speaks it when you return.
  voice_ping "$VOICE_SOUND_READY"
fi
exit 0
