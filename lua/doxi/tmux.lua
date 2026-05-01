local M = {}

local direction_flags = {
  h = "-L",
  j = "-D",
  k = "-U",
  l = "-R",
  p = "-l",
}

local function tmux_env(env)
  return env or vim.env
end

local function executable(env)
  local tmux = tmux_env(env).TMUX or ""

  if tmux:find("tmate", 1, true) then
    return "tmate"
  end

  return "tmux"
end

local function socket(env)
  local tmux = tmux_env(env).TMUX
  if type(tmux) ~= "string" or tmux == "" then
    return nil
  end

  return vim.split(tmux, ",", { plain = true })[1]
end

function M.available(env)
  env = tmux_env(env)

  if type(env.TMUX) ~= "string" or env.TMUX == "" then
    return false
  end

  if type(env.TMUX_PANE) ~= "string" or env.TMUX_PANE == "" then
    return false
  end

  return vim.fn.executable(executable(env)) == 1
end

function M._build_select_pane_args(direction, env)
  env = tmux_env(env)
  local flag = direction_flags[direction]

  if not flag then
    return nil, "Invalid tmux navigation direction."
  end

  local pane = env.TMUX_PANE
  if type(pane) ~= "string" or pane == "" then
    return nil, "No active tmux pane is available."
  end

  local socket_path = socket(env)
  if not socket_path or socket_path == "" then
    return nil, "No tmux socket is available."
  end

  return {
    executable(env),
    "-S",
    socket_path,
    "select-pane",
    "-t",
    pane,
    flag,
  }
end

function M.navigate(direction)
  local args = M._build_select_pane_args(direction)
  if not args then
    return false
  end

  if vim.fn.executable(args[1]) ~= 1 then
    return false
  end

  vim.fn.system(args)
  return vim.v.shell_error == 0
end

return M
