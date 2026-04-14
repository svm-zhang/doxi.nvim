local importer = require("doxi.importer")
local util = require("doxi.util")

local M = {}
local example_indent = "    "

local function all_blank(lines)
  for _, line in ipairs(lines or {}) do
    if not util.is_blank(line) then
      return false
    end
  end

  return true
end

local function split_outer_blank_lines(lines)
  local first_nonblank = 1
  local last_nonblank = #lines

  while first_nonblank <= #lines and util.is_blank(lines[first_nonblank]) do
    first_nonblank = first_nonblank + 1
  end

  while last_nonblank >= first_nonblank and util.is_blank(lines[last_nonblank]) do
    last_nonblank = last_nonblank - 1
  end

  local leading = {}
  for index = 1, first_nonblank - 1 do
    table.insert(leading, lines[index])
  end

  local core = {}
  for index = first_nonblank, last_nonblank do
    table.insert(core, lines[index])
  end

  local trailing = {}
  for index = last_nonblank + 1, #lines do
    table.insert(trailing, lines[index])
  end

  return leading, core, trailing
end

local function get_line(bufnr, row)
  return vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
end

local function trimmed(line)
  return vim.trim(line or "")
end

local function is_docstring_delimiter(line)
  local stripped = trimmed(line)
  return stripped == '"""' or stripped == "'''"
end

local function is_examples_header(line)
  return trimmed(line) == "Examples:"
end

local function is_prompt_line(line)
  local stripped = trimmed(line)
  return stripped:sub(1, 4) == ">>> " or stripped:sub(1, 4) == "... "
end

local function find_previous_nonblank(bufnr, row)
  for current = row, 1, -1 do
    local line = get_line(bufnr, current)
    if is_docstring_delimiter(line) then
      return {
        row = current,
        line = line,
        delimiter = true,
      }
    end

    if not util.is_blank(line) then
      return {
        row = current,
        line = line,
        delimiter = false,
      }
    end
  end

  return nil
end

local function find_next_nonblank(bufnr, row)
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for current = row, line_count do
    local line = get_line(bufnr, current)
    if is_docstring_delimiter(line) then
      return {
        row = current,
        line = line,
        delimiter = true,
      }
    end

    if not util.is_blank(line) then
      return {
        row = current,
        line = line,
        delimiter = false,
      }
    end
  end

  return nil
end

local function indent_from_context(context)
  if not context then
    return nil
  end

  if is_examples_header(context.line) then
    return util.get_indent(context.line) .. example_indent
  end

  return util.get_indent(context.line)
end

local function infer_indent(bufnr, start_row, end_row, kind, fallback_indent)
  local previous = find_previous_nonblank(bufnr, start_row - 1)
  local next = find_next_nonblank(bufnr, end_row + 1)

  if kind == "blank" then
    if previous and is_examples_header(previous.line) then
      return indent_from_context(previous)
    end

    if next and not next.delimiter then
      return indent_from_context(next)
    end

    if previous then
      return indent_from_context(previous)
    end
  end

  if fallback_indent and fallback_indent ~= "" then
    return fallback_indent
  end

  if previous and not previous.delimiter then
    return indent_from_context(previous)
  end

  if next and not next.delimiter then
    return indent_from_context(next)
  end

  if previous then
    return indent_from_context(previous)
  end

  if next then
    return indent_from_context(next)
  end

  return fallback_indent or ""
end

local function has_doctest_region_above(bufnr, start_row)
  local saw_content = false

  for current = start_row - 1, 1, -1 do
    local line = get_line(bufnr, current)

    if is_docstring_delimiter(line) then
      break
    end

    if util.is_blank(line) then
      if saw_content then
        break
      end
    else
      saw_content = true

      if is_prompt_line(line) then
        return true
      end
    end
  end

  return false
end

function M.classify_lines(lines)
  if not lines or #lines == 0 then
    return nil, "Visual-select an empty docstring line or a contiguous doctest block first."
  end

  if all_blank(lines) then
    return {
      kind = "blank",
      indent = util.get_indent(lines[1] or ""),
      leading_blank_lines = {},
      trailing_blank_lines = vim.deepcopy(lines),
      editor_lines = {},
    }
  end

  local leading_blank_lines, core_lines, trailing_blank_lines = split_outer_blank_lines(lines)
  local imported, err = importer.parse_doctest_block(core_lines)
  if not imported then
    return nil, err
  end

  return {
    kind = "doctest",
    indent = imported.indent,
    leading_blank_lines = leading_blank_lines,
    trailing_blank_lines = trailing_blank_lines,
    editor_lines = imported.source_lines,
  }
end

function M.build_target(opts)
  if vim.bo[opts.bufnr].filetype ~= "python" then
    return nil, "doxi.nvim only supports Python buffers."
  end

  local in_docstring, docstring_err = util.selection_in_python_docstring(opts.bufnr, opts.start_row, opts.end_row)
  if not in_docstring then
    return nil, docstring_err or "Select an empty docstring line or doctest block inside a Python docstring."
  end

  local lines = vim.api.nvim_buf_get_lines(opts.bufnr, opts.start_row - 1, opts.end_row, false)
  local classified, err = M.classify_lines(lines)
  if not classified then
    return nil, err
  end

  local source_indent = infer_indent(
    opts.bufnr,
    opts.start_row,
    opts.end_row,
    classified.kind,
    classified.indent
  )
  local source_leading_blank_lines = classified.leading_blank_lines or {}

  if classified.kind == "blank" and has_doctest_region_above(opts.bufnr, opts.start_row) then
    source_leading_blank_lines = { source_indent }
  end

  return {
    kind = classified.kind,
    source_bufnr = opts.bufnr,
    source_range = {
      start_row = opts.start_row,
      end_row = opts.end_row,
    },
    source_indent = source_indent,
    source_lines_snapshot = lines,
    source_leading_blank_lines = source_leading_blank_lines,
    source_trailing_blank_lines = classified.trailing_blank_lines or {},
    editor_lines = classified.editor_lines,
  }
end

return M
