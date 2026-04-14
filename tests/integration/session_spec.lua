local backend = require("doxi.backend")
local env = require("doxi.env")
local session = require("doxi.session")
local util = require("doxi.util")
local t = require("tests")

local function run_with_picker_stub(fn)
  local original_picker = env.pick_interpreter
  local python = vim.fn.exepath("python3")

  if python == "" then
    error("python3 is required for session integration tests.")
  end

  env.pick_interpreter = function(_, callback)
    callback(python)
  end

  local ok, err = xpcall(fn, debug.traceback)

  env.pick_interpreter = original_picker

  if session.get_active() then
    session.cancel()
  end

  if not ok then
    error(err)
  end
end

local function run_with_docstring_gate_stub(fn)
  local original_check = util.selection_in_python_docstring

  util.selection_in_python_docstring = function()
    return true
  end

  local ok, err = xpcall(fn, debug.traceback)

  util.selection_in_python_docstring = original_check

  if not ok then
    error(err)
  end
end

local function with_override(target, key, value, fn)
  local original = target[key]
  target[key] = value

  local ok, err = xpcall(fn, debug.traceback)

  target[key] = original

  if not ok then
    error(err)
  end
end

return {
  {
    name = "backend restart starts a fresh interpreter process",
    fn = function()
      local python = vim.fn.exepath("python3")
      if python == "" then
        error("python3 is required for backend integration tests.")
      end

      local instance = backend.new({
        interpreter_path = python,
      })
      local import_result
      local import_err

      instance:execute("import random", function(result, err)
        import_result = result
        import_err = err
      end)

      t.wait_until(function()
        return import_result ~= nil or import_err ~= nil
      end, 3000, "Initial backend execution did not complete.")

      t.assert_equal(import_err, nil, "Initial backend execution should succeed.")

      local restarted
      local restart_err
      instance:restart(function(_, err)
        restarted = true
        restart_err = err
      end)

      t.wait_until(function()
        return restarted
      end, 3000, "Backend restart did not complete.")

      t.assert_equal(restart_err, nil, "Backend restart should start a new interpreter process.")

      local post_restart_result
      local post_restart_err
      instance:execute("import sys\n'random' in sys.modules", function(result, err)
        post_restart_result = result
        post_restart_err = err
      end)

      t.wait_until(function()
        return post_restart_result ~= nil or post_restart_err ~= nil
      end, 3000, "Post-restart execution did not complete.")

      instance:stop()

      t.assert_equal(post_restart_err, nil, "Execution after restart should succeed.")
      t.assert_deep_equal(post_restart_result.chunks[2].result_lines, {
        "False",
      })
    end,
  },
  {
    name = "session open run apply path works with the live backend",
    fn = function()
      run_with_picker_stub(function()
        run_with_docstring_gate_stub(function()
          local current_bufnr = vim.api.nvim_get_current_buf()
          local source_bufnr = vim.api.nvim_create_buf(true, true)

          vim.api.nvim_set_current_buf(source_bufnr)
          vim.api.nvim_set_option_value("filetype", "python", { buf = source_bufnr })
          vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, {
            "def f():",
            '    """',
            "    Examples:",
            "        >>> before()",
            "        1",
            "",
            "        After this:",
            '    """',
          })

          local ok, err = xpcall(function()
            session.open({
              line1 = 6,
              line2 = 6,
              range = 2,
            })

            local active = t.wait_until(function()
              return session.get_active()
            end, 2000, "Session did not open.")

            vim.api.nvim_buf_set_lines(active.editor_bufnr, 0, -1, false, {
              "x = 1",
              "x + 1",
            })

            session.run_all()

            t.wait_until(function()
              local lines = vim.api.nvim_buf_get_lines(active.output_bufnr, 0, -1, false)
              return #lines > 0 and lines[#lines] == "2"
            end, 3000, "Transcript output did not render.")

            session.apply()

            t.wait_until(function()
              return session.get_active() == nil
            end, 2000, "Session did not close after apply.")

            t.assert_deep_equal(vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false), {
              "def f():",
              '    """',
              "    Examples:",
              "        >>> before()",
              "        1",
              "        ",
              "        >>> x = 1",
              "        >>> x + 1",
              "        2",
              "",
              "        After this:",
              '    """',
            })
          end, debug.traceback)

          if vim.api.nvim_buf_is_valid(source_bufnr) then
            pcall(vim.api.nvim_buf_delete, source_bufnr, { force = true })
          end

          if vim.api.nvim_buf_is_valid(current_bufnr) then
            vim.api.nvim_set_current_buf(current_bufnr)
          end

          if not ok then
            error(err)
          end
        end)
      end)
    end,
  },
  {
    name = "invalid session open never reaches interpreter picking",
    fn = function()
      local current_bufnr = vim.api.nvim_get_current_buf()
      local source_bufnr = vim.api.nvim_create_buf(true, true)
      local picker_calls = 0

      vim.api.nvim_set_current_buf(source_bufnr)
      vim.api.nvim_set_option_value("filetype", "python", { buf = source_bufnr })
      vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, {
        "def f():",
        '    """',
        "    not a valid doctest block",
        '    """',
      })

      local ok, err = xpcall(function()
        with_override(env, "pick_interpreter", function()
          picker_calls = picker_calls + 1
        end, function()
          with_override(util, "notify", function() end, function()
            with_override(util, "selection_in_python_docstring", function()
              return false
            end, function()
              session.open({
                line1 = 3,
                line2 = 3,
                range = 2,
              })
            end)
          end)
        end)

        t.assert_equal(session.get_active(), nil)
        t.assert_equal(picker_calls, 0, "Invalid selections should not reach interpreter picking.")
      end, debug.traceback)

      if vim.api.nvim_buf_is_valid(source_bufnr) then
        pcall(vim.api.nvim_buf_delete, source_bufnr, { force = true })
      end

      if vim.api.nvim_buf_is_valid(current_bufnr) then
        vim.api.nvim_set_current_buf(current_bufnr)
      end

      if not ok then
        error(err)
      end
    end,
  },
  {
    name = "open_visual respects each current selection instead of reusing the previous one",
    fn = function()
      local current_bufnr = vim.api.nvim_get_current_buf()
      local source_bufnr = vim.api.nvim_create_buf(true, true)
      local picker_calls = 0
      local notifications = {}
      local selection_ranges = {
        { 4, 5 },
        { 3, 5 },
        { 4, 5 },
      }
      local selection_index = 0

      vim.api.nvim_set_current_buf(source_bufnr)
      vim.api.nvim_set_option_value("filetype", "python", { buf = source_bufnr })
      vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, {
        "def canonical_function_case():",
        '    """A canonical function docstring.',
        "    Examples:",
        "        >>> items = [1, 2]",
        "        >>> len(items)",
        "        2",
        '    """',
      })

      local ok, err = xpcall(function()
        with_override(util, "escape_visual_mode", function() end, function()
          with_override(util, "notify", function(message)
            table.insert(notifications, message)
          end, function()
            with_override(util, "selection_in_python_docstring", function()
              return true
            end, function()
              with_override(env, "pick_interpreter", function(_, callback)
                picker_calls = picker_calls + 1
                callback(nil)
              end, function()
                with_override(util, "get_visual_line_range", function()
                  selection_index = selection_index + 1
                  local range = selection_ranges[selection_index]
                  return range[1], range[2]
                end, function()
                  session.open_visual()
                  t.assert_equal(picker_calls, 1, "Valid doctest-only selection should reach the picker.")
                  t.assert_equal(#notifications, 0)

                  session.open_visual()
                  t.assert_equal(picker_calls, 1, "Invalid mixed selection should not reach the picker.")
                  t.assert_true(type(notifications[#notifications]) == "string" and notifications[#notifications] ~= "")

                  session.open_visual()
                  t.assert_equal(picker_calls, 2, "Returning to the valid selection should reach the picker again.")
                end)
              end)
            end)
          end)
        end)
      end, debug.traceback)

      if vim.api.nvim_buf_is_valid(source_bufnr) then
        pcall(vim.api.nvim_buf_delete, source_bufnr, { force = true })
      end

      if vim.api.nvim_buf_is_valid(current_bufnr) then
        vim.api.nvim_set_current_buf(current_bufnr)
      end

      if not ok then
        error(err)
      end
    end,
  },
}
