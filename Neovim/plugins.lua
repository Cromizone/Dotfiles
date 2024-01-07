local plugins = {

 {
   "williamboman/mason.nvim",
   opts = {
      ensure_installed = {
        "pyright",
        "mypy",
        "black",
      },
    },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "html",
        "css",
        "bash",
        "python",
        "json",
        "javascript"
      },
    },
  },

  {
    "neovim/nvim-lspconfig",

     dependencies = {
       "nvimtools/none-ls.nvim",
       config = function()
         require "custom.configs.null-ls"
       end,
     },
   
     config = function()
        require "plugins.configs.lspconfig"
        require "custom.configs.lspconfig"
     end,
  },

}

return plugins
