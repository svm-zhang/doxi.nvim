local t = require("tests")
local ui = require("doxi.ui")

local function has_highlight(hints, group)
  for _, highlight in ipairs(hints.highlights or {}) do
    if highlight.group == group then
      return true
    end
  end

  return false
end

return {
  {
    name = "formats key hints horizontally with labeled entries and a shared leader prefix",
    fn = function()
      local hints = ui.build_hints({
        run_all = "<leader>ra",
        run_selection = "<leader>rs",
        restart = "<leader>rr",
        restart_rerun = "<leader>rR",
        apply = "<leader>da",
        cancel = "q",
      })

      t.assert_equal(#hints.lines, 2)
      t.assert_equal(
        hints.lines[1],
        "Leader: <leader>    Run all: ra    Run selection: rs    Apply: da"
      )
      t.assert_equal(
        hints.lines[2],
        "Restart: rr    Fresh rerun: rR    Cancel: q"
      )
      t.assert_true(has_highlight(hints, "DoxiHintLabel"), "Hint labels should be highlighted.")
      t.assert_true(has_highlight(hints, "DoxiHintKey"), "Hint keys should be highlighted.")
      t.assert_true(has_highlight(hints, "DoxiHintPrefix"), "The shared leader prefix should be highlighted.")
    end,
  },
  {
    name = "resolves fixed and proportional UI sizes",
    fn = function()
      t.assert_equal(ui.resolve_size(100, 160, 80), 100)
      t.assert_equal(ui.resolve_size(0.5, 200, 80), 100)
      t.assert_equal(ui.resolve_size(500, 120, 80), 120)
      t.assert_equal(ui.resolve_size(0.2, 200, 80), 80)
    end,
  },
  {
    name = "opens the editor pane with a visible sign column, lower zindex, and synthetic buffer name",
    fn = function()
      local view = ui.open({
        editor_buffer_name = "/project/doxi-test.py",
        workflow = "new example",
        shared_imports = {
          ordered = {},
          seen = {},
        },
      })

      local ok, err = xpcall(function()
        t.assert_equal(vim.api.nvim_get_option_value("signcolumn", { win = view.editor_winid }), "yes:1")
        t.assert_equal(vim.api.nvim_get_option_value("buftype", { buf = view.editor_bufnr }), "nofile")
        t.assert_equal(vim.api.nvim_buf_get_name(view.editor_bufnr), "/project/doxi-test.py")
        t.assert_equal(vim.api.nvim_win_get_config(view.editor_winid).zindex, 40)
        t.assert_equal(vim.api.nvim_win_get_config(view.output_winid).zindex, 40)
      end, debug.traceback)

      ui.close(view)

      if not ok then
        error(err)
      end
    end,
  },
}
