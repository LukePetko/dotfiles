return {
    "sbdchd/neoformat",
    config = function ()
        vim.g.neoformat_try_node_exe = 1
        vim.g.neoformat_enabled_javascript       = {'biome', 'prettier'}
        vim.g.neoformat_enabled_typescript       = {'biome', 'prettier'}
        vim.g.neoformat_enabled_javascriptreact  = {'biome', 'prettier'}
        vim.g.neoformat_enabled_typescriptreact  = {'biome', 'prettier'}
        vim.g.neoformat_enabled_json             = {'biome', 'prettier'}
        vim.g.neoformat_enabled_jsonc            = {'biome', 'prettier'}
    end
}
