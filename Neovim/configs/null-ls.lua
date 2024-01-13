local null_ls = require "null-ls"

local formatting = null_ls.builtins.formatting
local lint = null_ls.builtins.diagnostics

local sources = {
   formatting.black.with({
    extra_args = {"-l", "100"},
  }),

  lint.ruff
}

null_ls.setup {
   sources = sources,
}

