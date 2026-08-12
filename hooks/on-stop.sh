#!/usr/bin/env bash
# Claude Code Stop hook. Speak the 🔊 summary if you're looking at this pane;
# otherwise queue it, flag the tab, and (auto mode) ping. Never voices the body.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../lib/voice-lib.sh"
voice_init
pane="${WEZTERM_PANE:-}"
mode="$(voice_mode)"

msg="$(jq -r '.last_assistant_message // empty' | grep -m1 '🔊' | sed 's/.*🔊[[:space:]]*//')"
if [ -z "$msg" ]; then voice_clear_state "$pane"; exit 0; fi

if [ "$mode" = auto ] && voice_is_focused "$pane"; then
  voice_clear_state "$pane"
  voice_say "$msg"
  exit 0
fi

[ -n "$pane" ] && printf '%s\n' "$msg" >> "$QUEUE_DIR/$pane"
voice_set_state "$pane" ready
[ "$mode" = auto ] && voice_ping "$VOICE_SOUND_READY"
exit 0
