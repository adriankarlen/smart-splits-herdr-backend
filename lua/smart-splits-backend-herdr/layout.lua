---Pure functions over herdr's layout snapshot. No requests are made here, which
---keeps the geometry testable on its own.

local M = {}

---@param direction HerdrBackend.Direction
---@return boolean
local function is_horizontal(direction)
  return direction == 'left' or direction == 'right'
end

---@param layout HerdrBackend.Layout|nil
---@param pane_id string
---@return HerdrBackend.Rect|nil
function M.pane_rect(layout, pane_id)
  if type(layout) ~= 'table' or type(layout.panes) ~= 'table' then
    return nil
  end
  for _, pane in ipairs(layout.panes) do
    if pane.pane_id == pane_id and type(pane.rect) == 'table' then
      return pane.rect
    end
  end
  return nil
end

---Length of the overlap between `[a1, a2)` and `[b1, b2)`.
---@return number
local function overlap(a1, a2, b1, b2)
  return math.max(0, math.min(a2, b2) - math.max(a1, b1))
end

---The pane to wrap to when `pane_id` has nothing in `direction`: the one on the
---opposite outer edge of the tab that shares the most of this pane's row (or
---column), ties going to the one whose centre is nearest. A pane that shares
---none of it is no wrap target: the pane already spans that axis on its own.
---@param layout HerdrBackend.Layout|nil
---@param pane_id string
---@param direction HerdrBackend.Direction
---@return string|nil
function M.wrap_target(layout, pane_id, direction)
  local current = M.pane_rect(layout, pane_id)
  if not layout or not current or type(layout.area) ~= 'table' then
    return nil
  end
  local area = layout.area
  local horizontal = is_horizontal(direction)

  ---@param rect HerdrBackend.Rect
  ---@return boolean
  local function on_far_edge(rect)
    if direction == 'right' then
      return rect.x == area.x
    elseif direction == 'left' then
      return rect.x + rect.width == area.x + area.width
    elseif direction == 'down' then
      return rect.y == area.y
    end
    return rect.y + rect.height == area.y + area.height
  end

  local c1 = horizontal and current.y or current.x
  local c2 = c1 + (horizontal and current.height or current.width)
  local centre = (c1 + c2) / 2

  ---@type string|nil, number, number
  local best, best_overlap, best_distance = nil, 0, math.huge
  for _, pane in ipairs(layout.panes) do
    local rect = pane.rect
    if pane.pane_id ~= pane_id and type(rect) == 'table' and on_far_edge(rect) then
      local p1 = horizontal and rect.y or rect.x
      local p2 = p1 + (horizontal and rect.height or rect.width)
      local shared = overlap(c1, c2, p1, p2)
      local distance = math.abs((p1 + p2) / 2 - centre)
      if shared > 0 and (shared > best_overlap or (shared == best_overlap and distance < best_distance)) then
        best, best_overlap, best_distance = pane.pane_id, shared, distance
      end
    end
  end
  return best
end

---Where a split's divider sits, in cells along its axis.
---@param split HerdrBackend.LayoutSplit
---@return number
local function divider(split)
  if split.direction == 'right' then
    return split.rect.x + split.rect.width * split.ratio
  end
  return split.rect.y + split.rect.height * split.ratio
end

---@param split HerdrBackend.LayoutSplit
---@param rect HerdrBackend.Rect
---@return boolean
local function contains(split, rect)
  local s = split.rect
  return rect.x >= s.x
    and rect.y >= s.y
    and rect.x + rect.width <= s.x + s.width
    and rect.y + rect.height <= s.y + s.height
end

---Translate a resize of `cells` into the fraction `pane.resize` expects.
---
---herdr moves one of the pane's borders towards `direction`: the border on that
---side when there is one, otherwise the opposite border. The amount is a change
---to that split's ratio, so the same number of cells is a bigger fraction of a
---small split than of a large one. Falls back to the tab's size when the split
---cannot be found.
---@param layout HerdrBackend.Layout|nil
---@param pane_id string
---@param direction HerdrBackend.Direction
---@param cells number
---@return number|nil
function M.resize_fraction(layout, pane_id, direction, cells)
  if type(cells) ~= 'number' or cells <= 0 then
    return nil
  end
  local rect = M.pane_rect(layout, pane_id)
  if not layout or not rect then
    return nil
  end

  local horizontal = is_horizontal(direction)
  local axis = horizontal and 'right' or 'down'
  local near, far
  if horizontal then
    near, far = rect.x, rect.x + rect.width
  else
    near, far = rect.y, rect.y + rect.height
  end
  -- the border herdr prefers, then the one it falls back to
  local preferred, fallback = far, near
  if direction == 'left' or direction == 'up' then
    preferred, fallback = near, far
  end

  ---@param border number
  ---@return HerdrBackend.LayoutSplit|nil
  local function split_at(border)
    local found, found_distance = nil, math.huge
    for _, split in ipairs(layout.splits or {}) do
      if split.direction == axis and type(split.rect) == 'table' and contains(split, rect) then
        local distance = math.abs(divider(split) - border)
        if distance <= 1.5 and distance < found_distance then
          found, found_distance = split, distance
        end
      end
    end
    return found
  end

  local split = split_at(preferred) or split_at(fallback)
  local size
  if split then
    size = horizontal and split.rect.width or split.rect.height
  elseif type(layout.area) == 'table' then
    size = horizontal and layout.area.width or layout.area.height
  end
  if type(size) ~= 'number' or size <= 0 then
    return nil
  end
  return math.min(1, cells / size)
end

return M
