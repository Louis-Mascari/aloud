# Wiring claude-voice into an existing `wezterm.lua`

The WezTerm layer is optional (the hooks + `say` work without it). It adds:
per-tab **state glyphs**, an aggregate **"needs you" badge**, auto-speak on
return, and the recap/jump keys. `VOICE_BIN` is the absolute path to `bin/voice`.

Fresh config with no `format-tab-title` / `update-status` of your own? Copy
`wezterm/voice.lua` and `require` it instead of hand-merging.

### 1. Near the top, after `config`

```lua
local VOICE_BIN = wezterm.home_dir .. '/Desktop/personal/claude-voice/bin/voice'
local VOICE_STATE_DIR = wezterm.home_dir .. '/.claude/voice/state'
local VOICE_GLYPH = {  -- a tab lights up only when done or needing you; working stays plain
  ready = { g = '✓', c = '#76946a' }, -- green: done
  input = { g = '⏸', c = '#e6c384' }, -- amber: blocked on you
  error = { g = '✗', c = '#c34043' }, -- red: failed
}
local function voice_state(pane_id)
  local f = io.open(VOICE_STATE_DIR .. '/' .. tostring(pane_id), 'r')
  if not f then return nil end
  local s = f:read 'l'; f:close(); return s
end
local function voice_badge_cells()
  local n = { error = 0, input = 0, ready = 0 }
  local ok, entries = pcall(wezterm.read_dir, VOICE_STATE_DIR)
  if ok and entries then
    for _, p in ipairs(entries) do
      local f = io.open(p, 'r')
      if f then local s = f:read 'l'; f:close(); if n[s] ~= nil then n[s] = n[s] + 1 end end
    end
  end
  local cells = {}
  local function add(st)
    if n[st] > 0 then
      table.insert(cells, { Foreground = { Color = VOICE_GLYPH[st].c } })
      table.insert(cells, { Text = ' ' .. VOICE_GLYPH[st].g .. n[st] })
    end
  end
  add 'error'; add 'input'   -- only what needs an action; "done" shows per-tab, not in the count
  return cells
end
```

### 2. Inside your `format-tab-title`, a colored glyph on inactive tabs

```lua
local vg = tab.is_active and nil or VOICE_GLYPH[voice_state(tab.active_pane.pane_id) or '']
-- then, when building your returned cells, prepend when vg is set:
--   { Foreground = { Color = vg.c } }, { Text = ' ' .. vg.g },
```

### 3. Inside your `update-status`: badge + speak-on-return

```lua
local vb = voice_badge_cells()
window:set_left_status(#vb > 0 and wezterm.format(vb) or '')
if window:is_focused() then
  local pid = pane:pane_id()
  local trigger = voice_state(pid) == 'ready'   -- landed on a done tab: mark it seen
  if not trigger then
    local qf = io.open(wezterm.home_dir .. '/.claude/voice/queue/' .. tostring(pid), 'r')
    if qf then local sz = qf:seek 'end'; qf:close(); if sz and sz > 0 then trigger = true end end
  end
  if trigger then wezterm.background_child_process { VOICE_BIN, 'refocus', tostring(pid) } end
end
```

### 4. Keybinds

```lua
for _, b in ipairs {
  { 'v', 'CMD|SHIFT', 'drain', true },   -- speak this pane's queued summary
  { 'r', 'CMD|SHIFT', 'recap', true },   -- say what this tab is doing
  { 'j', 'CMD|SHIFT', 'jump', false },   -- jump to the most urgent pane + recap
  { '.', 'CMD', 'stop', false },         -- interrupt speech (barge-in)
  { 'v', 'CMD|CTRL', 'toggle', false },  -- auto <-> wait
} do
  local key, mods, sub, wp = b[1], b[2], b[3], b[4]
  table.insert(config.keys, { key = key, mods = mods,
    action = wezterm.action_callback(function(_win, pane)
      if wp then wezterm.background_child_process { VOICE_BIN, sub, tostring(pane:pane_id()) }
      else wezterm.background_child_process { VOICE_BIN, sub } end
    end) })
end
```

Validate with: `wezterm --config-file ~/.wezterm.lua ls-fonts >/dev/null && echo ok`
