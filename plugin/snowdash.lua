if vim.g.loaded_snowdash then
  return
end
vim.g.loaded_snowdash = true

-- Default keymaps (can be overridden by user before plugin loads)
vim.keymap.set("n", "<F2>", function() require("snowdash").toggle() end, { desc = "Toggle Snowdash" })
vim.keymap.set("n", "<F3>", function() require("snowdash").refresh() end, { desc = "Refresh Snowdash" })
vim.keymap.set("n", "<F4>", function() require("snowdash").sync_custom() end, { desc = "Sync custom section" })
