local config = require("doxi.config")
local util = require("doxi.util")

local M = {}

local function set_buffer_defaults(bufnr)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
end

local function set_window_defaults(winid, opts)
  vim.api.nvim_set_option_value("number", false, { win = winid })
  vim.api.nvim_set_option_value("relativenumber", false, { win = winid })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = winid })
  vim.api.nvim_set_option_value("wrap", false, { win = winid })
  vim.api.nvim_set_option_value("cursorline", opts.cursorline or false, { win = winid })
end

function M.open(session)
  local ui_config = config.get().ui
  local total_width = math.max(80, math.floor(vim.o.columns * ui_config.width))
  local hints_height = math.max(2, ui_config.hints_height or 2)
  local total_inner_height = math.max(14, math.floor((vim.o.lines - 10) * ui_config.height))
  local editor_height = math.max(6, math.floor(total_inner_height * ui_config.editor_height))
  local output_height = math.max(5, total_inner_height - editor_height - hints_height)
  local total_height = editor_height + output_height + hints_height + 6
  local row = math.max(1, math.floor((vim.o.lines - total_height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - total_width) / 2))

  local editor_bufnr = vim.api.nvim_create_buf(false, true)
  local output_bufnr = vim.api.nvim_create_buf(false, true)
  local hints_bufnr = vim.api.nvim_create_buf(false, true)

  set_buffer_defaults(editor_bufnr)
  set_buffer_defaults(output_bufnr)
  set_buffer_defaults(hints_bufnr)

  vim.api.nvim_set_option_value("filetype", "python", { buf = editor_bufnr })
  vim.api.nvim_set_option_value("modifiable", true, { buf = editor_bufnr })

  vim.api.nvim_set_option_value("filetype", "python", { buf = output_bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = output_bufnr })
  vim.api.nvim_set_option_value("readonly", true, { buf = output_bufnr })

  vim.api.nvim_set_option_value("filetype", "text", { buf = hints_bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = hints_bufnr })
  vim.api.nvim_set_option_value("readonly", true, { buf = hints_bufnr })

  local editor_winid = vim.api.nvim_open_win(editor_bufnr, true, {
    relative = "editor",
    row = row,
    col = col,
    width = total_width,
    height = editor_height,
    border = ui_config.border,
    style = "minimal",
    title = (" doxi %s "):format(session.workflow),
    title_pos = "center",
  })

  local output_winid = vim.api.nvim_open_win(output_bufnr, false, {
    relative = "editor",
    row = row + editor_height + 2,
    col = col,
    width = total_width,
    height = output_height,
    border = ui_config.border,
    style = "minimal",
    title = " doctest transcript ",
    title_pos = "center",
  })

  local hints_winid = vim.api.nvim_open_win(hints_bufnr, false, {
    relative = "editor",
    row = row + editor_height + output_height + 4,
    col = col,
    width = total_width,
    height = hints_height,
    border = ui_config.border,
    style = "minimal",
    title = " key hints ",
    title_pos = "center",
  })

  set_window_defaults(editor_winid, { cursorline = true })
  set_window_defaults(output_winid, { cursorline = false })
  set_window_defaults(hints_winid, { cursorline = false })

  return {
    editor_bufnr = editor_bufnr,
    editor_winid = editor_winid,
    output_bufnr = output_bufnr,
    output_winid = output_winid,
    hints_bufnr = hints_bufnr,
    hints_winid = hints_winid,
  }
end

function M.set_editor_lines(view, lines)
  util.set_buf_lines(view.editor_bufnr, lines)
end

function M.set_output_lines(view, lines)
  util.set_buf_lines(view.output_bufnr, lines or {})
end

function M.set_hints_lines(view, lines)
  util.set_buf_lines(view.hints_bufnr, lines or {})
end

function M.build_hint_lines(keymaps)
  return {
    table.concat({
      ("%s run all"):format(keymaps.run_all),
      ("%s run selection"):format(keymaps.run_selection),
      ("%s apply"):format(keymaps.apply),
    }, "   |   "),
    table.concat({
      ("%s restart"):format(keymaps.restart),
      ("%s fresh rerun"):format(keymaps.restart_rerun),
      ("%s env"):format(keymaps.env_switch),
      ("%s cancel"):format(keymaps.cancel),
    }, "   |   "),
  }
end

function M.focus_editor(view)
  if view and view.editor_winid and vim.api.nvim_win_is_valid(view.editor_winid) then
    vim.api.nvim_set_current_win(view.editor_winid)
  end
end

function M.close(view)
  if not view then
    return
  end

  util.close_win(view.editor_winid)
  util.close_win(view.output_winid)
  util.close_win(view.hints_winid)
  util.delete_buf(view.editor_bufnr)
  util.delete_buf(view.output_bufnr)
  util.delete_buf(view.hints_bufnr)
end

return M
