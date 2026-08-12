#!/usr/bin/env bash
# Claude Code PreToolUse hook. Running a tool = actively working, so clear any
# stale "input"/"ready" glyph on this pane. Minimal (no lib source) because it
# fires on every tool call.
p="${WEZTERM_PANE:-}"; [ -n "$p" ] || exit 0
d="${VOICE_DIR:-$HOME/.claude/voice}/state"
mkdir -p "$d" && printf working > "$d/$p.tmp.$$" && mv "$d/$p.tmp.$$" "$d/$p"
exit 0
