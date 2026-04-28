local util = require("doxi.util")

local M = {}

local block_openers = {
  ["if"] = true,
  ["elif"] = true,
  ["else"] = true,
  ["for"] = true,
  ["while"] = true,
  ["try"] = true,
  ["except"] = true,
  ["finally"] = true,
  ["with"] = true,
  ["def"] = true,
  ["class"] = true,
  ["async def"] = true,
  ["async for"] = true,
  ["async with"] = true,
  ["match"] = true,
  ["case"] = true,
}

local function prompt_content(line, prefix)
  if line == prefix:sub(1, #prefix - 1) then
    return ""
  end

  if line:sub(1, #prefix) == prefix then
    return line:sub(#prefix + 1)
  end

  return nil
end

local function line_indent_width(line)
  local indent = util.get_indent(line)
  local width = 0

  for index = 1, #indent do
    if indent:sub(index, index) == "\t" then
      width = width + 4
    else
      width = width + 1
    end
  end

  return width
end

local function strip_comment(line)
  local quote = nil
  local triple = false
  local escaped = false
  local index = 1

  while index <= #line do
    local char = line:sub(index, index)
    local next_two = line:sub(index, index + 2)

    if quote then
      if escaped then
        escaped = false
      elseif char == "\\" then
        escaped = true
      elseif triple and next_two == quote .. quote .. quote then
        quote = nil
        triple = false
        index = index + 2
      elseif not triple and char == quote then
        quote = nil
      end
    elseif char == "'" or char == '"' then
      quote = char
      triple = next_two == char .. char .. char
      if triple then
        index = index + 2
      end
    elseif char == "#" then
      return line:sub(1, index - 1)
    end

    index = index + 1
  end

  return line
end

local function block_keyword(line)
  local without_comment = vim.trim(strip_comment(line or ""))

  if without_comment:sub(-1) ~= ":" then
    return nil
  end

  local header = vim.trim(without_comment:sub(1, -2))
  local first = header:match("^([%a_][%w_]*)")
  if not first then
    return nil
  end

  if first == "async" then
    local second = header:match("^async%s+([%a_][%w_]*)")
    local keyword = second and "async " .. second or nil
    return block_openers[keyword] and keyword or nil
  end

  return block_openers[first] and first or nil
end

local function opens_block(line)
  return block_keyword(line) ~= nil
end

local function continues_compound_block(line)
  local keyword = block_keyword(line)

  return keyword == "elif"
    or keyword == "else"
    or keyword == "except"
    or keyword == "finally"
    or keyword == "case"
end

local function update_lexical_state(state, line)
  local quote = state.quote
  local triple = state.triple
  local escaped = false
  local bracket_depth = state.bracket_depth or 0
  local index = 1

  while index <= #line do
    local char = line:sub(index, index)
    local next_two = line:sub(index, index + 2)

    if quote then
      if escaped then
        escaped = false
      elseif char == "\\" then
        escaped = true
      elseif triple and next_two == quote .. quote .. quote then
        quote = nil
        triple = false
        index = index + 2
      elseif not triple and char == quote then
        quote = nil
      end
    elseif char == "#" then
      break
    elseif char == "'" or char == '"' then
      quote = char
      triple = next_two == char .. char .. char
      if triple then
        index = index + 2
      end
    elseif char == "(" or char == "[" or char == "{" then
      bracket_depth = bracket_depth + 1
    elseif char == ")" or char == "]" or char == "}" then
      bracket_depth = math.max(0, bracket_depth - 1)
    end

    index = index + 1
  end

  state.quote = quote
  state.triple = triple
  state.bracket_depth = bracket_depth
  state.ends_with_backslash = strip_comment(line):match("\\%s*$") ~= nil
end

local function new_statement_tracker()
  return {
    bracket_depth = 0,
    block_indents = {},
    ends_with_backslash = false,
    quote = nil,
    triple = false,
  }
end

local function trim_closed_blocks(tracker, line)
  local indent = line_indent_width(line)

  while #tracker.block_indents > 0 and indent <= tracker.block_indents[#tracker.block_indents] do
    table.remove(tracker.block_indents)
  end
end

local function add_source_line(tracker, line)
  local before_indent = line_indent_width(line)
  local previous_opens_block = opens_block(line)

  if
    #tracker.block_indents > 0
    and (tracker.bracket_depth or 0) == 0
    and not (tracker.ends_with_backslash or false)
  then
    while #tracker.block_indents > 0 and before_indent <= tracker.block_indents[#tracker.block_indents] do
      table.remove(tracker.block_indents)
    end
  end

  update_lexical_state(tracker, line)

  if previous_opens_block then
    table.insert(tracker.block_indents, before_indent)
  end
end

local function can_recover_unprompted_source(tracker, line)
  if not tracker then
    return false
  end

  if tracker.quote ~= nil or (tracker.bracket_depth or 0) > 0 or tracker.ends_with_backslash then
    return true
  end

  if #tracker.block_indents == 0 then
    return false
  end

  local indent = line_indent_width(line)
  local block_indent = tracker.block_indents[#tracker.block_indents]

  return indent > block_indent
    or (indent == block_indent and continues_compound_block(line))
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
  local current_tracker = nil
  local saw_prompt = false
  local saw_output_since_prompt = false

  local function flush_statement()
    if current_statement == nil then
      return
    end

    vim.list_extend(source_lines, current_statement)
    current_statement = nil
    current_tracker = nil
  end

  for index, line in ipairs(stripped) do
    if util.is_blank(line) then
      if not saw_prompt then
        return nil, "Selection does not start with a doctest prompt."
      end

      flush_statement()
      saw_output_since_prompt = false
    else
      local statement = prompt_content(line, ">>> ")
      if statement ~= nil then
        saw_prompt = true
        flush_statement()
        current_statement = { statement }
        current_tracker = new_statement_tracker()
        add_source_line(current_tracker, statement)
        saw_output_since_prompt = false
      else
        local continuation = prompt_content(line, "... ")
        if continuation ~= nil then
          if current_statement ~= nil and not saw_output_since_prompt then
            table.insert(current_statement, continuation)
            add_source_line(current_tracker, continuation)
          elseif current_statement == nil then
            return nil,
              ("Invalid doctest block: continuation without an active statement at line %d."):format(index)
          else
            saw_output_since_prompt = true
          end
        else
          if not saw_prompt then
            return nil, "Selection does not start with a doctest prompt."
          end

          if current_statement == nil then
            return nil,
              ("Invalid doctest block: unexpected prose or title at line %d."):format(index)
          end

          if not saw_output_since_prompt and can_recover_unprompted_source(current_tracker, line) then
            trim_closed_blocks(current_tracker, line)
            table.insert(current_statement, line)
            add_source_line(current_tracker, line)
          else
            saw_output_since_prompt = true
          end
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
