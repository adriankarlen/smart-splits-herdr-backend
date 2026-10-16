local h = require('tests.helpers')

local backend = require('smart-splits-backend-herdr')
local protocol_tests = require('smart-splits.protocol_tests')

---@param result true|string
---@param name string
local function assert_passes(result, name)
  assert.is_true(result == true, name .. ': ' .. tostring(result))
end

describe('backend protocol conformance', function()
  after_each(function()
    h.restore()
  end)

  it('implements the v3 backend protocol', function()
    h.reset_backend()
    for _, test in ipairs(protocol_tests.tests(backend)) do
      assert_passes(test.fn(), test.name)
    end
  end)

  it('implements the v3 backend protocol outside a herdr session', function()
    h.reset_backend()
    h.leave_session()
    for _, test in ipairs(protocol_tests.tests(backend)) do
      assert_passes(test.fn(), test.name)
    end
  end)

  it('implements the v3 backend protocol when herdr is unreachable', function()
    h.reset_backend({ fail = 'socket_connect_failed' })
    for _, test in ipairs(protocol_tests.tests(backend)) do
      assert_passes(test.fn(), test.name)
    end
  end)

  it('declares the protocol fields', function()
    assert.are.equal('herdr', backend.name)
    assert.are.equal('3.0.0', backend.protocol_version)
    assert.are.equal('function', type(backend.detect))
    assert.are.equal('function', type(backend.move))
    assert.are.equal('function', type(backend.resize))
    assert.are.equal('function', type(backend.health))
    assert.are.equal('function', type(backend.setup))
  end)

  it('keeps setup() inert', function()
    local fake = h.reset_backend()
    backend.setup({ disable_nav_when_zoomed = false })
    assert.are.equal(0, #fake.calls)
    assert.is_false(require('smart-splits-backend-herdr.config').options.disable_nav_when_zoomed)
  end)

  it('is accepted by core', function()
    h.reset_backend()
    assert.is_nil(require('smart-splits.backend').validate(backend))
  end)
end)
