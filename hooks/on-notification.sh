#!/usr/bin/env bash
# Claude Code Notification hook. Blocking notifications flag the tab "input" (amber,
# needs you); idle just confirms "done". In wait mode nothing sounds.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../lib/voice-lib.sh"
voice_init
pane="${WEZTERM_PANE:-}"
mode="$(voice_mode)"
t="$(jq -r '.notification_type // empty')"

case "$t" in
  permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input)
    voice_set_state "$pane" input
    [ "$mode" = auto ] && voice_ping "$VOICE_SOUND_INPUT" ;;
  idle_prompt)
    voice_set_state "$pane" ready ;;   # finished, waiting on you; Stop already made the sound
  *) exit 0 ;;
esac
exit 0
