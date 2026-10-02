-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Helper to search upwards for a specific file (e.g. CMakeLists.txt, Makefile)
local function find_upward(filename, start_dir)
  local path = start_dir
  while path and path ~= "" do
    local target = path .. "/" .. filename
    if vim.fn.filereadable(target) == 1 then
      return path, target
    end
    local parent = vim.fn.fnamemodify(path, ":h")
    if parent == path then
      break
    end
    path = parent
  end
  return nil, nil
end

-- Generate a starter CMakeLists.txt that automatically tracks all .cpp files
local function generate_cmakelists(dir)
  local proj_name = vim.fn.fnamemodify(dir, ":t")
  if proj_name == "" or proj_name == "/" then
    proj_name = "app"
  end
  proj_name = proj_name:gsub("[^%w_]", "_")

  local cmake_file = dir .. "/CMakeLists.txt"
  if vim.fn.filereadable(cmake_file) == 1 then
    return proj_name
  end

  local lines = {
    "cmake_minimum_required(VERSION 3.20)",
    string.format("project(%s CXX)", proj_name),
    "",
    "set(CMAKE_CXX_STANDARD 20)",
    "set(CMAKE_CXX_STANDARD_REQUIRED ON)",
    "set(CMAKE_EXPORT_COMPILE_COMMANDS ON)",
    "",
    "# Automatically tracks all .cpp files in this directory",
    "file(GLOB SOURCES CONFIGURE_DEPENDS *.cpp)",
    string.format("add_executable(%s ${SOURCES})", proj_name),
  }
  vim.fn.writefile(lines, cmake_file)
  Snacks.notify.info("Auto-created CMakeLists.txt for '" .. proj_name .. "'")
  return proj_name
end

-- Smart Compile & Run: Single-file, Multi-file, CMake, and Makefile

local function quiet_cmake(run)
  return "( out=$(cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON 2>&1 && cmake --build build 2>&1)"
    .. ' || { echo "$out"; exit 1; } )'
    .. " && ln -sf build/compile_commands.json . 2>/dev/null && "
    .. run
end

local function compile_and_run()
  local ft = vim.bo.filetype
  if ft ~= "cpp" and ft ~= "c" then
    Snacks.notify.warn("Current file is not C or C++ (" .. ft .. ")")
    return
  end

  vim.cmd("silent! update")
  local file = vim.fn.expand("%:p")
  local dir = vim.fn.expand("%:p:h")

  -- 1. Check for CMakeLists.txt in current or parent directory
  local cmake_root, cmake_path = find_upward("CMakeLists.txt", dir)
  if cmake_root then
    local target_name = nil
    for _, line in ipairs(vim.fn.readfile(cmake_path)) do
      local t = line:match("add_executable%s*%(%s*([%w_%-]+)")
      if t then
        target_name = t
        break
      end
    end

    local run_target = target_name and ("./build/" .. target_name)
      or "$(find build -maxdepth 2 -type f -executable ! -name '*.so*' ! -name '*.a' ! -name 'cmake*' | head -n 1)"
    local cmd = quiet_cmake(run_target)
    Snacks.terminal(cmd, { cwd = cmake_root, auto_close = false })
    return
  end

  -- 2. Check for Makefile in current or parent directory
  local make_root = find_upward("Makefile", dir)
  if make_root then
    local cmd =
      "make && ($(find . -maxdepth 2 -type f -executable ! -name '*.sh' ! -name 'Makefile' | head -n 1) || make run)"
    Snacks.terminal(cmd, { cwd = make_root, auto_close = false })
    return
  end

  -- 3. Check for multiple .cpp files in current directory
  local cpp_files = vim.fn.globpath(dir, "*.cpp", false, true)
  if #cpp_files > 1 then
    local proj_name = generate_cmakelists(dir)
    local cmd = quiet_cmake("./build/" .. proj_name)
    Snacks.terminal(cmd, { cwd = dir, auto_close = false })
    return
  end

  -- 4. Single-file fallback
  local bin = vim.fn.expand("%:p:r")
  local cmd
  if ft == "cpp" then
    cmd = string.format(
      "g++ -std=c++20 -Wall -Wextra %s -o %s && %s",
      vim.fn.shellescape(file),
      vim.fn.shellescape(bin),
      vim.fn.shellescape(bin)
    )
  else
    cmd = string.format(
      "gcc -Wall -Wextra %s -o %s && %s",
      vim.fn.shellescape(file),
      vim.fn.shellescape(bin),
      vim.fn.shellescape(bin)
    )
  end

  Snacks.terminal(cmd, { cwd = dir, auto_close = false })
end

vim.keymap.set("n", "<F5>", compile_and_run, { desc = "Compile & Run (Single / Multi-file / CMake)" })
vim.keymap.set("n", "<leader>rc", compile_and_run, { desc = "Compile & Run (Single / Multi-file / CMake)" })

vim.api.nvim_create_user_command("CMakeInit", function()
  generate_cmakelists(vim.fn.expand("%:p:h"))
end, { desc = "Create starter CMakeLists.txt in current directory" })

-- Popup window displaying all custom shortcuts
local function show_shortcuts()
  local text = {
    "# ⚡ Custom & Essential Shortcuts",
    "",
    "## 🚀 C / C++ Coding & Smart Build",
    "  <F5>           Smart Compile & Run (Single file, Multi-file, or CMake!)",
    "  <leader>rc     Smart Compile & Run (same as <F5>)",
    "  :CMakeInit     Create auto-updating CMakeLists.txt for current folder",
    "  q              Close the terminal window when execution finishes",
    "  <leader>cf     Format code with clang-format (also auto on save)",
    "  <leader>ch     Switch between Header and Source (.cpp <-> .h)",
    "  <leader>cd     Show line diagnostics / error explanation",
    "  <leader>cr     Rename variable / symbol across project",
    "  gd             Jump to definition",
    "  K              Hover documentation for symbol under cursor",
    "",
    "## 📐 Code Block Navigation (mini.indentscope)",
    "  [i             Jump to top of current code block",
    "  ]i             Jump to bottom of current code block",
    "  vii            Visually select inside code block",
    "  vai            Visually select entire code block (with braces)",
    "",
    "## 🎨 Visuals & Toggles",
    "  :SmearCursorToggle  Toggle smooth cursor gliding on/off",
    "  <leader>uL          Toggle relative / normal line numbers",
    "  <leader>uf          Toggle auto-format on save",
    "",
    "## 🔍 Files & Navigation (LazyVim)",
    "  <leader><space>     Find files in project",
    "  <leader>/           Search text across files (grep)",
    "  <leader>e           Toggle file explorer tree",
    "  <leader>bd          Close current buffer / tab",
    "",
    "*(Press 'q' or 'Esc' to close this window)*",
  }

  Snacks.win({
    text = text,
    width = 0.68,
    height = 0.78,
    border = "rounded",
    title = " Custom Shortcuts ",
    title_pos = "center",
    bo = { filetype = "markdown" },
    keys = {
      ["q"] = "close",
      ["<Esc>"] = "close",
    },
  })
end

vim.api.nvim_create_user_command("Shortcuts", show_shortcuts, { desc = "Show custom shortcuts cheat sheet" })
vim.keymap.set("n", "<leader>?", show_shortcuts, { desc = "Show custom shortcuts" })

-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

local map = vim.keymap.set

map("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment" }) -- line 197
map("n", "<C-_>", "gcc", { remap = true, desc = "Toggle comment" }) -- line 198

map("v", "<C-/>", "gc", { remap = true, desc = "Toggle comment" }) -- line 200
map("v", "<C-_>", "gc", { remap = true, desc = "Toggle comment" }) -- line 201

if vim.g.neovide then
  vim.o.guifont = "JetBrainsMono Nerd Font:h14" -- change to a font you have
  vim.g.neovide_cursor_animation_length = 0.08
  -- vim.g.neovide_cursor_vfx_mode = "railgun" -- fun cursor trail, remove if you dislike it
  vim.g.neovide_scroll_animation_length = 0.2

  vim.keymap.set("n", "<A-CR>", function()
    vim.g.neovide_fullscreen = not vim.g.neovide_fullscreen
  end, { desc = "Toggle Neovide fullscreen" })

  -- vim.g.neovide_fullscreen = true
end
