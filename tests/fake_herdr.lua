---A fake herdr server. It keeps a tab layout of pane rectangles, answers the
---requests the backend makes by looking at that geometry, and records every
---request it received.
---
---It plugs in at `transport.set_handler`, so it sits below the request
---envelope: what is tested is what the backend would put on the wire.

local M = {}

---@class FakeHerdr.Pane
---@field pane_id string
---@field rect HerdrBackend.Rect

---@class FakeHerdr.Opts
---@field panes? FakeHerdr.Pane[]
---@field focused? string
---@field area? HerdrBackend.Rect
---@field splits? HerdrBackend.LayoutSplit[]
---@field zoomed? boolean
---@field plugins? HerdrBackend.Plugin[]
---@field fail? string|boolean every request fails with this transport error
---@field fail_on? table<string, string> method -> herdr error code
---@field no_cli_focus? boolean behave like the CLI transport: `pane.focus` is unavailable

---@class FakeHerdr.Call
---@field method string
---@field params table
---@field cli_args string[]|nil

---@param a HerdrBackend.Rect
---@return HerdrBackend.Rect
local function copy(a)
  return { x = a.x, y = a.y, width = a.width, height = a.height }
end

local function overlap(a1, a2, b1, b2)
  return math.max(0, math.min(a2, b2) - math.max(a1, b1))
end

---@param opts? FakeHerdr.Opts
function M.new(opts)
  opts = opts or {}

  local state = {
    area = opts.area or { x = 0, y = 0, width = 120, height = 40 },
    panes = vim.deepcopy(opts.panes) or {
      { pane_id = 'w1:p1', rect = { x = 0, y = 0, width = 60, height = 40 } },
      { pane_id = 'w1:p2', rect = { x = 60, y = 0, width = 60, height = 40 } },
    },
    splits = vim.deepcopy(opts.splits),
    zoomed = opts.zoomed or false,
    plugins = vim.deepcopy(opts.plugins) or {},
    fail = opts.fail,
    fail_on = opts.fail_on or {},
    no_cli_focus = opts.no_cli_focus or false,
    ---@type FakeHerdr.Call[]
    calls = {},
    next_id = 0,
  }
  state.focused = opts.focused or state.panes[1].pane_id
  for _, pane in ipairs(state.panes) do
    local n = tonumber(pane.pane_id:match('p(%d+)$')) or 0
    state.next_id = math.max(state.next_id, n)
  end

  local function find(id)
    for index, pane in ipairs(state.panes) do
      if pane.pane_id == id then
        return pane, index
      end
    end
    return nil
  end

  ---Every split rect is the whole tab unless the test gave explicit ones.
  local function splits()
    if state.splits then
      return vim.deepcopy(state.splits)
    end
    return {}
  end

  local function layout()
    local panes = {}
    for _, pane in ipairs(state.panes) do
      table.insert(panes, { pane_id = pane.pane_id, focused = pane.pane_id == state.focused, rect = copy(pane.rect) })
    end
    return {
      workspace_id = 'w1',
      tab_id = 'w1:t1',
      zoomed = state.zoomed,
      area = copy(state.area),
      focused_pane_id = state.focused,
      panes = panes,
      splits = splits(),
    }
  end

  ---@param rect HerdrBackend.Rect
  ---@param direction HerdrBackend.Direction
  local function at_edge(rect, direction)
    local area = state.area
    if direction == 'left' then
      return rect.x == area.x
    elseif direction == 'right' then
      return rect.x + rect.width == area.x + area.width
    elseif direction == 'up' then
      return rect.y == area.y
    end
    return rect.y + rect.height == area.y + area.height
  end

  ---The adjacent pane in `direction` sharing the most of this pane's side.
  local function neighbour(id, direction)
    local pane = find(id)
    if not pane then
      return nil
    end
    local r = pane.rect
    local best, best_shared = nil, 0
    for _, other in ipairs(state.panes) do
      local o = other.rect
      local touching, shared
      if direction == 'left' then
        touching, shared = o.x + o.width == r.x, overlap(r.y, r.y + r.height, o.y, o.y + o.height)
      elseif direction == 'right' then
        touching, shared = r.x + r.width == o.x, overlap(r.y, r.y + r.height, o.y, o.y + o.height)
      elseif direction == 'up' then
        touching, shared = o.y + o.height == r.y, overlap(r.x, r.x + r.width, o.x, o.x + o.width)
      else
        touching, shared = r.y + r.height == o.y, overlap(r.x, r.x + r.width, o.x, o.x + o.width)
      end
      if other ~= pane and touching and shared > best_shared then
        best, best_shared = other, shared
      end
    end
    return best
  end

  local function err(code)
    return { id = 'fake', error = { code = code, message = code } }
  end

  local function ok(result)
    return { id = 'fake', result = result }
  end

  local handlers = {}

  function handlers.ping()
    return ok({ type = 'pong', version = '0.9.3', protocol = 22 })
  end

  function handlers.pane_edges(params)
    local pane = find(params.pane_id)
    if not pane then
      return err('pane_not_found')
    end
    return ok({
      type = 'pane_edges',
      edges = {
        pane_id = pane.pane_id,
        left = at_edge(pane.rect, 'left'),
        right = at_edge(pane.rect, 'right'),
        up = at_edge(pane.rect, 'up'),
        down = at_edge(pane.rect, 'down'),
        layout = layout(),
      },
    })
  end

  function handlers.pane_focus_direction(params)
    if not find(params.pane_id) then
      return err('pane_not_found')
    end
    local target = neighbour(params.pane_id, params.direction)
    if target then
      state.focused = target.pane_id
    end
    return ok({
      type = 'pane_focus_direction',
      focus = {
        changed = target ~= nil,
        reason = target == nil and 'no_neighbor' or nil,
        source_pane_id = params.pane_id,
        focused_pane_id = state.focused,
        layout = layout(),
      },
    })
  end

  function handlers.pane_focus(params)
    if state.no_cli_focus then
      return nil, 'no_cli_equivalent'
    end
    local pane = find(params.pane_id)
    if not pane then
      return err('pane_not_found')
    end
    state.focused = pane.pane_id
    return ok({ type = 'pane_info', pane = { pane_id = pane.pane_id, focused = true } })
  end

  function handlers.pane_split(params)
    local pane = find(params.target_pane_id)
    if not pane then
      return err('pane_not_found')
    end
    state.next_id = state.next_id + 1
    local id = ('w1:p%d'):format(state.next_id)
    local r = pane.rect
    local new
    if params.direction == 'right' then
      local half = math.floor(r.width / 2)
      new = { x = r.x + half, y = r.y, width = r.width - half, height = r.height }
      r.width = half
    else
      local half = math.floor(r.height / 2)
      new = { x = r.x, y = r.y + half, width = r.width, height = r.height - half }
      r.height = half
    end
    table.insert(state.panes, { pane_id = id, rect = new })
    if params.focus then
      state.focused = id
    end
    return ok({ type = 'pane_info', pane = { pane_id = id, focused = params.focus == true } })
  end

  function handlers.pane_swap(params)
    local pane = find(params.pane_id)
    if not pane then
      return err('pane_not_found')
    end
    local other = neighbour(params.pane_id, params.direction)
    if not other then
      return ok({
        type = 'pane_swap',
        swap = { changed = false, reason = 'no_neighbor', source_pane_id = pane.pane_id },
      })
    end
    pane.rect, other.rect = other.rect, pane.rect
    return ok({
      type = 'pane_swap',
      swap = { changed = true, source_pane_id = pane.pane_id, target_pane_id = other.pane_id },
    })
  end

  function handlers.pane_resize(params)
    if not find(params.pane_id) then
      return err('pane_not_found')
    end
    return ok({
      type = 'pane_resize',
      resize = { changed = true, pane_id = params.pane_id, focused_pane_id = state.focused, layout = layout() },
    })
  end

  function handlers.plugin_list()
    return ok({ type = 'plugin_list', plugins = vim.deepcopy(state.plugins) })
  end

  ---@type HerdrBackend.Handler
  function state.handler(method, params, cli_args, _timeout)
    table.insert(state.calls, { method = method, params = vim.deepcopy(params), cli_args = cli_args })
    if state.fail then
      return nil, type(state.fail) == 'string' and state.fail or 'timeout'
    end
    if state.fail_on[method] then
      return err(state.fail_on[method])
    end
    local fn = handlers[method:gsub('%.', '_')]
    if not fn then
      return err('invalid_request')
    end
    return fn(params, cli_args)
  end

  ---Requests made with `method`.
  ---@param method string
  ---@return FakeHerdr.Call[]
  function state.called(method)
    return vim.tbl_filter(function(call)
      return call.method == method
    end, state.calls)
  end

  ---@param method string
  ---@return integer
  function state.count(method)
    return #state.called(method)
  end

  ---@param method string
  ---@return FakeHerdr.Call|nil
  function state.first(method)
    return state.called(method)[1]
  end

  ---@param id string
  ---@return HerdrBackend.Rect|nil
  function state.rect(id)
    local pane = find(id)
    return pane and copy(pane.rect)
  end

  return state
end

return M
