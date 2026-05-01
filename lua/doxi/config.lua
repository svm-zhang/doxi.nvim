local M = {}

local defaults = {
	python_path = nil,
	lsp = {
		enabled = true,
		warn_unsupported = true,
		signature_help = {
			provider = "ambient",
			relative = "cursor",
			anchor_bias = "below",
			offset_x = 2,
			offset_y = 1,
			width = 100,
			height = 20,
			border = "rounded",
			focus = false,
			focusable = false,
			mouse = true,
			silent = true,
			zindex = 60,
		},
	},
	ui = {
		width = 100,
		height = 0.75,
		imports_height = 2,
		editor_height = 0.45,
		hints_height = 2,
		border = "rounded",
		lock_focus = true,
		tmux_navigation = true,
	},
	session_keymaps = {
		run_all = "<leader>ra",
		run_selection = "<leader>rs",
		restart = "<leader>rr",
		restart_rerun = "<leader>rR",
		apply = "<leader>da",
		cancel = "q",
		focus_next_pane = "<leader>j",
		focus_previous_pane = "<leader>k",
		tmux_left = "<C-h>",
		tmux_down = "<C-j>",
		tmux_up = "<C-k>",
		tmux_right = "<C-l>",
	},
}

local options = vim.deepcopy(defaults)

function M.setup(user_opts)
	options =
		vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
	return options
end

function M.get()
	return options
end

function M.defaults()
	return vim.deepcopy(defaults)
end

return M
