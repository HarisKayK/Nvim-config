return {
  "nickjvandyke/opencode.nvim",
  dependencies = {
    { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
  },
  config = function()
    vim.g.opencode_opts = {}
    vim.o.autoread = true -- lets nvim reload files that opencode changed

    -- open or close opencode in a side panel
    vim.keymap.set("n", "<leader>ot", function()
      require("snacks").terminal.toggle("opencode", { win = { position = "right", width = 0.35 } })
    end, { desc = "Toggle opencode" })

    vim.keymap.set("n", "<leader>oa", function()
      require("opencode").ask("@cursor: ")
    end, { desc = "Ask opencode about this" })
    vim.keymap.set("v", "<leader>oa", function()
      require("opencode").ask("@selection: ")
    end, { desc = "Ask opencode about selection" })
    vim.keymap.set({ "n", "v" }, "<leader>os", function()
      require("opencode").select()
    end, { desc = "Opencode actions" })
  end,
}
