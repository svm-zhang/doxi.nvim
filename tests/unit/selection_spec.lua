local selection = require("doxi.selection")
local t = require("tests")

return {
  {
    name = "builds a blank-line target inside a docstring",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "def f():",
        '    """',
        "    ",
        '    """',
      })

      local target, err = selection.build_target({
        bufnr = bufnr,
        start_row = 3,
        end_row = 3,
      })

      t.assert_equal(err, nil, "A selected blank docstring line should open a new session target.")
      t.assert_equal(target.kind, "blank")
      t.assert_equal(target.source_indent, "    ")
      t.assert_deep_equal(target.source_leading_blank_lines, {})
      t.assert_deep_equal(target.source_trailing_blank_lines, {
        "    ",
      })
      t.assert_deep_equal(target.editor_lines, {})
    end,
  },
  {
    name = "infers blank-line indentation from an Examples header",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "def f():",
        '    """',
        "    Examples:",
        "",
        '    """',
      })

      local target, err = selection.build_target({
        bufnr = bufnr,
        start_row = 4,
        end_row = 4,
      })

      t.assert_equal(err, nil, "A blank selection below Examples should infer doctest indentation.")
      t.assert_equal(target.source_indent, "        ")
      t.assert_deep_equal(target.source_leading_blank_lines, {})
      t.assert_deep_equal(target.source_trailing_blank_lines, {
        "",
      })
    end,
  },
  {
    name = "builds a doctest target from a selected block",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "def f():",
        '    """',
        "    >>> x = 1",
        "    >>> x + 1",
        "    2",
        '    """',
      })

      local target, err = selection.build_target({
        bufnr = bufnr,
        start_row = 3,
        end_row = 5,
      })

      t.assert_equal(err, nil, "A valid doctest block should open an edit session target.")
      t.assert_equal(target.kind, "doctest")
      t.assert_deep_equal(target.editor_lines, {
        "x = 1",
        "x + 1",
      })
      t.assert_deep_equal(target.source_leading_blank_lines, {})
      t.assert_deep_equal(target.source_trailing_blank_lines, {})
    end,
  },
  {
    name = "captures a leading blank separator from the selected range",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "def f():",
        '    """',
        "    ",
        "    >>> x = 1",
        "    1",
        '    """',
      })

      local target, err = selection.build_target({
        bufnr = bufnr,
        start_row = 3,
        end_row = 5,
      })

      t.assert_equal(err, nil, "A selected leading separator line should be preserved.")
      t.assert_deep_equal(target.source_leading_blank_lines, {
        "    ",
      })
      t.assert_deep_equal(target.source_trailing_blank_lines, {})
      t.assert_deep_equal(target.editor_lines, {
        "x = 1",
      })
    end,
  },
  {
    name = "synthesizes a leading separator for a blank line after a doctest region",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "def f():",
        '    """',
        "    Examples:",
        "        >>> x = 1",
        "        1",
        "",
        "        Title:",
        '    """',
      })

      local target, err = selection.build_target({
        bufnr = bufnr,
        start_row = 6,
        end_row = 6,
      })

      t.assert_equal(err, nil, "A blank selection between examples should synthesize a leading separator.")
      t.assert_equal(target.source_indent, "        ")
      t.assert_deep_equal(target.source_leading_blank_lines, {
        "        ",
      })
      t.assert_deep_equal(target.source_trailing_blank_lines, {
        "",
      })
    end,
  },
  {
    name = "captures a trailing blank separator from the selected range",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "def f():",
        '    """',
        "    >>> x = 1",
        "    1",
        "    ",
        '    """',
      })

      local target, err = selection.build_target({
        bufnr = bufnr,
        start_row = 3,
        end_row = 5,
      })

      t.assert_equal(err, nil, "A selected trailing separator line should be preserved.")
      t.assert_deep_equal(target.source_leading_blank_lines, {})
      t.assert_deep_equal(target.source_trailing_blank_lines, {
        "    ",
      })
    end,
  },
  {
    name = "rejects selections outside a docstring",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "python", { buf = bufnr })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "x = 1",
        "x + 1",
      })

      local target, err = selection.build_target({
        bufnr = bufnr,
        start_row = 1,
        end_row = 1,
      })

      t.assert_equal(target, nil)
      t.assert_equal(err, "Select an empty docstring line or doctest block inside a Python docstring.")
    end,
  },
}
