local config = require("doxi.config")
local util = require("doxi.util")

local M = {}
local hint_namespace = vim.api.nvim_create_namespace("doxi.hints")

local hint_entries = {
  { key = "run_all", label = "Run all", leader = true },
  { key = "run_selection", label = "Run selection", leader = true },
  { key = "apply", label = "Apply", leader = true },
  { key = "restart", label = "Restart", leader = true },
  { key = "restart_rerun", label = "Fresh rerun", leader = true },
  { key = "env_switch", label = "Env", leader = true },
  { key = "cancel", label = "Cancel", leader = false },
}

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

function M.resolve_size(value, available, minimum)
  local resolved = available

  if type(value) == "number" and value > 0 then
    if value <= 1 then
      resolved = math.floor(available * value)
    else
      resolved = math.floor(value)
    end
  end

  resolved = math.min(available, resolved)
  return math.max(minimum or 1, resolved)
end

function M.open(session)
  local ui_config = config.get().ui
  local hints = M.build_hints(config.get().session_keymaps)
  local available_width = math.max(80, vim.o.columns - 4)
  local total_width = M.resolve_size(ui_config.width, available_width, 80)
  local hints_height = math.max(#hints.lines, ui_config.hints_height or 2)
  local available_height = math.max(14, vim.o.lines - 10)
  local total_inner_height = M.resolve_size(ui_config.height, available_height, 14)
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

local function ensure_highlights()
  vim.api.nvim_set_hl(0, "DoxiHintLabel", {
    default = true,
    link = "Title",
  })
  vim.api.nvim_set_hl(0, "DoxiHintKey", {
    default = true,
    link = "Special",
  })
  vim.api.nvim_set_hl(0, "DoxiHintPrefix", {
    default = true,
    link = "Comment",
  })
end

local function build_entries(keymaps)
  local entries = {}

  for _, entry in ipairs(hint_entries) do
    local key = keymaps[entry.key]
    if type(key) ~= "string" or key == "" then
      key = "unmapped"
    end

    table.insert(entries, {
      label = entry.label,
      key = key,
      leader = entry.leader,
    })
  end

  return entries
end

local function shared_leader_prefix(entries)
  local prefix = "<leader>"
  local found = false

  for _, entry in ipairs(entries) do
    if entry.leader then
      if type(entry.key) ~= "string" or entry.key:sub(1, #prefix) ~= prefix then
        return nil
      end

      found = true
    end
  end

  if found then
    return prefix
  end

  return nil
end

local function display_key(entry, leader_prefix)
  if leader_prefix and entry.leader and entry.key:sub(1, #leader_prefix) == leader_prefix then
    return entry.key:sub(#leader_prefix + 1)
  end

  return entry.key
end

local function render_entry(entry, leader_prefix)
  local label = ("%s:"):format(entry.label)
  local key = display_key(entry, leader_prefix)

  return {
    text = ("%s %s"):format(label, key),
    label = label,
    key = key,
    key_group = entry.key_group or "DoxiHintKey",
  }
end

local function build_rows(entries, leader_prefix)
  local rows = {
    {},
    {},
  }

  if leader_prefix then
    table.insert(rows[1], {
      label = "Leader",
      key = leader_prefix,
      leader = false,
      key_group = "DoxiHintPrefix",
    })

    for _, index in ipairs({ 1, 2, 3 }) do
      table.insert(rows[1], entries[index])
    end

    for _, index in ipairs({ 4, 5, 6, 7 }) do
      table.insert(rows[2], entries[index])
    end
  else
    for _, index in ipairs({ 1, 2, 3, 4 }) do
      table.insert(rows[1], entries[index])
    end

    for _, index in ipairs({ 5, 6, 7 }) do
      table.insert(rows[2], entries[index])
    end
  end

  return rows
end

function M.build_hints(keymaps)
  local entries = build_entries(keymaps)
  local leader_prefix = shared_leader_prefix(entries)
  local rows = build_rows(entries, leader_prefix)
  local lines = {}
  local highlights = {}

  for row_index, row in ipairs(rows) do
    local line = ""

    for entry_index, entry in ipairs(row) do
      if entry_index > 1 then
        line = line .. "    "
      end

      local start_col = #line
      local rendered = render_entry(entry, leader_prefix)
      line = line .. rendered.text

      table.insert(highlights, {
        line = row_index - 1,
        start_col = start_col,
        end_col = start_col + #rendered.label,
        group = "DoxiHintLabel",
      })
      table.insert(highlights, {
        line = row_index - 1,
        start_col = start_col + #rendered.label + 1,
        end_col = start_col + #rendered.text,
        group = rendered.key_group,
      })
    end

    table.insert(lines, line)
  end

  return {
    lines = lines,
    highlights = highlights,
  }
end

function M.set_hints(view, keymaps)
  ensure_highlights()

  local hints = M.build_hints(keymaps)
  M.set_hints_lines(view, hints.lines)
  vim.api.nvim_buf_clear_namespace(view.hints_bufnr, hint_namespace, 0, -1)

  for _, highlight in ipairs(hints.highlights) do
    vim.api.nvim_buf_add_highlight(
      view.hints_bufnr,
      hint_namespace,
      highlight.group,
      highlight.line,
      highlight.start_col,
      highlight.end_col
    )
  end
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
