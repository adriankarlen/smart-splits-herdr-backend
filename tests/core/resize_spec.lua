local h = require('tests.helpers')

local backend = require('smart-splits-backend-herdr')

describe('resize()', function()
  after_each(function()
    h.restore()
  end)

  it('converts cells into a fraction of the split', function()
    local fake = h.reset_backend(h.three_panes())
    assert.is_true(backend.resize('right', { amount = 12 }))
    local params = fake.first('pane.resize').params
    assert.are.equal('w1:p1', params.pane_id)
    assert.are.equal('right', params.direction)
    -- the root split is 120 cells wide
    assert.are.equal(0.1, params.amount)
  end)

  it('uses the inner split for a pane inside it', function()
    local opts = h.three_panes()
    opts.focused = 'w1:p2'
    local fake = h.reset_backend(opts)
    assert.is_true(backend.resize('down', { amount = 4 }))
    -- the right column's split is 40 cells tall
    assert.are.equal(0.1, fake.first('pane.resize').params.amount)
  end)

  it('falls back to its own resize_amount', function()
    local fake = h.reset_backend(vim.tbl_extend('force', h.three_panes(), { config = { resize_amount = 6 } }))
    assert.is_true(backend.resize('left', {}))
    assert.are.equal(0.05, fake.first('pane.resize').params.amount)
    assert.is_true(backend.resize('left'))
  end)

  it('offers the CLI equivalent', function()
    local fake = h.reset_backend(h.three_panes())
    backend.resize('right', { amount = 12 })
    assert.are.same(
      { 'pane', 'resize', '--direction', 'right', '--amount', '0.1', '--pane', 'w1:p1' },
      fake.first('pane.resize').cli_args
    )
  end)

  it('returns false when herdr is unreachable', function()
    h.reset_backend({ fail = 'timeout' })
    assert.is_false(backend.resize('right', { amount = 3 }))
  end)

  it('returns false when herdr refuses', function()
    h.reset_backend({ fail_on = { ['pane.resize'] = 'pane_not_found' } })
    assert.is_false(backend.resize('right', { amount = 3 }))
  end)

  it('returns false without asking herdr when disabled or outside a session', function()
    local fake = h.reset_backend({ config = { enable = false } })
    assert.is_false(backend.resize('right', { amount = 3 }))
    h.reset_backend()
    h.leave_session()
    assert.is_false(backend.resize('right', { amount = 3 }))
    assert.are.equal(0, #fake.calls)
  end)
end)
