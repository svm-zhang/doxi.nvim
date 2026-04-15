local util = require("doxi.util")

local M = {}

local import_statement_types = {
  import_statement = true,
  import_from_statement = true,
}

local function empty_shared_imports()
  return {
    ordered = {},
    seen = {},
  }
end

local function strip_base_indent(lines)
  local base_indent = util.common_indent(lines)
  local stripped = {}

  for _, line in ipairs(lines or {}) do
    table.insert(stripped, util.strip_prefix(line, base_indent))
  end

  return stripped
end

local function prompt_content(line, prefix)
  if line == prefix:sub(1, #prefix - 1) then
    return ""
  end

  if line:sub(1, #prefix) == prefix then
    return line:sub(#prefix + 1)
  end

  return nil
end

local function collect_leading_statements(lines)
  local stripped = strip_base_indent(lines)
  local statements = {}
  local current_statement = nil
  local saw_prompt = false
  local saw_output_since_prompt = false

  local function flush_statement()
    if current_statement == nil then
      return
    end

    table.insert(statements, current_statement)
    current_statement = nil
  end

  for _, line in ipairs(stripped) do
    if util.is_blank(line) then
      flush_statement()
      saw_output_since_prompt = false
    else
      local statement = prompt_content(line, ">>> ")
      if statement ~= nil then
        saw_prompt = true
        flush_statement()
        current_statement = { statement }
        saw_output_since_prompt = false
      else
        local continuation = prompt_content(line, "... ")
        if continuation ~= nil then
          if current_statement ~= nil and not saw_output_since_prompt then
            table.insert(current_statement, continuation)
          else
            return statements
          end
        else
          if not saw_prompt then
            return {}
          end

          if current_statement == nil then
            return statements
          end

          saw_output_since_prompt = true
        end
      end
    end
  end

  flush_statement()

  return statements
end

function M._parse_statement(statement_source, parser_factory)
  local parser_source = statement_source
  if parser_source ~= "" and parser_source:sub(-1) ~= "\n" then
    parser_source = parser_source .. "\n"
  end

  local factory = parser_factory or vim.treesitter.get_string_parser
  local ok, parser_or_err = pcall(factory, parser_source, "python")
  if not ok or not parser_or_err then
    return nil, util._python_treesitter_required_message()
  end

  local trees = parser_or_err:parse()
  local tree = trees and trees[1]
  if not tree then
    return nil, "Failed to parse shared import statement."
  end

  return tree:root()
end

function M._is_import_statement(statement_source, parser_factory)
  local root, err = M._parse_statement(statement_source, parser_factory)
  if not root then
    return nil, err
  end

  local first = root:named_child(0)
  if not first then
    return false
  end

  return import_statement_types[first:type()] == true
end

function M.discover(opts)
  if not opts or not opts.bufnr or not opts.start_row or not opts.end_row or opts.end_row < opts.start_row then
    return empty_shared_imports()
  end

  local lines = vim.api.nvim_buf_get_lines(opts.bufnr, opts.start_row - 1, opts.end_row, false)
  local statements = collect_leading_statements(lines)
  local imports = empty_shared_imports()

  for _, statement_lines in ipairs(statements) do
    local statement_source = table.concat(statement_lines, "\n")
    local is_import, err = M._is_import_statement(statement_source, opts.parser_factory)
    if is_import == nil then
      return nil, err
    end

    if not is_import then
      break
    end

    if not imports.seen[statement_source] then
      imports.seen[statement_source] = true
      table.insert(imports.ordered, statement_source)
    end
  end

  return imports
end

function M.render_lines(imports)
  if not imports or not imports.ordered or #imports.ordered == 0 then
    return { "No shared imports" }
  end

  local lines = {}

  for _, statement in ipairs(imports.ordered) do
    for chunk in (statement .. "\n"):gmatch("(.-)\n") do
      table.insert(lines, chunk)
    end
  end

  return lines
end

return M
