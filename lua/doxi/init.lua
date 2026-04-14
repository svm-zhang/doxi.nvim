local compat = require("doxi.compat")
local commands = require("doxi.commands")
local config = require("doxi.config")

local M = {}

local did_setup = false

function M.setup(opts)
  compat.assert_ready()
  config.setup(opts or {})
  commands.setup()
  did_setup = true
end

function M.ensure_setup()
  if did_setup then
    return
  end

  M.setup()
end

function M.open_visual()
  M.ensure_setup()
  require("doxi.session").open_visual()
end

return M
