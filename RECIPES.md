# Binding `voice stop` (interrupt / barge-in)

`voice stop` cuts off whatever's speaking. It's a plain command, so bind it however
your setup allows. Two automatic interrupts already work with no binding:
- **Stop-on-send** — submitting a prompt stops speech (a Claude Code hook; every terminal, every OS).
- **On switch** — moving to another pane stops the one you left (WezTerm).

Replace `~/aloud/bin/voice` in each snippet below with the path to this repo's `bin/voice`.

## OS-global hotkey (fires no matter what's focused — most portable)

**macOS — [skhd](https://github.com/koekeishiya/skhd)** (`brew install koekeishiya/formulae/skhd && skhd --start-service`; grant skhd Accessibility, then `skhd --restart-service`). `~/.config/skhd/skhdrc`:
```
cmd + alt - period : ~/aloud/bin/voice stop
```
Already run Hammerspoon? `~/.hammerspoon/init.lua`:
```lua
hs.hotkey.bind({"cmd","alt"}, ".", function() hs.execute("~/aloud/bin/voice stop") end)
```

Point the same binding at **`voice toggle`** instead (e.g. `cmd + alt - m`) for a
global **mute** switch — silence everything from any app right before a meeting.

**Linux — bind in your compositor/DE (Wayland-safe, no root):**
- sway/Hyprland: `bindsym Ctrl+Shift+s exec ~/aloud/bin/voice stop`
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
bind-key -n F13 run-shell "~/aloud/bin/voice stop &"
```
**kitty** (`kitty.conf`):
```
map f13 launch --type=background ~/aloud/bin/voice stop
```
**Alacritty** (`alacritty.toml`):
```toml
[keyboard]
bindings = [ { key = "F13", command = { program = "sh", args = ["-c", "~/…/bin/voice stop"] } } ]
```
**iTerm2** — Settings → Keys → `+` → action "Run Coprocess" → `~/…/bin/voice stop`.

# Global keys for the PDF reader (`pdf-ctl`)

`pdf-read` opens a clickable control bar, but to drive playback while your PDF
viewer (or any app) is focused, bind `pdf-ctl` to OS-global hotkeys. Same tools as
above. macOS **skhd** (`~/.config/skhd/skhdrc`):
```
cmd + alt - space  : ~/aloud/bin/pdf-ctl toggle   # play/pause
cmd + alt - right  : ~/aloud/bin/pdf-ctl next     # skip junk forward
cmd + alt - left   : ~/aloud/bin/pdf-ctl prev
cmd + alt - 0      : ~/aloud/bin/pdf-ctl stop
```
One stop for everything (summaries + reader): point your global stop key at a line
that runs both `voice stop` and `pdf-ctl stop`.

## Why not auto-stop the instant dictation starts

No terminal or Claude Code emits a portable "recording started" event, so there's
nothing reliable to hook. Stop-on-send + a global hotkey covers it on every setup
without a per-tool hack.
