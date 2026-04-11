local M = {}

local function deep_equal(left, right)
  if type(left) ~= type(right) then
    return false
  end

  if type(left) ~= "table" then
    return left == right
  end

  for key, value in pairs(left) do
    if not deep_equal(value, right[key]) then
      return false
    end
  end

  for key, value in pairs(right) do
    if not deep_equal(value, left[key]) then
      return false
    end
  end

  return true
end

function M.assert_equal(actual, expected, message)
  if actual ~= expected then
    error(("%s\nexpected: %s\nactual: %s"):format(
      message or "Values are not equal.",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

function M.assert_true(value, message)
  if not value then
    error(message or "Expected value to be truthy.")
  end
end

function M.assert_deep_equal(actual, expected, message)
  if not deep_equal(actual, expected) then
    error(("%s\nexpected: %s\nactual: %s"):format(
      message or "Tables are not equal.",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

function M.wait_until(predicate, timeout_ms, message)
  local result
  local ok = vim.wait(timeout_ms or 3000, function()
    result = predicate()
    return not not result
  end, 20)

  if not ok then
    error(message or "Timed out waiting for condition.")
  end

  return result
end

function M.run_suite(modules)
  local failures = {}
  local total = 0

  for _, module_name in ipairs(modules) do
    local cases = require(module_name)
    for _, case in ipairs(cases) do
      total = total + 1
      local ok, err = pcall(case.fn)
      if not ok then
        table.insert(failures, ("%s :: %s\n%s"):format(module_name, case.name, err))
      end
    end
  end

  if #failures > 0 then
    io.stderr:write(table.concat(failures, "\n\n") .. "\n")
    os.exit(1)
  end

  print(("ok - %d tests"):format(total))
  os.exit(0)
end

return M
