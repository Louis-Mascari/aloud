#!/usr/bin/env bash
# Claude Code Notification hook. Blocking notifications flag the tab "input" (amber,
# needs you); idle just confirms "done". In wait mode nothing sounds.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../lib/voice-lib.sh"
voice_init
pane="${WEZTERM_PANE:-}"
mode="$(voice_mode)"
t="$(jq -r '.notification_type // empty')"
[ -n "${VOICE_DEBUG:-}" ] && printf '%s %s\n' "$(date +%H:%M:%S)" "$t" >> "$VOICE_DIR/notify.log"

case "$t" in
  permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input)
    voice_set_state "$pane" input
    [ "$mode" = auto ] && voice_ping "$VOICE_SOUND_INPUT" ;;
  # You answered the elicitation: drop the "needs you" glyph now instead of waiting
  # for the next tool. Scoped to elicitation answers only — permission prompts have
  # no answer event, so they still clear on the next PreToolUse.
  elicitation_complete|elicitation_response)
    [ -n "$pane" ] && [ "$(cat "$STATE_DIR/$pane" 2>/dev/null)" = input ] && voice_set_state "$pane" working ;;
  idle_prompt)
    voice_set_state "$pane" ready ;;   # finished, waiting on you; Stop already made the sound
  *) exit 0 ;;
esac
exit 0
