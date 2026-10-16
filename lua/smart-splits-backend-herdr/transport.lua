---How requests reach the herdr server.
---
---herdr speaks newline-delimited JSON over a local socket, and every pane it
---starts gets the path in `$HERDR_SOCKET_PATH`. Talking to that socket directly
---costs no subprocess, which matters on a path that runs on every keypress at a
---window edge. The `herdr` CLI wraps the same requests and prints the same
---envelope, so it is the fallback when the socket cannot be reached.
---
---Nothing here throws. Every failure comes back as `nil, reason`.

local config = require('smart-splits-backend-herdr.config')

local M = {}

---@class HerdrBackend.Envelope
---@field id? string
---@field result? table
---@field error? { code?: string, message?: string }

---@alias HerdrBackend.Handler fun(method: string, params: table, cli_args: string[]|nil, timeout: integer):HerdrBackend.Envelope|nil, string|nil

---@return string|nil
function M.socket_path()
  local path = vim.env.HERDR_SOCKET_PATH
  if type(path) ~= 'string' or #path == 0 then
    return nil
  end
  return path
end

---The herdr binary. herdr exports the path of the running binary to its panes,
---which keeps the CLI and the server on the same version.
---@return string
function M.bin()
  local bin = vim.env.HERDR_BIN_PATH
  if type(bin) == 'string' and #bin > 0 then
    return bin
  end
  return 'herdr'
end

local request_seq = 0

---@param chunks string[]
---@return HerdrBackend.Envelope|nil, string|nil
local function decode(chunks)
  local raw = table.concat(chunks)
  local line = raw:match('^[^\n]*') or ''
  if #vim.trim(line) == 0 then
    return nil, 'empty_response'
  end
  local ok, decoded = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
  if not ok or type(decoded) ~= 'table' then
    return nil, 'invalid_response'
  end
  return decoded, nil
end

---Send one request over the socket and wait for its single-line answer.
---
---The second return value says whether the request may have reached the
---server. A request that never left Neovim is safe to retry over the CLI; one
---that might have been applied is not, because focus and split are not
---idempotent.
---@param path string
---@param method string
---@param params table
---@param timeout integer
---@return HerdrBackend.Envelope|nil envelope, string|nil err, boolean sent
function M.socket_request(path, method, params, timeout)
  local uv = vim.uv
  local pipe = uv.new_pipe(false)
  if not pipe then
    return nil, 'socket_unavailable', false
  end

  request_seq = request_seq + 1
  local ok_encode, payload = pcall(vim.json.encode, {
    id = ('smart-splits-%d'):format(request_seq),
    method = method,
    params = vim.tbl_isempty(params) and vim.empty_dict() or params,
  })
  if not ok_encode then
    pipe:close()
    return nil, 'encode_failed', false
  end

  ---@type { done: boolean, sent: boolean, err: string|nil, chunks: string[] }
  local state = { done = false, sent = false, err = nil, chunks = {} }

  local function finish(err)
    if state.done then
      return
    end
    state.err = err
    state.done = true
  end

  local ok_connect = pcall(pipe.connect, pipe, path, function(connect_err)
    if connect_err then
      return finish('socket_connect_failed')
    end
    state.sent = true
    pipe:write(payload .. '\n', function(write_err)
      if write_err then
        finish('socket_write_failed')
      end
    end)
    pipe:read_start(function(read_err, chunk)
      if read_err then
        return finish('socket_read_failed')
      end
      if not chunk then
        return finish(nil)
      end
      table.insert(state.chunks, chunk)
      if chunk:find('\n', 1, true) then
        finish(nil)
      end
    end)
  end)
  if not ok_connect then
    pipe:close()
    return nil, 'socket_connect_failed', false
  end

  local ok_wait, finished = pcall(vim.wait, timeout, function()
    return state.done
  end, 1)
  if not pipe:is_closing() then
    pipe:close()
  end
  if not ok_wait then
    -- vim.wait refuses to run inside a fast event; nothing was necessarily sent
    return nil, 'cannot_wait', state.sent
  end
  if not finished then
    return nil, 'timeout', state.sent
  end
  if state.err and #state.chunks == 0 then
    return nil, state.err, state.sent
  end

  local envelope, decode_err = decode(state.chunks)
  return envelope, decode_err, true
end

---Run the CLI equivalent of a request. herdr prints the same envelope on stdout
---whether the request succeeded or not, and exits non-zero on errors.
---@param cli_args string[]
---@param timeout integer
---@return HerdrBackend.Envelope|nil, string|nil
function M.cli_request(cli_args, timeout)
  local cmd = { M.bin() }
  vim.list_extend(cmd, cli_args)
  local ok, result = pcall(function()
    return vim.system(cmd, { text = true, timeout = timeout }):wait()
  end)
  if not ok or type(result) ~= 'table' then
    return nil, 'cli_unavailable'
  end
  if result.signal and result.signal ~= 0 then
    return nil, 'timeout'
  end
  local envelope, err = decode({ result.stdout or '' })
  if not envelope then
    return nil, result.code == 0 and err or 'cli_failed'
  end
  return envelope, nil
end

---@type HerdrBackend.Handler
local default_handler = function(method, params, cli_args, timeout)
  local mode = config.options.transport
  local path = M.socket_path()

  if mode ~= 'cli' and path then
    local envelope, err, sent = M.socket_request(path, method, params, timeout)
    if envelope or mode == 'socket' or sent then
      return envelope, err
    end
  elseif mode == 'socket' then
    return nil, 'no_socket'
  end

  if not cli_args then
    return nil, 'no_cli_equivalent'
  end
  return M.cli_request(cli_args, timeout)
end

---@type HerdrBackend.Handler
local handler = default_handler

---Replace how requests are delivered. Tests use this; nothing else should.
---@param fn? HerdrBackend.Handler
function M.set_handler(fn)
  handler = fn or default_handler
end

function M.reset_handler()
  handler = default_handler
end

---Send a request and unwrap its envelope.
---@param method string socket API method, e.g. `pane.focus_direction`
---@param params table
---@param cli_args? string[] the CLI equivalent, without the binary; `nil` when the CLI has none
---@return table|nil result, string|nil err
function M.request(method, params, cli_args)
  local ok, envelope, err = pcall(handler, method, params, cli_args, config.options.timeout)
  if not ok then
    return nil, 'handler_error'
  end
  ---@cast envelope HerdrBackend.Envelope|nil
  ---@cast err string|nil
  if not envelope then
    return nil, err or 'no_response'
  end
  if type(envelope.error) == 'table' then
    return nil, envelope.error.code or 'herdr_error'
  end
  if type(envelope.result) ~= 'table' then
    return nil, 'invalid_response'
  end
  return envelope.result, nil
end

return M
