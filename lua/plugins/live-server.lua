return {
  "barrett-ruth/live-server.nvim",
  cmd = { "LiveServerStart", "LiveServerStop" },
  config = function()
    vim.g.live_server.setup({
      args = { "--port=8080" },
    })
  end,
  keys = {
    { "ls", "LiveServerStart", desc = "Start Live Server" },
    { "lx", "LiveServerStop", desc = "Stop Live Server" },
  },
}
