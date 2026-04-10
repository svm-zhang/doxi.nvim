local config = require("doxi.config")
local util = require("doxi.util")

local M = {}

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

function M._collect_candidates(opts)
  local candidates = {}
  local seen = {}

  local function add(path, label)
    if not path or path == "" or seen[path] or not opts.is_executable(path) then
      return
    end

    seen[path] = true
    table.insert(candidates, {
      path = path,
      label = label,
    })
  end

  add(opts.config_path, "Configured interpreter")

  if opts.virtual_env and opts.virtual_env ~= "" then
    add(util.join_paths(opts.virtual_env, "bin", "python"), "VIRTUAL_ENV")
  end

  for _, dir in ipairs(parent_directories(opts.start_dir)) do
    add(util.join_paths(dir, ".venv", "bin", "python"), ".venv")
    add(util.join_paths(dir, "venv", "bin", "python"), "venv")
  end

  if opts.poetry_lookup then
    add(opts.poetry_lookup(opts.project_root), "Poetry")
  end

  add(opts.python3_path, "python3")
  add(opts.python_path, "python")

  return candidates
end

function M.discover(bufnr)
  local project_root, start_dir = M.project_context(bufnr)
  local user_config = config.get()

  return M._collect_candidates({
    config_path = user_config.python_path,
    virtual_env = vim.env.VIRTUAL_ENV,
    start_dir = start_dir,
    project_root = project_root,
    poetry_lookup = M._poetry_executable,
    python3_path = vim.fn.exepath("python3"),
    python_path = vim.fn.exepath("python"),
    is_executable = function(path)
      return path and path ~= "" and vim.fn.executable(path) == 1
    end,
  })
end

function M.resolve_default(bufnr)
  local candidates = M.discover(bufnr)
  if #candidates == 0 then
    return nil, "No Python interpreter found."
  end

  return candidates[1].path, candidates
end

function M.pick_interpreter(opts, callback)
  local candidates = M.discover(opts.bufnr)
  local items = vim.deepcopy(candidates)

  table.insert(items, {
    label = "Enter path manually...",
    path = nil,
  })

  vim.ui.select(items, {
    prompt = "Select Python interpreter",
    format_item = function(item)
      if item.path then
        return ("%s [%s]"):format(item.label, item.path)
      end

      return item.label
    end,
  }, function(choice)
    if not choice then
      callback(nil)
      return
    end

    if choice.path then
      callback(choice.path)
      return
    end

    if vim.ui.input then
      vim.ui.input({
        prompt = "Python interpreter path: ",
        default = opts.current or "",
      }, function(input)
        if not input or input == "" then
          callback(nil)
          return
        end

        if vim.fn.executable(input) ~= 1 then
          util.notify(("Interpreter is not executable: %s"):format(input), vim.log.levels.ERROR)
          callback(nil)
          return
        end

        callback(input)
      end)
      return
    end

    local input = vim.fn.input("Python interpreter path: ", opts.current or "")
    if input == "" then
      callback(nil)
      return
    end

    if vim.fn.executable(input) ~= 1 then
      util.notify(("Interpreter is not executable: %s"):format(input), vim.log.levels.ERROR)
      callback(nil)
      return
    end

    callback(input)
  end)
end

return M
