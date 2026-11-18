-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- half page up/down centered view
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

-- search / centered view
vim.keymap.set("n", "n", "nzz")
vim.keymap.set("n", "N", "Nzz")

-- keymap to access my external hard drive
vim.api.nvim_create_user_command("Hdd", function(opts)
  local base_path = "/run/media/haris/New Volume/"
  local target = opts.args ~= "" and (base_path .. "/" .. opts.args) or base_path
  vim.cmd("cd " .. vim.fn.fnameescape(target))
end, {
  nargs = "?",
  complete = "dir",
  desc = "Change directory to external drive or a subdirectory inside it",
})

-- Helper to search upwards for a specific file (e.g. CMakeLists.txt, Makefile)
local function find_upward(filename, start_dir)
  local path = start_dir
  while path and path ~= "" do
    local target = path .. "/" .. filename
    if vim.fn.filereadable(target) == 1 or vim.fn.isdirectory(target) == 1 then
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

-- Generate a starter CMakeLists.txt that automatically tracks all .cpp or .c files
local function generate_cmakelists(dir, is_c)
  local proj_name = vim.fn.fnamemodify(dir, ":t")
  if proj_name == "" or proj_name == "/" then
    proj_name = "app"
  end
  proj_name = proj_name:gsub("[^%w_]", "_")

  local cmake_file = dir .. "/CMakeLists.txt"
  if vim.fn.filereadable(cmake_file) == 1 then
    return proj_name
  end

  local lang = is_c and "C" or "CXX"
  local std_line = is_c and "set(CMAKE_C_STANDARD 11)" or "set(CMAKE_CXX_STANDARD 20)"
  local std_req = is_c and "set(CMAKE_C_STANDARD_REQUIRED ON)" or "set(CMAKE_CXX_STANDARD_REQUIRED ON)"
  local glob_pattern = is_c and "*.c" or "*.cpp"

  local lines = {
    "cmake_minimum_required(VERSION 3.20)",
    string.format("project(%s %s)", proj_name, lang),
    "",
    std_line,
    std_req,
    "set(CMAKE_EXPORT_COMPILE_COMMANDS ON)",
    "",
    string.format("# Automatically tracks all %s files in this directory", glob_pattern),
    string.format("file(GLOB SOURCES CONFIGURE_DEPENDS %s)", glob_pattern),
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

-- Remember last used CLI arguments
local last_run_args = ""

local function execute_run(args)
  local ft = vim.bo.filetype
  vim.cmd("silent! update")
  local file = vim.fn.expand("%:p")
  local dir = vim.fn.expand("%:p:h")

  local arg_str = (args and args ~= "") and (" " .. args) or ""

  -- Python execution
  if ft == "python" then
    local python_bin = "python3"
    if vim.env.VIRTUAL_ENV and vim.fn.executable(vim.env.VIRTUAL_ENV .. "/bin/python") == 1 then
      python_bin = vim.env.VIRTUAL_ENV .. "/bin/python"
    elseif vim.env.CONDA_PREFIX and vim.fn.executable(vim.env.CONDA_PREFIX .. "/bin/python") == 1 then
      python_bin = vim.env.CONDA_PREFIX .. "/bin/python"
    else
      local venv_root = find_upward(".venv", dir)
      if venv_root and vim.fn.executable(venv_root .. "/.venv/bin/python") == 1 then
        python_bin = venv_root .. "/.venv/bin/python"
      end
    end
    local cmd = string.format("%s %s%s", vim.fn.shellescape(python_bin), vim.fn.shellescape(file), arg_str)
    Snacks.terminal(cmd, { cwd = dir, auto_close = false })
    return
  end

  -- 1. Check for CMakeLists.txt in current or parent directory
  local cmake_root, cmake_path = find_upward("CMakeLists.txt", dir)
  if cmake_root and cmake_path then
    local target_name = nil
    for _, line in ipairs(vim.fn.readfile(cmake_path)) do
      local t = line:match("add_executable%s*%(%s*([%w_%-]+)")
      if t then
        target_name = t
        break
      end
    end

    local run_target = (target_name and ("./build/" .. target_name)
      or "$(find build -maxdepth 2 -type f -executable ! -name '*.so*' ! -name '*.a' ! -name 'cmake*' | head -n 1)")
      .. arg_str
    local cmd = quiet_cmake(run_target)
    Snacks.terminal(cmd, { cwd = cmake_root, auto_close = false })
    return
  end

  -- 2. Check for Makefile in current or parent directory
  local make_root = find_upward("Makefile", dir)
  if make_root then
    local cmd = string.format(
      "make && ($(find . -maxdepth 2 -type f -executable ! -name '*.sh' ! -name 'Makefile' | head -n 1)%s || make run%s)",
      arg_str,
      (args and args ~= "") and (" ARGS=" .. vim.fn.shellescape(args)) or ""
    )
    Snacks.terminal(cmd, { cwd = make_root, auto_close = false })
    return
  end

  -- 3. Check for multiple .cpp / .c files in current directory
  local cpp_files = vim.fn.globpath(dir, "*.cpp", false, true)
  local c_files = vim.fn.globpath(dir, "*.c", false, true)
  if ft == "cpp" and #cpp_files > 1 then
    local proj_name = generate_cmakelists(dir, false)
    local cmd = quiet_cmake("./build/" .. proj_name .. arg_str)
    Snacks.terminal(cmd, { cwd = dir, auto_close = false })
    return
  elseif ft == "c" and #c_files > 1 then
    local proj_name = generate_cmakelists(dir, true)
    local cmd = quiet_cmake("./build/" .. proj_name .. arg_str)
    Snacks.terminal(cmd, { cwd = dir, auto_close = false })
    return
  end

  -- 4. Single-file fallback
  local bin = vim.fn.expand("%:p:r")
  local run_cmd = vim.fn.shellescape(bin) .. arg_str
  local cmd
  if ft == "cpp" then
    cmd = string.format(
      "g++ -std=c++20 -Wall -Wextra %s -o %s && %s",
      vim.fn.shellescape(file),
      vim.fn.shellescape(bin),
      run_cmd
    )
  else
    cmd = string.format(
      "gcc -std=c11 -Wall -Wextra %s -o %s -lm && %s",
      vim.fn.shellescape(file),
      vim.fn.shellescape(bin),
      run_cmd
    )
  end

  Snacks.terminal(cmd, { cwd = dir, auto_close = false })
end

local function compile_and_run(prompt_for_args)
  if prompt_for_args == nil then
    prompt_for_args = true
  end

  local ft = vim.bo.filetype
  if ft ~= "cpp" and ft ~= "c" and ft ~= "python" then
    Snacks.notify.warn("Current file is not C, C++, or Python (" .. ft .. ")")
    return
  end

  if prompt_for_args then
    vim.ui.input({
      prompt = "CLI Arguments (Enter to run): ",
      default = last_run_args,
    }, function(input)
      if input == nil then
        return
      end
      local trimmed = input:match("^%s*(.-)%s*$") or ""
      last_run_args = trimmed
      execute_run(trimmed)
    end)
  else
    execute_run(last_run_args)
  end
end

-- Smart F5: Continue debugger if active session exists, otherwise compile & run
local function smart_f5()
  local ok, dap = pcall(require, "dap")
  if ok and dap.session() then
    dap.continue()
  else
    compile_and_run(true)
  end
end

vim.keymap.set("n", "<F5>", smart_f5, { desc = "Run Code / Continue Debugger" })
vim.keymap.set("n", "<leader>rc", function()
  compile_and_run(true)
end, { desc = "Run Code (Prompt Args)" })
vim.keymap.set("n", "<leader>rr", function()
  compile_and_run(false)
end, { desc = "Re-run Code (Last Args)" })

local ok_wk, wk = pcall(require, "which-key")
if ok_wk then
  wk.add({
    { "<leader>r", group = "run" },
    { "<leader>rc", desc = "Run Code (with Args)" },
    { "<leader>rr", desc = "Re-run Code (Last Args)" },
    { "<leader>d", group = "debug" },
  })
end

-- Universal Debugger Keymaps (F-Keys & Leader Shortcuts)
local function get_dap()
  return require("dap")
end
local function get_dapui()
  return require("dapui")
end

-- Breakpoints
vim.keymap.set("n", "<F9>", function()
  get_dap().toggle_breakpoint()
end, { desc = "Toggle Breakpoint" })
vim.keymap.set("n", "<leader>db", function()
  get_dap().toggle_breakpoint()
end, { desc = "Toggle Breakpoint" })
vim.keymap.set("n", "<leader>dB", function()
  get_dap().set_breakpoint(vim.fn.input("Breakpoint condition: "))
end, { desc = "Breakpoint Condition" })

-- Stepping & Execution
vim.keymap.set("n", "<leader>dc", function()
  get_dap().continue()
end, { desc = "Start / Continue Debugger" })
vim.keymap.set("n", "<F10>", function()
  get_dap().step_over()
end, { desc = "Step Over" })
vim.keymap.set("n", "<leader>do", function()
  get_dap().step_over()
end, { desc = "Step Over" })
vim.keymap.set("n", "<leader>dO", function()
  get_dap().step_out()
end, { desc = "Step Out" })
vim.keymap.set("n", "<F11>", function()
  get_dap().step_into()
end, { desc = "Step Into" })
vim.keymap.set("n", "<leader>di", function()
  get_dap().step_into()
end, { desc = "Step Into" })
vim.keymap.set("n", "<F12>", function()
  get_dap().step_out()
end, { desc = "Step Out" })
vim.keymap.set("n", "<S-F5>", function()
  get_dap().terminate()
  pcall(function()
    get_dapui().close()
  end)
end, { desc = "Terminate Debugger & Close UI" })
vim.keymap.set("n", "<leader>dt", function()
  get_dap().terminate()
  pcall(function()
    get_dapui().close()
  end)
end, { desc = "Terminate Debugger & Close UI" })

-- UI and Variable Inspection
vim.keymap.set("n", "<leader>du", function()
  get_dapui().toggle({})
end, { desc = "Toggle Debug UI" })
vim.keymap.set({ "n", "v" }, "<leader>de", function()
  get_dapui().eval()
end, { desc = "Eval Expression" })
vim.keymap.set("n", "<leader>dr", function()
  get_dap().repl.toggle()
end, { desc = "Toggle REPL / Console" })
vim.keymap.set("n", "<leader>dl", function()
  get_dap().run_last()
end, { desc = "Run Last Debug Session" })

vim.api.nvim_create_user_command("CMakeInit", function()
  generate_cmakelists(vim.fn.expand("%:p:h"))
end, { desc = "Create starter CMakeLists.txt in current directory" })

-- Popup window displaying all custom shortcuts
local function show_shortcuts()
  local text = {
    "# ⚡ Custom & Essential Shortcuts",
    "",
    "## 🚀 Code Runner & Build (<F5> or <leader>rc)",
    "  <F5>           Run Code (prompts for CLI arguments, Enter to run)",
    "  <leader>rc     Run Code (prompts for CLI arguments, Enter to run)",
    "  <leader>rr     Re-run Code (runs immediately with last arguments)",
    "  <leader>cv     Select Python VirtualEnv (venv-selector)",
    "  :CMakeInit     Create auto-updating CMakeLists.txt for current folder",
    "  q              Close the terminal window when execution finishes",
    "  <leader>cf     Format code with Ruff / clang-format (also auto on save)",
    "  <leader>ch     Switch between Header and Source (.cpp <-> .h)",
    "  <leader>cd     Show line diagnostics / error explanation",
    "  <leader>cr     Rename variable / symbol across project",
    "  gd             Jump to definition",
    "  K              Hover documentation for symbol under cursor",
    "",
    "## 🐛 Universal Debugger (Python, C/C++, Rust, Any Language)",
    "  <leader>dc         Start Debugger (Auto-detects language & builds if needed)",
    "  <F5>               Continue to next breakpoint (when debugging) / Run Code",
    "  <F9> / <leader>db  Toggle Breakpoint on current line",
    "  <leader>dB         Set Conditional Breakpoint",
    "  <F10> / <leader>do Step Over (next line)",
    "  <F11> / <leader>di Step Into (into function call)",
    "  <F12> / <leader>dO Step Out (exit current function)",
    "  <leader>de         Eval expression under cursor (or visual selection)",
    "  <leader>du         Toggle Debug UI (Variables, Call Stack, Watches)",
    "  <leader>dr         Toggle Debug REPL / Console",
    "  <S-F5> / <leader>dt Terminate debugging session & close UI",
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
  vim.keymap.set("n", "<A-CR>", function()
    vim.g.neovide_fullscreen = not vim.g.neovide_fullscreen
  end, { desc = "Toggle Neovide fullscreen" })
end

-- ==========================================
-- ccc.nvim (Color Picker & Highlighter)
-- ==========================================

-- Open the color picker over a color code
vim.keymap.set("n", "<leader>cp", "<cmd>CccPick<cr>", { desc = "Color Picker: Open UI" })

-- Cycle the color under cursor through formats (Hex -> RGB -> HSL)
vim.keymap.set("n", "<leader>cc", "<cmd>CccConvert<cr>", { desc = "Color Picker: Convert Format" })

-- Toggle the color highlighter on/off for the current file
vim.keymap.set("n", "<leader>ch", "<cmd>CccHighlighterToggle<cr>", { desc = "Color Picker: Toggle Highlighter" })
