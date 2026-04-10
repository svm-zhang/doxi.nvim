local backend = require("doxi.backend")
local config = require("doxi.config")
local env = require("doxi.env")
local importer = require("doxi.importer")
local inserter = require("doxi.inserter")
local transcript = require("doxi.transcript")
local ui = require("doxi.ui")
local util = require("doxi.util")

local M = {}

local Session = {}
Session.__index = Session

local active_session = nil

local function current_line(bufnr, row)
  return vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
end

local function ensure_python_buffer()
  local bufnr = vim.api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= "python" then
    return nil, "doxi.nvim only supports Python buffers."
  end

  return bufnr
end

local function close_active_session()
  if active_session then
    active_session:close()
  end
end

local function create_session(mode, target, editor_lines)
  close_active_session()

  local interpreter_path, err = env.resolve_default(target.source_bufnr)
  if not interpreter_path then
    return nil, err
  end

  local session = setmetatable({
    mode = mode,
    source_bufnr = target.source_bufnr,
    source_cursor = target.source_cursor,
    source_range = target.source_range,
    source_indent = target.source_indent or "",
    source_line_snapshot = target.source_line_snapshot,
    source_lines_snapshot = target.source_lines_snapshot,
    transcript_lines = {},
    interpreter_path = interpreter_path,
  }, Session)

  session.backend = backend.new({
    interpreter_path = interpreter_path,
  })
  session.view = ui.open(session)
  session.editor_bufnr = session.view.editor_bufnr
  session.editor_winid = session.view.editor_winid
  session.output_bufnr = session.view.output_bufnr
  session.output_winid = session.view.output_winid

  ui.set_editor_lines(session.view, editor_lines or {})
  ui.set_output_lines(session.view, {})
  session:_set_keymaps()
  ui.focus_editor(session.view)

  active_session = session
  return session
end

local function create_insert_target()
  local bufnr, err = ensure_python_buffer()
  if not bufnr then
    return nil, err
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local line = current_line(bufnr, row)

  if not util.probably_in_python_docstring(bufnr, row) then
    return nil, "Place the cursor inside a Python docstring before opening a session."
  end

  return {
    source_bufnr = bufnr,
    source_cursor = { row, cursor[2] },
    source_indent = util.get_indent(line),
    source_line_snapshot = line,
  }
end

local function create_replace_target(line1, line2)
  local bufnr, err = ensure_python_buffer()
  if not bufnr then
    return nil, err
  end

  local selected_lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  local imported, import_err = importer.parse_doctest_block(selected_lines)
  if not imported then
    return nil, import_err
  end

  return {
    source_bufnr = bufnr,
    source_range = {
      start_row = line1,
      end_row = line2,
    },
    source_indent = imported.indent,
    source_lines_snapshot = selected_lines,
    editor_lines = imported.source_lines,
  }
end

function Session:_map(bufnr, mode, lhs, rhs, desc)
  if not lhs or lhs == "" then
    return
  end

  vim.keymap.set(mode, lhs, rhs, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = desc,
  })
end

function Session:_set_keymaps()
  local keymaps = config.get().session_keymaps

  self:_map(self.editor_bufnr, "n", keymaps.run_all, function()
    self:run_all()
  end, "Run all example code")

  self:_map(self.editor_bufnr, "x", keymaps.run_selection, function()
    self:run_selection()
  end, "Run selected example code")

  self:_map(self.editor_bufnr, "n", keymaps.restart, function()
    self:restart()
  end, "Restart Python session")

  self:_map(self.editor_bufnr, "n", keymaps.restart_rerun, function()
    self:restart_and_rerun()
  end, "Restart and rerun example code")

  self:_map(self.editor_bufnr, "n", keymaps.switch_interpreter, function()
    self:switch_interpreter()
  end, "Switch Python interpreter")

  self:_map(self.editor_bufnr, "n", keymaps.apply, function()
    self:apply_transcript()
  end, "Apply transcript")

  self:_map(self.editor_bufnr, "n", keymaps.copy, function()
    self:copy_transcript()
  end, "Copy transcript")

  self:_map(self.editor_bufnr, "n", keymaps.cancel, function()
    self:close()
  end, "Cancel example session")

  self:_map(self.output_bufnr, "n", keymaps.apply, function()
    self:apply_transcript()
  end, "Apply transcript")

  self:_map(self.output_bufnr, "n", keymaps.copy, function()
    self:copy_transcript()
  end, "Copy transcript")

  self:_map(self.output_bufnr, "n", keymaps.cancel, function()
    self:close()
  end, "Cancel example session")
end

function Session:set_transcript(lines)
  self.transcript_lines = vim.deepcopy(lines or {})
  ui.set_output_lines(self.view, self.transcript_lines)
end

function Session:get_editor_lines()
  return vim.api.nvim_buf_get_lines(self.editor_bufnr, 0, -1, false)
end

function Session:_execute(code)
  if util.is_blank(code) then
    self:set_transcript({})
    util.notify("No code to run.", vim.log.levels.WARN)
    return
  end

  self.backend:execute(code, function(result, err)
    if err then
      util.notify(err, vim.log.levels.ERROR)
      return
    end

    local lines = transcript.render_chunks(result and result.chunks or {})
    self:set_transcript(lines)
  end)
end

function Session:run_all()
  self:_execute(table.concat(self:get_editor_lines(), "\n"))
end

function Session:run_selection()
  if vim.api.nvim_get_current_buf() ~= self.editor_bufnr then
    util.notify("Focus the editor pane and select lines to run.", vim.log.levels.WARN)
    return
  end

  local start_row, end_row = util.get_visual_line_range()
  if not start_row then
    util.notify("Select some lines in the editor pane first.", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(self.editor_bufnr, start_row - 1, end_row, false)
  util.escape_visual_mode()
  self:_execute(table.concat(lines, "\n"))
end

function Session:restart(after_restart)
  self.backend:reset(function(_, err)
    if err then
      util.notify(err, vim.log.levels.ERROR)
      return
    end

    self:set_transcript({})

    if after_restart then
      after_restart()
    else
      util.notify("Python session restarted.")
    end
  end)
end

function Session:restart_and_rerun()
  self:restart(function()
    self:run_all()
  end)
end

function Session:switch_interpreter()
  env.pick_interpreter({
    bufnr = self.source_bufnr,
    current = self.interpreter_path,
  }, function(path)
    if not path or path == self.interpreter_path then
      return
    end

    self.interpreter_path = path
    self.backend:set_interpreter(path)

    if config.get().clear_transcript_on_env_switch then
      self:set_transcript({})
    end

    util.notify(("Switched interpreter to %s"):format(path))
  end)
end

function Session:copy_transcript()
  if not self.transcript_lines or #self.transcript_lines == 0 then
    util.notify("There is no transcript to copy yet.", vim.log.levels.WARN)
    return
  end

  local text = table.concat(self.transcript_lines, "\n")
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  util.notify("Transcript copied to the clipboard.")
end

function Session:insert_transcript()
  if self.mode ~= "insert" then
    util.notify("The active session is not in insert mode.", vim.log.levels.ERROR)
    return
  end

  local ok, err = inserter.insert({
    bufnr = self.source_bufnr,
    row = self.source_cursor[1],
    indent = self.source_indent,
    line_snapshot = self.source_line_snapshot,
  }, self.transcript_lines)

  if not ok then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  self:close()
end

function Session:replace_transcript()
  if self.mode ~= "replace" then
    util.notify("The active session is not in replace mode.", vim.log.levels.ERROR)
    return
  end

  local ok, err = inserter.replace({
    bufnr = self.source_bufnr,
    start_row = self.source_range.start_row,
    end_row = self.source_range.end_row,
    indent = self.source_indent,
    lines_snapshot = self.source_lines_snapshot,
  }, self.transcript_lines)

  if not ok then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  self:close()
end

function Session:apply_transcript()
  if self.mode == "insert" then
    self:insert_transcript()
    return
  end

  self:replace_transcript()
end

function Session:close()
  if self.backend then
    self.backend:stop()
  end

  if self.view then
    ui.close(self.view)
  end

  if active_session == self then
    active_session = nil
  end
end

function M.open_new()
  local target, err = create_insert_target()
  if not target then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  local _, session_err = create_session("insert", target, {})
  if session_err then
    util.notify(session_err, vim.log.levels.ERROR)
  end
end

function M.open_edit(opts)
  local line1 = opts and opts.line1 or nil
  local line2 = opts and opts.line2 or nil

  if not line1 or not line2 or line1 == 0 or line2 == 0 then
    line1, line2 = util.get_visual_line_range()
  end

  if not line1 or not line2 then
    util.notify("Select a contiguous doctest block before editing it.", vim.log.levels.ERROR)
    return
  end

  local target, err = create_replace_target(line1, line2)
  if not target then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  local _, session_err = create_session("replace", {
    source_bufnr = target.source_bufnr,
    source_range = target.source_range,
    source_indent = target.source_indent,
    source_lines_snapshot = target.source_lines_snapshot,
  }, target.editor_lines)

  if session_err then
    util.notify(session_err, vim.log.levels.ERROR)
  end
end

function M.get_active()
  return active_session
end

function M.run_all()
  if active_session then
    active_session:run_all()
  else
    util.notify("No active doxi session.", vim.log.levels.WARN)
  end
end

function M.run_selection()
  if active_session then
    active_session:run_selection()
  else
    util.notify("No active doxi session.", vim.log.levels.WARN)
  end
end

function M.restart()
  if active_session then
    active_session:restart()
  else
    util.notify("No active doxi session.", vim.log.levels.WARN)
  end
end

function M.restart_and_rerun()
  if active_session then
    active_session:restart_and_rerun()
  else
    util.notify("No active doxi session.", vim.log.levels.WARN)
  end
end

function M.switch_interpreter()
  if active_session then
    active_session:switch_interpreter()
  else
    util.notify("No active doxi session.", vim.log.levels.WARN)
  end
end

function M.copy_transcript()
  if active_session then
    active_session:copy_transcript()
  else
    util.notify("No active doxi session.", vim.log.levels.WARN)
  end
end

function M.insert_transcript()
  if active_session then
    active_session:insert_transcript()
  else
    util.notify("No active doxi session.", vim.log.levels.WARN)
  end
end

function M.replace_transcript()
  if active_session then
    active_session:replace_transcript()
  else
    util.notify("No active doxi session.", vim.log.levels.WARN)
  end
end

function M.cancel()
  if active_session then
    active_session:close()
  else
    util.notify("No active doxi session.", vim.log.levels.WARN)
  end
end

return M
