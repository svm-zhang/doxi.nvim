local util = require("doxi.util")

local M = {}

function M.indent_transcript(lines, indent)
  local indented = {}

  for _, line in ipairs(lines or {}) do
    table.insert(indented, indent .. line)
  end

  return indented
end

function M.insert(target, transcript_lines)
  if not (target and target.bufnr and vim.api.nvim_buf_is_valid(target.bufnr)) then
    return nil, "The source buffer is no longer available."
  end

  if not transcript_lines or #transcript_lines == 0 then
    return nil, "Run some code before inserting a transcript."
  end

  local current_line = vim.api.nvim_buf_get_lines(target.bufnr, target.row - 1, target.row, false)[1] or ""
  if current_line ~= target.line_snapshot then
    return nil, "The source location changed before insertion. Aborting."
  end

  local replacement = M.indent_transcript(transcript_lines, target.indent or "")

  vim.api.nvim_buf_set_lines(target.bufnr, target.row - 1, target.row - 1, false, replacement)
  return true
end

function M.replace(target, transcript_lines)
  if not (target and target.bufnr and vim.api.nvim_buf_is_valid(target.bufnr)) then
    return nil, "The source buffer is no longer available."
  end

  if not transcript_lines or #transcript_lines == 0 then
    return nil, "Run some code before replacing a transcript."
  end

  local current_lines = vim.api.nvim_buf_get_lines(
    target.bufnr,
    target.start_row - 1,
    target.end_row,
    false
  )

  if not util.table_equals(current_lines, target.lines_snapshot) then
    return nil, "The selected source range changed before apply. Aborting."
  end

  local replacement = M.indent_transcript(transcript_lines, target.indent or "")
  local leading_blank_lines = vim.deepcopy(target.leading_blank_lines or {})
  local trailing_blank_lines = vim.deepcopy(target.trailing_blank_lines or {})

  if #leading_blank_lines > 0 then
    vim.list_extend(leading_blank_lines, replacement)
    replacement = leading_blank_lines
  end

  vim.list_extend(replacement, trailing_blank_lines)

  vim.api.nvim_buf_set_lines(target.bufnr, target.start_row - 1, target.end_row, false, replacement)
  return true
end

return M
