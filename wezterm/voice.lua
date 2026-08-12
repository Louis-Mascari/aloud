-- voice.lua — drop-in WezTerm layer for claude-voice, for configs that don't
-- already define format-tab-title / update-status. If you DO have those, don't
-- require this; hand-merge the snippets in INTEGRATE.md instead (only one
-- format-tab-title handler can win).
--
--   local voice = require 'voice'   -- with this repo's wezterm/ on your lua path
--   voice.apply(config)             -- pass your config table
--
-- Or set VOICE_BIN to an explicit path: voice.apply(config, '/path/to/bin/voice')

local wezterm = require 'wezterm'
local M = {}

local function state_of(pane_id)
  local f = io.open(wezterm.home_dir .. '/.claude/voice/state/' .. tostring(pane_id), 'r')
  if not f then return nil end
  local s = f:read 'l'; f:close(); return s
end

function M.apply(config, voice_bin)
  local VOICE_BIN = voice_bin or (wezterm.home_dir .. '/Desktop/personal/claude-voice/bin/voice')

  wezterm.on('format-tab-title', function(tab)
    local glyph = ''
    if not tab.is_active then
      local s = state_of(tab.active_pane.pane_id)
      if s == 'working' then glyph = '◍ '
      elseif s == 'ready' then glyph = '🔔 '
      elseif s == 'input' then glyph = '⏳ ' end
    end
    return ' ' .. glyph .. (tab.tab_index + 1) .. '· ' .. tab.active_pane.title .. ' '
  end)

  wezterm.on('update-status', function(window, pane)
    if not window:is_focused() then return end
    local qf = io.open(wezterm.home_dir .. '/.claude/voice/queue/' .. tostring(pane:pane_id()), 'r')
    if qf then
      local sz = qf:seek 'end'; qf:close()
      if sz and sz > 0 then
        wezterm.background_child_process { VOICE_BIN, 'refocus', tostring(pane:pane_id()) }
      end
    end
  end)

  config.keys = config.keys or {}
  table.insert(config.keys, { key = 'v', mods = 'CMD|SHIFT',
    action = wezterm.action_callback(function(_win, pane)
      wezterm.background_child_process { VOICE_BIN, 'drain', tostring(pane:pane_id()) }
    end) })
  table.insert(config.keys, { key = 'v', mods = 'CMD|CTRL',
    action = wezterm.action_callback(function()
      wezterm.background_child_process { VOICE_BIN, 'toggle' }
    end) })
end

return M
