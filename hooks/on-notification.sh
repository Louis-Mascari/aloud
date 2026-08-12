#!/usr/bin/env bash
# Claude Code Notification hook. Blocked / needs-input cue, same focus + mode rules
# as on-stop. In wait mode it only flags the tab, so nothing speaks in a meeting.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../lib/voice-lib.sh"
voice_init
pane="${WEZTERM_PANE:-}"
mode="$(voice_mode)"

t="$(jq -r '.notification_type // empty')"
case "$t" in permission_prompt|elicitation_dialog|agent_needs_input|idle_prompt) ;; *) exit 0 ;; esac

if [ "$mode" = auto ] && voice_is_focused "$pane"; then
  voice_say "Claude needs you."
  exit 0
fi

voice_set_state "$pane" input
[ "$mode" = auto ] && voice_ping "$VOICE_SOUND_INPUT"
exit 0
