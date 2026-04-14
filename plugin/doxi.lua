local compat = require("doxi.compat")

local ok, message = compat.check_ready()
if not ok then
  vim.api.nvim_echo({ { message, "ErrorMsg" } }, true, {})
  return
end

if vim.g.loaded_doxi == 1 then
  return
end

vim.g.loaded_doxi = 1

require("doxi").ensure_setup()
