local null_ls = require "null-ls"

local formatting = null_ls.builtins.formatting
local lint = null_ls.builtins.diagnostics

local sources = {
   formatting.black.with({
    extra_args = {"-l", "100"},
  }),

   lint.mypy.with({
      extra_args = {"--ignore-missing-imports", "--python-executable", "/usr/bin/python"},
      method = null_ls.methods.DIAGNOSTICS_ON_SAVE,
  }),
}

null_ls.setup {
   sources = sources,
}

