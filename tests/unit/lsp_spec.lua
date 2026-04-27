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

local function with_current_buffer(bufnr, fn)
  local winid = vim.api.nvim_get_current_win()
  local previous = vim.api.nvim_win_get_buf(winid)

  vim.api.nvim_win_set_buf(winid, bufnr)

  local ok, err = xpcall(fn, debug.traceback)

  if vim.api.nvim_buf_is_valid(previous) then
    pcall(vim.api.nvim_win_set_buf, winid, previous)
  end

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
    name = "attach_from_source attaches supported clients, sets omnifunc, and registers doxi signature help state",
    fn = function()
      local editor_bufnr = vim.api.nvim_create_buf(false, true)
      local attached = {}

      local ok, err = xpcall(function()
        local result = lsp.attach_from_source({
          source_bufnr = 1,
          editor_bufnr = editor_bufnr,
          signature_help_config = {
            provider = "doxi",
            max_width = 72,
            zindex = 60,
          },
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
        t.assert_deep_equal(lsp._signature_help_config(editor_bufnr), {
          provider = "doxi",
          relative = "cursor",
          anchor_bias = "below",
          offset_x = 2,
          offset_y = 1,
          focus = false,
          focusable = false,
          mouse = true,
          max_width = 72,
          zindex = 60,
        })
        t.assert_deep_equal(lsp._signature_help_state(editor_bufnr).attached_client_ids, { 11 })

        lsp.detach({
          editor_bufnr = editor_bufnr,
          attached_client_ids = { 11 },
        }, function() end)

        t.assert_equal(lsp._signature_help_config(editor_bufnr), nil)
      end, debug.traceback)

      if vim.api.nvim_buf_is_valid(editor_bufnr) then
        pcall(vim.api.nvim_buf_delete, editor_bufnr, { force = true })
      end

      if not ok then
        error(err)
      end
    end,
  },
  {
    name = "attach_from_source leaves signature help ambient when provider is ambient",
    fn = function()
      local editor_bufnr = vim.api.nvim_create_buf(false, true)

      local ok, err = xpcall(function()
        local result = lsp.attach_from_source({
          source_bufnr = 1,
          editor_bufnr = editor_bufnr,
          signature_help_config = {
            provider = "ambient",
            max_width = 72,
          },
          get_clients = function()
            return {
              {
                id = 11,
                name = "pyright",
                supports_method = function(_, method)
                  return method == "textDocument/signatureHelp"
                end,
              },
            }
          end,
          buf_attach_client = function()
            return true
          end,
        })

        t.assert_equal(result.status, "attached")
        t.assert_equal(lsp._signature_help_config(editor_bufnr), nil)

        lsp.detach({
          editor_bufnr = editor_bufnr,
          attached_client_ids = { 11 },
        }, function() end)
      end, debug.traceback)

      if vim.api.nvim_buf_is_valid(editor_bufnr) then
        pcall(vim.api.nvim_buf_delete, editor_bufnr, { force = true })
      end

      if not ok then
        error(err)
      end
    end,
  },
  {
    name = "signature help provider normalization accepts only the provider surface",
    fn = function()
      t.assert_equal(lsp._signature_help_provider({
        provider = "doxi",
      }), "doxi")
      t.assert_equal(lsp._signature_help_provider({
        provider = "ambient",
      }), "ambient")
      t.assert_equal(lsp._signature_help_provider({
        provider = "unexpected",
      }), "ambient")
      t.assert_equal(lsp._signature_help_provider({}), "ambient")
    end,
  },
  {
    name = "show_signature_help renders through a doxi-owned floating preview for the editor pane",
    fn = function()
      local editor_bufnr = vim.api.nvim_create_buf(false, true)
      local preview_winid
      local preview_bufnr
      local captured = {}

      vim.api.nvim_set_option_value("filetype", "python", { buf = editor_bufnr })
      vim.api.nvim_buf_set_lines(editor_bufnr, 0, -1, false, {
        "parse_hgvs(",
      })

      local ok, err = xpcall(function()
        with_current_buffer(editor_bufnr, function()
          vim.api.nvim_win_set_cursor(0, { 1, 11 })

          lsp._register_signature_help(editor_bufnr, {
            attached_client_ids = { 11, 12 },
            config = {
              provider = "doxi",
              border = "rounded",
              height = 11,
              max_height = 9,
              max_width = 72,
              width = 40,
              zindex = 60,
            },
          })

          with_override(vim.lsp, "buf_request_all", function(bufnr, method, params, callback)
            t.assert_equal(bufnr, editor_bufnr)
            t.assert_equal(method, "textDocument/signatureHelp")
            local generated = params({
              offset_encoding = "utf-16",
            })
            t.assert_true(type(generated) == "table" and generated.textDocument ~= nil)

            callback({
              [11] = {
                result = {
                  signatures = {
                    {
                      label = "parse_hgvs(value, strict=False)",
                    },
                  },
                  activeSignature = 0,
                  activeParameter = 1,
                },
              },
              [12] = {
                result = {
                  signatures = {
                    {
                      label = "fallback(value)",
                    },
                  },
                },
              },
            }, {
              bufnr = editor_bufnr,
            })
          end, function()
            with_override(vim.lsp, "get_client_by_id", function(client_id)
              local names = {
                [11] = "pyright",
                [12] = "ruff",
              }

              return {
                id = client_id,
                name = names[client_id],
                offset_encoding = "utf-16",
                server_capabilities = {
                  signatureHelpProvider = {
                    triggerCharacters = { "(", "," },
                  },
                },
              }
            end, function()
              with_override(vim.lsp.util, "convert_signature_help_to_markdown_lines", function(result, ft, triggers)
                captured.convert = {
                  result = vim.deepcopy(result),
                  ft = ft,
                  triggers = vim.deepcopy(triggers),
                }

                return {
                  "parse_hgvs(value, strict=False)",
                }, { 0, 0, 0, 10 }
              end, function()
                with_override(vim.lsp.util, "open_floating_preview", function(lines, syntax, opts)
                  captured.preview = {
                    lines = vim.deepcopy(lines),
                    syntax = syntax,
                    opts = vim.deepcopy(opts),
                  }

                  preview_bufnr = vim.api.nvim_create_buf(false, true)
                  preview_winid = vim.api.nvim_open_win(preview_bufnr, false, {
                    relative = "cursor",
                    anchor = "SW",
                    row = 1,
                    col = 0,
                    width = 30,
                    height = 3,
                    style = "minimal",
                  })

                  return preview_bufnr, preview_winid
                end, function()
                  lsp.show_signature_help(editor_bufnr)
                end)
              end)
            end)
          end)

          local state = lsp._signature_help_state(editor_bufnr)
          t.assert_true(state.float_winid ~= nil and vim.api.nvim_win_is_valid(state.float_winid))
          t.assert_deep_equal(captured.convert, {
            result = {
              signatures = {
                {
                  label = "parse_hgvs(value, strict=False)",
                },
              },
              activeSignature = 0,
              activeParameter = 1,
            },
            ft = "python",
            triggers = { "(", "," },
          })
          t.assert_deep_equal(captured.preview.lines, {
            "parse_hgvs(value, strict=False)",
          })
          t.assert_equal(captured.preview.syntax, "markdown")
          t.assert_equal(captured.preview.opts.max_width, 72)
          t.assert_equal(captured.preview.opts.max_height, 9)
          t.assert_equal(captured.preview.opts.width, 40)
          t.assert_equal(captured.preview.opts.height, 11)
          t.assert_equal(captured.preview.opts.focus, false)
          t.assert_equal(captured.preview.opts.mouse, true)
          t.assert_equal(captured.preview.opts.relative, "cursor")
          t.assert_equal(captured.preview.opts.anchor_bias, "below")
          t.assert_equal(captured.preview.opts.offset_x, 2)
          t.assert_equal(captured.preview.opts.offset_y, 1)
          t.assert_equal(captured.preview.opts.title, "Signature Help: pyright")
          t.assert_equal(captured.preview.opts.provider, nil)
          t.assert_equal(captured.preview.opts._update_win, nil)
          t.assert_equal(vim.api.nvim_win_get_config(preview_winid).row, -1)
          t.assert_equal(vim.api.nvim_win_get_config(preview_winid).width, 40)
          t.assert_equal(vim.api.nvim_win_get_config(preview_winid).height, 11)
          t.assert_equal(vim.api.nvim_win_get_config(preview_winid).focusable, false)
          t.assert_equal(vim.api.nvim_win_get_config(preview_winid).mouse, true)

          lsp.detach({
            editor_bufnr = editor_bufnr,
            attached_client_ids = { 11, 12 },
          }, function() end)
        end)
      end, debug.traceback)

      if preview_winid and vim.api.nvim_win_is_valid(preview_winid) then
        pcall(vim.api.nvim_win_close, preview_winid, true)
      end

      if preview_bufnr and vim.api.nvim_buf_is_valid(preview_bufnr) then
        pcall(vim.api.nvim_buf_delete, preview_bufnr, { force = true })
      end

      if vim.api.nvim_buf_is_valid(editor_bufnr) then
        pcall(vim.api.nvim_buf_delete, editor_bufnr, { force = true })
      end

      if not ok then
        error(err)
      end
    end,
  },
  {
    name = "registering doxi signature help suppresses noice signature handling only for doxi buffers",
    fn = function()
      local editor_bufnr = vim.api.nvim_create_buf(false, true)
      local other_bufnr = vim.api.nvim_create_buf(false, true)
      local calls = {
        check = 0,
        signature = 0,
      }
      local stub = {
        check = function()
          calls.check = calls.check + 1
          return "checked"
        end,
        on_signature = function()
          calls.signature = calls.signature + 1
          return "signature"
        end,
      }
      local original_check = stub.check
      local original_on_signature = stub.on_signature
      local original_loaded = package.loaded["noice.lsp.signature"]

      package.loaded["noice.lsp.signature"] = stub

      local ok, err = xpcall(function()
        lsp._register_signature_help(editor_bufnr, {
          attached_client_ids = { 11 },
          config = {
            provider = "doxi",
            border = "rounded",
          },
        })

        with_current_buffer(editor_bufnr, function()
          t.assert_equal(stub.check(), nil)
        end)

        t.assert_equal(stub.on_signature(nil, {}, { bufnr = editor_bufnr }, {}), nil)

        with_current_buffer(other_bufnr, function()
          t.assert_equal(stub.check(), "checked")
        end)

        t.assert_equal(stub.on_signature(nil, {}, { bufnr = other_bufnr }, {}), "signature")
        t.assert_equal(calls.check, 1)
        t.assert_equal(calls.signature, 1)

        lsp._unregister_signature_help(editor_bufnr)
        t.assert_equal(stub.check, original_check)
        t.assert_equal(stub.on_signature, original_on_signature)
      end, debug.traceback)

      package.loaded["noice.lsp.signature"] = original_loaded

      if vim.api.nvim_buf_is_valid(editor_bufnr) then
        pcall(vim.api.nvim_buf_delete, editor_bufnr, { force = true })
      end

      if vim.api.nvim_buf_is_valid(other_bufnr) then
        pcall(vim.api.nvim_buf_delete, other_bufnr, { force = true })
      end

      if not ok then
        error(err)
      end
    end,
  },
  {
    name = "show_signature_help closes an existing preview when no signature is available",
    fn = function()
      local editor_bufnr = vim.api.nvim_create_buf(false, true)
      local preview_winid
      local preview_bufnr

      vim.api.nvim_set_option_value("filetype", "python", { buf = editor_bufnr })
      vim.api.nvim_buf_set_lines(editor_bufnr, 0, -1, false, {
        "parse_hgvs(",
      })

      local ok, err = xpcall(function()
        with_current_buffer(editor_bufnr, function()
          vim.api.nvim_win_set_cursor(0, { 1, 11 })

          lsp._register_signature_help(editor_bufnr, {
            attached_client_ids = { 11 },
            config = {
              provider = "doxi",
              border = "rounded",
            },
          })

          with_override(vim.lsp, "buf_request_all", function(bufnr, _, _, callback)
            callback({
              [11] = {
                result = {
                  signatures = {
                    {
                      label = "parse_hgvs(value)",
                    },
                  },
                },
              },
            }, {
              bufnr = bufnr,
            })
          end, function()
            with_override(vim.lsp, "get_client_by_id", function()
              return {
                id = 11,
                name = "pyright",
                offset_encoding = "utf-16",
                server_capabilities = {
                  signatureHelpProvider = {
                    triggerCharacters = { "(" },
                  },
                },
              }
            end, function()
              with_override(vim.lsp.util, "convert_signature_help_to_markdown_lines", function()
                return { "parse_hgvs(value)" }, { 0, 0, 0, 5 }
              end, function()
                with_override(vim.lsp.util, "open_floating_preview", function()
                  preview_bufnr = vim.api.nvim_create_buf(false, true)
                  preview_winid = vim.api.nvim_open_win(preview_bufnr, false, {
                    relative = "editor",
                    row = 0,
                    col = 0,
                    width = 20,
                    height = 2,
                    style = "minimal",
                  })

                  return preview_bufnr, preview_winid
                end, function()
                  lsp.show_signature_help(editor_bufnr)
                end)
              end)
            end)
          end)

          t.assert_true(preview_winid ~= nil and vim.api.nvim_win_is_valid(preview_winid))

          with_override(vim.lsp, "buf_request_all", function(bufnr, _, _, callback)
            callback({
              [11] = {
                result = nil,
              },
            }, {
              bufnr = bufnr,
            })
          end, function()
            lsp.show_signature_help(editor_bufnr)
          end)

          t.assert_equal(vim.api.nvim_win_is_valid(preview_winid), false)
          t.assert_equal(lsp._signature_help_state(editor_bufnr).float_winid, nil)

          lsp.detach({
            editor_bufnr = editor_bufnr,
            attached_client_ids = { 11 },
          }, function() end)
        end)
      end, debug.traceback)

      if preview_bufnr and vim.api.nvim_buf_is_valid(preview_bufnr) then
        pcall(vim.api.nvim_buf_delete, preview_bufnr, { force = true })
      end

      if vim.api.nvim_buf_is_valid(editor_bufnr) then
        pcall(vim.api.nvim_buf_delete, editor_bufnr, { force = true })
      end

      if not ok then
        error(err)
      end
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

      if vim.api.nvim_buf_is_valid(editor_bufnr) then
        pcall(vim.api.nvim_buf_delete, editor_bufnr, { force = true })
      end
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
