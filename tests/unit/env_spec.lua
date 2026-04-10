local env = require("doxi.env")
local t = require("tests")

local function paths(candidates)
  local values = {}
  for _, candidate in ipairs(candidates) do
    table.insert(values, candidate.path)
  end
  return values
end

return {
  {
    name = "collects interpreters in priority order without duplicates",
    fn = function()
      local candidates = env._collect_candidates({
        config_path = "/cfg/python",
        virtual_env = "/venv",
        start_dir = "/project/subdir",
        project_root = "/project",
        poetry_lookup = function()
          return "/poetry/python"
        end,
        python3_path = "/usr/bin/python3",
        python_path = "/usr/bin/python",
        is_executable = function(path)
          return path ~= "/project/subdir/venv/bin/python"
        end,
      })

      t.assert_deep_equal(paths(candidates), {
        "/cfg/python",
        "/venv/bin/python",
        "/project/subdir/.venv/bin/python",
        "/project/.venv/bin/python",
        "/project/venv/bin/python",
        "/poetry/python",
        "/usr/bin/python3",
        "/usr/bin/python",
      })
    end,
  },
}
