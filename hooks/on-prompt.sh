#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook. Flag the tab "working" so a backgrounded pane
# shows activity until it finishes. Emits nothing on stdout (that would inject
# context into the prompt).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../lib/voice-lib.sh"
voice_init
voice_set_state "${WEZTERM_PANE:-}" working
exit 0
