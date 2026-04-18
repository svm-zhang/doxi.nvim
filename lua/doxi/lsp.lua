local M = {}

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
