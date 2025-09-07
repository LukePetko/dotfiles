vim.api.nvim_create_user_command('Rfinder',
    function()
        local path = vim.api.nvim_buf_get_name(0)
        if path == '' then
            print("Somehow invalid path, at least it doesn't break the whole neovim anymore lol")
            return
        end
        os.execute('open -R ' .. path)
    end,
    {}
)

vim.cmd([[
    autocmd BufWritePre ~/Projects/**/{*.js,*.jsx,*.ts,*.tsx,*.astro} Neoformat
]])

vim.cmd([[
    autocmd BufWritePost ~/Akular/**/{*.js,*.jsx,*.ts,*.tsx} :EslintFixAll
]])

vim.cmd([[
    autocmd BufNewFile,BufRead *.ebnf setf ebnf
]])

vim.lsp.enable('biome')

local autocmd = vim.api.nvim_create_autocmd

autocmd('LspAttach', {
    callback = function(e)
        local opts = { buffer = e.buf }
        vim.keymap.set("n", "gd", function() vim.lsp.buf.definition() end, opts)
        vim.keymap.set("n", "gc", "<Cmd>vsplit<CR>gd", { noremap = true, silent = true })
        vim.keymap.set("n", "K", function() vim.lsp.buf.hover() end, opts)
        vim.keymap.set("n", "<leader>vws", function() vim.lsp.buf.workspace_symbol() end, opts)
        vim.keymap.set("n", "<leader>vd", function() vim.diagnostic.open_float() end, opts)
        vim.keymap.set("n", "<leader>vca", function() vim.lsp.buf.code_action() end, opts)
        vim.keymap.set("n", "<leader>vrr", function() vim.lsp.buf.references() end, opts)
        vim.keymap.set("n", "<leader>vrn", function() vim.lsp.buf.rename() end, opts)
        vim.keymap.set("i", "<C-h>", function() vim.lsp.buf.signature_help() end, opts)
        vim.keymap.set("n", "[d", function() vim.diagnostic.goto_next() end, opts)
        vim.keymap.set("n", "]d", function() vim.diagnostic.goto_prev() end, opts)
    end
})

