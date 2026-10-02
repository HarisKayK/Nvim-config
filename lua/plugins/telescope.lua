return {
  "nvim-telescope/telescope.nvim",
  version = "*",
  dependencies = {
    "nvim-lua/plenary.nvim",
    -- optional but recommended for faster sorting
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
  },
}
