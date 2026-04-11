local backend = require("doxi.backend")
local config = require("doxi.config")
local env = require("doxi.env")
local inserter = require("doxi.inserter")
local selection = require("doxi.selection")
local transcript = require("doxi.transcript")
local ui = require("doxi.ui")
local util = require("doxi.util")

local M = {}

local Session = {}
Session.__index = Session

local active_session = nil

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

local function create_session(target, interpreter_path)
  close_active_session()

  local session = setmetatable({
    kind = target.kind,
    workflow = target.kind == "blank" and "new example" or "edit example",
    source_bufnr = target.source_bufnr,
    source_range = target.source_range,
    source_indent = target.source_indent or "",
    source_lines_snapshot = vim.deepcopy(target.source_lines_snapshot or {}),
    source_leading_blank_lines = vim.deepcopy(target.source_leading_blank_lines or {}),
    source_trailing_blank_lines = vim.deepcopy(target.source_trailing_blank_lines or {}),
    transcript_lines = {},
    interpreter_path = interpreter_path,
    closed = false,
  }, Session)

  session.backend = backend.new({
    interpreter_path = interpreter_path,
  })
  session.view = ui.open(session)
  session.editor_bufnr = session.view.editor_bufnr
  session.editor_winid = session.view.editor_winid
  session.output_bufnr = session.view.output_bufnr
  session.output_winid = session.view.output_winid
  session.hints_bufnr = session.view.hints_bufnr
  session.hints_winid = session.view.hints_winid

  ui.set_editor_lines(session.view, target.editor_lines or {})
  ui.set_output_lines(session.view, {})
  ui.set_hints(session.view, config.get().session_keymaps)
  session:_set_keymaps()
  ui.focus_editor(session.view)

  active_session = session
  return session
end

local function create_target(line1, line2)
  local bufnr, err = ensure_python_buffer()
  if not bufnr then
    return nil, err
  end

  return selection.build_target({
    bufnr = bufnr,
    start_row = line1,
    end_row = line2,
  })
end

local function open_with_target(target)
  env.pick_interpreter({
    bufnr = target.source_bufnr,
  }, function(path)
    if not path then
      return
    end

    local _, err = create_session(target, path)
    if err then
      util.notify(err, vim.log.levels.ERROR)
    end
  end)
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

  self:_map(self.editor_bufnr, "x", keymaps.run_selection, ":DoxiRunSelection<CR>", "Run selected example code")

  self:_map(self.editor_bufnr, "n", keymaps.restart, function()
    self:restart()
  end, "Restart Python session")

  self:_map(self.editor_bufnr, "n", keymaps.restart_rerun, function()
    self:restart_and_rerun()
  end, "Restart and rerun example code")

  self:_map(self.editor_bufnr, "n", keymaps.env_switch, function()
    self:env_switch()
  end, "Switch Python environment")

  self:_map(self.editor_bufnr, "n", keymaps.apply, function()
    self:apply()
  end, "Apply transcript")

  self:_map(self.editor_bufnr, "n", keymaps.cancel, function()
    self:close()
  end, "Cancel example session")

  self:_map(self.output_bufnr, "n", keymaps.apply, function()
    self:apply()
  end, "Apply transcript")

  self:_map(self.output_bufnr, "n", keymaps.cancel, function()
    self:close()
  end, "Cancel example session")

  self:_map(self.hints_bufnr, "n", keymaps.run_all, function()
    self:run_all()
  end, "Run all example code")

  self:_map(self.hints_bufnr, "n", keymaps.restart, function()
    self:restart()
  end, "Restart Python session")

  self:_map(self.hints_bufnr, "n", keymaps.restart_rerun, function()
    self:restart_and_rerun()
  end, "Restart and rerun example code")

  self:_map(self.hints_bufnr, "n", keymaps.env_switch, function()
    self:env_switch()
  end, "Switch Python environment")

  self:_map(self.hints_bufnr, "n", keymaps.apply, function()
    self:apply()
  end, "Apply transcript")

  self:_map(self.hints_bufnr, "n", keymaps.cancel, function()
    self:close()
  end, "Cancel example session")
end

function Session:set_transcript(lines)
  if self.closed then
    return
  end

  self.transcript_lines = vim.deepcopy(lines or {})
  ui.set_output_lines(self.view, self.transcript_lines)
end

function Session:get_editor_lines()
  return vim.api.nvim_buf_get_lines(self.editor_bufnr, 0, -1, false)
end

function Session:_execute(code)
  if self.closed then
    return
  end

  if util.is_blank(code) then
    self:set_transcript({})
    util.notify("No code to run.", vim.log.levels.WARN)
    return
  end

  self.backend:execute(code, function(result, err)
    if self.closed then
      return
    end

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

function Session:run_selection(opts)
  if vim.api.nvim_get_current_buf() ~= self.editor_bufnr then
    util.notify("Focus the editor pane and select lines to run.", vim.log.levels.WARN)
    return
  end

  if not opts or not opts.line1 or not opts.line2 or opts.range == 0 then
    util.notify("Select some lines in the editor pane first.", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(self.editor_bufnr, opts.line1 - 1, opts.line2, false)
  self:_execute(table.concat(lines, "\n"))
end

function Session:restart(after_restart)
  self.backend:reset(function(_, err)
    if self.closed then
      return
    end

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

function Session:env_switch()
  env.pick_interpreter({
    bufnr = self.source_bufnr,
    current = self.interpreter_path,
  }, function(path)
    if self.closed or not path or path == self.interpreter_path then
      return
    end

    self.interpreter_path = path
    self.backend:set_interpreter(path)

    if config.get().clear_transcript_on_env_switch then
      self:set_transcript({})
    end

    util.notify(("Switched environment to %s"):format(path))
  end)
end

function Session:apply()
  local ok, err = inserter.replace({
    bufnr = self.source_bufnr,
    start_row = self.source_range.start_row,
    end_row = self.source_range.end_row,
    indent = self.source_indent,
    lines_snapshot = self.source_lines_snapshot,
    leading_blank_lines = self.source_leading_blank_lines,
    trailing_blank_lines = self.source_trailing_blank_lines,
  }, self.transcript_lines)

  if not ok then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  self:close()
end

function Session:close()
  if self.closed then
    return
  end

  self.closed = true

  if self.backend then
    self.backend:stop()
  end

  if self.view then
    ui.close(self.view)
  end

  if active_session == self then
    active_session = nil
  end

  self.view = nil
  self.backend = nil
  self.editor_bufnr = nil
  self.output_bufnr = nil
  self.hints_bufnr = nil
  self.transcript_lines = {}
end

function M.open(opts)
  if not opts or opts.range == 0 or not opts.line1 or not opts.line2 then
    util.notify("Visual-select an empty docstring line or contiguous doctest block first.", vim.log.levels.ERROR)
    return
  end

  local target, err = create_target(opts.line1, opts.line2)
  if not target then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  open_with_target(target)
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

function M.run_selection(opts)
  if active_session then
    active_session:run_selection(opts)
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

function M.env_switch()
  if active_session then
    active_session:env_switch()
  else
    util.notify("No active doxi session.", vim.log.levels.WARN)
  end
end

function M.apply()
  if active_session then
    active_session:apply()
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
