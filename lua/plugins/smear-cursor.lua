return {
  "sphamba/smear-cursor.nvim",
  cond = not vim.g.neovide,
  opts = {
    -- Prevent the smear from overlapping and fighting with the real terminal cursor
    never_draw_over_target = true,

    -- Disable the target hack that draws a block "█" which flickers in terminals like Konsole
    hide_target_hack = false,

    -- Use a fixed clean cursor color so it doesn't recalculate treesitter colors on every frame
    cursor_color = "#c0caf5",

    -- Snappier animation to minimize frame delays and eliminate trailing ghost flicker
    stiffness = 0.8,
    trailing_stiffness = 0.6,
    damping = 0.95,

    -- Insert mode settings: fast and smooth
    smear_insert_mode = true,
    distance_stop_animating_vertical_bar = 0.1,
    stiffness_insert_mode = 0.7,
    trailing_stiffness_insert_mode = 0.7,
    damping_insert_mode = 0.95,
    max_length_insert_mode = 8,
  },
}
