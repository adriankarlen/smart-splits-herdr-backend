---Typed wrappers around the herdr requests this backend makes. Each one names
---its socket method and, where herdr has one, the CLI equivalent.
---
---Every request targets this Neovim's own pane, `$HERDR_PANE_ID`, rather than
---whichever pane herdr has focused: the two only differ in edge cases, and in
---those Neovim's pane is the one the user meant.

local transport = require('smart-splits-backend-herdr.transport')

local M = {}

---@alias HerdrBackend.Direction 'left'|'right'|'up'|'down'

---@class HerdrBackend.Rect
---@field x integer
---@field y integer
---@field width integer
---@field height integer

---@class HerdrBackend.LayoutPane
---@field pane_id string
---@field focused boolean
---@field rect HerdrBackend.Rect

---@class HerdrBackend.LayoutSplit
---@field id string
---@field direction 'right'|'down'
---@field ratio number
---@field rect HerdrBackend.Rect

---@class HerdrBackend.Layout
---@field workspace_id string
---@field tab_id string
---@field zoomed boolean
---@field area HerdrBackend.Rect
---@field focused_pane_id string
---@field panes HerdrBackend.LayoutPane[]
---@field splits HerdrBackend.LayoutSplit[]

---@class HerdrBackend.Edges
---@field pane_id string
---@field left boolean
---@field right boolean
---@field up boolean
---@field down boolean
---@field layout HerdrBackend.Layout

---@class HerdrBackend.FocusResult
---@field changed boolean
---@field reason? 'no_neighbor'
---@field source_pane_id string
---@field focused_pane_id? string
---@field layout HerdrBackend.Layout

---@class HerdrBackend.ResizeResult
---@field changed boolean
---@field reason? 'unchanged'
---@field pane_id string
---@field layout HerdrBackend.Layout

---@class HerdrBackend.SwapResult
---@field changed boolean
---@field reason? string
---@field source_pane_id string
---@field target_pane_id? string

---@class HerdrBackend.Pong
---@field version? string
---@field protocol? integer

---@class HerdrBackend.Plugin
---@field plugin_id string
---@field enabled boolean
---@field plugin_root? string
---@field warnings? string[]

M.DIRECTIONS = { left = true, right = true, up = true, down = true }

---herdr only splits towards the right or down. Left and up are a split followed
---by a swap.
---@type table<HerdrBackend.Direction, 'right'|'down'>
M.SPLIT_DIRECTIONS = {
  left = 'right',
  right = 'right',
  up = 'down',
  down = 'down',
}

---@type table<HerdrBackend.Direction, HerdrBackend.Direction>
M.OPPOSITE = {
  left = 'right',
  right = 'left',
  up = 'down',
  down = 'up',
}

---The pane this Neovim runs in, as herdr exported it.
---@return string|nil
function M.pane_id()
  local pane = vim.env.HERDR_PANE_ID
  if type(pane) ~= 'string' or #pane == 0 then
    return nil
  end
  return pane
end

---herdr sets `$HERDR_ENV=1` and `$HERDR_PANE_ID` for every process it starts in
---a pane, and nothing else sets them.
---@return boolean
function M.in_session()
  local env = vim.env.HERDR_ENV
  return type(env) == 'string' and #env > 0 and env ~= '0' and M.pane_id() ~= nil
end

---@param result table|nil
---@param key string
---@return table|nil
local function field(result, key)
  if type(result) ~= 'table' or type(result[key]) ~= 'table' then
    return nil
  end
  return result[key]
end

---@return HerdrBackend.Pong|nil, string|nil
function M.ping()
  local result, err = transport.request('ping', {}, nil)
  return result, err
end

---Which edges of its tab the pane sits against, plus the layout snapshot.
---@param pane string
---@return HerdrBackend.Edges|nil, string|nil
function M.edges(pane)
  local result, err = transport.request('pane.edges', { pane_id = pane }, { 'pane', 'edges', '--pane', pane })
  return field(result, 'edges'), err
end

---Move focus one pane in `direction`, starting from `pane`. herdr never wraps:
---at an edge it answers `changed = false, reason = 'no_neighbor'`.
---@param pane string
---@param direction HerdrBackend.Direction
---@return HerdrBackend.FocusResult|nil, string|nil
function M.focus_direction(pane, direction)
  local result, err = transport.request(
    'pane.focus_direction',
    { pane_id = pane, direction = direction },
    { 'pane', 'focus', '--direction', direction, '--pane', pane }
  )
  return field(result, 'focus'), err
end

---Focus a pane by id. The CLI has no equivalent, so this fails when the socket
---cannot be reached.
---@param pane string
---@return boolean
function M.focus(pane)
  local result = transport.request('pane.focus', { pane_id = pane }, nil)
  return field(result, 'pane') ~= nil
end

---Split `pane` towards `direction` ('right' or 'down') and focus the new pane.
---@param pane string
---@param direction 'right'|'down'
---@return string|nil new_pane_id, string|nil err
function M.split(pane, direction)
  local result, err = transport.request(
    'pane.split',
    { target_pane_id = pane, direction = direction, focus = true },
    { 'pane', 'split', '--pane', pane, '--direction', direction, '--focus' }
  )
  local info = field(result, 'pane')
  if not info or type(info.pane_id) ~= 'string' then
    return nil, err or 'invalid_response'
  end
  return info.pane_id, nil
end

---Swap `pane` with its neighbour in `direction`.
---@param pane string
---@param direction HerdrBackend.Direction
---@return HerdrBackend.SwapResult|nil, string|nil
function M.swap(pane, direction)
  local result, err = transport.request(
    'pane.swap',
    { pane_id = pane, direction = direction },
    { 'pane', 'swap', '--direction', direction, '--pane', pane }
  )
  return field(result, 'swap'), err
end

---Move one of `pane`'s borders towards `direction`. `amount` is a fraction of
---the split being resized, not a number of cells.
---@param pane string
---@param direction HerdrBackend.Direction
---@param amount number
---@return HerdrBackend.ResizeResult|nil, string|nil
function M.resize(pane, direction, amount)
  local result, err = transport.request(
    'pane.resize',
    { pane_id = pane, direction = direction, amount = amount },
    { 'pane', 'resize', '--direction', direction, '--amount', tostring(amount), '--pane', pane }
  )
  return field(result, 'resize'), err
end

---Installed and linked herdr plugins.
---@return HerdrBackend.Plugin[]|nil, string|nil
function M.plugins()
  local result, err = transport.request('plugin.list', {}, nil)
  return field(result, 'plugins'), err
end

---The `herdr --version` banner. Works without a running server.
---@return string|nil
function M.version()
  local ok, result = pcall(function()
    return vim.system({ transport.bin(), '--version' }, { text = true, timeout = 2000 }):wait()
  end)
  if not ok or type(result) ~= 'table' or result.code ~= 0 then
    return nil
  end
  local out = vim.trim(result.stdout or '')
  return #out > 0 and out or nil
end

return M
