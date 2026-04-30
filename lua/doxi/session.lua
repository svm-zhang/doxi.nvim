local backend = require("doxi.backend")
local config = require("doxi.config")
local examples_context = require("doxi.examples_context")
local interpreter = require("doxi.interpreter")
local inserter = require("doxi.inserter")
local lsp = require("doxi.lsp")
local selection = require("doxi.selection")
local shared_imports = require("doxi.shared_imports")
local transcript = require("doxi.transcript")
local tmux = require("doxi.tmux")
local ui = require("doxi.ui")
local util = require("doxi.util")

local M = {}

local Session = {}
Session.__index = Session

local active_session = nil
local session_id = 0

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

local function bind_common_keymaps(session, bufnr, keymaps)
  session:_map(bufnr, "n", keymaps.run_all, function()
    session:run_all()
  end, "Run all example code")

  session:_map(bufnr, "n", keymaps.restart, function()
    session:restart()
  end, "Restart Python session")

  session:_map(bufnr, "n", keymaps.restart_rerun, function()
    session:restart_and_rerun()
  end, "Restart and rerun example code")

  session:_map(bufnr, "n", keymaps.apply, function()
    session:apply()
  end, "Apply transcript")

  session:_map(bufnr, "n", keymaps.cancel, function()
    session:close()
  end, "Cancel example session")
end

local function valid_win(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local tmux_keymaps = {
  {
    key = "tmux_left",
    direction = "h",
    desc = "Navigate tmux pane left",
  },
  {
    key = "tmux_down",
    direction = "j",
    desc = "Navigate tmux pane down",
  },
  {
    key = "tmux_up",
    direction = "k",
    desc = "Navigate tmux pane up",
  },
  {
    key = "tmux_right",
    direction = "l",
    desc = "Navigate tmux pane right",
  },
}

local function create_session(target, interpreter_info, context)
  close_active_session()
  local current_config = config.get()
  session_id = session_id + 1

  local session = setmetatable({
    id = session_id,
    kind = target.kind,
    workflow = target.kind == "blank" and "new example" or "edit example",
    source_bufnr = target.source_bufnr,
    source_range = target.source_range,
    source_indent = target.source_indent or "",
    source_lines_snapshot = vim.deepcopy(target.source_lines_snapshot or {}),
    source_leading_blank_lines = vim.deepcopy(target.source_leading_blank_lines or {}),
    source_trailing_blank_lines = vim.deepcopy(target.source_trailing_blank_lines or {}),
    transcript_lines = {},
    shared_imports = vim.deepcopy((context and context.shared_imports) or {
      ordered = {},
      seen = {},
    }),
    editor_buffer_name = util.synthetic_editor_path(target.source_bufnr),
    interpreter_path = interpreter_info.interpreter_path,
    interpreter_mode = interpreter_info.mode,
    interpreter_provenance = interpreter_info.provenance,
    keymaps = vim.deepcopy(current_config.session_keymaps),
    ui_config = vim.deepcopy(current_config.ui),
    lsp_config = vim.deepcopy(current_config.lsp),
    closing = false,
    closed = false,
  }, Session)

  session.backend = backend.new({
    interpreter_path = interpreter_info.interpreter_path,
  })
  session.view = ui.open(session)
  session.imports_bufnr = session.view.imports_bufnr
  session.imports_winid = session.view.imports_winid
  session.editor_bufnr = session.view.editor_bufnr
  session.editor_winid = session.view.editor_winid
  session.output_bufnr = session.view.output_bufnr
  session.output_winid = session.view.output_winid
  session.hints_bufnr = session.view.hints_bufnr
  session.hints_winid = session.view.hints_winid
  session:_set_panes()

  ui.set_imports_lines(session.view, shared_imports.render_lines(session.shared_imports))
  ui.set_editor_lines(session.view, target.editor_lines or {})
  ui.set_output_lines(session.view, {})
  ui.set_hints(session.view, session.keymaps)
  session.lsp_state = lsp.attach_from_source({
    source_bufnr = session.source_bufnr,
    editor_bufnr = session.editor_bufnr,
    enabled = session.lsp_config.enabled,
    signature_help_config = session.lsp_config.signature_help,
  })
  session:_set_keymaps()
  session:_set_autocmds()
  ui.focus_editor(session.view)

  if session.lsp_config.warn_unsupported then
    if session.lsp_state.status == "unsupported" or session.lsp_state.status == "attach_failed" then
      util.notify(session.lsp_state.message, vim.log.levels.WARN)
    end
  end

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

local function open_with_request(request)
  interpreter.pick_for_open({
    bufnr = request.target.source_bufnr,
  }, function(result)
    if not result or not result.interpreter_path then
      return
    end

    local ok, err = pcall(create_session, request.target, result, request.context)
    if not ok then
      util.notify(err, vim.log.levels.ERROR)
      return
    end

    if result.warning then
      util.notify(result.warning, vim.log.levels.WARN)
    end
  end)
end

local function validate_open_opts(opts)
  if not opts or opts.range == 0 or not opts.line1 or not opts.line2 then
    return nil, "Visual-select an empty docstring line or contiguous doctest block first."
  end

  local line1, line2 = util.normalize_line_range(opts.line1, opts.line2)
  if not line1 or not line2 then
    return nil, "Visual-select an empty docstring line or contiguous doctest block first."
  end

  return {
    line1 = line1,
    line2 = line2,
    range = opts.range,
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
  local keymaps = self.keymaps

  self:_map(self.editor_bufnr, "x", keymaps.run_selection, ":DoxiRunSelection<CR>", "Run selected example code")
  bind_common_keymaps(self, self.editor_bufnr, keymaps)
  bind_common_keymaps(self, self.output_bufnr, keymaps)
  bind_common_keymaps(self, self.imports_bufnr, keymaps)
  bind_common_keymaps(self, self.hints_bufnr, keymaps)

  for _, pane in ipairs(self.owned_panes or {}) do
    self:_map(pane.bufnr, "n", keymaps.focus_next_pane, function()
      self:focus_next_pane()
    end, "Focus next doxi pane")

    self:_map(pane.bufnr, "n", keymaps.focus_previous_pane, function()
      self:focus_previous_pane()
    end, "Focus previous doxi pane")

    if self:_uses_tmux_navigation() then
      for _, mapping in ipairs(tmux_keymaps) do
        self:_map(pane.bufnr, "n", keymaps[mapping.key], function()
          self:navigate_tmux(mapping.direction)
        end, mapping.desc)
      end
    end
  end
end

function Session:_uses_tmux_navigation()
  return self.ui_config
    and self.ui_config.tmux_navigation ~= false
    and tmux.available()
end

function Session:_set_panes()
  self.work_panes = {
    {
      name = "imports",
      bufnr = self.imports_bufnr,
      winid = self.imports_winid,
    },
    {
      name = "editor",
      bufnr = self.editor_bufnr,
      winid = self.editor_winid,
    },
    {
      name = "output",
      bufnr = self.output_bufnr,
      winid = self.output_winid,
    },
  }

  self.owned_panes = vim.deepcopy(self.work_panes)
  table.insert(self.owned_panes, {
    name = "hints",
    bufnr = self.hints_bufnr,
    winid = self.hints_winid,
  })
  self.last_work_pane = "editor"
end

function Session:_work_pane_index_by_win(winid)
  for index, pane in ipairs(self.work_panes or {}) do
    if pane.winid == winid and valid_win(pane.winid) then
      return index
    end
  end

  return nil
end

function Session:_work_pane_index_by_name(name)
  for index, pane in ipairs(self.work_panes or {}) do
    if pane.name == name and valid_win(pane.winid) then
      return index
    end
  end

  return nil
end

function Session:_is_owned_win(winid)
  if not valid_win(winid) then
    return false
  end

  for _, pane in ipairs(self.owned_panes or {}) do
    if pane.winid == winid then
      return true
    end
  end

  return false
end

function Session:_owns_winid(winid)
  for _, pane in ipairs(self.owned_panes or {}) do
    if pane.winid == winid then
      return true
    end
  end

  return false
end

function Session:_is_owned_buf(bufnr)
  for _, pane in ipairs(self.owned_panes or {}) do
    if pane.bufnr == bufnr then
      return true
    end
  end

  return false
end

function Session:_remember_current_work_pane()
  local index = self:_work_pane_index_by_win(vim.api.nvim_get_current_win())
  if index then
    self.last_work_pane = self.work_panes[index].name
  end
end

function Session:_last_valid_session_win()
  local last_index = self:_work_pane_index_by_name(self.last_work_pane)
  if last_index then
    return self.work_panes[last_index].winid
  end

  for _, pane in ipairs(self.work_panes or {}) do
    if valid_win(pane.winid) then
      self.last_work_pane = pane.name
      return pane.winid
    end
  end

  return nil
end

function Session:_focus_work_pane(index)
  local panes = self.work_panes or {}
  local pane = panes[index]

  if not pane or not valid_win(pane.winid) then
    return
  end

  vim.api.nvim_set_current_win(pane.winid)
  self.last_work_pane = pane.name
end

function Session:_current_work_pane_index()
  local current_index = self:_work_pane_index_by_win(vim.api.nvim_get_current_win())
  if current_index then
    return current_index
  end

  return self:_work_pane_index_by_name(self.last_work_pane) or 2
end

function Session:focus_next_pane()
  if self.closed then
    return
  end

  local panes = self.work_panes or {}
  if #panes == 0 then
    return
  end

  local index = self:_current_work_pane_index() + 1
  if index > #panes then
    index = 1
  end

  self:_focus_work_pane(index)
end

function Session:focus_previous_pane()
  if self.closed then
    return
  end

  local panes = self.work_panes or {}
  if #panes == 0 then
    return
  end

  local index = self:_current_work_pane_index() - 1
  if index < 1 then
    index = #panes
  end

  self:_focus_work_pane(index)
end

function Session:navigate_tmux(direction)
  if self.closed then
    return
  end

  tmux.navigate(direction)
end

function Session:_refocus_if_needed()
  if
    self.closed
    or self.closing
    or not (self.ui_config and self.ui_config.lock_focus)
  then
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  if self:_is_owned_win(current_win) then
    self:_remember_current_work_pane()
    return
  end

  vim.schedule(function()
    if
      self.closed
      or self.closing
      or not (self.ui_config and self.ui_config.lock_focus)
    then
      return
    end

    if self:_is_owned_win(vim.api.nvim_get_current_win()) then
      self:_remember_current_work_pane()
      return
    end

    local winid = self:_last_valid_session_win()
    if winid then
      pcall(vim.api.nvim_set_current_win, winid)
      self:_remember_current_work_pane()
    end
  end)
end

function Session:_handle_owned_pane_closed()
  if self.closed or self.closing then
    return
  end

  self:close({
    reason = "owned_pane_closed",
  })
end

function Session:_set_autocmds()
  self.autocmd_group = vim.api.nvim_create_augroup(("doxi_session_%d"):format(self.id), {
    clear = true,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = self.autocmd_group,
    callback = function()
      self:_refocus_if_needed()
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = self.autocmd_group,
    callback = function(args)
      local winid = tonumber(args.match)
      if winid and self:_owns_winid(winid) then
        vim.schedule(function()
          self:_handle_owned_pane_closed()
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = self.autocmd_group,
    callback = function(args)
      if self:_is_owned_buf(args.buf) then
        vim.schedule(function()
          self:_handle_owned_pane_closed()
        end)
      end
    end,
  })
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

function Session:_shared_import_code()
  if not self.shared_imports or not self.shared_imports.ordered or #self.shared_imports.ordered == 0 then
    return nil
  end

  return table.concat(self.shared_imports.ordered, "\n")
end

function Session:_set_shared_import_failure(result, err)
  local lines = {
    "Shared imports failed before running the current example:",
  }

  if err and err ~= "" then
    table.insert(lines, err)
  else
    table.insert(lines, "")
    vim.list_extend(lines, transcript.render_chunks(result and result.chunks or {}))
  end

  self:set_transcript(lines)
  util.notify("Shared imports failed before running the current example.", vim.log.levels.ERROR)
end

function Session:_execute_code(code)
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

function Session:_execute(code)
  if self.closed then
    return
  end

  if util.is_blank(code) then
    self:set_transcript({})
    util.notify("No code to run.", vim.log.levels.WARN)
    return
  end

  local import_code = self:_shared_import_code()
  if util.is_blank(import_code) then
    self:_execute_code(code)
    return
  end

  self.backend:execute(import_code, function(result, err)
    if self.closed then
      return
    end

    if err then
      self:_set_shared_import_failure(nil, err)
      return
    end

    local chunks = result and result.chunks or {}
    for _, chunk in ipairs(chunks) do
      if chunk.status == "error" then
        self:_set_shared_import_failure(result, nil)
        return
      end
    end

    self:_execute_code(code)
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
  self.backend:restart(function(_, err)
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
  self.closing = true

  if self.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, self.autocmd_group)
    self.autocmd_group = nil
  end

  if self.lsp_state then
    lsp.detach(self.lsp_state)
  end

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
  self.imports_bufnr = nil
  self.hints_bufnr = nil
  self.work_panes = nil
  self.owned_panes = nil
  self.lsp_state = nil
  self.transcript_lines = {}
end

function M.prepare_open(opts)
  local normalized, err = validate_open_opts(opts)
  if not normalized then
    return nil, err
  end

  local target, target_err = create_target(normalized.line1, normalized.line2)
  if not target then
    return nil, target_err
  end

  local context, context_err = examples_context.build({
    bufnr = target.source_bufnr,
    start_row = normalized.line1,
    end_row = normalized.line2,
  })
  if not context then
    return nil, context_err
  end

  return {
    target = target,
    context = context,
  }
end

function M.open_prepared(request)
  if not request or not request.target then
    return nil, "Invalid doxi open request."
  end

  open_with_request(request)
  return true
end

function M.open(opts)
  local request, err = M.prepare_open(opts)
  if not request then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  M.open_prepared(request)
end

function M.open_visual()
  local line1, line2 = util.get_visual_line_range()
  util.escape_visual_mode()

  local request, err = M.prepare_open({
    line1 = line1,
    line2 = line2,
    range = (line1 and line2) and 2 or 0,
  })
  if not request then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  M.open_prepared(request)
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
