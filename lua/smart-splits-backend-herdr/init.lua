local config = require('smart-splits-backend-herdr.config')
local health = require('smart-splits-backend-herdr.health')
local herdr = require('smart-splits-backend-herdr.herdr')
local move = require('smart-splits-backend-herdr.move')
local resize = require('smart-splits-backend-herdr.resize')

---@class HerdrBackend: SmartSplitsBackend
---@field setup fun(opts?: HerdrBackend.PartialConfig)
local M = {
  name = 'herdr',
  protocol_version = '3.0.0',
  ---Configuration only. Core never calls this, and being configured says
  ---nothing about being selected, so it stays free of side effects.
  ---@param opts? HerdrBackend.PartialConfig
  setup = function(opts)
    config.setup(opts)
  end,
  ---Cheap and side-effect free, as the protocol requires: herdr sets
  ---`$HERDR_ENV` and `$HERDR_PANE_ID` for every process it starts in a pane.
  detect = function()
    return config.options.enable and herdr.in_session()
  end,
  move = move.move,
  resize = resize.resize,
  health = health.report,
}

return M
