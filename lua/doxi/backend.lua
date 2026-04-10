local util = require("doxi.util")

local M = {}

local Backend = {}
Backend.__index = Backend

local function job_is_running(job_id)
  if not job_id then
    return false
  end

  return vim.fn.jobwait({ job_id }, 0)[1] == -1
end

function Backend:_fail_pending(message)
  local pending = self.pending
  self.pending = {}

  for _, callback in pairs(pending) do
    vim.schedule(function()
      callback(nil, message)
    end)
  end
end

function Backend:_on_stdout(data)
  for _, line in ipairs(data or {}) do
    if line ~= "" then
      local ok, decoded = pcall(util.json_decode, line)
      if not ok then
        util.notify(("Backend emitted invalid JSON: %s"):format(line), vim.log.levels.ERROR)
      elseif decoded and decoded.id and self.pending[decoded.id] then
        local callback = self.pending[decoded.id]
        self.pending[decoded.id] = nil

        vim.schedule(function()
          if decoded.ok == false then
            callback(nil, decoded.error or "Python backend request failed.")
            return
          end

          callback(decoded.result, nil)
        end)
      end
    end
  end
end

function Backend:_on_stderr(data)
  local lines = {}

  for _, line in ipairs(data or {}) do
    if line ~= "" then
      table.insert(lines, line)
    end
  end

  if #lines > 0 then
    self.last_stderr = table.concat(lines, "\n")
  end
end

function Backend:_on_exit(code)
  self.job_id = nil

  if next(self.pending) == nil then
    return
  end

  local message = ("Python backend exited with code %d."):format(code or -1)
  if self.last_stderr and self.last_stderr ~= "" then
    message = ("%s\n%s"):format(message, self.last_stderr)
  end

  self:_fail_pending(message)
end

function Backend:start()
  if job_is_running(self.job_id) then
    return true
  end

  self.last_stderr = nil

  local job_id = vim.fn.jobstart({
    self.interpreter_path,
    "-u",
    self.bridge_path,
  }, {
    stdin = "pipe",
    on_stdout = function(_, data, _)
      self:_on_stdout(data)
    end,
    on_stderr = function(_, data, _)
      self:_on_stderr(data)
    end,
    on_exit = function(_, code, _)
      self:_on_exit(code)
    end,
  })

  if job_id <= 0 then
    return nil, ("Failed to start Python backend with %s."):format(self.interpreter_path)
  end

  self.job_id = job_id
  return true
end

function Backend:_request(payload, callback)
  local ok, err = self:start()
  if not ok then
    callback(nil, err)
    return
  end

  self.next_request_id = self.next_request_id + 1
  payload.id = self.next_request_id
  self.pending[payload.id] = callback

  local bytes = vim.fn.chansend(self.job_id, util.json_encode(payload) .. "\n")
  if bytes <= 0 then
    self.pending[payload.id] = nil
    callback(nil, "Failed to communicate with the Python backend.")
  end
end

function Backend:execute(code, callback)
  self:_request({
    action = "exec",
    code = code,
  }, callback)
end

function Backend:reset(callback)
  self:_request({
    action = "reset",
  }, callback or function() end)
end

function Backend:set_interpreter(path)
  self.interpreter_path = path
  self:stop()
end

function Backend:stop()
  if not self.job_id then
    return
  end

  local job_id = self.job_id
  self.job_id = nil

  pcall(vim.fn.chansend, job_id, util.json_encode({
    action = "quit",
    id = 0,
  }) .. "\n")
  pcall(vim.fn.jobstop, job_id)

  if next(self.pending) ~= nil then
    self:_fail_pending("Python backend stopped.")
  end
end

function M.new(opts)
  return setmetatable({
    bridge_path = opts.bridge_path
      or util.join_paths(util.get_plugin_root(), "python", "doxi_bridge.py"),
    interpreter_path = opts.interpreter_path,
    job_id = nil,
    last_stderr = nil,
    next_request_id = 0,
    pending = {},
  }, Backend)
end

return M
