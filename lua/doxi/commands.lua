local M = {}

local did_setup = false

function M.setup()
  if did_setup then
    return
  end

  did_setup = true

  vim.api.nvim_create_user_command("DoxiNew", function()
    require("doxi.session").open_new()
  end, {})

  vim.api.nvim_create_user_command("DoxiEdit", function(opts)
    require("doxi.session").open_edit({
      line1 = opts.line1,
      line2 = opts.line2,
    })
  end, {
    range = true,
  })

  vim.api.nvim_create_user_command("DoxiRunAll", function()
    require("doxi.session").run_all()
  end, {})

  vim.api.nvim_create_user_command("DoxiRunSelection", function()
    require("doxi.session").run_selection()
  end, {})

  vim.api.nvim_create_user_command("DoxiRestart", function()
    require("doxi.session").restart()
  end, {})

  vim.api.nvim_create_user_command("DoxiRestartRerun", function()
    require("doxi.session").restart_and_rerun()
  end, {})

  vim.api.nvim_create_user_command("DoxiSwitchInterpreter", function()
    require("doxi.session").switch_interpreter()
  end, {})

  vim.api.nvim_create_user_command("DoxiInsert", function()
    require("doxi.session").insert_transcript()
  end, {})

  vim.api.nvim_create_user_command("DoxiReplace", function()
    require("doxi.session").replace_transcript()
  end, {})

  vim.api.nvim_create_user_command("DoxiCopy", function()
    require("doxi.session").copy_transcript()
  end, {})

  vim.api.nvim_create_user_command("DoxiCancel", function()
    require("doxi.session").cancel()
  end, {})
end

return M
