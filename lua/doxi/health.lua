local compat = require("doxi.compat")

local M = {}

function M.check()
  vim.health.start("doxi.nvim")

  local version_ok, version_message = compat.check()
  if version_ok then
    vim.health.ok(("Neovim %s+ is supported."):format(compat.minimum_string()))
  else
    vim.health.error(version_message)
  end

  local parser_ok, parser_message = compat.check_python_parser()
  if parser_ok then
    vim.health.ok("Python Treesitter parser is available.")
  else
    vim.health.error(parser_message, {
      "Install the `python` Treesitter parser.",
      "The most common setup path is via nvim-treesitter.",
      "Restart Neovim after installing the parser.",
    })
  end
end

return M
