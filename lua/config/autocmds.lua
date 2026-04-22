-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Smart gf for JS/TS buffers.
-- Prefers a quoted string at cursor (import/require paths) over vim's <cfile>,
-- resolves `@/` aliases and relative paths against the current file's dir,
-- and tries common extensions plus `/index.*`.
local function smart_gf_js()
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col(".")

  local function quoted_at_cursor()
    local i = 1
    while i <= #line do
      local q_start = line:find("['\"`]", i)
      if not q_start then
        return nil
      end
      local q_char = line:sub(q_start, q_start)
      local q_end = line:find(q_char, q_start + 1, true)
      if not q_end then
        return nil
      end
      if col > q_start and col <= q_end then
        return line:sub(q_start + 1, q_end - 1)
      end
      i = q_end + 1
    end
    return nil
  end

  local path = quoted_at_cursor() or vim.fn.expand("<cfile>")
  if path == "" then
    vim.notify("gf: no path at cursor", vim.log.levels.WARN)
    return
  end

  local cur_dir = vim.fn.expand("%:p:h")
  local root = vim.fs.root(0, { "package.json", "jsconfig.json", "tsconfig.json", ".git" }) or vim.fn.getcwd()

  local candidates = {}
  if path:match("^@/") then
    local rest = path:sub(3)
    table.insert(candidates, root .. "/src/" .. rest)
    table.insert(candidates, root .. "/" .. rest)
  elseif path:match("^%.") then
    table.insert(candidates, cur_dir .. "/" .. path)
  elseif path:match("^/") then
    table.insert(candidates, path)
  else
    table.insert(candidates, root .. "/" .. path)
    table.insert(candidates, root .. "/src/" .. path)
    table.insert(candidates, root .. "/node_modules/" .. path)
  end

  local exts = {
    "",
    ".ts",
    ".tsx",
    ".js",
    ".jsx",
    "/index.ts",
    "/index.tsx",
    "/index.js",
    "/index.jsx",
    "/package.json",
  }

  for _, base in ipairs(candidates) do
    for _, ext in ipairs(exts) do
      local full = base .. ext
      if vim.fn.filereadable(full) == 1 then
        vim.cmd("edit " .. vim.fn.fnameescape(full))
        return
      end
    end
  end

  vim.notify("gf: file not found for '" .. path .. "'", vim.log.levels.WARN)
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
  callback = function()
    vim.opt_local.suffixesadd:prepend({
      ".ts",
      ".tsx",
      ".js",
      ".jsx",
      "/index.ts",
      "/index.tsx",
      "/index.js",
      "/index.jsx",
    })
    vim.opt_local.includeexpr = "substitute(v:fname, '^@/', 'src/', '')"
    -- Mappings.
    local map = function(mode, l, r, opts)
      opts = opts or {}
      opts.silent = true
      opts.buffer = bufnr
      vim.keymap.set(mode, l, r, opts)
    end

    map("n", "gd", function()
      vim.lsp.buf.definition({
        on_list = function(options)
          -- custom logic to avoid showing multiple definition when you use this style of code:
          -- `local M.my_fn_name = function() ... end`.
          -- See also post here: https://www.reddit.com/r/neovim/comments/19cvgtp/any_way_to_remove_redundant_definition_in_lua_file/

          -- vim.print(options.items)
          local unique_defs = {}
          local def_loc_hash = {}

          -- each item in options.items contain the location info for a definition provided by LSP server
          for _, def_location in pairs(options.items) do
            -- use filename and line number to uniquelly indentify a definition,
            -- we do not expect/want multiple definition in single line!
            local hash_key = def_location.filename .. def_location.lnum

            if not def_loc_hash[hash_key] then
              def_loc_hash[hash_key] = true
              table.insert(unique_defs, def_location)
            end
          end

          options.items = unique_defs

          -- set the location list
          ---@diagnostic disable-next-line: param-type-mismatch
          vim.fn.setloclist(0, {}, " ", options)

          -- open the location list when we have more than 1 definitions found,
          -- otherwise, jump directly to the definition
          if #options.items > 1 then
            vim.cmd.lopen()
          else
            vim.cmd([[silent! lfirst]])
          end
        end,
      })
    end, { desc = "go to definition" })
  end,
})
