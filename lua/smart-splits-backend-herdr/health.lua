local config = require('smart-splits-backend-herdr.config')
local herdr = require('smart-splits-backend-herdr.herdr')
local transport = require('smart-splits-backend-herdr.transport')

local M = {}

---The id in this repository's `herdr-plugin.toml`.
M.PLUGIN_ID = 'smart-splits-backend-herdr'

---The id smart-splits.nvim v2 shipped its herdr plugin under. Core v3 dropped
---the manifest, so a link to it is left dangling.
M.LEGACY_PLUGIN_ID = 'smart-splits.nvim'

---@param msg string
---@param ... any
local function ok(msg, ...)
  vim.health.ok(msg:format(...))
end

---@param msg string
---@param ... any
local function info(msg, ...)
  vim.health.info(msg:format(...))
end

---@param msg string
---@param ... any
local function warn(msg, ...)
  vim.health.warn(msg:format(...))
end

local function check_binary()
  local bin = transport.bin()
  if vim.fn.executable(bin) ~= 1 then
    if config.options.transport == 'socket' then
      info('`%s` is not executable, but `transport = "socket"` does not need it', bin)
    else
      warn('`%s` is not executable, so there is no CLI fallback when the socket is unreachable', bin)
    end
    return
  end
  local version = herdr.version()
  if version then
    ok('%s (%s)', version, bin)
  else
    warn('`%s --version` did not answer', bin)
  end
end

local function check_plugin()
  local plugins = herdr.plugins()
  if not plugins then
    warn('could not list herdr plugins, so cannot check the herdr-side key bindings')
    return
  end

  ---@type HerdrBackend.Plugin|nil, HerdrBackend.Plugin|nil
  local found, legacy
  for _, plugin in ipairs(plugins) do
    if plugin.plugin_id == M.PLUGIN_ID then
      found = plugin
    elseif plugin.plugin_id == M.LEGACY_PLUGIN_ID then
      legacy = plugin
    end
  end

  if legacy then
    warn(
      'the smart-splits.nvim v2 herdr plugin `%s` is still registered; v3 removed its manifest. Run `herdr plugin unlink %s` and bind `%s.*` instead',
      M.LEGACY_PLUGIN_ID,
      M.LEGACY_PLUGIN_ID,
      M.PLUGIN_ID
    )
  end

  if not found then
    warn(
      "herdr plugin `%s` is not installed, so herdr keeps <C-hjkl> to itself and never moves into Neovim (see this plugin's README)",
      M.PLUGIN_ID
    )
    return
  end
  if found.enabled == false then
    warn('herdr plugin `%s` is installed but disabled: `herdr plugin enable %s`', M.PLUGIN_ID, M.PLUGIN_ID)
    return
  end
  for _, warning in ipairs(found.warnings or {}) do
    warn('herdr plugin `%s`: %s', M.PLUGIN_ID, warning)
  end
  ok('herdr plugin `%s` is enabled (%s)', M.PLUGIN_ID, found.plugin_root or 'unknown location')
end

local function check_session()
  if not herdr.in_session() then
    info('$HERDR_ENV or $HERDR_PANE_ID is not set, this Neovim is not running inside herdr')
    return
  end
  ok('$HERDR_PANE_ID: %s', herdr.pane_id())

  local socket = transport.socket_path()
  if socket then
    if vim.uv.fs_stat(socket) then
      ok('$HERDR_SOCKET_PATH: %s', socket)
    else
      warn('$HERDR_SOCKET_PATH points at %s, which does not exist', socket)
    end
  else
    warn('$HERDR_SOCKET_PATH is not set, every request will go through the slower `herdr` CLI')
  end

  local pong, err = herdr.ping()
  if pong then
    ok('herdr server answered: version %s, API protocol %s', tostring(pong.version), tostring(pong.protocol))
  elseif socket and config.options.transport ~= 'cli' then
    vim.health.error(('herdr server did not answer over the socket (%s)'):format(err or 'unknown error'))
    return
  end

  check_plugin()
end

---Called by core under a header it emits itself, for every backend that
---validated rather than only the one in use, so this has to keep working when
---there is no herdr to talk to.
function M.report()
  check_binary()
  check_session()
  info('enable: %s', vim.inspect(config.options.enable))
  info('disable_nav_when_zoomed: %s', vim.inspect(config.options.disable_nav_when_zoomed))
  info('resize_amount: %s', vim.inspect(config.options.resize_amount))
  info('timeout: %sms', vim.inspect(config.options.timeout))
  info('transport: %s', vim.inspect(config.options.transport))
end

---Entry point for `:checkhealth smart-splits-backend-herdr`, for users who want
---to check the backend without going through core.
function M.check()
  vim.health.start('smart-splits-backend-herdr')
  M.report()
end

return M
