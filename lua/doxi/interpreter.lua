local env = require("doxi.env")
local lsp = require("doxi.lsp")
local util = require("doxi.util")

local M = {}

local fallback_warning =
  "doxi.nvim could not determine the interpreter used by the attached source-buffer LSP. The session is using a fallback interpreter, so editor assistance and code execution may not match."

local aligned_labels = {
  client_settings = "Source buffer LSP",
  cmd_env = "Source buffer LSP",
  env_var = "Source buffer LSP (environment)",
  venv_selector = "Source buffer LSP (venv-selector)",
}

local function is_executable(path)
  return type(path) == "string" and path ~= "" and vim.fn.executable(path) == 1
end

local function python_from_env_root(root, executable_check)
  local check = executable_check or is_executable
  if type(root) ~= "string" or root == "" then
    return nil
  end

  local candidates = {
    util.join_paths(root, "bin", "python"),
    util.join_paths(root, "Scripts", "python.exe"),
    util.join_paths(root, "Scripts", "python"),
  }

  for _, candidate in ipairs(candidates) do
    if check(candidate) then
      return candidate
    end
  end

  return nil
end

local function python_from_settings(settings, executable_check)
  local check = executable_check or is_executable
  if type(settings) ~= "table" then
    return nil
  end

  local python = settings.python
  if type(python) ~= "table" then
    return nil
  end

  if check(python.pythonPath) then
    return python.pythonPath
  end

  if type(python.venv) == "string" and python.venv ~= "" and type(python.venvPath) == "string" and python.venvPath ~= "" then
    return python_from_env_root(util.join_paths(python.venvPath, python.venv), check)
  end

  return nil
end

local function python_from_cmd_env(cmd_env, executable_check)
  if type(cmd_env) ~= "table" then
    return nil
  end

  return python_from_env_root(cmd_env.VIRTUAL_ENV or cmd_env.CONDA_PREFIX, executable_check)
end

local function client_settings(client)
  if type(client) ~= "table" then
    return nil
  end

  if client.config and type(client.config.settings) == "table" then
    return client.config.settings
  end

  return client.settings
end

local function recover_from_clients(clients, executable_check)
  for _, client in ipairs(clients or {}) do
    local path = python_from_settings(client_settings(client), executable_check)
    if path then
      return {
        interpreter_path = path,
        provenance = "client_settings",
        client_name = client.name,
      }
    end

    path = python_from_cmd_env(client.config and client.config.cmd_env or nil, executable_check)
    if path then
      return {
        interpreter_path = path,
        provenance = "cmd_env",
        client_name = client.name,
      }
    end
  end

  return nil
end

function M._venv_selector_python(executable_check)
  local ok, plugin = pcall(require, "venv-selector")
  if not ok or type(plugin) ~= "table" or type(plugin.python) ~= "function" then
    return nil
  end

  local path = plugin.python()
  if (executable_check or is_executable)(path) then
    return path
  end

  return nil
end

local function recover_from_env_vars(env_vars, executable_check)
  local vars = env_vars or vim.env
  return python_from_env_root(vars.VIRTUAL_ENV or vars.CONDA_PREFIX, executable_check)
end

local function fallback_result(bufnr, discover, warning)
  return {
    mode = "fallback",
    interpreter_path = nil,
    provenance = "discovered",
    items = discover(bufnr),
    allow_manual = true,
    warning = warning,
  }
end

function M.resolve(bufnr, opts)
  opts = opts or {}

  local source_client_state = (opts.get_source_client_state or lsp.source_client_state)(bufnr)
  local executable_check = opts.is_executable or is_executable
  local discover = opts.discover or env.discover
  local venv_selector_python = opts.venv_selector_python or M._venv_selector_python
  local env_vars = opts.env_vars or vim.env

  if #source_client_state.supported_clients == 0 then
    return fallback_result(bufnr, discover, nil)
  end

  local recovered = recover_from_clients(source_client_state.supported_clients, executable_check)
  if not recovered then
    local venv_selector_path = venv_selector_python(executable_check)
    if venv_selector_path then
      recovered = {
        interpreter_path = venv_selector_path,
        provenance = "venv_selector",
      }
    end
  end

  if not recovered then
    local env_var_path = recover_from_env_vars(env_vars, executable_check)
    if env_var_path then
      recovered = {
        interpreter_path = env_var_path,
        provenance = "env_var",
      }
    end
  end

  if recovered then
    return {
      mode = "aligned_lsp",
      interpreter_path = recovered.interpreter_path,
      provenance = recovered.provenance,
      items = {
        {
          path = recovered.interpreter_path,
          label = aligned_labels[recovered.provenance] or "Source buffer LSP",
        },
      },
      allow_manual = false,
      warning = nil,
    }
  end

  return fallback_result(bufnr, discover, fallback_warning)
end

function M.pick_for_open(opts, callback)
  opts = opts or {}

  local result = (opts.resolve or M.resolve)(opts.bufnr, opts)
  local prompt = result.mode == "aligned_lsp" and "Confirm Python environment" or "Select Python environment"

  (opts.pick_candidates or env.pick_candidates)({
    bufnr = opts.bufnr,
    current = result.interpreter_path,
    items = result.items,
    allow_manual = result.allow_manual,
    prompt = prompt,
  }, function(path, choice)
    if not path then
      callback(nil)
      return
    end

    local selected = vim.deepcopy(result)
    selected.interpreter_path = path
    if choice and choice.manual then
      selected.provenance = "manual"
    end

    callback(selected)
  end)
end

function M.fallback_warning()
  return fallback_warning
end

return M
