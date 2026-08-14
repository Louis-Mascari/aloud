# ~/.claude/voice/config.sh — claude-voice overrides. Sourced by voice-lib.sh.
# Uncomment and edit; changes take effect on the next spoken line, no restart.

# --- TTS backend --------------------------------------------------------------
# say    = macOS built-in (zero install, robotic).
# kokoro = local neural voice (run ./setup-kokoro.sh first; 100% offline).
# VOICE_TTS=kokoro
# VOICE_KOKORO_VOICE=af_heart   # af_sarah, am_adam, am_michael, bf_emma, bm_george, ...
# VOICE_KOKORO_SPEED=1.0        # or: voice speed 1.2
# VOICE_AUTO_SPEAK=true         # false = never auto-speaks; press a key to hear (voice autospeak off)
# VOICE_PANE_VOICES=true        # give each pane its own Kokoro voice, to tell concurrent sessions apart
# VOICE_PANE_VOICE_POOL="af_heart af_sarah am_adam am_michael bf_emma bm_george"   # cycled by pane

# --- Audio backend (auto-detected from PATH; set to force or on Windows) -------
# speak: say (macOS) / spd-say / espeak-ng / espeak; play: afplay / paplay / aplay / ...
# VOICE_SPEAK_CMD="espeak-ng -s 160"
# VOICE_PLAY_CMD="paplay"
# Windows (Git Bash): point these at PowerShell one-liners.

# --- macOS `say` voice (only used when VOICE_SPEAK_CMD is `say`) ---------------
# For a better native voice, download a Premium/Enhanced one:
#   System Settings ▸ Accessibility ▸ Spoken Content ▸ System Voice ▸ Manage Voices…
# then name it exactly as `say -v '?'` prints it:
# VOICE_SAY_VOICE="Ava (Premium)"
# VOICE_SAY_RATE=185

# --- Cue sounds (path to any .aiff/.wav, or "" to silence one) ----------------
# VOICE_SOUND_READY="/System/Library/Sounds/Glass.aiff"
# VOICE_SOUND_INPUT="/System/Library/Sounds/Ping.aiff"
# VOICE_SOUND_ERROR="/System/Library/Sounds/Basso.aiff"
# VOICE_SOUND_WAIT="/System/Library/Sounds/Submarine.aiff"
