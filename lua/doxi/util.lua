local compat = require("doxi.compat")

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

function M.normalize_line_range(start_row, end_row)
  if not start_row or not end_row or start_row == 0 or end_row == 0 then
    return nil
  end

  if start_row > end_row then
    start_row, end_row = end_row, start_row
  end

  return start_row, end_row
end

local function is_active_visual_mode(mode)
  return mode == "v"
    or mode == "V"
    or mode == "\22"
    or mode == "s"
    or mode == "S"
    or mode == "\19"
end

function M.get_visual_line_range()
  local mode = vim.api.nvim_get_mode().mode

  if is_active_visual_mode(mode) then
    local anchor = vim.fn.getpos("v")
    local cursor = vim.api.nvim_win_get_cursor(0)
    return M.normalize_line_range(anchor[2], cursor[1])
  end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  return M.normalize_line_range(start_pos[2], end_pos[2])
end

function M.escape_visual_mode()
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)
end

local function node_type(node)
  if not node then
    return nil
  end

  return node:type()
end

local function node_parent(node)
  if not node then
    return nil
  end

  return node:parent()
end

local function node_named_child(node, index)
  if not node then
    return nil
  end

  return node:named_child(index)
end

local function node_range(node)
  if not node then
    return nil
  end

  if type(node.range) == "function" then
    return node:range()
  end

  return vim.treesitter.get_node_range(node)
end

function M._python_treesitter_required_message()
  return compat.python_parser_message()
end

function M._same_node(left, right)
  if not left or not right then
    return false
  end

  if left == right then
    return true
  end

  if type(left.equal) == "function" then
    return left:equal(right)
  end

  return false
end

function M._is_string_like_node(node)
  local kind = node_type(node)
  return kind == "string" or kind == "concatenated_string"
end

function M._first_named_child(node)
  return node_named_child(node, 0)
end

function M._is_first_named_child(parent, node)
  return M._same_node(M._first_named_child(parent), node)
end

function M._node_contains_row(node, row)
  local start_row, _, end_row, _ = node_range(node)
  if start_row == nil then
    return false
  end

  local zero_based_row = row - 1
  return start_row <= zero_based_row and zero_based_row <= end_row
end

function M._is_canonical_docstring_node(node)
  if not M._is_string_like_node(node) then
    return false
  end

  local statement = node_parent(node)
  if node_type(statement) ~= "expression_statement" then
    return false
  end

  if not M._is_first_named_child(statement, node) then
    return false
  end

  local container = node_parent(statement)
  local container_type = node_type(container)

  if container_type == "module" then
    return M._is_first_named_child(container, statement)
  end

  if container_type ~= "block" then
    return false
  end

  if not M._is_first_named_child(container, statement) then
    return false
  end

  local owner = node_parent(container)
  local owner_type = node_type(owner)

  return owner_type == "function_definition"
    or owner_type == "async_function_definition"
    or owner_type == "class_definition"
end

function M._find_canonical_docstring_node(node)
  local current = node

  while current do
    if M._is_canonical_docstring_node(current) then
      return current
    end

    current = node_parent(current)
  end

  return nil
end

function M._get_python_parser(bufnr)
  if not vim.treesitter or type(vim.treesitter.get_parser) ~= "function" then
    return nil, M._python_treesitter_required_message()
  end

  local parser = vim.treesitter.get_parser(bufnr, "python")
  if not parser then
    return nil, M._python_treesitter_required_message()
  end

  return parser
end

function M._get_python_node_at_row(bufnr, row)
  local parser, err = M._get_python_parser(bufnr)
  if not parser then
    return nil, err
  end

  local row_index = math.max(row - 1, 0)
  local line = vim.api.nvim_buf_get_lines(bufnr, row_index, row_index + 1, false)[1] or ""
  local range = {
    row_index,
    0,
    row_index,
    #line,
  }

  parser:parse(range)

  return parser:named_node_for_range(range, {
    ignore_injections = true,
  })
end

function M.selection_in_python_docstring(bufnr, start_row, end_row)
  if vim.bo[bufnr].filetype ~= "python" then
    return false
  end

  local start_node, start_err = M._get_python_node_at_row(bufnr, start_row)
  if not start_node then
    if start_err then
      return nil, start_err
    end

    return false
  end

  local end_node, end_err = M._get_python_node_at_row(bufnr, end_row)
  if not end_node then
    if end_err then
      return nil, end_err
    end

    return false
  end

  local start_docstring = M._find_canonical_docstring_node(start_node)
  local end_docstring = M._find_canonical_docstring_node(end_node)

  if not start_docstring or not end_docstring then
    return false
  end

  if not M._same_node(start_docstring, end_docstring) then
    return false
  end

  if not M._node_contains_row(start_docstring, start_row)
    or not M._node_contains_row(start_docstring, end_row)
  then
    return false
  end

  return true
end

return M
