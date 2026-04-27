local M = {}

local minimum = {
  major = 0,
  minor = 11,
  patch = 0,
}

local function format_version(version)
  if not version then
    return "unknown"
  end

  return ("%d.%d.%d"):format(
    version.major or 0,
    version.minor or 0,
    version.patch or 0
  )
end

local function is_supported(version)
  local current = {
    version.major or 0,
    version.minor or 0,
    version.patch or 0,
  }

  local required = {
    minimum.major,
    minimum.minor,
    minimum.patch,
  }

  for index = 1, 3 do
    if current[index] > required[index] then
      return true
    end

    if current[index] < required[index] then
      return false
    end
  end

  return true
end

function M.minimum()
  return {
    major = minimum.major,
    minor = minimum.minor,
    patch = minimum.patch,
  }
end

function M.minimum_string()
  return format_version(minimum)
end

function M.python_parser_message()
  return table.concat({
    "doxi.nvim requires the Python Treesitter parser for docstring detection.",
    "Install the `python` parser and restart Neovim.",
  }, "\n")
end

function M.check(version)
  if version ~= nil then
    if is_supported(version) then
      return true
    end

    return false, ("doxi.nvim requires Neovim %s+ (detected %s)."):format(
      M.minimum_string(),
      format_version(version)
    )
  end

  if vim.fn.has("nvim-0.11") == 1 then
    return true
  end

  local current_version = nil
  if type(vim.version) == "function" then
    current_version = vim.version()
  end

  return false, ("doxi.nvim requires Neovim %s+ (detected %s)."):format(
    M.minimum_string(),
    format_version(current_version)
  )
end

local function can_load_python_parser_with_language_api()
  if not vim.treesitter or not vim.treesitter.language then
    return nil
  end

  if type(vim.treesitter.language.add) ~= "function" then
    return nil
  end

  local ok, loaded_or_err = pcall(vim.treesitter.language.add, "python")
  if ok and loaded_or_err then
    return true
  end

  return false, loaded_or_err
end

local function can_load_python_parser_with_parser_api()
  if not vim.treesitter or type(vim.treesitter.get_parser) ~= "function" then
    return false
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  local ok, parser_or_nil, err = pcall(vim.treesitter.get_parser, bufnr, "python")

  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })

  if ok and parser_or_nil then
    return true
  end

  return false, err
end

function M.check_python_parser(parser_loader)
  local ok, err

  if parser_loader then
    ok, err = parser_loader("python")
  else
    ok, err = can_load_python_parser_with_language_api()
    if ok == nil then
      ok, err = can_load_python_parser_with_parser_api()
    end
  end

  if ok then
    return true
  end

  return false, M.python_parser_message(), err
end

function M.check_ready(opts)
  opts = opts or {}

  local ok, message = M.check(opts.version)
  if not ok then
    return false, message
  end

  local parser_ok, parser_message = M.check_python_parser(opts.parser_loader)
  if not parser_ok then
    return false, parser_message
  end

  return true
end

function M.assert_supported(version)
  local ok, message = M.check(version)
  if not ok then
    error(message)
  end
end

function M.assert_ready(opts)
  local ok, message = M.check_ready(opts)
  if not ok then
    error(message)
  end
end

return M
