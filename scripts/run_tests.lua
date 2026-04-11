local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(script_path))

package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/?.lua",
  root .. "/?/init.lua",
  package.path,
}, ";")

require("tests").run_suite({
  "tests.unit.importer_spec",
  "tests.unit.selection_spec",
  "tests.unit.transcript_spec",
  "tests.unit.env_spec",
  "tests.unit.inserter_spec",
  "tests.unit.ui_spec",
})
