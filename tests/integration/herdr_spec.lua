---Integration tests against a real herdr server.
---
---The fakes in `tests/core` pin down what the backend *sends*; these pin down
---that herdr answers the way the backend assumes. Nothing here touches the
---developer's own herdr: the server runs in a named session with `HOME` and
---`XDG_CONFIG_HOME` pointed at a temporary directory, so its sockets, config
---and logs all live there and disappear with it.

local backend = require('smart-splits-backend-herdr')
local config = require('smart-splits-backend-herdr.config')
local transport = require('smart-splits-backend-herdr.transport')

local HERDR = vim.fn.exepath('herdr')
local SESSION = 'smart-splits-tests'
local ENV_KEYS = { 'HERDR_ENV', 'HERDR_PANE_ID', 'HERDR_SOCKET_PATH', 'HERDR_BIN_PATH' }

local saved_env = {}
for _, key in ipairs(ENV_KEYS) do
  saved_env[key] = vim.env[key]
end

local root, socket, server_job

---The environment for every herdr process started here: nothing inherited from
---a herdr this suite may itself be running inside.
---@return table<string, string>
local function isolated_env()
  return {
    HOME = root .. '/home',
    XDG_CONFIG_HOME = root .. '/config',
    XDG_STATE_HOME = root .. '/state',
    XDG_DATA_HOME = root .. '/data',
    TMPDIR = root .. '/tmp',
    PATH = vim.env.PATH or '/usr/bin:/bin',
    SHELL = '/bin/sh',
    TERM = 'xterm-256color',
  }
end

---Run a herdr CLI command against the test server.
---@param args string[]
---@return string stdout, integer code
local function herdr_cli(args)
  local cmd = { HERDR, '--session', SESSION }
  vim.list_extend(cmd, args)
  local result = vim.system(cmd, { text = true, timeout = 10000, env = isolated_env(), clear_env = true }):wait()
  return vim.trim(result.stdout or ''), result.code
end

---Talk to the test server directly, bypassing the backend.
---@param method string
---@param params? table
---@return table result
local function raw(method, params)
  local envelope, err = transport.socket_request(socket, method, params or {}, 5000)
  assert(envelope, ('%s failed: %s'):format(method, tostring(err)))
  assert(envelope.result, ('%s failed: %s'):format(method, vim.inspect(envelope.error)))
  return envelope.result
end

---@param pane string
---@return HerdrBackend.Layout
local function layout_of(pane)
  return raw('pane.edges', { pane_id = pane }).edges.layout
end

---@param pane string
---@return string
local function focused(pane)
  return layout_of(pane).focused_pane_id
end

---@param pane string
---@param id string
---@return HerdrBackend.Rect
local function rect(pane, id)
  for _, p in ipairs(layout_of(pane).panes) do
    if p.pane_id == id then
      return p.rect
    end
  end
  error('no pane ' .. id)
end

---A fresh tab holding one pane, with Neovim pretending to run in it.
---@return string pane
local function fresh_tab()
  local created = raw('workspace.create', { cwd = root, focus = true })
  local pane = created.root_pane.pane_id
  vim.env.HERDR_ENV = '1'
  vim.env.HERDR_PANE_ID = pane
  vim.env.HERDR_SOCKET_PATH = socket
  vim.env.HERDR_BIN_PATH = HERDR
  return pane
end

---Split `pane` towards the right without moving focus.
---@param pane string
---@param direction? 'right'|'down'
---@return string new_pane
local function split(pane, direction)
  return raw('pane.split', { target_pane_id = pane, direction = direction or 'right', focus = false }).pane.pane_id
end

local function start_server()
  -- short on purpose: a Unix socket path must fit in ~104 bytes, and macOS
  -- puts `tempname()` deep under /var/folders
  root = assert(vim.uv.fs_mkdtemp('/tmp/ssbh-XXXXXX'))
  for _, dir in ipairs({ 'home', 'config', 'state', 'data', 'tmp' }) do
    vim.fn.mkdir(root .. '/' .. dir, 'p')
  end
  socket = ('%s/config/herdr/sessions/%s/herdr.sock'):format(root, SESSION)
  server_job = vim.system(
    { HERDR, '--session', SESSION, 'server' },
    { env = isolated_env(), clear_env = true, text = true }
  )
  local up = vim.wait(10000, function()
    if not vim.uv.fs_stat(socket) then
      return false
    end
    local envelope = transport.socket_request(socket, 'ping', {}, 500)
    return envelope ~= nil and envelope.result ~= nil
  end, 50)
  if not up then
    server_job:kill('sigterm')
    local result = server_job:wait(2000)
    error(('herdr server did not come up on %s\n%s'):format(socket, result.stderr or ''))
  end
end

local function stop_server()
  if server_job then
    herdr_cli({ 'server', 'stop' })
    vim.wait(3000, function()
      return server_job:is_closing()
    end, 50)
    if not server_job:is_closing() then
      server_job:kill('sigterm')
    end
    server_job = nil
  end
  if root then
    vim.fn.delete(root, 'rf')
  end
end

local describe_herdr = HERDR ~= '' and describe or pending

describe_herdr('against a real herdr', function()
  setup(start_server)
  teardown(function()
    stop_server()
    for _, key in ipairs(ENV_KEYS) do
      vim.env[key] = saved_env[key]
    end
  end)

  before_each(function()
    config.setup({ timeout = 5000 })
    transport.reset_handler()
  end)

  it('passes the protocol conformance tests', function()
    fresh_tab()
    for _, test in ipairs(require('smart-splits.protocol_tests').tests(backend)) do
      local result = test.fn()
      assert.is_true(result == true, test.name .. ': ' .. tostring(result))
    end
  end)

  it('moves to a neighbouring pane', function()
    local pane = fresh_tab()
    local right = split(pane)
    raw('pane.focus', { pane_id = pane })
    assert.is_true(backend.move('right'))
    assert.are.equal(right, focused(pane))
  end)

  it('stops at the edge, because herdr never wraps on its own', function()
    local pane = fresh_tab()
    split(pane)
    raw('pane.focus', { pane_id = pane })
    assert.is_false(backend.move('left', { at_edge = 'stop' }))
    assert.are.equal(pane, focused(pane))
  end)

  it('wraps to the far edge when asked', function()
    local pane = fresh_tab()
    local middle = split(pane)
    local far = split(middle)
    raw('pane.focus', { pane_id = pane })
    assert.is_true(backend.move('left', { at_edge = 'wrap' }))
    assert.are.equal(far, focused(pane))
  end)

  it('wraps by walking when only the CLI is available', function()
    local pane = fresh_tab()
    local middle = split(pane)
    local far = split(middle)
    raw('pane.focus', { pane_id = far })
    vim.env.HERDR_PANE_ID = far
    config.setup({ timeout = 5000, transport = 'cli' })
    assert.is_true(backend.move('right', { at_edge = 'wrap' }))
    assert.are.equal(pane, focused(pane))
  end)

  it('splits towards every direction', function()
    for _, direction in ipairs({ 'right', 'down', 'left', 'up' }) do
      local pane = fresh_tab()
      assert.is_true(backend.move(direction, { at_edge = 'split' }), direction)
      local panes = layout_of(pane).panes
      assert.are.equal(2, #panes, direction)
      local new = focused(pane)
      assert.are_not.equal(pane, new, direction)
      local a, b = rect(pane, new), rect(pane, pane)
      if direction == 'right' then
        assert.is_true(a.x > b.x, direction)
      elseif direction == 'left' then
        assert.is_true(a.x < b.x, direction)
      elseif direction == 'down' then
        assert.is_true(a.y > b.y, direction)
      else
        assert.is_true(a.y < b.y, direction)
      end
    end
  end)

  it('resizes by roughly the number of cells asked for', function()
    local pane = fresh_tab()
    split(pane)
    local before = rect(pane, pane).width
    assert.is_true(backend.resize('right', { amount = 6 }))
    local grown = rect(pane, pane).width
    assert.is_true(math.abs(grown - before - 6) <= 1, ('grew by %d'):format(grown - before))
    assert.is_true(backend.resize('left', { amount = 6 }))
    assert.is_true(math.abs(rect(pane, pane).width - before) <= 1)
  end)

  it('refuses to leave a zoomed pane', function()
    local pane = fresh_tab()
    split(pane)
    raw('pane.focus', { pane_id = pane })
    raw('pane.zoom', { pane_id = pane, mode = 'on' })
    assert.is_false(backend.move('right'))
    assert.are.equal(pane, focused(pane))
    raw('pane.zoom', { pane_id = pane, mode = 'off' })
  end)

  it('works over the CLI alone', function()
    local pane = fresh_tab()
    local right = split(pane)
    raw('pane.focus', { pane_id = pane })
    config.setup({ timeout = 5000, transport = 'cli' })
    assert.is_true(backend.move('right'))
    assert.are.equal(right, focused(pane))
  end)

  describe('herdr-navigate.sh', function()
    local script = vim.fn.getcwd() .. '/scripts/herdr-navigate.sh'

    ---@param pane string
    ---@param direction string
    ---@return integer code
    local function navigate(pane, direction)
      local env = isolated_env()
      env.HERDR_BIN_PATH = HERDR
      env.HERDR_SOCKET_PATH = socket
      env.HERDR_PANE_ID = pane
      local result = vim.system({ 'bash', script, direction }, { env = env, clear_env = true, timeout = 10000 }):wait()
      return result.code
    end

    it('moves herdr focus out of a shell pane', function()
      local pane = fresh_tab()
      local right = split(pane)
      raw('pane.focus', { pane_id = pane })
      assert.are.equal(0, navigate(pane, 'right'))
      assert.are.equal(right, focused(pane))
    end)

    it('hands the key back to the shell at an edge', function()
      local pane = fresh_tab()
      split(pane)
      raw('pane.focus', { pane_id = pane })
      assert.are.equal(0, navigate(pane, 'left'))
      assert.are.equal(pane, focused(pane))
    end)

    it('rejects unknown directions', function()
      local pane = fresh_tab()
      assert.are.equal(2, navigate(pane, 'sideways'))
    end)
  end)
end)
