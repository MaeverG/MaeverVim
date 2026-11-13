-- bootstrap lazy.nvim and load plugins
require("config.lazy")

-- TEMP
vim.keymap.set("n", "<leader>ct", [[02f lvg_"+y]], { desc = "Copy card title" })
-- vim.keymap.set("n", "<leader>ct", [[1f lvg_"+y]], { desc = "Copy card title" })
vim.keymap.set("n", "<leader>cb", [[jV/^## <CR>k"+y:noh<CR>]], { desc = "Copy card body" })
