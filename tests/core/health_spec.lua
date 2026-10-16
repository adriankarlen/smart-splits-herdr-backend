local h = require('tests.helpers')

local backend = require('smart-splits-backend-herdr')
local health = require('smart-splits-backend-herdr.health')

local OUR_PLUGIN = { plugin_id = 'smart-splits-backend-herdr', enabled = true, plugin_root = '/plugins/ours' }
local LEGACY_PLUGIN = { plugin_id = 'smart-splits.nvim', enabled = true, warnings = { 'manifest unavailable' } }

---@return { level: string, msg: string }[]
local function report()
  return h.capture_health(backend.health)
end

describe('health()', function()
  after_each(function()
    h.restore()
  end)

  it('never starts its own section when called by core', function()
    h.reset_backend({ plugins = { OUR_PLUGIN } })
    for _, r in ipairs(report()) do
      assert.are_not.equal('start', r.level)
    end
  end)

  it('works outside herdr', function()
    h.reset_backend()
    h.leave_session()
    local reports = report()
    assert.is_true(h.reported(reports, 'info', 'not running inside herdr'))
    assert.is_false(h.reported(reports, 'error', ''))
  end)

  it('reports the server and the installed plugin', function()
    h.reset_backend({ plugins = { OUR_PLUGIN } })
    local reports = report()
    assert.is_true(h.reported(reports, 'ok', '$HERDR_PANE_ID: w1:p1'))
    assert.is_true(h.reported(reports, 'ok', 'version 0.9.3, API protocol 22'))
    assert.is_true(h.reported(reports, 'ok', 'smart-splits-backend-herdr` is enabled (/plugins/ours)'))
  end)

  it('warns when the herdr plugin is missing', function()
    h.reset_backend()
    assert.is_true(h.reported(report(), 'warn', 'is not installed'))
  end)

  it('warns when the herdr plugin is disabled', function()
    h.reset_backend({ plugins = { vim.tbl_extend('force', OUR_PLUGIN, { enabled = false }) } })
    assert.is_true(h.reported(report(), 'warn', 'installed but disabled'))
  end)

  it('warns about the v2 plugin left behind by core', function()
    h.reset_backend({ plugins = { OUR_PLUGIN, LEGACY_PLUGIN } })
    assert.is_true(h.reported(report(), 'warn', 'herdr plugin unlink smart-splits.nvim'))
  end)

  it('reports an unreachable server', function()
    h.reset_backend({ fail = 'socket_connect_failed' })
    assert.is_true(h.reported(report(), 'error', 'did not answer'))
  end)

  it('warns when the socket path is missing', function()
    h.reset_backend({ plugins = { OUR_PLUGIN } })
    vim.env.HERDR_SOCKET_PATH = nil
    assert.is_true(h.reported(report(), 'warn', '$HERDR_SOCKET_PATH is not set'))
  end)

  it('lists the effective options', function()
    h.reset_backend({ config = { timeout = 123, transport = 'cli' } })
    local reports = report()
    assert.is_true(h.reported(reports, 'info', 'timeout: 123ms'))
    assert.is_true(h.reported(reports, 'info', 'transport: "cli"'))
  end)

  it('has a standalone :checkhealth entry point', function()
    h.reset_backend()
    local reports = h.capture_health(health.check)
    assert.are.equal('start', reports[1].level)
    assert.are.equal('smart-splits-backend-herdr', reports[1].msg)
  end)
end)
