local examples_context = require("doxi.examples_context")
local shared_imports = require("doxi.shared_imports")
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

local function create_python_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

return {
  {
    name = "builds shared import context for a google-style Examples section",
    fn = function()
      local bufnr = create_python_buffer({
        "def f():",
        '    """',
        "    Summary.",
        "    Examples:",
        "        >>> from math import sqrt",
        "",
        "        >>> sqrt(9)",
        "        3.0",
        '    """',
      })
      local discover_args

      with_override(util, "resolve_python_docstring", function()
        return {
          start_row = 2,
          end_row = 9,
        }
      end, function()
        with_override(shared_imports, "discover", function(opts)
          discover_args = opts
          return {
            ordered = { "from math import sqrt" },
            seen = { ["from math import sqrt"] = true },
          }
        end, function()
          local context, err = examples_context.build({
            bufnr = bufnr,
            start_row = 7,
            end_row = 8,
          })

          t.assert_equal(err, nil)
          t.assert_equal(context.header.kind, "google")
          t.assert_equal(context.header.header_row, 4)
          t.assert_equal(context.header.body_start_row, 5)
          t.assert_equal(discover_args.start_row, 5)
          t.assert_equal(discover_args.end_row, 6)
          t.assert_deep_equal(context.shared_imports.ordered, {
            "from math import sqrt",
          })
        end)
      end)
    end,
  },
  {
    name = "builds shared import context for a numpy-style Examples section",
    fn = function()
      local bufnr = create_python_buffer({
        '"""',
        "Examples",
        "--------",
        ">>> import os",
        ">>> os.getcwd()",
        '"""',
      })

      with_override(util, "resolve_python_docstring", function()
        return {
          start_row = 1,
          end_row = 6,
        }
      end, function()
        with_override(shared_imports, "discover", function()
          return {
            ordered = { "import os" },
            seen = { ["import os"] = true },
          }
        end, function()
          local context, err = examples_context.build({
            bufnr = bufnr,
            start_row = 5,
            end_row = 5,
          })

          t.assert_equal(err, nil)
          t.assert_equal(context.header.kind, "numpy")
          t.assert_equal(context.header.header_row, 2)
          t.assert_equal(context.header.underline_row, 3)
          t.assert_equal(context.header.body_start_row, 4)
        end)
      end)
    end,
  },
  {
    name = "rejects selections above the Examples body",
    fn = function()
      local bufnr = create_python_buffer({
        '"""',
        "Examples:",
        "",
        '"""',
      })

      with_override(util, "resolve_python_docstring", function()
        return {
          start_row = 1,
          end_row = 4,
        }
      end, function()
        local context, err = examples_context.build({
          bufnr = bufnr,
          start_row = 2,
          end_row = 2,
        })

        t.assert_equal(context, nil)
        t.assert_equal(err, "Select an example block or blank line inside a supported Examples section.")
      end)
    end,
  },
  {
    name = "rejects docstrings without a supported Examples header",
    fn = function()
      local bufnr = create_python_buffer({
        '"""',
        "Usage:",
        "    >>> demo()",
        '"""',
      })

      with_override(util, "resolve_python_docstring", function()
        return {
          start_row = 1,
          end_row = 4,
        }
      end, function()
        local context, err = examples_context.build({
          bufnr = bufnr,
          start_row = 3,
          end_row = 3,
        })

        t.assert_equal(context, nil)
        t.assert_equal(err, "Select an example block or blank line inside a supported Examples section.")
      end)
    end,
  },
}
