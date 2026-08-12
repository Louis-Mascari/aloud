#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook. Mark the tab "working" and remember what the
# session is doing (first line of the prompt) so a recap can name the work.
# Emits nothing on stdout (that would inject into the prompt).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../lib/voice-lib.sh"
voice_init
pane="${WEZTERM_PANE:-}"
task="$(jq -r '.user_input // .prompt // empty' 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ *$//' | cut -c1-80)"
[ -n "$task" ] && voice_set_task "$pane" "$task"
voice_set_state "$pane" working
exit 0
