#!/usr/bin/env bash
# Claude Code StopFailure hook. The turn ended on an API error — flag the tab red.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../lib/voice-lib.sh"
voice_init
pane="${WEZTERM_PANE:-}"
voice_set_state "$pane" error
voice_set_last "$pane" "This session hit an error and stopped."
[ "$(voice_mode)" = auto ] && voice_ping "$VOICE_SOUND_ERROR"
exit 0
