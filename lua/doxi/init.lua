local commands = require("doxi.commands")
local config = require("doxi.config")

local M = {}

local did_setup = false

function M.setup(opts)
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

return M
