#!/usr/bin/env bash
# test-audio.sh — verify the portable audio layer without needing a real speaker:
# a fake backend proves the override is honored and the file/text arg passes through.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; log="$tmp/log"; export FAKELOG="$log"
export VOICE_DIR="$tmp"   # isolate from the real ~/.claude/voice/config.sh
cat > "$tmp/fake" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKELOG"
EOF
chmod +x "$tmp/fake"
fail() { echo "FAIL: $1"; rm -rf "$tmp"; exit 1; }
# audio runs in the background, so poll for the marker rather than a fixed sleep
wait_for() { local i; for i in $(seq 1 60); do grep -q "$1" "$log" 2>/dev/null && return 0; sleep 0.05; done; return 1; }

# 1. play honors VOICE_PLAY_CMD override and passes the file through
export VOICE_PLAY_CMD="$tmp/fake"
bash -c ". '$R/lib/voice-lib.sh'; voice_play /some/cue.wav"
wait_for '/some/cue.wav' || fail "voice_play did not run the override backend"
: > "$log"; unset VOICE_PLAY_CMD

# 2. speak (native) honors a multi-word VOICE_SPEAK_CMD and passes the text
export VOICE_SPEAK_CMD="$tmp/fake --flag" VOICE_TTS=say
bash -c ". '$R/lib/voice-lib.sh'; voice_speak_sync 'hello world'"
wait_for 'hello world' || fail "voice_speak did not run the override backend"
grep -q -- '--flag' "$log" || fail "multi-word speak command not parsed"
unset VOICE_SPEAK_CMD VOICE_TTS

# 3. no backend -> warns once, exits 0 (never breaks a hook). Blank the var AFTER
# sourcing so detection (which would find a real player) can't refill it.
out="$(bash -c ". '$R/lib/voice-lib.sh'; VOICE_PLAY_CMD=''; rm -f \"\$VOICE_DIR/.no-PLAY-warned\"; voice_play /x.wav" 2>&1)"
echo "$out" | grep -qi 'no PLAY backend' || fail "missing warning when no backend"

rm -rf "$tmp"
echo "ok"
