local h = require('tests.helpers')

local backend = require('smart-splits-backend-herdr')

describe('detect()', function()
  after_each(function()
    h.restore()
  end)

  it('is true inside a herdr pane', function()
    h.reset_backend()
    assert.is_true(backend.detect())
  end)

  it('makes no requests', function()
    local fake = h.reset_backend()
    backend.detect()
    assert.are.equal(0, #fake.calls)
  end)

  it('is false outside herdr', function()
    h.reset_backend()
    h.leave_session()
    assert.is_false(backend.detect())
  end)

  it('is false without a pane id', function()
    h.reset_backend()
    vim.env.HERDR_PANE_ID = nil
    assert.is_false(backend.detect())
  end)

  it('is false when HERDR_ENV is 0 or empty', function()
    h.reset_backend()
    vim.env.HERDR_ENV = '0'
    assert.is_false(backend.detect())
    vim.env.HERDR_ENV = ''
    assert.is_false(backend.detect())
  end)

  it('is false when disabled', function()
    h.reset_backend({ config = { enable = false } })
    assert.is_false(backend.detect())
  end)

  it('does not need the socket path', function()
    h.reset_backend()
    vim.env.HERDR_SOCKET_PATH = nil
    assert.is_true(backend.detect())
  end)
end)
