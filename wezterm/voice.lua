-- voice.lua — drop-in WezTerm layer for claude-voice, for configs that don't
-- already define format-tab-title / update-status. If you DO have those, don't
-- require this; hand-merge the snippets in INTEGRATE.md (only one
-- format-tab-title handler can win).
--
--   local voice = require 'voice'   -- with this repo's wezterm/ on your lua path
--   voice.apply(config)             -- optionally: voice.apply(config, '/path/to/bin/voice')

local wezterm = require 'wezterm'
local M = {}

local STATE_DIR = wezterm.home_dir .. '/.claude/voice/state'
-- A tab lights up only when it needs you or is done; "working" stays plain.
local GLYPH = {
  ready = { g = '✓', c = '#76946a' }, -- green: done, review/next
  input = { g = '⏸', c = '#e6c384' }, -- amber: blocked on you
  error = { g = '✗', c = '#c34043' }, -- red: failed
}
local LAST_FOCUSED = {}  -- window_id -> last focused pane_id, to detect switches

local function state_of(pane_id)
  local f = io.open(STATE_DIR .. '/' .. tostring(pane_id), 'r')
  if not f then return nil end
  local s = f:read 'l'; f:close(); return s
end

-- Live pane ids across all windows (nil if the mux call fails).
local function live_panes()
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

-- Count panes needing an action (error, input) on live panes; prune orphans.
local function badge_cells()
  local n = { error = 0, input = 0 }
  local live = live_panes()
  local ok, entries = pcall(wezterm.read_dir, STATE_DIR)
  if ok and entries then
    for _, path in ipairs(entries) do
      local id = path:match '([^/]+)$'
      if id and id:match '^%d+$' then
        if live and not live[id] then
          os.remove(path)
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
      table.insert(cells, { Foreground = { Color = GLYPH[st].c } })
      table.insert(cells, { Text = ' ' .. GLYPH[st].g .. n[st] })
    end
  end
  add 'error'; add 'input'
  return cells
end

function M.apply(config, voice_bin)
  local BIN = voice_bin or (wezterm.home_dir .. '/Desktop/personal/claude-voice/bin/voice')

  wezterm.on('format-tab-title', function(tab)
    local vg = tab.is_active and nil or GLYPH[state_of(tab.active_pane.pane_id) or '']
    local label = ' ' .. (tab.tab_index + 1) .. '· ' .. (tab.active_pane.title or '') .. ' '
    if vg then
      return {
        { Foreground = { Color = vg.c } }, { Text = ' ' .. vg.g },
        { Foreground = 'Default' }, { Text = label },
      }
    end
    return label
  end)

  wezterm.on('update-status', function(window, pane)
    local b = badge_cells()
    window:set_left_status(#b > 0 and wezterm.format(b) or '')
    if window:is_focused() then
      local wid = window:window_id()
      local pid = pane:pane_id()
      if LAST_FOCUSED[wid] ~= pid then
        LAST_FOCUSED[wid] = pid
        wezterm.background_child_process { BIN, 'switched', tostring(pid) }   -- stop old pane, speak this one
      else
        local trigger = state_of(pid) == 'ready'
        if not trigger then
          local qf = io.open(wezterm.home_dir .. '/.claude/voice/queue/' .. tostring(pid), 'r')
          if qf then local sz = qf:seek 'end'; qf:close(); if sz and sz > 0 then trigger = true end end
        end
        if trigger then wezterm.background_child_process { BIN, 'refocus', tostring(pid) } end
      end
    end
  end)

  config.keys = config.keys or {}
  local function bind(key, mods, sub, with_pane)
    table.insert(config.keys, { key = key, mods = mods,
      action = wezterm.action_callback(function(_win, pane)
        if with_pane then
          wezterm.background_child_process { BIN, sub, tostring(pane:pane_id()) }
        else
          wezterm.background_child_process { BIN, sub }
        end
      end) })
  end
  bind('v', 'CMD|SHIFT', 'drain', true)   -- play a background tab's pending summary
  bind('r', 'CMD|SHIFT', 'recap', true)   -- replay the last summary from the start
  bind('j', 'CMD|SHIFT', 'jump', false)   -- jump to the most urgent pane + read it
  bind('.', 'CMD', 'stop', false)         -- interrupt speech (barge-in)
  bind('v', 'CMD|CTRL', 'toggle', false)  -- wait mode on/off
  table.insert(config.keys, { key = '/', mods = 'CMD|SHIFT',
    action = wezterm.action_callback(function(window)
      window:toast_notification('claude-voice',
        'V drain · R replay · J jump · ⌘. stop · ⌃⌘V mode\nCLI: voice help', nil, 8000)
    end) })
end

return M
