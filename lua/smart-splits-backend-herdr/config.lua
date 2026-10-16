---Options for the herdr backend. Storing them is all this module does: a backend
---that is merely configured may not be the one that ends up selected, so every
---side effect belongs in `activate()` instead.
---@class HerdrBackend.Config
---@field enable boolean whether this backend may be selected at all
---@field disable_nav_when_zoomed boolean refuse to move out of a zoomed herdr pane
---@field resize_amount integer cells to resize by when the caller names no amount
---@field timeout integer milliseconds to wait for herdr to answer
---@field transport HerdrBackend.Transport how to reach the herdr server

---@alias HerdrBackend.Transport
---| 'auto' # the socket in `$HERDR_SOCKET_PATH`, falling back to the `herdr` CLI
---| 'socket' # the socket only
---| 'cli' # the `herdr` CLI only

---@class HerdrBackend.PartialConfig
---@field enable? boolean
---@field disable_nav_when_zoomed? boolean
---@field resize_amount? integer
---@field timeout? integer
---@field transport? HerdrBackend.Transport

local M = {}

---@type HerdrBackend.Config
M.defaults = {
  enable = true,
  disable_nav_when_zoomed = true,
  -- smart-splits' own default
  resize_amount = 3,
  -- these run on every keypress at a window edge; a herdr that is not answering
  -- should degrade to plain Neovim movement rather than stall the editor
  timeout = 300,
  transport = 'auto',
}

---@type HerdrBackend.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? HerdrBackend.PartialConfig
---@return HerdrBackend.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.defaults, opts or {})
  return M.options
end

return M
