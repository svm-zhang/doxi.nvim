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
        env_switch = "<leader>re",
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
        "Restart: rr    Fresh rerun: rR    Env: re    Cancel: q"
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
}
