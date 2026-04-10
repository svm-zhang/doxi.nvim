if vim.g.loaded_doxi == 1 then
  return
end

vim.g.loaded_doxi = 1

require("doxi").ensure_setup()
