-- if vim.g.neovide then
--   -- Set total window opacity (0.0 = fully transparent, 1.0 = fully opaque)
--   vim.g.neovide_opacity = 0.1
--
--   -- Optional: Set opacity specifically for normal background color
--   vim.g.neovide_normal_opacity = 0.1
-- end

vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

if vim.g.neovide then
  vim.o.guifont = "JetBrainsMono Nerd Font:h14" -- change to a font you have
  vim.g.neovide_cursor_animation_length = 0.08
  -- vim.g.neovide_cursor_vfx_mode = "railgun" -- fun cursor trail, remove if you dislike it
  vim.g.neovide_scroll_animation_length = 0.2
end

vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
  callback = function()
    if vim.bo.modifiable and vim.bo.modified and not vim.bo.readonly and vim.fn.expand("%") ~= "" then
      vim.cmd("silent! update")
    end
  end,
})
