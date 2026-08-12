# ~/.claude/voice/config.sh — claude-voice overrides. Sourced by voice-lib.sh.
# Uncomment and edit; changes take effect on the next spoken line, no restart.

# --- TTS backend --------------------------------------------------------------
# say    = macOS built-in (zero install, robotic).
# kokoro = local neural voice (run ./setup-kokoro.sh first; 100% offline).
# VOICE_TTS=kokoro
# VOICE_KOKORO_VOICE=af_heart   # af_sarah, am_adam, am_michael, bf_emma, bm_george, ...
# VOICE_KOKORO_SPEED=1.0

# --- macOS `say` voice (only used when VOICE_TTS=say) -------------------------
# For a better native voice, download a Premium/Enhanced one:
#   System Settings ▸ Accessibility ▸ Spoken Content ▸ System Voice ▸ Manage Voices…
# then name it exactly as `say -v '?'` prints it:
# VOICE_SAY_VOICE="Ava (Premium)"
# VOICE_SAY_RATE=185

# --- Cue sounds (path to any .aiff/.wav, or "" to silence one) ----------------
# VOICE_SOUND_READY="/System/Library/Sounds/Glass.aiff"
# VOICE_SOUND_INPUT="/System/Library/Sounds/Ping.aiff"
# VOICE_SOUND_WAIT="/System/Library/Sounds/Submarine.aiff"
