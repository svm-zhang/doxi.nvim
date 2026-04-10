local M = {}

local function get_json_encode()
  return (vim.json and vim.json.encode) or vim.fn.json_encode
end

local function get_json_decode()
  return (vim.json and vim.json.decode) or vim.fn.json_decode
end

M.json_encode = get_json_encode()
M.json_decode = get_json_decode()

function M.notify(message, level)
  vim.schedule(function()
    vim.notify(message, level or vim.log.levels.INFO, {
      title = "doxi.nvim",
    })
  end)
end

function M.join_paths(...)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end

  local parts = {}
  for _, part in ipairs({ ... }) do
    if part and part ~= "" then
      table.insert(parts, tostring(part))
    end
  end

  return table.concat(parts, "/")
end

function M.get_plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
end

function M.is_blank(line)
  return line == nil or line:match("^%s*$") ~= nil
end

function M.get_indent(line)
  return (line or ""):match("^(%s*)") or ""
end

function M.common_indent(lines)
  local indent

  for _, line in ipairs(lines or {}) do
    if not M.is_blank(line) then
      local current = M.get_indent(line)
      if indent == nil or #current < #indent then
        indent = current
      end
    end
  end

  return indent or ""
end

function M.strip_prefix(text, prefix)
  if prefix == "" then
    return text
  end

  if text:sub(1, #prefix) == prefix then
    return text:sub(#prefix + 1)
  end

  return text
end

function M.table_equals(left, right)
  if type(left) ~= type(right) then
    return false
  end

  if type(left) ~= "table" then
    return left == right
  end

  for key, value in pairs(left) do
    if not M.table_equals(value, right[key]) then
      return false
    end
  end

  for key, value in pairs(right) do
    if not M.table_equals(value, left[key]) then
      return false
    end
  end

  return true
end

function M.with_modifiable(bufnr, fn)
  local modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
  local readonly = vim.api.nvim_get_option_value("readonly", { buf = bufnr })

  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  if readonly then
    vim.api.nvim_set_option_value("readonly", false, { buf = bufnr })
  end

  local ok, result = pcall(fn)

  vim.api.nvim_set_option_value("modifiable", modifiable, { buf = bufnr })
  vim.api.nvim_set_option_value("readonly", readonly, { buf = bufnr })

  if not ok then
    error(result)
  end

  return result
end

function M.set_buf_lines(bufnr, lines)
  M.with_modifiable(bufnr, function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or {})
  end)
end

function M.close_win(winid)
  if winid and vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
end

function M.delete_buf(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
end

function M.get_visual_line_range()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_row = start_pos[2]
  local end_row = end_pos[2]

  if start_row == 0 or end_row == 0 then
    return nil
  end

  if start_row > end_row then
    start_row, end_row = end_row, start_row
  end

  return start_row, end_row
end

function M.escape_visual_mode()
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)
end

function M.probably_in_python_docstring(bufnr, row)
  if vim.bo[bufnr].filetype ~= "python" then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, row, false)
  local active_delimiter = nil

  for _, line in ipairs(lines) do
    local index = 1
    while true do
      local triple_double = line:find('"""', index, true)
      local triple_single = line:find("'''", index, true)
      local position
      local delimiter

      if triple_double and triple_single then
        if triple_double < triple_single then
          position = triple_double
          delimiter = '"""'
        else
          position = triple_single
          delimiter = "'''"
        end
      elseif triple_double then
        position = triple_double
        delimiter = '"""'
      elseif triple_single then
        position = triple_single
        delimiter = "'''"
      else
        break
      end

      if active_delimiter == delimiter then
        active_delimiter = nil
      elseif active_delimiter == nil then
        active_delimiter = delimiter
      end

      index = position + 3
    end
  end

  return active_delimiter ~= nil
end

return M
