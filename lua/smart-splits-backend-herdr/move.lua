local config = require('smart-splits-backend-herdr.config')
local herdr = require('smart-splits-backend-herdr.herdr')
local layout = require('smart-splits-backend-herdr.layout')

local M = {}

---Walk to the far edge one pane at a time. Used for wrapping when the socket is
---out of reach, since the CLI cannot focus a pane by id.
---@param pane string
---@param direction HerdrBackend.Direction the direction to walk in
---@param limit integer
---@return boolean moved
local function walk(pane, direction, limit)
  local current, moved = pane, false
  for _ = 1, limit do
    local focus = herdr.focus_direction(current, direction)
    if not focus or focus.changed ~= true or type(focus.focused_pane_id) ~= 'string' then
      break
    end
    current, moved = focus.focused_pane_id, true
  end
  return moved
end

---@param pane string
---@param direction HerdrBackend.Direction
---@param snapshot HerdrBackend.Layout|nil
---@return boolean
local function wrap(pane, direction, snapshot)
  local target = layout.wrap_target(snapshot, pane, direction)
  if not target then
    -- nothing on the far side, so let core wrap among Neovim's windows
    return false
  end
  if herdr.focus(target) then
    return true
  end
  local limit = snapshot and snapshot.panes and #snapshot.panes or 0
  return walk(pane, herdr.OPPOSITE[direction], limit)
end

---@param pane string
---@param direction HerdrBackend.Direction
---@return boolean
local function split(pane, direction)
  local new_pane = herdr.split(pane, herdr.SPLIT_DIRECTIONS[direction])
  if not new_pane then
    return false
  end
  if direction == 'left' or direction == 'up' then
    -- herdr put the new pane after this one; swap it over to the side the user
    -- asked for. Even if that fails a pane was made, which is still "handled".
    herdr.swap(new_pane, direction)
  end
  return true
end

---Move focus one herdr pane. Core only calls this once the cursor is already at
---the edge of Neovim's own layout, and only applies its own `at_edge` handling
---when this returns `false`.
---@param direction SmartSplitsDirection
---@param opts? SmartSplitsBackendMoveOpts
---@return boolean
function M.move(direction, opts)
  opts = opts or {}
  if not config.options.enable or not herdr.in_session() or not herdr.DIRECTIONS[direction] then
    return false
  end
  local pane = herdr.pane_id() --[[@as string]]

  -- core has no concept of zoom, so the decision is ours
  if config.options.disable_nav_when_zoomed then
    local edges = herdr.edges(pane)
    if not edges or (type(edges.layout) == 'table' and edges.layout.zoomed == true) then
      return false
    end
  end

  -- herdr never wraps, so a single request both moves and answers "was there
  -- anything that way?"
  local focus = herdr.focus_direction(pane, direction)
  if not focus then
    return false
  end
  if focus.changed == true then
    return true
  end
  if focus.reason ~= 'no_neighbor' then
    return false
  end

  if opts.at_edge == 'wrap' then
    return wrap(pane, direction, focus.layout)
  elseif opts.at_edge == 'split' then
    return split(pane, direction)
  end
  return false
end

return M
