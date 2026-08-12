#!/usr/bin/env bash
# Claude Code Stop hook. Queue the 🔊 summary and flag the tab done. Focus is
# decided by WezTerm's update-status poll, not here: a hook can't reliably tell
# which pane is up front (no $WEZTERM_PANE under tmux/ssh; ambiguous across windows).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../lib/voice-lib.sh"
voice_init
pane="${WEZTERM_PANE:-}"
mode="$(voice_mode)"

# The summary is the last line that STARTS with the 🔊 marker (prose may mention it earlier).
msg="$(jq -r '.last_assistant_message // empty' | grep '^[[:space:]]*🔊' | tail -1 | sed 's/.*🔊[[:space:]]*//')"

if [ -z "$msg" ]; then
  voice_set_state "$pane" ready   # no summary line, but the turn is done
  exit 0
fi

[ -n "$pane" ] && printf '%s\n' "$msg" >> "$QUEUE_DIR/$pane"
voice_set_last "$pane" "$msg"
voice_set_state "$pane" ready
# Soft nudge for a background finish. Best-effort focus check; a stray ping is harmless.
if [ "$mode" = auto ] && ! voice_is_focused "$pane"; then voice_ping "$VOICE_SOUND_READY"; fi
exit 0
