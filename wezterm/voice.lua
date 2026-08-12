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

local function state_of(pane_id)
  local f = io.open(STATE_DIR .. '/' .. tostring(pane_id), 'r')
  if not f then return nil end
  local s = f:read 'l'; f:close(); return s
end

-- Aggregate of panes needing an action (error, input) — not "done".
local function badge_cells()
  local n = { error = 0, input = 0 }
  local ok, entries = pcall(wezterm.read_dir, STATE_DIR)
  if ok and entries then
    for _, p in ipairs(entries) do
      local f = io.open(p, 'r')
      if f then local s = f:read 'l'; f:close(); if n[s] ~= nil then n[s] = n[s] + 1 end end
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
      local pid = pane:pane_id()
      local trigger = state_of(pid) == 'ready'   -- landed on a done tab: mark it seen
      if not trigger then
        local qf = io.open(wezterm.home_dir .. '/.claude/voice/queue/' .. tostring(pid), 'r')
        if qf then local sz = qf:seek 'end'; qf:close(); if sz and sz > 0 then trigger = true end end
      end
      if trigger then wezterm.background_child_process { BIN, 'refocus', tostring(pid) } end
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
  bind('v', 'CMD|SHIFT', 'drain', true)   -- speak this pane's queued summary
  bind('r', 'CMD|SHIFT', 'recap', true)   -- say what this tab is doing
  bind('j', 'CMD|SHIFT', 'jump', false)   -- jump to the most urgent pane + recap
  bind('.', 'CMD', 'stop', false)         -- interrupt speech (barge-in)
  bind('v', 'CMD|CTRL', 'toggle', false)  -- auto <-> wait
end

return M
