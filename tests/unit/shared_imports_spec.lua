local shared_imports = require("doxi.shared_imports")
local util = require("doxi.util")
local t = require("tests")

local function parser_factory(source, language)
  if language ~= "python" then
    error("Unexpected parser language: " .. tostring(language))
  end

  local normalized = source:gsub("\n$", "")
  if normalized == "trigger parser error" then
    error("missing parser")
  end

  local kind = "expression_statement"
  if normalized:match("^import ") then
    kind = "import_statement"
  elseif normalized:match("^from ") then
    kind = "import_from_statement"
  end

  return {
    parse = function()
      return {
        {
          root = function()
            return {
              named_child = function(_, index)
                if index ~= 0 then
                  return nil
                end

                return {
                  type = function()
                    return kind
                  end,
                }
              end,
            }
          end,
        },
      }
    end,
  }
end

local function create_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

return {
  {
    name = "discovers leading import statements and stops at the first non-import statement",
    fn = function()
      local bufnr = create_buffer({
        "        >>> import os",
        "        >>> from math import sqrt",
        "        >>> value = sqrt(9)",
        "        3.0",
        "        >>> import sys",
      })

      local imports, err = shared_imports.discover({
        bufnr = bufnr,
        start_row = 1,
        end_row = 5,
        parser_factory = parser_factory,
      })

      t.assert_equal(err, nil)
      t.assert_deep_equal(imports.ordered, {
        "import os",
        "from math import sqrt",
      })
    end,
  },
  {
    name = "supports multiline import statements and deduplicates repeated imports",
    fn = function()
      local bufnr = create_buffer({
        "        >>> from pkg import (",
        "        ...     a,",
        "        ...     b,",
        "        ... )",
        "        >>> import os",
        "        >>> import os",
        "        >>> run_example()",
      })

      local imports, err = shared_imports.discover({
        bufnr = bufnr,
        start_row = 1,
        end_row = 7,
        parser_factory = parser_factory,
      })

      t.assert_equal(err, nil)
      t.assert_deep_equal(imports.ordered, {
        "from pkg import (\n    a,\n    b,\n)",
        "import os",
      })
    end,
  },
  {
    name = "ignores sections that start with prose before any doctest prompts",
    fn = function()
      local bufnr = create_buffer({
        "        First explain the example.",
        "        >>> import os",
        "        >>> os.getcwd()",
      })

      local imports, err = shared_imports.discover({
        bufnr = bufnr,
        start_row = 1,
        end_row = 3,
        parser_factory = parser_factory,
      })

      t.assert_equal(err, nil)
      t.assert_deep_equal(imports.ordered, {})
    end,
  },
  {
    name = "surfaces parser availability errors during shared import discovery",
    fn = function()
      local bufnr = create_buffer({
        "        >>> trigger parser error",
      })

      local imports, err = shared_imports.discover({
        bufnr = bufnr,
        start_row = 1,
        end_row = 1,
        parser_factory = parser_factory,
      })

      t.assert_equal(imports, nil)
      t.assert_equal(err, util._python_treesitter_required_message())
    end,
  },
  {
    name = "renders a placeholder when there are no shared imports",
    fn = function()
      t.assert_deep_equal(shared_imports.render_lines({
        ordered = {},
        seen = {},
      }), {
        "No shared imports",
      })
    end,
  },
}
