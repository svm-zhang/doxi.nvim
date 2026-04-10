local transcript = require("doxi.transcript")
local t = require("tests")

return {
  {
    name = "renders prompts and result ordering",
    fn = function()
      local lines = transcript.render_chunks({
        {
          input_lines = {
            "x = 1",
            "x + 1",
          },
          stdout_lines = {
            "hello",
          },
          stderr_lines = {
            "warning",
          },
          result_lines = {
            "2",
          },
        },
      })

      t.assert_deep_equal(lines, {
        ">>> x = 1",
        "... x + 1",
        "hello",
        "warning",
        "2",
      })
    end,
  },
}
