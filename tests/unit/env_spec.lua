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
  {
    name = "pick_candidates can restrict the picker to provided items without manual entry",
    fn = function()
      local captured_opts
      local picked_path

      local original_select = vim.ui.select
      vim.ui.select = function(items, opts, on_choice)
        captured_opts = {
          prompt = opts.prompt,
          size = #items,
        }
        on_choice(items[1])
      end

      local ok, err = xpcall(function()
        env.pick_candidates({
          items = {
            {
              label = "Source buffer LSP",
              path = "/aligned/python",
            },
          },
          allow_manual = false,
          prompt = "Confirm Python environment",
        }, function(path)
          picked_path = path
        end)

        t.assert_equal(picked_path, "/aligned/python")
        t.assert_deep_equal(captured_opts, {
          prompt = "Confirm Python environment",
          size = 1,
        })
      end, debug.traceback)

      vim.ui.select = original_select

      if not ok then
        error(err)
      end
    end,
  },
}
