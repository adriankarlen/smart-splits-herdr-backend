---The transport against a real Unix socket served from inside the test process,
---and a fake `herdr` executable for the CLI path.

local h = require('tests.helpers')

local config = require('smart-splits-backend-herdr.config')
local transport = require('smart-splits-backend-herdr.transport')

local uv = vim.uv

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, 'p')
local SOCKET = tmpdir .. '/herdr.sock'
local CLI_LOG = tmpdir .. '/cli.log'
local CLI = tmpdir .. '/herdr'

local fake_cli = [[#!/bin/sh
echo "$@" >> "]] .. CLI_LOG .. [["
case "$*" in
  "pane edges"*) echo '{"id":"cli:pane:edges","result":{"type":"pane_edges","edges":{"pane_id":"w1:p1","left":true}}}' ;;
  "pane focus"*) echo '{"error":{"code":"pane_not_found","message":"pane not found"},"id":"cli:pane:focus"}'; exit 1 ;;
  "pane swap"*) echo 'not json'; exit 1 ;;
  *) exit 2 ;;
esac
]]
local file = assert(io.open(CLI, 'w'))
file:write(fake_cli)
file:close()
uv.fs_chmod(CLI, 493) -- 0755

---@return string[]
local function cli_calls()
  local f = io.open(CLI_LOG, 'r')
  if not f then
    return {}
  end
  local lines = vim.split(f:read('*a'), '\n', { trimempty = true })
  f:close()
  return lines
end

---Close a listening pipe and wait until it is really gone, so the next test
---cannot connect to it.
---@param pipe uv.uv_pipe_t
local function close_listener(pipe)
  os.remove(SOCKET)
  if pipe:is_closing() then
    return
  end
  local closed = false
  pipe:close(function()
    closed = true
  end)
  vim.wait(200, function()
    return closed
  end, 1)
end

---Serve one-line requests on `SOCKET`. `respond` gets the decoded request and
---returns the envelope to send back, or nil to stay silent.
---@param respond fun(request: table):table|nil
---@return { requests: table[], close: fun() }
local function serve(respond)
  os.remove(SOCKET)
  local server = assert(uv.new_pipe(false))
  assert(server:bind(SOCKET))
  local handle = { requests = {} }
  server:listen(8, function()
    local client = assert(uv.new_pipe(false))
    server:accept(client)
    local buffer = ''
    client:read_start(function(_, chunk)
      if not chunk then
        client:close()
        return
      end
      buffer = buffer .. chunk
      local line = buffer:match('^(.-)\n')
      if line then
        local request = vim.json.decode(line)
        table.insert(handle.requests, request)
        local reply = respond(request)
        if reply then
          client:write(vim.json.encode(reply) .. '\n')
        end
      end
    end)
  end)
  function handle.close()
    close_listener(server)
  end
  return handle
end

describe('transport', function()
  local server

  before_each(function()
    os.remove(CLI_LOG)
    os.remove(SOCKET)
    -- generous: the first run of a freshly written script can be slow (macOS
    -- scans new executables); only the timeout test wants a short one
    config.setup({ timeout = 5000 })
    transport.reset_handler()
    h.enter_session({ socket = SOCKET })
    vim.env.HERDR_BIN_PATH = CLI
  end)

  after_each(function()
    if server then
      server.close()
      server = nil
    end
    h.restore()
  end)

  describe('over the socket', function()
    it('sends one JSON line and unwraps the answer', function()
      server = serve(function(request)
        return { id = request.id, result = { type = 'pong', version = '0.9.3', protocol = 22 } }
      end)
      local result, err = transport.request('ping', {}, nil)
      assert.is_nil(err)
      assert.are.equal('0.9.3', result.version)
      assert.are.equal('ping', server.requests[1].method)
      assert.is_string(server.requests[1].id)
      assert.are.same({}, server.requests[1].params)
      assert.are.same({}, cli_calls())
    end)

    it('sends empty params as an object, not an array', function()
      local raw
      os.remove(SOCKET)
      local listener = assert(uv.new_pipe(false))
      assert(listener:bind(SOCKET))
      listener:listen(1, function()
        local client = assert(uv.new_pipe(false))
        listener:accept(client)
        client:read_start(function(_, chunk)
          if chunk then
            raw = chunk
            client:write('{"id":"x","result":{"type":"pong"}}\n')
          else
            client:close()
          end
        end)
      end)
      transport.request('ping', {}, nil)
      close_listener(listener)
      assert.truthy(raw:find('"params":{}', 1, true), raw)
    end)

    it('passes params through', function()
      server = serve(function(request)
        return { id = request.id, result = { type = 'pane_edges', edges = { pane_id = request.params.pane_id } } }
      end)
      local result = transport.request('pane.edges', { pane_id = 'w1:p7' }, { 'pane', 'edges', '--pane', 'w1:p7' })
      assert.are.equal('w1:p7', result.edges.pane_id)
      assert.are.same({ pane_id = 'w1:p7' }, server.requests[1].params)
    end)

    it('reports herdr errors by code', function()
      server = serve(function(request)
        return { id = request.id, error = { code = 'pane_not_found', message = 'pane not found' } }
      end)
      local result, err = transport.request('pane.edges', { pane_id = 'nope' }, { 'pane', 'edges' })
      assert.is_nil(result)
      assert.are.equal('pane_not_found', err)
      assert.are.same({}, cli_calls(), 'a herdr error is an answer, not a reason to retry')
    end)

    it('times out, and does not retry a request that may have been applied', function()
      config.setup({ timeout = 200 })
      server = serve(function()
        return nil
      end)
      local start = uv.hrtime()
      local result, err = transport.request('pane.focus_direction', { direction = 'left' }, { 'pane', 'focus' })
      local elapsed = (uv.hrtime() - start) / 1e6
      assert.is_nil(result)
      assert.are.equal('timeout', err)
      assert.is_true(elapsed < 1000, ('took %dms'):format(elapsed))
      assert.are.same({}, cli_calls())
    end)

    it('rejects an answer that is not JSON', function()
      os.remove(SOCKET)
      local listener = assert(uv.new_pipe(false))
      assert(listener:bind(SOCKET))
      listener:listen(1, function()
        local client = assert(uv.new_pipe(false))
        listener:accept(client)
        client:read_start(function(_, chunk)
          if chunk then
            client:write('garbage\n')
          else
            client:close()
          end
        end)
      end)
      local result, err = transport.request('ping', {}, nil)
      close_listener(listener)
      assert.is_nil(result)
      assert.are.equal('invalid_response', err)
    end)
  end)

  describe('falling back to the CLI', function()
    it('uses the CLI when nothing is listening on the socket', function()
      local result, err = transport.request('pane.edges', { pane_id = 'w1:p1' }, { 'pane', 'edges', '--pane', 'w1:p1' })
      assert.is_nil(err)
      assert.is_true(result.edges.left)
      assert.are.same({ 'pane edges --pane w1:p1' }, cli_calls())
    end)

    it('uses the CLI when there is no socket path', function()
      vim.env.HERDR_SOCKET_PATH = nil
      local result = transport.request('pane.edges', {}, { 'pane', 'edges' })
      assert.is_true(result.edges.left)
    end)

    it('reads error envelopes from a failing CLI', function()
      local result, err = transport.request('pane.focus_direction', {}, { 'pane', 'focus', '--direction', 'left' })
      assert.is_nil(result)
      assert.are.equal('pane_not_found', err)
    end)

    it('reports a CLI that prints garbage', function()
      local result, err = transport.request('pane.swap', {}, { 'pane', 'swap' })
      assert.is_nil(result)
      assert.are.equal('cli_failed', err)
    end)

    it('reports requests the CLI cannot make', function()
      local result, err = transport.request('pane.focus', { pane_id = 'w1:p1' }, nil)
      assert.is_nil(result)
      assert.are.equal('no_cli_equivalent', err)
    end)

    it('reports a missing binary', function()
      vim.env.HERDR_BIN_PATH = tmpdir .. '/does-not-exist'
      local result, err = transport.request('pane.edges', {}, { 'pane', 'edges' })
      assert.is_nil(result)
      assert.are.equal('cli_unavailable', err)
    end)
  end)

  describe('transport option', function()
    it("'socket' never runs the CLI", function()
      config.setup({ transport = 'socket', timeout = 5000 })
      local result, err = transport.request('pane.edges', {}, { 'pane', 'edges' })
      assert.is_nil(result)
      assert.are.equal('socket_connect_failed', err)
      vim.env.HERDR_SOCKET_PATH = nil
      assert.are.equal('no_socket', select(2, transport.request('pane.edges', {}, { 'pane', 'edges' })))
      assert.are.same({}, cli_calls())
    end)

    it("'cli' never touches the socket", function()
      server = serve(function(request)
        return { id = request.id, result = { type = 'pane_edges', edges = { left = false } } }
      end)
      config.setup({ transport = 'cli', timeout = 5000 })
      local result = transport.request('pane.edges', {}, { 'pane', 'edges' })
      assert.is_true(result.edges.left)
      assert.are.equal(0, #server.requests)
    end)
  end)

  describe('bin()', function()
    it('prefers $HERDR_BIN_PATH', function()
      assert.are.equal(CLI, transport.bin())
      vim.env.HERDR_BIN_PATH = ''
      assert.are.equal('herdr', transport.bin())
    end)
  end)
end)
