local config = require('smart-splits-backend-herdr.config')
local herdr = require('smart-splits-backend-herdr.herdr')
local layout = require('smart-splits-backend-herdr.layout')

local M = {}

---Resize the current herdr pane. Core calls this only when the Neovim window
---already fills that axis, and never falls back to a Neovim resize afterwards,
---so the return value is reported but changes nothing.
---@param direction SmartSplitsDirection
---@param opts? SmartSplitsBackendResizeOpts
---@return boolean
function M.resize(direction, opts)
  opts = opts or {}
  if not config.options.enable or not herdr.in_session() or not herdr.DIRECTIONS[direction] then
    return false
  end
  local pane = herdr.pane_id() --[[@as string]]

  -- `opts.amount` is cells, already multiplied by `v:count1`; herdr wants a
  -- fraction of the split, so the layout is needed to translate it
  local cells = tonumber(opts.amount) or config.options.resize_amount
  local edges = herdr.edges(pane)
  if not edges then
    return false
  end
  local amount = layout.resize_fraction(edges.layout, pane, direction, cells)
  if not amount then
    return false
  end

  local result = herdr.resize(pane, direction, amount)
  return result ~= nil and result.changed == true
end

return M
