local M = {}

function M.render_prompt_lines(input_lines)
  local lines = {}

  for index, line in ipairs(input_lines or {}) do
    local prefix = index == 1 and ">>> " or "... "
    table.insert(lines, prefix .. line)
  end

  return lines
end

function M.render_chunks(chunks)
  local rendered = {}

  for _, chunk in ipairs(chunks or {}) do
    vim.list_extend(rendered, M.render_prompt_lines(chunk.input_lines or {}))
    vim.list_extend(rendered, chunk.stdout_lines or {})
    vim.list_extend(rendered, chunk.stderr_lines or {})
    vim.list_extend(rendered, chunk.result_lines or {})
    vim.list_extend(rendered, chunk.traceback_lines or {})
  end

  return rendered
end

return M
