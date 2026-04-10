local M = {}

local did_setup = false

function M.setup()
  if did_setup then
    return
  end

  did_setup = true

  vim.api.nvim_create_user_command("DoxiOpen", function(opts)
    require("doxi.session").open({
      line1 = opts.line1,
      line2 = opts.line2,
      range = opts.range,
    })
  end, {
    range = true,
  })

  vim.api.nvim_create_user_command("DoxiRunAll", function()
    require("doxi.session").run_all()
  end, {})

  vim.api.nvim_create_user_command("DoxiRunSelection", function(opts)
    require("doxi.session").run_selection({
      line1 = opts.line1,
      line2 = opts.line2,
      range = opts.range,
    })
  end, {
    range = true,
  })

  vim.api.nvim_create_user_command("DoxiRestart", function()
    require("doxi.session").restart()
  end, {})

  vim.api.nvim_create_user_command("DoxiRestartRerun", function()
    require("doxi.session").restart_and_rerun()
  end, {})

  vim.api.nvim_create_user_command("DoxiEnvSwitch", function()
    require("doxi.session").env_switch()
  end, {})

  vim.api.nvim_create_user_command("DoxiApply", function()
    require("doxi.session").apply()
  end, {})

  vim.api.nvim_create_user_command("DoxiCancel", function()
    require("doxi.session").cancel()
  end, {})
end

return M
