local interpreter = require("doxi.interpreter")
local t = require("tests")

local function with_temp_python(fn)
  local root = vim.fn.tempname()
  local bin = root .. "/bin"
  local python = bin .. "/python"

  vim.fn.mkdir(bin, "p")
  vim.fn.writefile({
    "#!/bin/sh",
    "exit 0",
  }, python)
  vim.fn.setfperm(python, "rwxr-xr-x")

  local ok, err = xpcall(function()
    fn(root, python)
  end, debug.traceback)

  vim.fn.delete(root, "rf")

  if not ok then
    error(err)
  end
end

return {
  {
    name = "resolve prefers supported client settings for aligned lsp interpreter recovery",
    fn = function()
      local python = vim.fn.exepath("python3")
      if python == "" then
        error("python3 is required for interpreter unit tests.")
      end

      local result = interpreter.resolve(1, {
        get_source_client_state = function()
          return {
            supported_clients = {
              {
                name = "pyright",
                config = {
                  settings = {
                    python = {
                      pythonPath = python,
                    },
                  },
                },
              },
            },
          }
        end,
        discover = function()
          return {}
        end,
      })

      t.assert_equal(result.mode, "aligned_lsp")
      t.assert_equal(result.interpreter_path, python)
      t.assert_equal(result.provenance, "client_settings")
      t.assert_equal(result.allow_manual, false)
      t.assert_equal(result.items[1].label, "Source buffer LSP")
    end,
  },
  {
    name = "resolve can recover aligned lsp interpreter from client venv settings",
    fn = function()
      with_temp_python(function(root)
        local result = interpreter.resolve(1, {
          get_source_client_state = function()
            return {
              supported_clients = {
                {
                  name = "pyright",
                  config = {
                    settings = {
                      python = {
                        venv = vim.fn.fnamemodify(root, ":t"),
                        venvPath = vim.fn.fnamemodify(root, ":h"),
                      },
                    },
                  },
                },
              },
            }
          end,
          discover = function()
            return {}
          end,
        })

        t.assert_equal(result.mode, "aligned_lsp")
        t.assert_equal(result.interpreter_path, root .. "/bin/python")
        t.assert_equal(result.provenance, "client_settings")
      end)
    end,
  },
  {
    name = "resolve can recover aligned lsp interpreter from venv-selector when client config lacks a path",
    fn = function()
      local python = vim.fn.exepath("python3")
      if python == "" then
        error("python3 is required for interpreter unit tests.")
      end

      local result = interpreter.resolve(1, {
        get_source_client_state = function()
          return {
            supported_clients = {
              {
                name = "pyright",
                config = {},
              },
            },
          }
        end,
        venv_selector_python = function()
          return python
        end,
        discover = function()
          return {}
        end,
      })

      t.assert_equal(result.mode, "aligned_lsp")
      t.assert_equal(result.interpreter_path, python)
      t.assert_equal(result.provenance, "venv_selector")
      t.assert_equal(result.items[1].label, "Source buffer LSP (venv-selector)")
    end,
  },
  {
    name = "resolve can recover aligned lsp interpreter from environment variables",
    fn = function()
      with_temp_python(function(root)
        local result = interpreter.resolve(1, {
          get_source_client_state = function()
            return {
              supported_clients = {
                {
                  name = "pyright",
                  config = {},
                },
              },
            }
          end,
          venv_selector_python = function()
            return nil
          end,
          env_vars = {
            VIRTUAL_ENV = root,
          },
          discover = function()
            return {}
          end,
        })

        t.assert_equal(result.mode, "aligned_lsp")
        t.assert_equal(result.interpreter_path, root .. "/bin/python")
        t.assert_equal(result.provenance, "env_var")
      end)
    end,
  },
  {
    name = "resolve falls back without warning when no supported lsp is attached",
    fn = function()
      local discovered = {
        { label = ".venv", path = "/project/.venv/bin/python" },
      }

      local result = interpreter.resolve(1, {
        get_source_client_state = function()
          return {
            supported_clients = {},
          }
        end,
        discover = function()
          return vim.deepcopy(discovered)
        end,
      })

      t.assert_equal(result.mode, "fallback")
      t.assert_equal(result.warning, nil)
      t.assert_equal(result.allow_manual, true)
      t.assert_deep_equal(result.items, discovered)
    end,
  },
  {
    name = "resolve falls back with a warning when supported lsp is attached but recovery fails",
    fn = function()
      local discovered = {
        { label = ".venv", path = "/project/.venv/bin/python" },
      }

      local result = interpreter.resolve(1, {
        get_source_client_state = function()
          return {
            supported_clients = {
              {
                name = "pyright",
                config = {},
              },
            },
          }
        end,
        venv_selector_python = function()
          return nil
        end,
        env_vars = {},
        discover = function()
          return vim.deepcopy(discovered)
        end,
      })

      t.assert_equal(result.mode, "fallback")
      t.assert_equal(result.warning, interpreter.fallback_warning())
      t.assert_equal(result.allow_manual, true)
      t.assert_deep_equal(result.items, discovered)
    end,
  },
  {
    name = "pick_for_open uses a constrained confirmation picker for aligned lsp interpreters",
    fn = function()
      local captured_opts
      local picked

      interpreter.pick_for_open({
        bufnr = 1,
        resolve = function()
          return {
            mode = "aligned_lsp",
            interpreter_path = "/aligned/python",
            provenance = "client_settings",
            items = {
              {
                label = "Source buffer LSP",
                path = "/aligned/python",
              },
            },
            allow_manual = false,
            warning = nil,
          }
        end,
        pick_candidates = function(opts, callback)
          captured_opts = opts
          callback("/aligned/python", opts.items[1])
        end,
      }, function(result)
        picked = result
      end)

      t.assert_equal(captured_opts.prompt, "Confirm Python environment")
      t.assert_equal(captured_opts.allow_manual, false)
      t.assert_equal(#captured_opts.items, 1)
      t.assert_equal(picked.interpreter_path, "/aligned/python")
      t.assert_equal(picked.mode, "aligned_lsp")
    end,
  },
}
