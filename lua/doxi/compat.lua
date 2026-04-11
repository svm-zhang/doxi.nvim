local M = {}

local minimum = {
  major = 0,
  minor = 10,
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

  if vim.fn.has("nvim-0.10") == 1 then
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

function M.assert_supported(version)
  local ok, message = M.check(version)
  if not ok then
    error(message)
  end
end

return M
