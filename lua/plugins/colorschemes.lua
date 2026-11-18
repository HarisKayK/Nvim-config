return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      transparent = false,
    },
  },

  { "e-q/okcolors.nvim", name = "okcolors", lazy = false },

  -- {
  --   "alejandrolaguna20/noctis.nvim",
  --   lazy = false,
  --   config = function()
  --     vim.cmd.colorscheme("noctis")
  --   end,
  -- },

  {
    "ferrissushi/ferriouscolor.nvim",
    name = "ferriouscolor",
    lazy = false,
  },

  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    opts = {
      flavour = "mocha",
    },
  },

  { "ellisonleao/gruvbox.nvim", lazy = false, config = true },

  {
    "andreasvc/vim-256noir",
    name = "256noir",
    lazy = false,
  },

  {
    "metalelf0/black-metal-theme-neovim",
    lazy = false,
    config = function()
      require("black-metal").setup({
        trve = true,
      })
    end,
  },

  {
    "slugbyte/lackluster.nvim",
    lazy = false,
  },

  {
    "aktersnurra/no-clown-fiesta.nvim",
    lazy = false,
    opts = {
      theme = "dark",
      transparent = false,
    },
  },

  {
    "anAcc22/sakura.nvim",
    lazy = false,
    dependencies = "rktjmp/lush.nvim",
  },
}
