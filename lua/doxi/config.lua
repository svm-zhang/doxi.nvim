local M = {}

local defaults = {
  python_path = nil,
  clear_transcript_on_env_switch = true,
  ui = {
    width = 100,
    height = 0.75,
    editor_height = 0.45,
    hints_height = 2,
    border = "rounded",
  },
  session_keymaps = {
    run_all = "<leader>ra",
    run_selection = "<leader>rs",
    restart = "<leader>rr",
    restart_rerun = "<leader>rR",
    env_switch = "<leader>re",
    apply = "<leader>da",
    cancel = "q",
  },
}

local options = vim.deepcopy(defaults)

function M.setup(user_opts)
  options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
  return options
end

function M.get()
  return options
end

function M.defaults()
  return vim.deepcopy(defaults)
end

return M
