local util = require("doxi.util")
local t = require("tests")

local function with_override(target, key, value, fn)
  local original = target[key]
  target[key] = value

  local ok, err = xpcall(fn, debug.traceback)

  target[key] = original

  if not ok then
    error(err)
  end
end

local function node(kind, range)
  local current = {
    _kind = kind,
    _range = range or { 0, 0, 0, 0 },
    _parent = nil,
    _children = {},
  }

  function current:type()
    return self._kind
  end

  function current:parent()
    return self._parent
  end

  function current:named_child(index)
    return self._children[index + 1]
  end

  function current:named_child_count()
    return #self._children
  end

  function current:range()
    return unpack(self._range)
  end

  function current:equal(other)
    return rawequal(self, other)
  end

  function current:add(child)
    child._parent = self
    table.insert(self._children, child)
    return child
  end

  return current
end

local function module_docstring_tree()
  local module = node("module", { 0, 0, 4, 3 })
  local statement = module:add(node("expression_statement", { 0, 0, 4, 3 }))
  local string = statement:add(node("string", { 0, 0, 4, 3 }))

  return {
    module = module,
    statement = statement,
    string = string,
  }
end

local function function_docstring_tree(owner_type)
  local owner = node(owner_type or "function_definition", { 0, 0, 6, 0 })
  local block = node("block", { 1, 4, 5, 7 })
  block._parent = owner

  local statement = block:add(node("expression_statement", { 1, 4, 5, 7 }))
  local string = statement:add(node("string", { 1, 4, 5, 7 }))

  return {
    owner = owner,
    block = block,
    statement = statement,
    string = string,
  }
end

local function non_docstring_assignment_tree()
  local module = node("module", { 0, 0, 2, 3 })
  local assignment = module:add(node("assignment", { 0, 0, 2, 3 }))
  local string = assignment:add(node("string", { 0, 6, 2, 3 }))

  return {
    module = module,
    assignment = assignment,
    string = string,
  }
end

local function later_string_in_function_tree()
  local tree = function_docstring_tree("function_definition")
  tree.block:add(node("pass_statement", { 6, 4, 6, 8 }))
  local later_statement = tree.block:add(node("expression_statement", { 7, 4, 9, 7 }))
  local later_string = later_statement:add(node("string", { 7, 4, 9, 7 }))

  return {
    owner = tree.owner,
    block = tree.block,
    later_statement = later_statement,
    later_string = later_string,
  }
end

return {
  {
    name = "get_visual_line_range uses the active visual selection when still in visual mode",
    fn = function()
      with_override(vim.api, "nvim_get_mode", function()
        return { mode = "v" }
      end, function()
        with_override(vim.fn, "getpos", function(mark)
          if mark == "v" then
            return { 0, 9, 1, 0 }
          end

          if mark == "'<" then
            return { 0, 3, 1, 0 }
          end

          if mark == "'>" then
            return { 0, 4, 1, 0 }
          end

          error("Unexpected mark: " .. tostring(mark))
        end, function()
          with_override(vim.api, "nvim_win_get_cursor", function()
            return { 5, 0 }
          end, function()
            local start_row, end_row = util.get_visual_line_range()
            t.assert_equal(start_row, 5)
            t.assert_equal(end_row, 9)
          end)
        end)
      end)
    end,
  },
  {
    name = "get_visual_line_range falls back to visual marks outside visual mode",
    fn = function()
      with_override(vim.api, "nvim_get_mode", function()
        return { mode = "n" }
      end, function()
        with_override(vim.fn, "getpos", function(mark)
          if mark == "'<" then
            return { 0, 8, 1, 0 }
          end

          if mark == "'>" then
            return { 0, 6, 1, 0 }
          end

          error("Unexpected mark: " .. tostring(mark))
        end, function()
          local start_row, end_row = util.get_visual_line_range()
          t.assert_equal(start_row, 6)
          t.assert_equal(end_row, 8)
        end)
      end)
    end,
  },
  {
    name = "finds a canonical module docstring node",
    fn = function()
      local tree = module_docstring_tree()
      t.assert_equal(util._find_canonical_docstring_node(tree.string), tree.string)
    end,
  },
  {
    name = "finds a canonical function docstring node",
    fn = function()
      local tree = function_docstring_tree("function_definition")
      t.assert_equal(util._find_canonical_docstring_node(tree.string), tree.string)
    end,
  },
  {
    name = "finds a canonical async function docstring node",
    fn = function()
      local tree = function_docstring_tree("async_function_definition")
      t.assert_equal(util._find_canonical_docstring_node(tree.string), tree.string)
    end,
  },
  {
    name = "rejects assigned strings as docstrings",
    fn = function()
      local tree = non_docstring_assignment_tree()
      t.assert_equal(util._find_canonical_docstring_node(tree.string), nil)
    end,
  },
  {
    name = "rejects later standalone strings in a function body",
    fn = function()
      local tree = later_string_in_function_tree()
      t.assert_equal(util._find_canonical_docstring_node(tree.later_string), nil)
    end,
  },
  {
    name = "selection_in_python_docstring accepts rows in the same canonical docstring",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })

      local tree = module_docstring_tree()

      with_override(util, "_get_python_node_at_row", function()
        return tree.string
      end, function()
        local ok, err = util.selection_in_python_docstring(bufnr, 2, 4)
        t.assert_equal(err, nil)
        t.assert_equal(ok, true)
      end)
    end,
  },
  {
    name = "selection_in_python_docstring rejects rows outside a canonical docstring",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })

      local docstring = module_docstring_tree()
      local non_docstring = non_docstring_assignment_tree()

      with_override(util, "_get_python_node_at_row", function(_, row)
        if row == 2 then
          return docstring.string
        end

        return non_docstring.string
      end, function()
        local ok, err = util.selection_in_python_docstring(bufnr, 2, 8)
        t.assert_equal(err, nil)
        t.assert_equal(ok, false)
      end)
    end,
  },
  {
    name = "selection_in_python_docstring surfaces parser errors",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })

      with_override(util, "_get_python_node_at_row", function()
        return nil, util._python_treesitter_required_message()
      end, function()
        local ok, err = util.selection_in_python_docstring(bufnr, 2, 2)
        t.assert_equal(ok, nil)
        t.assert_equal(err, util._python_treesitter_required_message())
      end)
    end,
  },
  {
    name = "_get_python_parser returns a controlled error when the parser is unavailable",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)

      with_override(vim.treesitter, "get_parser", function()
        error("missing parser")
      end, function()
        local parser, err = util._get_python_parser(bufnr)
        t.assert_equal(parser, nil)
        t.assert_equal(err, util._python_treesitter_required_message())
      end)
    end,
  },
}
