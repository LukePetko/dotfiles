require("pi_bridge").setup()

-- Optional keymaps:
-- vim.keymap.set("v", "<leader>ps", require("pi_bridge").send_selection, { desc = "Send selection to pi" })
-- vim.keymap.set("n", "<leader>pb", require("pi_bridge").send_buffer, { desc = "Send buffer to pi" })
-- vim.keymap.set("n", "<leader>pa", function() require("pi_bridge").ask({ args = "" }) end, { desc = "Ask pi" })
