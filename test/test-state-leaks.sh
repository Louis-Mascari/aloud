#!/usr/bin/env bash
# test-state-leaks.sh — a state write killed between its tmp file and the rename
# must not count as a pane: `voice attention` reads pane-id files only, and
# _voice_put leaves no tmp name a `state/*` glob can see.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; export VOICE_DIR="$tmp"   # isolate from the real config
fail() { echo "FAIL: $1"; rm -rf "$tmp"; exit 1; }

mkdir -p "$tmp/state"
printf input > "$tmp/state/42"
printf error > "$tmp/state/7.tmp.123"     # leaked by the old tmp naming
printf error > "$tmp/state/.8.tmp.456"    # leaked by the new tmp naming
out="$("$R/bin/voice" attention 2>/dev/null)"
[ "$out" = "⏸1" ] || fail "attention counted a leaked tmp file: '$out'"

bash -c ". '$R/lib/voice-lib.sh'; voice_init >/dev/null 2>&1; voice_set_state 9 ready" || fail "voice_set_state failed"
[ "$(cat "$tmp/state/9" 2>/dev/null)" = ready ] || fail "voice_set_state did not write the state"
for f in "$tmp/state"/*; do case "${f##*/}" in *.tmp.*) [ "${f##*/}" = 7.tmp.123 ] || fail "visible tmp file ${f##*/}";; esac; done

rm -rf "$tmp"; echo "ok"
