# Wiring claude-voice into an existing `wezterm.lua`

The WezTerm layer is optional (the hooks + `say` work without it). It adds: the
tab glyph for background panes, and auto-speak when you switch back to a pane
that finished while you were away. Four small edits. `VOICE_BIN` is the absolute
path to `bin/voice` in this repo.

Fresh config with no `format-tab-title` / `update-status` of your own? Copy
`wezterm/voice.lua` and `require` it instead of hand-merging.

### 1. Near the top, after `config`

```lua
local VOICE_BIN = wezterm.home_dir .. '/Desktop/personal/claude-voice/bin/voice'
```

### 2. Inside your `format-tab-title`, before you build the title string

Shows ◍ working / 🔔 ready / ⏳ input on **inactive** tabs only (the active tab
you can already see). Reads a state file, so no tty is needed.

```lua
local vstate = ''
if not tab.is_active then
  local sf = io.open(wezterm.home_dir .. '/.claude/voice/state/' .. tostring(tab.active_pane.pane_id), 'r')
  if sf then
    local s = sf:read 'l'; sf:close()
    if s == 'working' then vstate = '◍ '
    elseif s == 'ready' then vstate = '🔔 '
    elseif s == 'input' then vstate = '⏳ ' end
  end
end
```

Then insert `vstate` into your title (e.g. before the program name).

### 3. Inside your `update-status` handler (or add one)

Speaks a pane's queued summary when it regains focus. Only spawns when the
queue actually has bytes, so the ~1/second tick stays cheap.

```lua
if window:is_focused() then
  local qf = io.open(wezterm.home_dir .. '/.claude/voice/queue/' .. tostring(pane:pane_id()), 'r')
  if qf then
    local sz = qf:seek 'end'; qf:close()
    if sz and sz > 0 then
      wezterm.background_child_process { VOICE_BIN, 'refocus', tostring(pane:pane_id()) }
    end
  end
end
```

### 4. Keybinds

```lua
table.insert(config.keys, { key = 'v', mods = 'CMD|SHIFT',
  action = wezterm.action_callback(function(_win, pane)
    wezterm.background_child_process { VOICE_BIN, 'drain', tostring(pane:pane_id()) }
  end) })
table.insert(config.keys, { key = 'v', mods = 'CMD|CTRL',
  action = wezterm.action_callback(function()
    wezterm.background_child_process { VOICE_BIN, 'toggle' }
  end) })
```

Validate with: `wezterm --config-file ~/.wezterm.lua ls-fonts >/dev/null && echo ok`
