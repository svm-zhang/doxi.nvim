local shared_imports = require("doxi.shared_imports")
local util = require("doxi.util")

local M = {}

local function trim(line)
  return vim.trim(line or "")
end

local function is_numpy_underline(line)
  return trim(line):match("^%-+$") ~= nil
end

local function is_doctest_prompt_line(line)
  local stripped = trim(line)
  return stripped:sub(1, 4) == ">>> " or stripped:sub(1, 4) == "... " or stripped == ">>>" or stripped == "..."
end

local function find_examples_headers(lines, start_row)
  local headers = {}
  local in_doctest_block = false

  for index, line in ipairs(lines or {}) do
    local stripped = trim(line)

    if stripped == "" then
      in_doctest_block = false
    elseif is_doctest_prompt_line(line) then
      in_doctest_block = true
    elseif not in_doctest_block and stripped == "Examples:" then
      local row = start_row + index - 1
      table.insert(headers, {
        kind = "google",
        header_row = row,
        body_start_row = row + 1,
      })
    elseif not in_doctest_block and stripped == "Examples" and is_numpy_underline(lines[index + 1]) then
      local row = start_row + index - 1
      table.insert(headers, {
        kind = "numpy",
        header_row = row,
        underline_row = row + 1,
        body_start_row = row + 2,
      })
    end
  end

  return headers
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

  local headers = find_examples_headers(lines, docstring.start_row)
  if #headers == 0 then
    return nil, "Select an example block or blank line inside a supported Examples section."
  end

  if #headers > 1 then
    return nil, "doxi.nvim supports only one Examples section per docstring."
  end

  local header = headers[1]
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
