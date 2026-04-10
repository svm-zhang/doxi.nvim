local importer = require("doxi.importer")
local util = require("doxi.util")

local M = {}

local function all_blank(lines)
  for _, line in ipairs(lines or {}) do
    if not util.is_blank(line) then
      return false
    end
  end

  return true
end

function M.classify_lines(lines)
  if not lines or #lines == 0 then
    return nil, "Visual-select an empty docstring line or a contiguous doctest block first."
  end

  if all_blank(lines) then
    return {
      kind = "blank",
      indent = util.get_indent(lines[1] or ""),
      editor_lines = {},
    }
  end

  local imported, err = importer.parse_doctest_block(lines)
  if not imported then
    return nil, err
  end

  return {
    kind = "doctest",
    indent = imported.indent,
    editor_lines = imported.source_lines,
  }
end

function M.build_target(opts)
  if vim.bo[opts.bufnr].filetype ~= "python" then
    return nil, "doxi.nvim only supports Python buffers."
  end

  if not util.selection_in_python_docstring(opts.bufnr, opts.start_row, opts.end_row) then
    return nil, "Select an empty docstring line or doctest block inside a Python docstring."
  end

  local lines = vim.api.nvim_buf_get_lines(opts.bufnr, opts.start_row - 1, opts.end_row, false)
  local classified, err = M.classify_lines(lines)
  if not classified then
    return nil, err
  end

  return {
    kind = classified.kind,
    source_bufnr = opts.bufnr,
    source_range = {
      start_row = opts.start_row,
      end_row = opts.end_row,
    },
    source_indent = classified.indent,
    source_lines_snapshot = lines,
    editor_lines = classified.editor_lines,
  }
end

return M
