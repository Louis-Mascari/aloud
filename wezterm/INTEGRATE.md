# Wiring claude-voice into an existing `wezterm.lua`

The WezTerm layer is optional (the hooks + `say` work without it). It adds:
per-tab **state glyphs**, an aggregate **"needs you" badge**, auto-speak on
return, and the recap/jump keys. `VOICE_BIN` is the absolute path to `bin/voice`.

Fresh config with no `format-tab-title` / `update-status` of your own? Copy
`wezterm/voice.lua` and `require` it instead of hand-merging.

### 1. Near the top, after `config`

```lua
local VOICE_BIN = wezterm.home_dir .. '/claude-voice/bin/voice'
local VOICE_STATE_DIR = wezterm.home_dir .. '/.claude/voice/state'
local VOICE_GLYPH = {  -- lights up only when done or needing you; colors are one theme's green/amber/red, swap for your own
  ready = { g = '✓', c = '#76946a' }, -- green: done
  input = { g = '⏸', c = '#e6c384' }, -- amber: blocked on you
  error = { g = '✗', c = '#c34043' }, -- red: failed
}
local function voice_state(pane_id)
  local f = io.open(VOICE_STATE_DIR .. '/' .. tostring(pane_id), 'r')
  if not f then return nil end
  local s = f:read 'l'; f:close(); return s
end
-- Most urgent state across ALL panes in a tab, not just its active pane, so a
-- Claude pane split behind an idle shell still lights the tab. error > input > ready.
-- Enumerated via the mux (matched by tab_id), which is reliable across versions.
local VOICE_TAB_PRIORITY = { 'error', 'input', 'ready' }
local function voice_tab_state(tab)
  local seen = {}
  local ok = pcall(function()
    for _, w in ipairs(wezterm.mux.all_windows()) do
      for _, t in ipairs(w:tabs()) do
        if t:tab_id() == tab.tab_id then
          for _, p in ipairs(t:panes()) do
            local s = voice_state(p:pane_id())
            if s then seen[s] = true end
          end
        end
      end
    end
  end)
  if not ok then                                    -- mux unavailable: at least the active pane
    local s = voice_state(tab.active_pane.pane_id)
    if s then seen[s] = true end
  end
  for _, s in ipairs(VOICE_TAB_PRIORITY) do
    if seen[s] then return s end
  end
  return nil
end
local VOICE_LAST_FOCUSED = {}  -- window_id -> last focused pane_id, to detect switches
local function voice_live_panes()
  local live = {}
  local ok = pcall(function()
    for _, w in ipairs(wezterm.mux.all_windows()) do
      for _, t in ipairs(w:tabs()) do
        for _, p in ipairs(t:panes()) do live[tostring(p:pane_id())] = true end
      end
    end
  end)
  return ok and live or nil
end
local function voice_badge_cells()  -- counts action states on live panes; prunes orphans
  local n = { error = 0, input = 0 }
  local live = voice_live_panes()
  local ok, entries = pcall(wezterm.read_dir, VOICE_STATE_DIR)
  if ok and entries then
    for _, path in ipairs(entries) do
      local id = path:match '([^/]+)$'
      if id and id:match '^%d+$' then
        if live and not live[id] then os.remove(path)
        else
          local f = io.open(path, 'r')
          if f then local s = f:read 'l'; f:close(); if n[s] ~= nil then n[s] = n[s] + 1 end end
        end
      end
    end
  end
  local cells = {}
  local function add(st)
    if n[st] > 0 then
      table.insert(cells, { Foreground = { Color = VOICE_GLYPH[st].c } })
      table.insert(cells, { Text = ' ' .. VOICE_GLYPH[st].g .. n[st] })
    end
  end
  add 'error'; add 'input'
  return cells
end
```

### 2. Inside your `format-tab-title`, a colored glyph on inactive tabs

```lua
local vg = tab.is_active and nil or VOICE_GLYPH[voice_tab_state(tab) or '']
-- then, when building your returned cells, prepend when vg is set:
--   { Foreground = { Color = vg.c } }, { Text = ' ' .. vg.g },
```

### 3. Inside your `update-status`: badge + speak-on-return

```lua
local vb = voice_badge_cells()
window:set_left_status(#vb > 0 and wezterm.format(vb) or '')
if window:is_focused() then
  local wid = window:window_id()
  local pid = pane:pane_id()
  if VOICE_LAST_FOCUSED[wid] ~= pid then          -- switched panes: stop the one you left, speak this one
    VOICE_LAST_FOCUSED[wid] = pid
    wezterm.background_child_process { VOICE_BIN, 'switched', tostring(pid) }
  else
    local trigger = voice_state(pid) == 'ready'   -- done tab you're already on: mark it seen
    if not trigger then
      local qf = io.open(wezterm.home_dir .. '/.claude/voice/queue/' .. tostring(pid), 'r')
      if qf then local sz = qf:seek 'end'; qf:close(); if sz and sz > 0 then trigger = true end end
    end
    if trigger then wezterm.background_child_process { VOICE_BIN, 'refocus', tostring(pid) } end
  end
end
```

### 4. Keybinds

```lua
for _, b in ipairs {
  { 'v', 'CMD|SHIFT', 'drain', true },   -- play a background tab's pending summary
  { 'r', 'CMD|SHIFT', 'recap', true },   -- replay the last summary from the start
  { 'j', 'CMD|SHIFT', 'jump', false },   -- jump to the most urgent pane + read it
  { '.', 'CMD', 'stop', false },         -- interrupt speech (barge-in)
  { 'm', 'CMD|CTRL', 'toggle', false },  -- wait mode on/off
} do
  local key, mods, sub, wp = b[1], b[2], b[3], b[4]
  table.insert(config.keys, { key = key, mods = mods,
    action = wezterm.action_callback(function(_win, pane)
      if wp then wezterm.background_child_process { VOICE_BIN, sub, tostring(pane:pane_id()) }
      else wezterm.background_child_process { VOICE_BIN, sub } end
    end) })
end
-- CMD+SHIFT+/ shows a quick reference (full list: `voice help`)
table.insert(config.keys, { key = '/', mods = 'CMD|SHIFT',
  action = wezterm.action_callback(function(window)
    window:toast_notification('claude-voice', 'V drain · R replay · J jump · ⌘. stop · ⌃⌘M mode\nCLI: voice help', nil, 8000)
  end) })
```

Validate with: `wezterm ls-fonts >/dev/null && echo ok` (WezTerm loads your active
config automatically, wherever it lives).
