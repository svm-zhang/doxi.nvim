local compat = require("doxi.compat")
local t = require("tests")

return {
  {
    name = "accepts minimum supported neovim version",
    fn = function()
      local ok, message = compat.check({ major = 0, minor = 10, patch = 0 })
      t.assert_true(ok, message)
    end,
  },
  {
    name = "rejects older neovim versions with a clear message",
    fn = function()
      local ok, message = compat.check({ major = 0, minor = 9, patch = 5 })
      t.assert_equal(ok, false, "Expected 0.9.x to be rejected.")
      t.assert_equal(
        message,
        "doxi.nvim requires Neovim 0.10.0+ (detected 0.9.5).",
        "Expected unsupported-version message to include minimum and detected versions."
      )
    end,
  },
  {
    name = "accepts newer neovim versions",
    fn = function()
      local ok, message = compat.check({ major = 0, minor = 11, patch = 2 })
      t.assert_true(ok, message)
    end,
  },
}
