local h = require('tests.helpers')

local backend = require('smart-splits-backend-herdr')

---Single pane filling the tab.
local SINGLE = {
  panes = { { pane_id = 'w1:p1', rect = { x = 0, y = 0, width = 120, height = 40 } } },
}

describe('move()', function()
  after_each(function()
    h.restore()
  end)

  it('moves to the neighbouring herdr pane', function()
    local fake = h.reset_backend()
    assert.is_true(backend.move('right'))
    assert.are.same({ pane_id = 'w1:p1', direction = 'right' }, fake.first('pane.focus_direction').params)
    assert.are.equal('w1:p2', fake.focused)
  end)

  it('passes every direction through unchanged', function()
    local moves = { { 'w1:p1', 'right', 'w1:p2' }, { 'w1:p2', 'down', 'w1:p3' }, { 'w1:p3', 'up', 'w1:p2' } }
    for _, case in ipairs(moves) do
      local opts = h.three_panes()
      opts.focused = case[1]
      local fake = h.reset_backend(opts)
      assert.is_true(backend.move(case[2]), case[2])
      assert.are.equal(case[3], fake.focused, case[2])
    end
    local fake = h.reset_backend(vim.tbl_extend('force', h.three_panes(), { focused = 'w1:p3' }))
    assert.is_true(backend.move('left'))
    assert.are.equal('w1:p1', fake.focused)
  end)

  it("moves from Neovim's own pane, not whichever pane herdr has focused", function()
    local fake = h.reset_backend({ focused = 'w1:p2', pane = 'w1:p1' })
    backend.move('right')
    assert.are.equal('w1:p1', fake.first('pane.focus_direction').params.pane_id)
  end)

  it('offers the CLI equivalent of each request', function()
    local fake = h.reset_backend()
    backend.move('right')
    assert.are.same({ 'pane', 'edges', '--pane', 'w1:p1' }, fake.first('pane.edges').cli_args)
    assert.are.same(
      { 'pane', 'focus', '--direction', 'right', '--pane', 'w1:p1' },
      fake.first('pane.focus_direction').cli_args
    )
  end)

  describe('at the outer edge of herdr', function()
    it('does not move with at_edge = stop', function()
      local fake = h.reset_backend()
      assert.is_false(backend.move('left', { at_edge = 'stop' }))
      assert.are.equal('w1:p1', fake.focused)
      assert.are.equal(0, fake.count('pane.split'))
      assert.are.equal(0, fake.count('pane.focus'))
    end)

    it('does not move when at_edge is absent', function()
      local fake = h.reset_backend()
      assert.is_false(backend.move('left', {}))
      assert.is_false(backend.move('left'))
      assert.are.equal('w1:p1', fake.focused)
    end)

    it('leaves a function at_edge to core', function()
      local fake = h.reset_backend()
      assert.is_false(backend.move('left', { at_edge = nil }))
      assert.are.equal(0, fake.count('pane.split'))
    end)

    describe('with at_edge = wrap', function()
      it('focuses the pane on the opposite edge', function()
        local fake = h.reset_backend()
        assert.is_true(backend.move('left', { at_edge = 'wrap' }))
        assert.are.same({ pane_id = 'w1:p2' }, fake.first('pane.focus').params)
        assert.are.equal('w1:p2', fake.focused)
      end)

      it('stays in the same row', function()
        local fake = h.reset_backend(vim.tbl_extend('force', h.three_panes(), { focused = 'w1:p3' }))
        assert.is_true(backend.move('right', { at_edge = 'wrap' }))
        assert.are.equal('w1:p1', fake.focused)
      end)

      it('stays in the same column', function()
        local fake = h.reset_backend(vim.tbl_extend('force', h.three_panes(), { focused = 'w1:p2' }))
        assert.is_true(backend.move('up', { at_edge = 'wrap' }))
        assert.are.equal('w1:p3', fake.focused)
      end)

      it('leaves wrapping to core when herdr has a single pane', function()
        local fake = h.reset_backend(SINGLE)
        assert.is_false(backend.move('left', { at_edge = 'wrap' }))
        assert.are.equal(0, fake.count('pane.focus'))
      end)

      it('leaves wrapping to core when the pane spans the axis', function()
        local fake = h.reset_backend(vim.tbl_extend('force', h.three_panes(), { focused = 'w1:p1' }))
        assert.is_false(backend.move('up', { at_edge = 'wrap' }))
        assert.are.equal(0, fake.count('pane.focus'))
      end)

      it('walks to the far edge when the socket is out of reach', function()
        local fake =
          h.reset_backend(vim.tbl_extend('force', h.three_panes(), { focused = 'w1:p3', no_cli_focus = true }))
        assert.is_true(backend.move('right', { at_edge = 'wrap' }))
        assert.are.equal('w1:p1', fake.focused)
        local walk = fake.called('pane.focus_direction')
        assert.are.same({ pane_id = 'w1:p3', direction = 'left' }, walk[2].params)
        assert.are.same({ pane_id = 'w1:p1', direction = 'left' }, walk[3].params)
      end)
    end)

    describe('with at_edge = split', function()
      it('splits right and down directly', function()
        for direction, split in pairs({ right = 'right', down = 'down' }) do
          local fake = h.reset_backend(SINGLE)
          assert.is_true(backend.move(direction, { at_edge = 'split' }), direction)
          assert.are.same(
            { target_pane_id = 'w1:p1', direction = split, focus = true },
            fake.first('pane.split').params,
            direction
          )
          assert.are.equal(0, fake.count('pane.swap'), direction)
          assert.are.equal('w1:p2', fake.focused, direction)
        end
      end)

      it('splits then swaps for left and up', function()
        for direction, split in pairs({ left = 'right', up = 'down' }) do
          local fake = h.reset_backend(SINGLE)
          assert.is_true(backend.move(direction, { at_edge = 'split' }), direction)
          assert.are.equal(split, fake.first('pane.split').params.direction, direction)
          assert.are.same({ pane_id = 'w1:p2', direction = direction }, fake.first('pane.swap').params, direction)
          local new, old = fake.rect('w1:p2'), fake.rect('w1:p1')
          if direction == 'left' then
            assert.is_true(new.x < old.x, 'new pane should be on the left')
          else
            assert.is_true(new.y < old.y, 'new pane should be on top')
          end
        end
      end)

      it('still reports the split when the swap fails', function()
        h.reset_backend(vim.tbl_extend('force', SINGLE, { fail_on = { ['pane.swap'] = 'pane_not_found' } }))
        assert.is_true(backend.move('left', { at_edge = 'split' }))
      end)

      it('reports failure when herdr refuses to split', function()
        local fake =
          h.reset_backend(vim.tbl_extend('force', SINGLE, { fail_on = { ['pane.split'] = 'pane_not_found' } }))
        assert.is_false(backend.move('right', { at_edge = 'split' }))
        assert.are.equal(1, fake.count('pane.split'))
      end)
    end)
  end)

  describe('zoom', function()
    it('refuses to leave a zoomed pane by default', function()
      local fake = h.reset_backend({ zoomed = true })
      assert.is_false(backend.move('right'))
      assert.are.equal(0, fake.count('pane.focus_direction'))
    end)

    it('moves out of a zoomed pane when the option is off', function()
      local fake = h.reset_backend({ zoomed = true, config = { disable_nav_when_zoomed = false } })
      assert.is_true(backend.move('right'))
      assert.are.equal(0, fake.count('pane.edges'))
    end)
  end)

  describe('failures', function()
    it('returns false when herdr is unreachable', function()
      h.reset_backend({ fail = 'socket_connect_failed' })
      assert.is_false(backend.move('right'))
      assert.is_false(backend.move('right', { at_edge = 'wrap' }))
      assert.is_false(backend.move('right', { at_edge = 'split' }))
    end)

    it('returns false when herdr answers with an error', function()
      h.reset_backend({
        config = { disable_nav_when_zoomed = false },
        fail_on = { ['pane.focus_direction'] = 'pane_not_found' },
      })
      assert.is_false(backend.move('right'))
    end)

    it('returns false without asking herdr when disabled', function()
      local fake = h.reset_backend({ config = { enable = false } })
      assert.is_false(backend.move('right'))
      assert.are.equal(0, #fake.calls)
    end)

    it('returns false without asking herdr outside a session', function()
      local fake = h.reset_backend()
      h.leave_session()
      assert.is_false(backend.move('right'))
      assert.are.equal(0, #fake.calls)
    end)

    it('rejects unknown directions', function()
      local fake = h.reset_backend()
      ---@diagnostic disable-next-line: param-type-mismatch
      assert.is_false(backend.move('sideways'))
      assert.are.equal(0, #fake.calls)
    end)

    it('survives a handler that throws', function()
      h.reset_backend()
      require('smart-splits-backend-herdr.transport').set_handler(function()
        error('boom')
      end)
      assert.is_false(backend.move('right'))
    end)
  end)
end)
