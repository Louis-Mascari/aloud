# Binding `voice stop` (interrupt / barge-in)

`voice stop` cuts off whatever's speaking. It's a plain command, so bind it however
your setup allows. Two automatic interrupts already work with no binding:
- **Stop-on-send** — submitting a prompt stops speech (a Claude Code hook; every terminal, every OS).
- **On switch** — moving to another pane stops the one you left (WezTerm).

Replace `~/claude-voice/bin/voice` in each snippet below with the path to this repo's `bin/voice`.

## OS-global hotkey (fires no matter what's focused — most portable)

**macOS — [skhd](https://github.com/koekeishiya/skhd)** (`brew install skhd && skhd --start-service`; grant Accessibility). `~/.config/skhd/skhdrc`:
```
cmd + alt - period : ~/claude-voice/bin/voice stop
```
Already run Hammerspoon? `~/.hammerspoon/init.lua`:
```lua
hs.hotkey.bind({"cmd","alt"}, ".", function() hs.execute("~/claude-voice/bin/voice stop") end)
```

**Linux — bind in your compositor/DE (Wayland-safe, no root):**
- sway/Hyprland: `bindsym Ctrl+Shift+s exec ~/claude-voice/bin/voice stop`
- GNOME/KDE: Settings → Keyboard → Custom Shortcut → command `~/…/bin/voice stop`.
- X11 only: sxhkd `super + shift + s` on one line, TAB-indented `~/…/bin/voice stop` on the next.

**Windows — [AutoHotkey v2](https://www.autohotkey.com/)** (`voicestop.ahk` in shell:startup):
```autohotkey
#Requires AutoHotkey v2.0
^!.::Run('"C:\path\voice.exe" stop', , "Hide")
```

## Per-terminal keybinding

**WezTerm** — already wired (`CMD+.`).
**tmux** (`~/.tmux.conf`):
```
bind-key -n F13 run-shell "~/claude-voice/bin/voice stop &"
```
**kitty** (`kitty.conf`):
```
map f13 launch --type=background ~/claude-voice/bin/voice stop
```
**Alacritty** (`alacritty.toml`):
```toml
[keyboard]
bindings = [ { key = "F13", command = { program = "sh", args = ["-c", "~/…/bin/voice stop"] } } ]
```
**iTerm2** — Settings → Keys → `+` → action "Run Coprocess" → `~/…/bin/voice stop`.

## Why not auto-stop the instant dictation starts

No terminal or Claude Code emits a portable "recording started" event, so there's
nothing reliable to hook. Stop-on-send + a global hotkey covers it on every setup
without a per-tool hack.
