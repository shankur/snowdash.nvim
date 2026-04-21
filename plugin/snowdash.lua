if vim.g.loaded_snowdash then
  return
end
vim.g.loaded_snowdash = true

local snowdash = require("snowdash")

-- Call setup with defaults if user hasn't called it yet via lazy config
if not snowdash._setup_done then
  snowdash.setup()
end

vim.keymap.set("n", "<F2>", function() snowdash.toggle() end, { desc = "Toggle Snowdash" })
vim.keymap.set("n", "<F3>", function() snowdash.refresh() end, { desc = "Refresh Snowdash" })
vim.keymap.set("n", "<F4>", function() snowdash.sync_custom() end, { desc = "Sync custom section" })
