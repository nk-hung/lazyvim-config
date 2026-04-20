return {
  -- tools
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed, {
        "stylua",
        "selene",
        "luacheck",
        "shellcheck",
        "shfmt",
        "tailwindcss-language-server",
        "typescript-language-server",
        "css-lsp",
        "gopls",
        "jdtls",
      })
    end,
  },

  -- lsp sjrvers
  {
    "neovim/nvim-lspconfig",
    opts = {
      keys = {
        {
          "gd",
          function()
            local word = vim.fn.expand("<cword>")
            local params = vim.lsp.util.make_position_params()
            local clients = vim.lsp.get_active_clients({ bufnr = 0 })

            -- Find the export/declaration line in destination buffer
            local function jump_to_definition(dest_lines)
              local w = vim.pesc(word)
              local priority = {
                "export%s+default%s+function%s+" .. w,
                "export%s+default%s+class%s+" .. w,
                "export%s+const%s+" .. w,
                "export%s+function%s+" .. w,
                "export%s+class%s+" .. w,
                "exports%." .. w .. "%s*=",
                "module%.exports%." .. w .. "%s*=",
                "const%s+" .. w .. "%s*[=:]",
                "function%s+" .. w .. "%s*[(%s]",
                "class%s+" .. w .. "%f[%W]",
              }
              for _, pat in ipairs(priority) do
                for i, l in ipairs(dest_lines) do
                  if l:match(pat) then
                    vim.api.nvim_win_set_cursor(0, { i, 0 })
                    vim.cmd("normal! zz")
                    return
                  end
                end
              end
            end

            local function fallback()
              local src_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
              local exts =
                { "", ".ts", ".tsx", ".js", ".jsx", "/index.ts", "/index.tsx", "/index.js", "/index.jsx" }

              -- Find project root (package.json / tsconfig / jsconfig / .git)
              local root = vim.fs.root(0, { "package.json", "tsconfig.json", "jsconfig.json", ".git" })
                or vim.fn.getcwd()
              local current_dir = vim.fn.expand("%:p:h")
              local alias_targets = { "src/", "" }
              local w = vim.pesc(word)

              -- Resolve the import/require path that brings `word` into scope.
              -- Handles ES6 `from 'path'` and CJS `require('path')`, including
              -- multi-line `const { a, b } = require('path')` destructuring.
              local function find_path()
                for _, line in ipairs(src_lines) do
                  if line:match("%f[%w]" .. w .. "%f[%W]") then
                    local p = line:match("from%s+['\"]([^'\"]+)['\"]")
                    if p then
                      return p
                    end
                  end
                end
                for i, line in ipairs(src_lines) do
                  local p = line:match("=%s*require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)")
                  if p then
                    if line:match("%f[%w]" .. w .. "%f[%W]") then
                      return p
                    end
                    for j = i - 1, math.max(1, i - 30), -1 do
                      local prev = src_lines[j]
                      if prev:match("%f[%w]" .. w .. "%f[%W]") then
                        return p
                      end
                      if prev:match("^%s*[%w]*%s*{") then
                        break
                      end
                    end
                  end
                end
                return nil
              end

              local path = find_path()
              if not path then
                vim.notify("gd: no definition found for " .. word, vim.log.levels.WARN)
                return
              end

              local candidates = {}
              if path:match("^@/") then
                for _, target in ipairs(alias_targets) do
                  table.insert(candidates, root .. "/" .. (path:gsub("^@/", target)))
                end
              elseif path:match("^%.") then
                table.insert(candidates, current_dir .. "/" .. path)
              else
                table.insert(candidates, root .. "/" .. path)
              end

              for _, base in ipairs(candidates) do
                for _, ext in ipairs(exts) do
                  local full = base .. ext
                  if vim.fn.filereadable(full) == 1 then
                    vim.cmd("edit " .. vim.fn.fnameescape(full))
                    jump_to_definition(vim.api.nvim_buf_get_lines(0, 0, -1, false))
                    return
                  end
                end
              end
              vim.notify("gd: could not resolve path " .. path, vim.log.levels.WARN)
            end

            if #clients == 0 then
              fallback()
              return
            end

            vim.lsp.buf_request(0, "textDocument/definition", params, function(err, result)
              if not err and result and not vim.tbl_isempty(result) then
                local loc = vim.islist(result) and result[1] or result
                local uri = loc.uri or loc.targetUri
                local range = loc.range or loc.targetSelectionRange
                local target_line_nr = range and range.start.line or 0

                -- Read the destination line to check if it's an import stmt
                local target_bufnr = vim.uri_to_bufnr(uri)
                vim.fn.bufload(target_bufnr)
                local target_line =
                  vim.api.nvim_buf_get_lines(target_bufnr, target_line_nr, target_line_nr + 1, false)[1] or ""

                local is_import = target_line:match("^%s*import%s") ~= nil
                local is_require = target_line:match("require%s*%(") ~= nil
                if not is_require and target_line:match("^%s*[%w_$%.%s,:{}]*$") then
                  local after =
                    vim.api.nvim_buf_get_lines(target_bufnr, target_line_nr, target_line_nr + 20, false)
                  for _, l in ipairs(after) do
                    if l:match("=%s*require%s*%(") then
                      is_require = true
                      break
                    end
                    if
                      l:match("[%(%);]")
                      or l:match("=>")
                      or l:match("function%s")
                      or l:match("^%s*class%s")
                      or l:match("^%s*return%s")
                    then
                      break
                    end
                  end
                end
                if not is_import and not is_require then
                  require("telescope.builtin").lsp_definitions({ reuse_win = false })
                  return
                end
              end
              fallback()
            end)
          end,
          desc = "Goto Definition",
        },
      },
      inlay_hints = { enabled = false },
      ---@type lspconfig.options
      servers = {
        vtsls = false,
        cssls = {},
        tailwindcss = {
          root_dir = function(...)
            return require("lspconfig.util").root_pattern(".git")(...)
          end,
        },
        tsserver = {
          root_dir = function(...)
            return require("lspconfig.util").root_pattern(".git")(...)
          end,
          single_file_support = false,
          settings = {
            typescript = {
              inlayHints = {
                includeInlayParameterNameHints = "literal",
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = false,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
              },
            },
            javascript = {
              inlayHints = {
                includeInlayParameterNameHints = "all",
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = true,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
              },
            },
          },
        },
        html = {},
        yamlls = {
          settings = {
            yaml = {
              keyOrdering = false,
            },
          },
        },
        gopls = {
          settings = {
            gopls = {
              analyses = {
                unusedparams = true,
              },
              staticcheck = true,
              usePlaceholders = true,
              completeUnimported = true, -- This enables auto-import
              matcher = "fuzzy",
              experimentalPostfixCompletions = true,
              gofumpt = true,
              -- Add these formatting options:
              formatting = {
                gofumpt = true, -- Use gofumpt formatting rules (stricter than gofmt)
              },
            },
          },
          -- Enable format on save
          on_attach = function(client, bufnr)
            -- You can add other on_attach functions here
            vim.api.nvim_create_autocmd("BufWritePre", {
              buffer = bufnr,
              callback = function()
                vim.lsp.buf.format({ async = false })
              end,
            })
          end,
        },
        lua_ls = {
          -- enabled = false,
          single_file_support = true,
          settings = {
            Lua = {
              workspace = {
                checkThirdParty = false,
              },
              completion = {
                workspaceWord = true,
                callSnippet = "Both",
              },
              misc = {
                parameters = {
                  -- "--log-level=trace",
                },
              },
              hint = {
                enable = true,
                setType = false,
                paramType = true,
                paramName = "Disable",
                semicolon = "Disable",
                arrayIndex = "Disable",
              },
              doc = {
                privateName = { "^_" },
              },
              type = {
                castNumberToInteger = true,
              },
              diagnostics = {
                disable = { "incomplete-signature-doc", "trailing-space" },
                -- enable = false,
                groupSeverity = {
                  strong = "Warning",
                  strict = "Warning",
                },
                groupFileStatus = {
                  ["ambiguity"] = "Opened",
                  ["await"] = "Opened",
                  ["codestyle"] = "None",
                  ["duplicate"] = "Opened",
                  ["global"] = "Opened",
                  ["luadoc"] = "Opened",
                  ["redefined"] = "Opened",
                  ["strict"] = "Opened",
                  ["strong"] = "Opened",
                  ["type-check"] = "Opened",
                  ["unbalanced"] = "Opened",
                  ["unused"] = "Opened",
                },
                unusedLocalExclude = { "_*" },
              },
              format = {
                enable = false,
                defaultConfig = {
                  indent_style = "space",
                  indent_size = "2",
                  continuation_indent_size = "2",
                },
              },
            },
          },
        },
      },
      setup = {},
    },
  },
}
