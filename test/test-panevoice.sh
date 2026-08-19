#!/usr/bin/env bash
# test-panevoice.sh — voice_pane_voice resolution. An explicit per-pane pick
# (menu-bar Voice submenu -> panevoice file) wins regardless of the auto-pool
# feature flag; with no pick and the pool off, a pane uses the global voice.
set -u
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; export VOICE_DIR="$tmp"   # isolate from the real config
fail() { echo "FAIL: $1"; rm -rf "$tmp"; exit 1; }
pv() { bash -c ". '$R/lib/voice-lib.sh'; voice_init >/dev/null 2>&1; voice_pane_voice '$1'"; }

# explicit pick honored with pool OFF (default)
mkdir -p "$tmp/panevoice"; printf am_puck > "$tmp/panevoice/22"
[ "$(pv 22)" = am_puck ] || fail "explicit pick ignored with pool off"

# no pick -> global default voice
[ "$(pv 99)" = af_heart ] || fail "unset pane should fall back to global voice"

# non-numeric / empty -> global default (never a pool draw)
[ "$(pv '')" = af_heart ] || fail "empty pane id should be global voice"

rm -rf "$tmp"; echo "ok"
