---Test scaffolding: a fake herdr behind the transport, plus the environment a
---herdr pane would have put Neovim in. Every assertion in `tests/core` is made
---against this rather than a real server, so the suite is hermetic and runs the
---same inside and outside herdr. `tests/integration` covers the real thing.

local config = require('smart-splits-backend-herdr.config')
local fake_herdr = require('tests.fake_herdr')
local transport = require('smart-splits-backend-herdr.transport')

local M = {}

M.PANE = 'w1:p1'
M.SOCKET = '/tmp/smart-splits-backend-herdr-tests.sock'

local ENV_KEYS = { 'HERDR_ENV', 'HERDR_PANE_ID', 'HERDR_SOCKET_PATH', 'HERDR_BIN_PATH' }
local saved_env = {}
for _, key in ipairs(ENV_KEYS) do
  saved_env[key] = vim.env[key]
end

---Pretend Neovim was started in a herdr pane.
---@param opts? { pane?: string, socket?: string|false }
function M.enter_session(opts)
  opts = opts or {}
  vim.env.HERDR_ENV = '1'
  vim.env.HERDR_PANE_ID = opts.pane or M.PANE
  if opts.socket == false then
    vim.env.HERDR_SOCKET_PATH = nil
  else
    vim.env.HERDR_SOCKET_PATH = opts.socket or M.SOCKET
  end
end

function M.leave_session()
  for _, key in ipairs(ENV_KEYS) do
    vim.env[key] = nil
  end
end

---Fresh config, a fresh fake herdr behind the transport, and a herdr session.
---@param opts? FakeHerdr.Opts|{ pane?: string, config?: HerdrBackend.PartialConfig }
---@return table fake the fake herdr state
function M.reset_backend(opts)
  opts = opts or {}
  config.setup(opts.config)
  local fake = fake_herdr.new(opts)
  transport.set_handler(fake.handler)
  M.enter_session({ pane = opts.pane or opts.focused })
  return fake
end

---Undo everything a test may have changed.
function M.restore()
  transport.reset_handler()
  config.setup()
  for _, key in ipairs(ENV_KEYS) do
    vim.env[key] = saved_env[key]
  end
end

---Three panes: one tall on the left, two stacked on the right.
---
---    +--------+--------+
---    |        |   p2   |
---    |   p1   +--------+
---    |        |   p3   |
---    +--------+--------+
---@return FakeHerdr.Opts
function M.three_panes()
  return {
    panes = {
      { pane_id = 'w1:p1', rect = { x = 0, y = 0, width = 60, height = 40 } },
      { pane_id = 'w1:p2', rect = { x = 60, y = 0, width = 60, height = 20 } },
      { pane_id = 'w1:p3', rect = { x = 60, y = 20, width = 60, height = 20 } },
    },
    splits = {
      { id = 'split_0_root', direction = 'right', ratio = 0.5, rect = { x = 0, y = 0, width = 120, height = 40 } },
      { id = 'split_1_1', direction = 'down', ratio = 0.5, rect = { x = 60, y = 0, width = 60, height = 40 } },
    },
  }
end

---Capture what `health()` reports.
---@param fn fun()
---@return { level: string, msg: string }[]
function M.capture_health(fn)
  local reports = {}
  local original = {}
  for _, level in ipairs({ 'ok', 'info', 'warn', 'error', 'start' }) do
    original[level] = vim.health[level]
    vim.health[level] = function(msg)
      table.insert(reports, { level = level, msg = msg })
    end
  end
  local ok, err = pcall(fn)
  for level, f in pairs(original) do
    vim.health[level] = f
  end
  if not ok then
    error(err)
  end
  return reports
end

---@param reports { level: string, msg: string }[]
---@param level string
---@param pattern string plain substring
---@return boolean
function M.reported(reports, level, pattern)
  for _, report in ipairs(reports) do
    if report.level == level and report.msg:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

return M
