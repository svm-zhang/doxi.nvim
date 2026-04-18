local lsp = require("doxi.lsp")
local t = require("tests")

local function with_override(target, key, value, fn)
  local original = target[key]
  target[key] = value

  local ok, err = xpcall(fn, debug.traceback)

  target[key] = original

  if not ok then
    error(err)
  end
end

return {
  {
    name = "attach_from_source returns disabled when the feature is disabled",
    fn = function()
      local result = lsp.attach_from_source({
        source_bufnr = 1,
        editor_bufnr = 2,
        enabled = false,
      })

      t.assert_equal(result.status, "disabled")
      t.assert_deep_equal(result.attached_client_ids, {})
      t.assert_deep_equal(result.features, {
        completion = false,
        signature_help = false,
        diagnostics = false,
      })
    end,
  },
  {
    name = "attach_from_source is a no-op when the source buffer has no clients",
    fn = function()
      local result = lsp.attach_from_source({
        source_bufnr = 1,
        editor_bufnr = 2,
        get_clients = function()
          return {}
        end,
      })

      t.assert_equal(result.status, "none")
      t.assert_deep_equal(result.source_client_names, {})
      t.assert_deep_equal(result.supported_client_names, {})
      t.assert_deep_equal(result.unsupported_client_names, {})
    end,
  },
  {
    name = "attach_from_source warns cleanly when only unsupported clients are attached",
    fn = function()
      local result = lsp.attach_from_source({
        source_bufnr = 1,
        editor_bufnr = 2,
        get_clients = function()
          return {
            { id = 7, name = "jedi_language_server" },
          }
        end,
      })

      t.assert_equal(result.status, "unsupported")
      t.assert_deep_equal(result.unsupported_client_names, { "jedi_language_server" })
      t.assert_equal(
        result.message,
        "doxi.nvim editor-pane LSP reuse does not support attached client(s): jedi_language_server."
      )
    end,
  },
  {
    name = "attach_from_source attaches supported clients and sets omnifunc as a completion fallback",
    fn = function()
      local editor_bufnr = vim.api.nvim_create_buf(false, true)
      local attached = {}

      local result = lsp.attach_from_source({
        source_bufnr = 1,
        editor_bufnr = editor_bufnr,
        get_clients = function()
          return {
            {
              id = 11,
              name = "pyright",
              supports_method = function(_, method)
                return method == "textDocument/completion"
                  or method == "textDocument/signatureHelp"
                  or method == "textDocument/publishDiagnostics"
              end,
            },
          }
        end,
        buf_attach_client = function(bufnr, client_id)
          table.insert(attached, { bufnr = bufnr, client_id = client_id })
          return true
        end,
      })

      t.assert_equal(result.status, "attached")
      t.assert_deep_equal(result.attached_client_ids, { 11 })
      t.assert_deep_equal(result.supported_client_names, { "pyright" })
      t.assert_deep_equal(result.features, {
        completion = true,
        signature_help = true,
        diagnostics = true,
      })
      t.assert_deep_equal(attached, {
        { bufnr = editor_bufnr, client_id = 11 },
      })
      t.assert_equal(vim.bo[editor_bufnr].omnifunc, "v:lua.vim.lsp.omnifunc")
    end,
  },
  {
    name = "attach_from_source detaches already attached clients if a later attach fails",
    fn = function()
      local detached = {}

      local result = lsp.attach_from_source({
        source_bufnr = 1,
        editor_bufnr = vim.api.nvim_create_buf(false, true),
        get_clients = function()
          return {
            {
              id = 11,
              name = "pyright",
              supports_method = function()
                return true
              end,
            },
            {
              id = 12,
              name = "ruff",
              supports_method = function()
                return true
              end,
            },
          }
        end,
        buf_attach_client = function(_, client_id)
          return client_id == 11
        end,
        buf_detach_client = function(_, client_id)
          table.insert(detached, client_id)
        end,
      })

      t.assert_equal(result.status, "attach_failed")
      t.assert_equal(result.message, "doxi.nvim could not attach ruff to the editor pane.")
      t.assert_deep_equal(detached, { 11 })
    end,
  },
  {
    name = "detach only removes clients from the editor buffer it owns",
    fn = function()
      local editor_bufnr = vim.api.nvim_create_buf(false, true)
      local detached = {}

      lsp.detach({
        editor_bufnr = editor_bufnr,
        attached_client_ids = { 21, 22 },
      }, function(bufnr, client_id)
        table.insert(detached, { bufnr = bufnr, client_id = client_id })
      end)

      t.assert_deep_equal(detached, {
        { bufnr = editor_bufnr, client_id = 21 },
        { bufnr = editor_bufnr, client_id = 22 },
      })
    end,
  },
  {
    name = "detach is a no-op when the editor buffer is already invalid",
    fn = function()
      local editor_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(editor_bufnr, { force = true })
      local called = false

      lsp.detach({
        editor_bufnr = editor_bufnr,
        attached_client_ids = { 21 },
      }, function()
        called = true
      end)

      t.assert_equal(called, false)
    end,
  },
}
