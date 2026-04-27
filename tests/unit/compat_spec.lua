local compat = require("doxi.compat")
local t = require("tests")

return {
  {
    name = "accepts minimum supported neovim version",
    fn = function()
      local ok, message = compat.check({ major = 0, minor = 11, patch = 0 })
      t.assert_true(ok, message)
    end,
  },
  {
    name = "rejects older neovim versions with a clear message",
    fn = function()
      local ok, message = compat.check({ major = 0, minor = 10, patch = 4 })
      t.assert_equal(ok, false, "Expected 0.10.x to be rejected.")
      t.assert_equal(
        message,
        "doxi.nvim requires Neovim 0.11.0+ (detected 0.10.4).",
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
  {
    name = "accepts neovim 0.12",
    fn = function()
      local ok, message = compat.check({ major = 0, minor = 12, patch = 0 })
      t.assert_true(ok, message)
    end,
  },
  {
    name = "accepts readiness when the python parser is available",
    fn = function()
      local ok, message = compat.check_ready({
        version = { major = 0, minor = 11, patch = 0 },
        parser_loader = function()
          return true
        end,
      })

      t.assert_true(ok, message)
    end,
  },
  {
    name = "rejects readiness when the python parser is missing",
    fn = function()
      local ok, message = compat.check_ready({
        version = { major = 0, minor = 11, patch = 0 },
        parser_loader = function()
          return false
        end,
      })

      t.assert_equal(ok, false)
      t.assert_equal(message, compat.python_parser_message())
    end,
  },
}
