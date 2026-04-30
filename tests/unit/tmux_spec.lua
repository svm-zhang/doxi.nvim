local tmux = require("doxi.tmux")
local t = require("tests")

return {
  {
    name = "builds direct tmux select-pane arguments",
    fn = function()
      local args, err = tmux._build_select_pane_args("l", {
        TMUX = "/tmp/tmux-501/default,123,0",
        TMUX_PANE = "%7",
      })

      t.assert_equal(err, nil)
      t.assert_deep_equal(args, {
        "tmux",
        "-S",
        "/tmp/tmux-501/default",
        "select-pane",
        "-t",
        "%7",
        "-R",
      })
    end,
  },
  {
    name = "uses tmate executable when the tmux environment is tmate-backed",
    fn = function()
      local args, err = tmux._build_select_pane_args("h", {
        TMUX = "/tmp/tmate/socket,123,0",
        TMUX_PANE = "%2",
      })

      t.assert_equal(err, nil)
      t.assert_deep_equal(args, {
        "tmate",
        "-S",
        "/tmp/tmate/socket",
        "select-pane",
        "-t",
        "%2",
        "-L",
      })
    end,
  },
  {
    name = "rejects invalid tmux navigation input",
    fn = function()
      local args, err = tmux._build_select_pane_args("x", {
        TMUX = "/tmp/tmux-501/default,123,0",
        TMUX_PANE = "%7",
      })

      t.assert_equal(args, nil)
      t.assert_equal(err, "Invalid tmux navigation direction.")
    end,
  },
  {
    name = "rejects missing tmux pane context",
    fn = function()
      local args, err = tmux._build_select_pane_args("l", {
        TMUX = "/tmp/tmux-501/default,123,0",
      })

      t.assert_equal(args, nil)
      t.assert_equal(err, "No active tmux pane is available.")
    end,
  },
}
