local config = require("doxi.config")
local util = require("doxi.util")

local M = {}
local python_executable_names = {
  python = true,
  python3 = true,
  ["python.exe"] = true,
  ["python3.exe"] = true,
}

local function normalize_candidate_path(path)
  local normalized = util.normalize_path(path)
  if type(normalized) ~= "string" or normalized == "" then
    return nil
  end

  return normalized
end

local function environment_root_key(path)
  local normalized = normalize_candidate_path(path)
  if not normalized then
    return nil
  end

  local executable_name = vim.fs.basename(normalized)
  if not python_executable_names[executable_name] then
    return nil
  end

  local executable_dir = vim.fs.dirname(normalized)
  local container_dir = executable_dir and vim.fs.basename(executable_dir) or nil
  if container_dir ~= "bin" and container_dir ~= "Scripts" then
    return nil
  end

  return normalize_candidate_path(vim.fs.dirname(executable_dir))
end

local function is_path_candidate(label)
  return label == "python (PATH)" or label == "python3 (PATH)"
end

local function path_separator()
  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    return ";"
  end

  return ":"
end

local function split_path(path_value)
  if type(path_value) ~= "string" or path_value == "" then
    return {}
  end

  return vim.split(path_value, path_separator(), {
    plain = true,
    trimempty = true,
  })
end

local function executable_dirs_for_root(root)
  if type(root) ~= "string" or root == "" then
    return {}
  end

  return {
    normalize_candidate_path(util.join_paths(root, "bin")),
    normalize_candidate_path(util.join_paths(root, "Scripts")),
  }
end

local function python_candidates_for_root(root)
  if type(root) ~= "string" or root == "" then
    return {}
  end

  return {
    normalize_candidate_path(util.join_paths(root, "bin", "python")),
    normalize_candidate_path(util.join_paths(root, "Scripts", "python.exe")),
    normalize_candidate_path(util.join_paths(root, "Scripts", "python")),
  }
end

local function global_path_value(env_vars)
  local vars = env_vars or vim.env
  local excluded = {}

  for _, root in ipairs({ vars.VIRTUAL_ENV, vars.CONDA_PREFIX }) do
    for _, dir in ipairs(executable_dirs_for_root(root)) do
      if dir then
        excluded[dir] = true
      end
    end
  end

  local filtered = {}
  for _, dir in ipairs(split_path(vars.PATH)) do
    local normalized_dir = normalize_candidate_path(dir)
    if normalized_dir and not excluded[normalized_dir] then
      table.insert(filtered, normalized_dir)
    end
  end

  return table.concat(filtered, path_separator())
end

local function path_lookup(command, path_value, executable_check)
  local check = executable_check or function(path)
    return path and path ~= "" and vim.fn.executable(path) == 1
  end
  if type(path_value) ~= "string" or path_value == "" or type(command) ~= "string" or command == "" then
    return nil
  end

  for _, dir in ipairs(split_path(path_value)) do
    local candidate = normalize_candidate_path(util.join_paths(dir, command))
    if candidate and check(candidate) then
      return candidate
    end

    if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
      local windows_candidate = normalize_candidate_path(util.join_paths(dir, command .. ".exe"))
      if windows_candidate and check(windows_candidate) then
        return windows_candidate
      end
    end
  end

  return nil
end

local function parent_directories(start_dir)
  local dirs = {}
  local dir = start_dir

  while dir and dir ~= "" do
    table.insert(dirs, dir)
    local parent = vim.fs.dirname(dir)
    if parent == dir or parent == "/" then
      break
    end
    dir = parent
  end

  return dirs
end

function M.project_context(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local start_dir = path ~= "" and vim.fs.dirname(path) or vim.uv.cwd()
  local marker = vim.fs.find({
    "pyproject.toml",
    ".git",
    "setup.py",
    "setup.cfg",
    "requirements.txt",
  }, {
    upward = true,
    path = start_dir,
  })[1]

  if marker then
    return vim.fs.dirname(marker), start_dir
  end

  return start_dir, start_dir
end

function M._poetry_executable(project_root)
  if not project_root or vim.fn.executable("poetry") ~= 1 or vim.system == nil then
    return nil
  end

  local result = vim.system({ "poetry", "env", "info", "--executable" }, {
    cwd = project_root,
    text = true,
  }):wait()

  if result.code ~= 0 then
    return nil
  end

  local path = vim.trim(result.stdout or "")
  if path == "" then
    return nil
  end

  return path
end

function M._normalize_candidate_path(path)
  return normalize_candidate_path(path)
end

function M._environment_root_key(path)
  return environment_root_key(path)
end

function M._global_path_value(env_vars)
  return global_path_value(env_vars)
end

function M._path_lookup(command, path_value, executable_check)
  return path_lookup(command, path_value, executable_check)
end

local function add_candidate(candidates, seen, seen_environment_roots, opts, path, label)
  if not path or path == "" or not opts.is_executable(path) then
    return
  end

  local normalized_path = opts.normalize_path(path)
  if not normalized_path or seen[normalized_path] then
    return
  end

  local env_root = environment_root_key(normalized_path)
  if env_root and is_path_candidate(label) and seen_environment_roots[env_root] then
    return
  end

  seen[normalized_path] = true
  if env_root and not is_path_candidate(label) then
    seen_environment_roots[env_root] = true
  end

  table.insert(candidates, {
    path = normalized_path,
    label = label,
  })
end

local function add_root_candidate(candidates, seen, seen_environment_roots, opts, root, label)
  for _, candidate in ipairs(python_candidates_for_root(root)) do
    add_candidate(candidates, seen, seen_environment_roots, opts, candidate, label)
    if candidate and seen[opts.normalize_path(candidate)] then
      return
    end
  end
end

function M._collect_candidates(opts)
  local candidates = {}
  local seen = {}
  local seen_environment_roots = {}
  opts = vim.tbl_extend("force", {
    normalize_path = normalize_candidate_path,
  }, opts or {})

  add_candidate(candidates, seen, seen_environment_roots, opts, opts.config_path, "Configured interpreter")

  if opts.virtual_env and opts.virtual_env ~= "" then
    add_root_candidate(candidates, seen, seen_environment_roots, opts, opts.virtual_env, "VIRTUAL_ENV")
  end

  for _, dir in ipairs(parent_directories(opts.start_dir)) do
    add_root_candidate(candidates, seen, seen_environment_roots, opts, util.join_paths(dir, ".venv"), ".venv")
    add_root_candidate(candidates, seen, seen_environment_roots, opts, util.join_paths(dir, "venv"), "venv")
  end

  if opts.poetry_lookup then
    add_candidate(
      candidates,
      seen,
      seen_environment_roots,
      opts,
      opts.poetry_lookup(opts.project_root),
      "Poetry"
    )
  end

  add_candidate(candidates, seen, seen_environment_roots, opts, opts.python_path, "python (PATH)")
  add_candidate(candidates, seen, seen_environment_roots, opts, opts.python3_path, "python3 (PATH)")
  add_candidate(
    candidates,
    seen,
    seen_environment_roots,
    opts,
    opts.global_python_path,
    "python (PATH)"
  )
  add_candidate(
    candidates,
    seen,
    seen_environment_roots,
    opts,
    opts.global_python3_path,
    "python3 (PATH)"
  )

  return candidates
end

function M.discover(bufnr)
  local project_root, start_dir = M.project_context(bufnr)
  local user_config = config.get()
  local executable_check = function(path)
    return path and path ~= "" and vim.fn.executable(path) == 1
  end
  local global_path = global_path_value(vim.env)

  return M._collect_candidates({
    config_path = user_config.python_path,
    virtual_env = vim.env.VIRTUAL_ENV,
    start_dir = start_dir,
    project_root = project_root,
    poetry_lookup = M._poetry_executable,
    python3_path = vim.fn.exepath("python3"),
    python_path = vim.fn.exepath("python"),
    global_python_path = path_lookup("python", global_path, executable_check),
    global_python3_path = path_lookup("python3", global_path, executable_check),
    is_executable = executable_check,
  })
end

function M.resolve_default(bufnr)
  local candidates = M.discover(bufnr)
  if #candidates == 0 then
    return nil, "No Python interpreter found."
  end

  return candidates[1].path, candidates
end

function M.pick_candidates(opts, callback)
  local items = vim.deepcopy(opts.items or {})
  local allow_manual = opts.allow_manual ~= false

  if allow_manual then
    table.insert(items, {
      label = "Enter path manually...",
      path = nil,
      manual = true,
    })
  end

  vim.ui.select(items, {
    prompt = opts.prompt or "Select Python environment",
    format_item = function(item)
      if item.path then
        return ("%s [%s]"):format(item.label, item.path)
      end

      return item.label
    end,
  }, function(choice)
    if not choice then
      callback(nil, nil)
      return
    end

    if choice.path then
      callback(choice.path, choice)
      return
    end

    if vim.ui.input then
      vim.ui.input({
        prompt = "Python interpreter path: ",
        default = opts.current or "",
      }, function(input)
        if not input or input == "" then
          callback(nil, nil)
          return
        end

        if vim.fn.executable(input) ~= 1 then
          util.notify(("Interpreter is not executable: %s"):format(input), vim.log.levels.ERROR)
          callback(nil, nil)
          return
        end

        callback(input, {
          label = "Manual path",
          path = input,
          manual = true,
        })
      end)
      return
    end

    local input = vim.fn.input("Python interpreter path: ", opts.current or "")
    if input == "" then
      callback(nil, nil)
      return
    end

    if vim.fn.executable(input) ~= 1 then
      util.notify(("Interpreter is not executable: %s"):format(input), vim.log.levels.ERROR)
      callback(nil, nil)
      return
    end

    callback(input, {
      label = "Manual path",
      path = input,
      manual = true,
    })
  end)
end

function M.pick_interpreter(opts, callback)
  M.pick_candidates({
    bufnr = opts.bufnr,
    current = opts.current,
    items = M.discover(opts.bufnr),
    allow_manual = true,
    prompt = "Select Python environment",
  }, callback)
end

return M
