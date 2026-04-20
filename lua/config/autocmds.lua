-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Allow gf to resolve TS/JS imports without extension and @/ aliases
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
  callback = function()
    vim.opt_local.suffixesadd:prepend({ ".ts", ".tsx", ".js", ".jsx" })
    vim.opt_local.includeexpr = "substitute(v:fname, '^@/', 'src/', '')"
  end,
})
