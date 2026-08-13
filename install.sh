#!/usr/bin/env bash
# install.sh — wire claude-voice into Claude Code. Idempotent; backs up before edits.
# WezTerm config is NOT auto-edited (it's usually hand-tuned): see wezterm/INTEGRATE.md.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
ts="$(date +%Y%m%d-%H%M%S)"

command -v jq  >/dev/null || { echo "need jq: brew install jq"; exit 1; }
command -v say >/dev/null || { echo "need macOS 'say' (this targets macOS)"; exit 1; }

echo "repo: $REPO"
chmod +x "$REPO"/hooks/*.sh "$REPO"/bin/voice
mkdir -p "$CLAUDE_DIR" "$HOME/.claude/voice/queue" "$HOME/.claude/voice/state"
[ -f "$HOME/.claude/voice/mode" ] || echo auto > "$HOME/.claude/voice/mode"

# ── hooks into settings.json ─────────────────────────────────────────
if [ -f "$SETTINGS" ] && grep -q 'hooks/on-stop.sh' "$SETTINGS"; then
  echo "settings.json: hooks already present, skipping"
else
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.pre-voice.$ts"; echo "backed up -> $SETTINGS.pre-voice.$ts"
  tmp="$(mktemp)"
  jq --arg s "$REPO/hooks/on-stop.sh" --arg n "$REPO/hooks/on-notification.sh" \
     --arg p "$REPO/hooks/on-prompt.sh" --arg sf "$REPO/hooks/on-stopfailure.sh" \
     --arg ses "$REPO/hooks/on-session.sh" --arg a "$REPO/hooks/on-active.sh" '
    .hooks.Stop             = ((.hooks.Stop // [])             + [{"hooks":[{"type":"command","command":("bash "+$s),"timeout":15}]}])
    | .hooks.StopFailure    = ((.hooks.StopFailure // [])      + [{"hooks":[{"type":"command","command":("bash "+$sf),"timeout":10}]}])
    | .hooks.Notification   = ((.hooks.Notification // [])     + [{"hooks":[{"type":"command","command":("bash "+$n),"timeout":15}]}])
    | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{"hooks":[{"type":"command","command":("bash "+$p),"timeout":10}]}])
    | .hooks.PreToolUse     = ((.hooks.PreToolUse // [])       + [{"matcher":".*","hooks":[{"type":"command","command":("bash "+$a),"timeout":5}]}])
    | .hooks.SessionStart   = ((.hooks.SessionStart // [])     + [{"hooks":[{"type":"command","command":("bash "+$ses),"timeout":10}]}])
    | .hooks.SessionEnd     = ((.hooks.SessionEnd // [])       + [{"hooks":[{"type":"command","command":("bash "+$ses),"timeout":10}]}])
  ' "$SETTINGS" > "$tmp"
  jq empty "$tmp"; mv "$tmp" "$SETTINGS"; echo "settings.json: hooks merged"
fi

# ── 🔊 rule into CLAUDE.md ────────────────────────────────────────────
if [ -f "$CLAUDE_MD" ] && grep -q 'claude-voice' "$CLAUDE_MD"; then
  echo "CLAUDE.md: 🔊 rule already present, skipping"
else
  [ -f "$CLAUDE_MD" ] && cp "$CLAUDE_MD" "$CLAUDE_MD.pre-voice.$ts"
  cat "$REPO/config/CLAUDE.snippet.md" >> "$CLAUDE_MD"
  echo "CLAUDE.md: 🔊 rule appended"
fi

# ── starter config.sh ────────────────────────────────────────────────
if [ ! -f "$HOME/.claude/voice/config.sh" ]; then
  cp "$REPO/config/config.sample.sh" "$HOME/.claude/voice/config.sh"
  echo "config: seeded ~/.claude/voice/config.sh"
fi

echo
echo "Done. Next:"
echo "  1. WezTerm users: apply wezterm/INTEGRATE.md (VOICE_BIN=$REPO/bin/voice), then reload."
echo "  2. Start a NEW Claude Code session so the hooks load."
echo "  3. Human voice (optional): ./setup-kokoro.sh, then set VOICE_TTS=kokoro in ~/.claude/voice/config.sh"
echo "  4. Try: '$REPO/bin/voice' status   |   toggle CMD+CTRL+V, drain CMD+SHIFT+V"
