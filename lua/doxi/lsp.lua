local M = {}
local signature_help_states = {}
local signature_help_namespace = vim.api.nvim_create_namespace("doxi.signature_help")
local noice_signature_patch = nil

local supported_client_names = {
  basedpyright = true,
  pyright = true,
  pylsp = true,
  ruff = true,
}

local supported_client_order = {
  basedpyright = 1,
  pyright = 2,
  pylsp = 3,
  ruff = 4,
}

local function sorted_names(names)
  local items = vim.deepcopy(names or {})
  table.sort(items)
  return items
end

local function list_names(clients)
  local names = {}

  for _, client in ipairs(clients or {}) do
    if type(client.name) == "string" and client.name ~= "" then
      table.insert(names, client.name)
    end
  end

  return sorted_names(names)
end

function M._supported_client_names()
  return sorted_names(vim.tbl_keys(supported_client_names))
end

function M._is_supported_client(client)
  return client and supported_client_names[client.name] == true
end

local function sort_clients(clients)
  local items = vim.deepcopy(clients or {})

  table.sort(items, function(left, right)
    local left_rank = supported_client_order[left.name] or 100
    local right_rank = supported_client_order[right.name] or 100

    if left_rank == right_rank then
      return (left.name or "") < (right.name or "")
    end

    return left_rank < right_rank
  end)

  return items
end

function M._get_clients(bufnr)
  if not vim.lsp or type(vim.lsp.get_clients) ~= "function" then
    return {}
  end

  return vim.lsp.get_clients({
    bufnr = bufnr,
  })
end

function M._split_supported_clients(clients)
  local supported = {}
  local unsupported = {}

  for _, client in ipairs(clients or {}) do
    if M._is_supported_client(client) then
      table.insert(supported, client)
    else
      table.insert(unsupported, client)
    end
  end

  return supported, unsupported
end

function M.source_client_state(bufnr)
  local source_clients = M._get_clients(bufnr)
  local supported_clients, unsupported_clients = M._split_supported_clients(source_clients)

  supported_clients = sort_clients(supported_clients)
  unsupported_clients = sort_clients(unsupported_clients)

  return {
    source_clients = sort_clients(source_clients),
    supported_clients = supported_clients,
    unsupported_clients = unsupported_clients,
    source_client_names = list_names(source_clients),
    supported_client_names = list_names(supported_clients),
    unsupported_client_names = list_names(unsupported_clients),
  }
end

function M._client_features(client, bufnr)
  local features = {
    completion = false,
    signature_help = false,
    diagnostics = false,
  }

  if not client or type(client.supports_method) ~= "function" then
    return features
  end

  features.completion = client:supports_method("textDocument/completion", bufnr) or false
  features.signature_help = client:supports_method("textDocument/signatureHelp", bufnr) or false
  features.diagnostics = client:supports_method("textDocument/publishDiagnostics", bufnr) or false

  return features
end

function M._merge_features(left, right)
  return {
    completion = (left and left.completion) or (right and right.completion) or false,
    signature_help = (left and left.signature_help) or (right and right.signature_help) or false,
    diagnostics = (left and left.diagnostics) or (right and right.diagnostics) or false,
  }
end

local function resolve_signature_help_config(config)
  local normalized = vim.deepcopy(config or {})
  local provider = normalized.provider

  if provider ~= "doxi" then
    provider = "ambient"
  end

  return vim.tbl_deep_extend("force", {
    provider = "ambient",
    relative = "cursor",
    anchor_bias = "below",
    offset_x = 2,
    offset_y = 1,
    width = nil,
    height = nil,
    focus = false,
    focusable = false,
    mouse = true,
  }, normalized, {
    provider = provider,
  })
end

local function positive_integer(value)
  if type(value) ~= "number" or value <= 0 then
    return nil
  end

  return math.floor(value)
end

local function signature_help_state(bufnr)
  return signature_help_states[bufnr]
end

function M._signature_help_state(bufnr)
  local state = signature_help_state(bufnr)
  if not state then
    return nil
  end

  return {
    attached_client_ids = vim.deepcopy(state.attached_client_ids or {}),
    config = vim.deepcopy(state.config or {}),
    float_bufnr = state.float_bufnr,
    float_winid = state.float_winid,
    group = state.group,
  }
end

function M._signature_help_config(bufnr)
  local state = signature_help_state(bufnr)
  if not state then
    return nil
  end

  return vim.deepcopy(state.config)
end

function M._close_signature_help(bufnr)
  local state = signature_help_state(bufnr)
  if not state then
    return
  end

  if state.float_winid and vim.api.nvim_win_is_valid(state.float_winid) then
    pcall(vim.api.nvim_win_close, state.float_winid, true)
  end

  state.float_bufnr = nil
  state.float_winid = nil
end

function M._apply_signature_help_window_config(winid, config)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local updates = {}
  local window_config = vim.api.nvim_win_get_config(winid)
  local width = positive_integer(config and config.width)
  local height = positive_integer(config and config.height)
  local offset_y = positive_integer(config and config.offset_y)

  if width then
    updates.width = width
  end

  if height then
    updates.height = height
  end

  if config and config.focusable ~= nil then
    updates.focusable = config.focusable
  end

  if config and config.mouse ~= nil then
    updates.mouse = config.mouse
  end

  if
    offset_y
    and config
    and config.relative == "cursor"
    and type(window_config.anchor) == "string"
    and (window_config.relative == "cursor" or window_config.relative == "win")
  then
    local vertical_anchor = window_config.anchor:sub(1, 1)
    if vertical_anchor == "N" then
      updates.row = 1 + offset_y
    elseif vertical_anchor == "S" then
      updates.row = -offset_y
    end

    if updates.row then
      updates.relative = window_config.relative
      updates.anchor = window_config.anchor
      updates.col = window_config.col
      if window_config.relative == "win" then
        updates.win = window_config.win
      end
    end
  end

  if next(updates) == nil then
    return
  end

  pcall(vim.api.nvim_win_set_config, winid, updates)
end

local function uses_doxi_signature_help(bufnr)
  local state = bufnr and signature_help_state(bufnr) or nil
  return state and state.config and state.config.provider == "doxi"
end

function M._signature_help_provider(config)
  return resolve_signature_help_config(config).provider
end

function M._suppress_ambient_signature_help()
  if noice_signature_patch then
    return true
  end

  local ok, noice_signature = pcall(require, "noice.lsp.signature")
  if not ok or type(noice_signature) ~= "table" then
    return false
  end

  if type(noice_signature.check) ~= "function" or type(noice_signature.on_signature) ~= "function" then
    return false
  end

  noice_signature_patch = {
    module = noice_signature,
    check = noice_signature.check,
    on_signature = noice_signature.on_signature,
  }

  noice_signature.check = function(...)
    if uses_doxi_signature_help(vim.api.nvim_get_current_buf()) then
      return
    end

    return noice_signature_patch.check(...)
  end

  noice_signature.on_signature = function(err, result, ctx, config)
    local bufnr = ctx and ctx.bufnr or vim.api.nvim_get_current_buf()
    if uses_doxi_signature_help(bufnr) then
      return
    end

    return noice_signature_patch.on_signature(err, result, ctx, config)
  end

  return true
end

function M._restore_ambient_signature_help()
  if not noice_signature_patch then
    return
  end

  noice_signature_patch.module.check = noice_signature_patch.check
  noice_signature_patch.module.on_signature = noice_signature_patch.on_signature
  noice_signature_patch = nil
end

function M._signature_help_params(bufnr, make_position_params)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return nil
  end

  local build_position = make_position_params or vim.lsp.util.make_position_params
  return function(client)
    return build_position(winid, client.offset_encoding)
  end
end

function M._select_signature_help_response(results, client_ids, get_client_by_id)
  local get_client = get_client_by_id or vim.lsp.get_client_by_id

  for _, client_id in ipairs(client_ids or {}) do
    local response = results and results[client_id] or nil
    local result = response and response.result or nil
    if result and result.signatures and result.signatures[1] then
      return get_client(client_id), result
    end
  end

  return nil, nil
end

local function normalize_preview_size(opts)
  opts.width = positive_integer(opts.width)
  opts.height = positive_integer(opts.height)
end

local function apply_signature_help_highlight(preview_bufnr, highlight_range)
  if
    not highlight_range
    or not preview_bufnr
    or not vim.api.nvim_buf_is_valid(preview_bufnr)
    or not vim.hl
    or type(vim.hl.range) ~= "function"
  then
    return
  end

  vim.api.nvim_buf_clear_namespace(preview_bufnr, signature_help_namespace, 0, -1)
  vim.hl.range(
    preview_bufnr,
    signature_help_namespace,
    "LspSignatureActiveParameter",
    { highlight_range[1], highlight_range[2] },
    { highlight_range[3], highlight_range[4] }
  )
end

local function build_preview_options(bufnr, config, client_name)
  local opts = vim.tbl_deep_extend("force", {}, config)
  opts.provider = nil
  opts.focus_id = opts.focus_id or ("doxi.signature_help.%d"):format(bufnr)
  opts.title = opts.border and ("Signature Help: %s"):format(client_name) or nil

  normalize_preview_size(opts)

  return opts
end

local function open_signature_preview(bufnr, state, client, lines, open_floating_preview)
  local preview_opts = build_preview_options(bufnr, state.config, client.name)

  if state.float_winid and vim.api.nvim_win_is_valid(state.float_winid) then
    M._close_signature_help(bufnr)
  end

  local preview_bufnr, preview_winid = open_floating_preview(lines, "markdown", preview_opts)
  state.float_bufnr = preview_bufnr
  state.float_winid = preview_winid
  M._apply_signature_help_window_config(preview_winid, state.config)

  return preview_bufnr, preview_winid, preview_opts
end

function M.show_signature_help(bufnr, opts)
  local state = signature_help_state(bufnr)
  if not state or state.config.provider ~= "doxi" then
    return false
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    M._unregister_signature_help(bufnr)
    return false
  end

  local params = (opts and opts.params) or M._signature_help_params(bufnr, opts and opts.make_position_params)
  if not params then
    M._close_signature_help(bufnr)
    return false
  end

  state.request_seq = (state.request_seq or 0) + 1
  local request_seq = state.request_seq
  local request = (opts and opts.buf_request_all) or vim.lsp.buf_request_all
  local get_client_by_id = (opts and opts.get_client_by_id) or vim.lsp.get_client_by_id
  local convert_signature_help = (opts and opts.convert_signature_help_to_markdown_lines)
    or vim.lsp.util.convert_signature_help_to_markdown_lines
  local open_floating_preview = (opts and opts.open_floating_preview) or vim.lsp.util.open_floating_preview

  request(bufnr, "textDocument/signatureHelp", params, function(results, ctx)
    local current = signature_help_state(bufnr)
    if not current or current ~= state or current.request_seq ~= request_seq then
      return
    end

    if ctx and ctx.bufnr and ctx.bufnr ~= bufnr then
      return
    end

    local client, result = M._select_signature_help_response(results, current.attached_client_ids, get_client_by_id)
    if not client or not result then
      M._close_signature_help(bufnr)
      return
    end

    local triggers = vim.tbl_get(client.server_capabilities, "signatureHelpProvider", "triggerCharacters")
    local lines, highlight_range = convert_signature_help(result, vim.bo[bufnr].filetype, triggers)
    if not lines or vim.tbl_isempty(lines) then
      M._close_signature_help(bufnr)
      return
    end

    local preview_bufnr = open_signature_preview(
      bufnr,
      current,
      client,
      lines,
      open_floating_preview
    )
    apply_signature_help_highlight(preview_bufnr, highlight_range)
  end)

  return true
end

function M._schedule_signature_help(bufnr)
  local state = signature_help_state(bufnr)
  if not state or state.scheduled then
    return
  end

  state.scheduled = true

  vim.schedule(function()
    local current = signature_help_state(bufnr)
    if not current or current ~= state then
      return
    end

    current.scheduled = false
    M.show_signature_help(bufnr)
  end)
end

function M._register_signature_help(bufnr, opts)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  M._unregister_signature_help(bufnr)

  local config = resolve_signature_help_config(opts and opts.config or opts)
  if config.provider ~= "doxi" then
    return
  end

  M._suppress_ambient_signature_help()

  local state = {
    attached_client_ids = vim.deepcopy(opts and opts.attached_client_ids or {}),
    config = config,
    float_bufnr = nil,
    float_winid = nil,
    request_seq = 0,
    scheduled = false,
  }

  state.group = vim.api.nvim_create_augroup(("doxi.signature_help.%d"):format(bufnr), { clear = true })
  signature_help_states[bufnr] = state

  vim.api.nvim_create_autocmd({
    "TextChangedI",
    "TextChangedP",
    "CursorMovedI",
  }, {
    group = state.group,
    buffer = bufnr,
    callback = function()
      M._schedule_signature_help(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({
    "InsertLeave",
    "BufLeave",
    "WinLeave",
  }, {
    group = state.group,
    buffer = bufnr,
    callback = function()
      M._close_signature_help(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = state.group,
    buffer = bufnr,
    callback = function()
      M._unregister_signature_help(bufnr)
    end,
  })
end

function M._unregister_signature_help(bufnr)
  local state = signature_help_state(bufnr)
  if not state then
    return
  end

  M._close_signature_help(bufnr)

  if state.group then
    pcall(vim.api.nvim_del_augroup_by_id, state.group)
  end

  signature_help_states[bufnr] = nil

  if next(signature_help_states) == nil then
    M._restore_ambient_signature_help()
  end
end

function M._set_editor_buffer_features(bufnr, features)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if features and features.completion and vim.bo[bufnr].omnifunc == "" then
    vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
  end
end

function M.attach_from_source(opts)
  opts = opts or {}

  if opts.enabled == false then
    return {
      status = "disabled",
      editor_bufnr = opts.editor_bufnr,
      attached_client_ids = {},
      features = {
        completion = false,
        signature_help = false,
        diagnostics = false,
      },
    }
  end

  local source_bufnr = opts.source_bufnr
  local editor_bufnr = opts.editor_bufnr
  local get_clients = opts.get_clients or M._get_clients
  local attach_client = opts.buf_attach_client or vim.lsp.buf_attach_client
  local detach_client = opts.buf_detach_client or vim.lsp.buf_detach_client
  local source_clients = get_clients(source_bufnr)

  if #source_clients == 0 then
    return {
      status = "none",
      editor_bufnr = editor_bufnr,
      attached_client_ids = {},
      source_client_names = {},
      supported_client_names = {},
      unsupported_client_names = {},
      features = {
        completion = false,
        signature_help = false,
        diagnostics = false,
      },
    }
  end

  local supported, unsupported = M._split_supported_clients(source_clients)
  local unsupported_names = list_names(unsupported)

  if #supported == 0 then
    return {
      status = "unsupported",
      editor_bufnr = editor_bufnr,
      attached_client_ids = {},
      source_client_names = list_names(source_clients),
      supported_client_names = {},
      unsupported_client_names = unsupported_names,
      features = {
        completion = false,
        signature_help = false,
        diagnostics = false,
      },
      message = ("doxi.nvim editor-pane LSP reuse does not support attached client(s): %s."):format(
        table.concat(unsupported_names, ", ")
      ),
    }
  end

  local attached_client_ids = {}
  local features = {
    completion = false,
    signature_help = false,
    diagnostics = false,
  }

  for _, client in ipairs(supported) do
    local ok = attach_client(editor_bufnr, client.id)
    if not ok then
      M.detach({
        editor_bufnr = editor_bufnr,
        attached_client_ids = attached_client_ids,
      }, detach_client)

      return {
        status = "attach_failed",
        editor_bufnr = editor_bufnr,
        attached_client_ids = {},
        source_client_names = list_names(source_clients),
        supported_client_names = list_names(supported),
        unsupported_client_names = unsupported_names,
        features = {
          completion = false,
          signature_help = false,
          diagnostics = false,
        },
        message = ("doxi.nvim could not attach %s to the editor pane."):format(client.name),
      }
    end

    table.insert(attached_client_ids, client.id)
    features = M._merge_features(features, M._client_features(client, editor_bufnr))
  end

  M._set_editor_buffer_features(editor_bufnr, features)
  if features.signature_help then
    M._register_signature_help(editor_bufnr, {
      attached_client_ids = attached_client_ids,
      config = opts.signature_help_config,
    })
  end

  return {
    status = "attached",
    editor_bufnr = editor_bufnr,
    attached_client_ids = attached_client_ids,
    source_client_names = list_names(source_clients),
    supported_client_names = list_names(supported),
    unsupported_client_names = unsupported_names,
    features = features,
  }
end

function M.detach(state, detach_client)
  if not state or not state.editor_bufnr or not state.attached_client_ids then
    return
  end

  M._unregister_signature_help(state.editor_bufnr)

  if not vim.api.nvim_buf_is_valid(state.editor_bufnr) then
    return
  end

  local detach = detach_client or vim.lsp.buf_detach_client
  if type(detach) ~= "function" then
    return
  end

  for _, client_id in ipairs(state.attached_client_ids) do
    pcall(detach, state.editor_bufnr, client_id)
  end
end

return M
