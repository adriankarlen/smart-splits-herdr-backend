local h = require('tests.helpers')

local layout = require('smart-splits-backend-herdr.layout')

---@param opts FakeHerdr.Opts
---@return HerdrBackend.Layout
local function snapshot(opts)
  return {
    workspace_id = 'w1',
    tab_id = 'w1:t1',
    zoomed = false,
    area = opts.area or { x = 0, y = 0, width = 120, height = 40 },
    focused_pane_id = 'w1:p1',
    panes = vim.tbl_map(function(p)
      return { pane_id = p.pane_id, focused = false, rect = p.rect }
    end, opts.panes),
    splits = opts.splits or {},
  }
end

---Four panes: two columns, the right one split, and its bottom half split again.
---
---    +-------+---------------+
---    |       |      p2       |
---    |  p1   +-------+-------+
---    |       |  p3   |  p4   |
---    +-------+-------+-------+
local FOUR = snapshot({
  panes = {
    { pane_id = 'w1:p1', rect = { x = 0, y = 0, width = 48, height = 40 } },
    { pane_id = 'w1:p2', rect = { x = 48, y = 0, width = 72, height = 20 } },
    { pane_id = 'w1:p3', rect = { x = 48, y = 20, width = 36, height = 20 } },
    { pane_id = 'w1:p4', rect = { x = 84, y = 20, width = 36, height = 20 } },
  },
  splits = {
    { id = 'split_0_root', direction = 'right', ratio = 0.39999998, rect = { x = 0, y = 0, width = 120, height = 40 } },
    { id = 'split_1_1', direction = 'down', ratio = 0.5, rect = { x = 48, y = 0, width = 72, height = 40 } },
    { id = 'split_2_11', direction = 'right', ratio = 0.5, rect = { x = 48, y = 20, width = 72, height = 20 } },
  },
})

describe('layout.wrap_target()', function()
  it('picks the pane on the opposite edge in the same row', function()
    assert.are.equal('w1:p1', layout.wrap_target(FOUR, 'w1:p4', 'right'))
    assert.are.equal('w1:p1', layout.wrap_target(FOUR, 'w1:p2', 'right'))
  end)

  it('picks the pane on the opposite edge in the same column', function()
    assert.are.equal('w1:p2', layout.wrap_target(FOUR, 'w1:p3', 'down'))
    assert.are.equal('w1:p2', layout.wrap_target(FOUR, 'w1:p4', 'down'))
  end)

  it('breaks ties by distance, then by order', function()
    -- p1 spans both rows; p2 and p4 share as much of it, p2 comes first
    assert.are.equal('w1:p2', layout.wrap_target(FOUR, 'w1:p1', 'left'))
    -- p3 and p4 share as much of p2's column and sit as far from its centre
    assert.are.equal('w1:p3', layout.wrap_target(FOUR, 'w1:p2', 'up'))
  end)

  it('returns nil when the pane spans the axis', function()
    assert.is_nil(layout.wrap_target(FOUR, 'w1:p1', 'up'))
  end)

  it('returns nil for unknown panes or missing layouts', function()
    assert.is_nil(layout.wrap_target(FOUR, 'w1:p9', 'left'))
    assert.is_nil(layout.wrap_target(nil, 'w1:p1', 'left'))
  end)
end)

describe('layout.resize_fraction()', function()
  it('uses the split on the side being resized', function()
    -- p3's right border is the inner split, 72 cells wide
    assert.are.equal(6 / 72, layout.resize_fraction(FOUR, 'w1:p3', 'right', 6))
    -- p3's left border is the root split, 120 cells wide
    assert.are.equal(6 / 120, layout.resize_fraction(FOUR, 'w1:p3', 'left', 6))
  end)

  it('falls back to the opposite border at the outer edge', function()
    -- p4 has no right border, herdr moves its left one: the inner split
    assert.are.equal(6 / 72, layout.resize_fraction(FOUR, 'w1:p4', 'right', 6))
    -- p1 has no left border, herdr moves its right one: the root split
    assert.are.equal(6 / 120, layout.resize_fraction(FOUR, 'w1:p1', 'left', 6))
  end)

  it('handles vertical resizes', function()
    assert.are.equal(4 / 40, layout.resize_fraction(FOUR, 'w1:p2', 'down', 4))
    assert.are.equal(4 / 40, layout.resize_fraction(FOUR, 'w1:p4', 'up', 4))
  end)

  it('falls back to the tab size when no split matches', function()
    local single = snapshot({ panes = { { pane_id = 'w1:p1', rect = { x = 0, y = 0, width = 120, height = 40 } } } })
    assert.are.equal(4 / 40, layout.resize_fraction(single, 'w1:p1', 'up', 4))
  end)

  it('never asks for more than the whole split', function()
    assert.are.equal(1, layout.resize_fraction(FOUR, 'w1:p2', 'down', 400))
  end)

  it('rejects nonsense', function()
    assert.is_nil(layout.resize_fraction(FOUR, 'w1:p1', 'left', 0))
    assert.is_nil(layout.resize_fraction(FOUR, 'w1:p9', 'left', 3))
    assert.is_nil(layout.resize_fraction(nil, 'w1:p1', 'left', 3))
  end)

  it('agrees with the fake used elsewhere', function()
    local opts = h.three_panes()
    local snap = snapshot(opts)
    assert.are.equal(12 / 120, layout.resize_fraction(snap, 'w1:p1', 'right', 12))
  end)
end)
