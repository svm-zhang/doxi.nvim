local shared_imports = require("doxi.shared_imports")
local util = require("doxi.util")

local M = {}

local function trim(line)
  return vim.trim(line or "")
end

local function is_numpy_underline(line)
  return trim(line):match("^%-+$") ~= nil
end

local function find_examples_header(lines, start_row)
  for index, line in ipairs(lines or {}) do
    local stripped = trim(line)

    if stripped == "Examples:" then
      local row = start_row + index - 1
      return {
        kind = "google",
        header_row = row,
        body_start_row = row + 1,
      }
    end

    if stripped == "Examples" and is_numpy_underline(lines[index + 1]) then
      local row = start_row + index - 1
      return {
        kind = "numpy",
        header_row = row,
        underline_row = row + 1,
        body_start_row = row + 2,
      }
    end
  end

  return nil
end

function M.build(opts)
  local docstring, err = util.resolve_python_docstring(opts.bufnr, opts.start_row, opts.end_row)
  if not docstring then
    return nil, err or "Select an example block or blank line inside a supported Examples section."
  end

  local lines = vim.api.nvim_buf_get_lines(
    opts.bufnr,
    docstring.start_row - 1,
    docstring.end_row,
    false
  )

  local header = find_examples_header(lines, docstring.start_row)
  if not header then
    return nil, "Select an example block or blank line inside a supported Examples section."
  end

  if opts.start_row < header.body_start_row then
    return nil, "Select an example block or blank line inside a supported Examples section."
  end

  local imports, imports_err = shared_imports.discover({
    bufnr = opts.bufnr,
    start_row = header.body_start_row,
    end_row = opts.start_row - 1,
  })
  if not imports then
    return nil, imports_err
  end

  return {
    docstring = docstring,
    header = header,
    shared_imports = imports,
  }
end

return M
