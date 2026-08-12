#!/usr/bin/env bash
# Claude Code SessionStart + SessionEnd hook. Clear this pane's files so a reused
# pane id (WezTerm reuses ids after a pane closes) can't show a stale glyph or
# speak a dead session's summary. SessionStart wipes leftovers before the new
# session runs; SessionEnd wipes on clean exit.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/../lib/voice-lib.sh"
voice_init
voice_clear_pane "${WEZTERM_PANE:-}"
exit 0
