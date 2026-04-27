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
      local executable_paths = {
        ["/cfg/python"] = true,
        ["/venv/bin/python"] = true,
        ["/project/subdir/.venv/bin/python"] = true,
        ["/project/.venv/bin/python"] = true,
        ["/project/venv/bin/python"] = true,
        ["/poetry/python"] = true,
        ["/usr/bin/python"] = true,
        ["/usr/bin/python3"] = true,
      }

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
          return executable_paths[path] == true
        end,
        normalize_path = function(path)
          return path
        end,
      })

      t.assert_deep_equal(paths(candidates), {
        "/cfg/python",
        "/venv/bin/python",
        "/project/subdir/.venv/bin/python",
        "/project/.venv/bin/python",
        "/project/venv/bin/python",
        "/poetry/python",
        "/usr/bin/python",
        "/usr/bin/python3",
      })
    end,
  },
  {
    name = "collects interpreters using normalized invocation paths without collapsing meaningful symlinks",
    fn = function()
      local candidates = env._collect_candidates({
        start_dir = "/project",
        project_root = "/project",
        python_path = "/shims/python",
        python3_path = "/shims/python3",
        is_executable = function(path)
          return path == "/shims/python" or path == "/shims/python3"
        end,
        normalize_path = function(path)
          return env._normalize_candidate_path(path)
        end,
      })

      t.assert_deep_equal(candidates, {
        {
          label = "python (PATH)",
          path = "/shims/python",
        },
        {
          label = "python3 (PATH)",
          path = "/shims/python3",
        },
      })
    end,
  },
  {
    name = "collects interpreters using normalized paths to deduplicate exact duplicates only",
    fn = function()
      local candidates = env._collect_candidates({
        start_dir = "/project",
        project_root = "/project",
        python_path = "/usr/bin/python3",
        python3_path = "/usr/bin/python3",
        is_executable = function(path)
          return path == "/usr/bin/python3"
        end,
        normalize_path = function(path)
          return env._normalize_candidate_path(path)
        end,
      })

      t.assert_deep_equal(candidates, {
        {
          label = "python (PATH)",
          path = "/usr/bin/python3",
        },
      })
    end,
  },
  {
    name = "suppresses PATH python3.exe when an explicit environment candidate already covers the same windows-style venv",
    fn = function()
      local candidates = env._collect_candidates({
        virtual_env = "C:/project/.venv",
        start_dir = "C:/project",
        project_root = "C:/project",
        python3_path = "C:/project/.venv/Scripts/python3.exe",
        is_executable = function(path)
          return path == "C:/project/.venv/Scripts/python.exe"
            or path == "C:/project/.venv/Scripts/python3.exe"
        end,
        normalize_path = function(path)
          return env._normalize_candidate_path(path)
        end,
      })

      t.assert_deep_equal(candidates, {
        {
          label = "VIRTUAL_ENV",
          path = "C:/project/.venv/Scripts/python.exe",
        },
      })
    end,
  },
  {
    name = "suppresses PATH interpreters when an explicit environment candidate already covers the same venv",
    fn = function()
      local candidates = env._collect_candidates({
        virtual_env = "/project/.venv",
        start_dir = "/project",
        project_root = "/project",
        python_path = "/project/.venv/bin/python",
        python3_path = "/project/.venv/bin/python3",
        global_python3_path = "/usr/bin/python3",
        is_executable = function(path)
          return path == "/project/.venv/bin/python"
            or path == "/project/.venv/bin/python3"
            or path == "/usr/bin/python3"
        end,
        normalize_path = function(path)
          return env._normalize_candidate_path(path)
        end,
      })

      t.assert_deep_equal(candidates, {
        {
          label = "VIRTUAL_ENV",
          path = "/project/.venv/bin/python",
        },
        {
          label = "python3 (PATH)",
          path = "/usr/bin/python3",
        },
      })
    end,
  },
  {
    name = "keeps PATH python and python3 entries when no explicit environment candidate exists",
    fn = function()
      local candidates = env._collect_candidates({
        start_dir = "/project",
        project_root = "/project",
        python_path = "/usr/bin/python",
        python3_path = "/usr/bin/python3",
        is_executable = function(path)
          return path == "/usr/bin/python" or path == "/usr/bin/python3"
        end,
        normalize_path = function(path)
          return env._normalize_candidate_path(path)
        end,
      })

      t.assert_deep_equal(candidates, {
        {
          label = "python (PATH)",
          path = "/usr/bin/python",
        },
        {
          label = "python3 (PATH)",
          path = "/usr/bin/python3",
        },
      })
    end,
  },
  {
    name = "omits global PATH entries when they resolve to the same interpreter as the active PATH lookup",
    fn = function()
      local candidates = env._collect_candidates({
        start_dir = "/project",
        project_root = "/project",
        python3_path = "/usr/bin/python3",
        global_python3_path = "/usr/bin/python3",
        is_executable = function(path)
          return path == "/usr/bin/python3"
        end,
        normalize_path = function(path)
          return env._normalize_candidate_path(path)
        end,
      })

      t.assert_deep_equal(candidates, {
        {
          label = "python3 (PATH)",
          path = "/usr/bin/python3",
        },
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
