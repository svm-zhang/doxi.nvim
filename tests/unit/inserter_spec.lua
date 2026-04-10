local inserter = require("doxi.inserter")
local t = require("tests")

return {
  {
    name = "inserts an indented transcript at the captured cursor row",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '"""',
        "    ",
        '"""',
      })

      local ok, err = inserter.insert({
        bufnr = bufnr,
        row = 2,
        indent = "    ",
        line_snapshot = "    ",
      }, {
        ">>> x = 1",
        "1",
      })

      t.assert_true(ok, err)
      t.assert_deep_equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), {
        '"""',
        "    >>> x = 1",
        "    1",
        "    ",
        '"""',
      })
    end,
  },
  {
    name = "replaces the originally selected doctest block",
    fn = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '"""',
        "    >>> x = 1",
        "    1",
        '"""',
      })

      local ok, err = inserter.replace({
        bufnr = bufnr,
        start_row = 2,
        end_row = 3,
        indent = "    ",
        lines_snapshot = {
          "    >>> x = 1",
          "    1",
        },
      }, {
        ">>> y = 2",
        "2",
      })

      t.assert_true(ok, err)
      t.assert_deep_equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), {
        '"""',
        "    >>> y = 2",
        "    2",
        '"""',
      })
    end,
  },
}
