local util = require("doxi.util")

local M = {}

local function prompt_content(line, prefix)
  if line == prefix:sub(1, #prefix - 1) then
    return ""
  end

  if line:sub(1, #prefix) == prefix then
    return line:sub(#prefix + 1)
  end

  return nil
end

function M.strip_base_indent(lines, base_indent)
  local stripped = {}

  for _, line in ipairs(lines or {}) do
    table.insert(stripped, util.strip_prefix(line, base_indent))
  end

  return stripped
end

function M.parse_doctest_block(lines)
  if not lines or #lines == 0 then
    return nil, "Select a contiguous doctest block first."
  end

  local base_indent = util.common_indent(lines)
  local stripped = M.strip_base_indent(lines, base_indent)
  local source_lines = {}
  local current_statement = nil
  local saw_prompt = false
  local saw_output_since_prompt = false

  local function flush_statement()
    if current_statement == nil then
      return
    end

    vim.list_extend(source_lines, current_statement)
    current_statement = nil
  end

  for index, line in ipairs(stripped) do
    local statement = prompt_content(line, ">>> ")
    if statement ~= nil then
      saw_prompt = true
      flush_statement()
      current_statement = { statement }
      saw_output_since_prompt = false
    else
      local continuation = prompt_content(line, "... ")
      if continuation ~= nil and current_statement ~= nil and not saw_output_since_prompt then
        if current_statement == nil then
          return nil,
            ("Invalid doctest block: continuation without a statement at line %d."):format(index)
        end

        table.insert(current_statement, continuation)
      else
        if not saw_prompt then
          return nil, "Selection does not start with a doctest prompt."
        end

        if current_statement ~= nil then
          saw_output_since_prompt = true
        end
      end
    end
  end

  flush_statement()

  if not saw_prompt then
    return nil, "Selection does not contain doctest prompts."
  end

  return {
    indent = base_indent,
    source_lines = source_lines,
  }
end

return M
