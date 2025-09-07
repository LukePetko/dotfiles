return {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.5",
    dependencies = {
        "nvim-lua/plenary.nvim"
    },
    config = function()
        local telescope = require('telescope')
        local builtin = require('telescope.builtin')

        telescope.setup {
            pickers = {
                find_files = {
                    hidden = true,
                }
            },
        }
        vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
        vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
        vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
        vim.keymap.set('n', '<leader>fw', builtin.grep_string, {})
        vim.keymap.set('n', '<leader>fr', builtin.lsp_incoming_calls, {})
    end
}
