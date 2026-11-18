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

-- Auto compile C/C++ projects or single files with -g
local function get_c_cpp_executable()
  local file = vim.fn.expand("%:p")
  local dir = vim.fn.expand("%:p:h")

  if file == "" then
    vim.notify("No file open to debug!", vim.log.levels.ERROR, { title = "DAP" })
    return nil
  end

  -- A. CMake project check
  local cmake_root, cmake_path = find_upward("CMakeLists.txt", dir)
  if cmake_root and cmake_path then
    vim.notify("Building CMake project in Debug mode...", vim.log.levels.INFO, { title = "DAP" })
    local build_cmd = string.format(
      "cmake -B %s/build -DCMAKE_BUILD_TYPE=Debug && cmake --build %s/build",
      vim.fn.shellescape(cmake_root),
      vim.fn.shellescape(cmake_root)
    )
    local res = vim.fn.system(build_cmd)
    if vim.v.shell_error ~= 0 then
      vim.notify("CMake Build Failed:\n" .. res, vim.log.levels.ERROR, { title = "DAP" })
      return nil
    end

    local executables = vim.fn.globpath(cmake_root .. "/build", "*", false, true)
    for _, exec in ipairs(executables) do
      if
        vim.fn.executable(exec) == 1
        and not exec:match("%.so")
        and not exec:match("%.a")
        and not exec:match("CMake")
      then
        return exec
      end
    end
  end

  -- B. Makefile check
  local make_root = find_upward("Makefile", dir)
  if make_root then
    vim.notify("Building with Makefile...", vim.log.levels.INFO, { title = "DAP" })
    local res = vim.fn.system(
      string.format("make -C %s CFLAGS='-g -O0' CXXFLAGS='-g -O0'", vim.fn.shellescape(make_root))
    )
    if vim.v.shell_error ~= 0 then
      vim.notify("Make Failed:\n" .. res, vim.log.levels.ERROR, { title = "DAP" })
      return nil
    end
    local executables = vim.fn.globpath(make_root, "*", false, true)
    for _, exec in ipairs(executables) do
      if vim.fn.executable(exec) == 1 and not exec:match("%.sh") and not exec:match("Makefile") then
        return exec
      end
    end
  end

  -- C. Direct compilation of .cpp / .c files in current directory
  local ft = vim.bo.filetype
  local bin = vim.fn.expand("%:p:r")
  local compiler = (ft == "c") and "gcc" or "g++"
  local std = (ft == "c") and "" or "-std=c++20"

  local cpp_files = vim.fn.globpath(dir, "*.cpp", false, true)
  local c_files = vim.fn.globpath(dir, "*.c", false, true)

  local sources_list = {}
  if ft == "cpp" and #cpp_files > 0 then
    for _, f in ipairs(cpp_files) do
      table.insert(sources_list, vim.fn.shellescape(f))
    end
  elseif ft == "c" and #c_files > 0 then
    for _, f in ipairs(c_files) do
      table.insert(sources_list, vim.fn.shellescape(f))
    end
  else
    table.insert(sources_list, vim.fn.shellescape(file))
  end

  local sources_str = table.concat(sources_list, " ")
  vim.notify("Compiling with debug symbols (-g -O0)...", vim.log.levels.INFO, { title = "DAP" })

  local cmd = string.format("%s -g -O0 %s %s -o %s", compiler, std, sources_str, vim.fn.shellescape(bin))
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("Compilation Failed:\n" .. out, vim.log.levels.ERROR, { title = "DAP" })
    return nil
  end

  return bin
end

-- Rust Cargo compilation helper
local function get_rust_executable()
  local dir = vim.fn.expand("%:p:h")
  local cargo_root = find_upward("Cargo.toml", dir)
  if cargo_root then
    vim.notify("Building Cargo project in Debug mode...", vim.log.levels.INFO, { title = "DAP" })
    local res = vim.fn.system(string.format("cargo build --manifest-path %s/Cargo.toml", vim.fn.shellescape(cargo_root)))
    if vim.v.shell_error ~= 0 then
      vim.notify("Cargo Build Failed:\n" .. res, vim.log.levels.ERROR, { title = "DAP" })
      return nil
    end
    local crate_name = vim.fn.fnamemodify(cargo_root, ":t")
    local bin = cargo_root .. "/target/debug/" .. crate_name
    if vim.fn.executable(bin) == 1 then
      return bin
    end
  end
  return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
end

-- Python interpreter detection (active venv / .venv / Conda / system python)
local function get_python_path()
  if vim.env.VIRTUAL_ENV and vim.fn.executable(vim.env.VIRTUAL_ENV .. "/bin/python") == 1 then
    return vim.env.VIRTUAL_ENV .. "/bin/python"
  elseif vim.env.CONDA_PREFIX and vim.fn.executable(vim.env.CONDA_PREFIX .. "/bin/python") == 1 then
    return vim.env.CONDA_PREFIX .. "/bin/python"
  end
  local venv_dir = find_upward(".venv", vim.fn.expand("%:p:h"))
  if venv_dir and vim.fn.executable(venv_dir .. "/.venv/bin/python") == 1 then
    return venv_dir .. "/.venv/bin/python"
  end
  return "python3"
end

return {
  -- 1. Mason DAP: Auto-installs and maps debuggers for ANY language
  {
    "jay-babu/mason-nvim-dap.nvim",
    dependencies = {
      "mason-org/mason.nvim",
      "mfussenegger/nvim-dap",
    },
    opts = {
      ensure_installed = { "codelldb", "debugpy" },
      automatic_installation = true,
      handlers = {
        -- Custom handler for CodeLLDB to force IPv4 (fixes ECONNREFUSED on Linux)
        codelldb = function(config)
          local mason_codelldb = vim.fn.stdpath("data") .. "/mason/bin/codelldb"
          local codelldb_cmd = vim.fn.executable(mason_codelldb) == 1 and mason_codelldb or "codelldb"
          config.adapters = {
            type = "server",
            port = "${port}",
            host = "127.0.0.1",
            executable = {
              command = codelldb_cmd,
              args = { "--port", "${port}" },
            },
          }
          require("mason-nvim-dap").default_setup(config)
        end,
      },
    },
  },

  -- 2. Virtual Text: Show inline variable values while stepping through code
  {
    "theHamsta/nvim-dap-virtual-text",
    opts = {
      enabled = true,
      enabled_commands = true,
      highlight_changed_variables = true,
      highlight_new_as_changed = false,
      show_stop_reason = true,
      commented = false,
      virt_text_pos = "eol",
    },
  },

  -- 3. DAP UI: Clean debugger interface (Variables, Stacks, Watches, Breakpoints, REPL)
  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "nvim-neotest/nvim-nio" },
    opts = {
      icons = { expanded = "▾", collapsed = "▸", current_frame = "▸" },
      layouts = {
        {
          elements = {
            { id = "scopes", size = 0.35 },
            { id = "breakpoints", size = 0.20 },
            { id = "stacks", size = 0.25 },
            { id = "watches", size = 0.20 },
          },
          size = 40,
          position = "left",
        },
        {
          elements = {
            { id = "repl", size = 0.60 },
            { id = "console", size = 0.40 },
          },
          size = 10,
          position = "bottom",
        },
      },
      floating = {
        border = "rounded",
        mappings = {
          close = { "q", "<Esc>" },
        },
      },
    },
  },

  -- 4. Main DAP setup
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "theHamsta/nvim-dap-virtual-text",
    },
    config = function()
      local dap = require("dap")

      -- Run LazyVim's mason-nvim-dap setup if available
      if LazyVim and LazyVim.has and LazyVim.has("mason-nvim-dap.nvim") then
        require("mason-nvim-dap").setup(LazyVim.opts("mason-nvim-dap.nvim"))
      end

      -- Automatically open DAP UI when debugging starts (loaded lazily on demand)
      dap.listeners.after.event_initialized["dapui_config"] = function()
        pcall(function() require("dapui").open() end)
      end

      -- Keep UI open after execution finishes so variables & output are readable,
      -- but display a clean status notification. (Close anytime with <leader>du or <leader>dt).
      dap.listeners.after.event_terminated["dapui_status"] = function()
        vim.notify("Debugging session terminated.", vim.log.levels.INFO, { title = "Debugger" })
      end
      dap.listeners.after.event_exited["dapui_status"] = function(_, body)
        local code = (body and body.exitCode) or 0
        vim.notify(
          string.format("Process exited with code %d. Press <leader>dt to close UI.", code),
          vim.log.levels.INFO,
          { title = "Debugger" }
        )
      end

      -- High-contrast Dap signs
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError", linehl = "", numhl = "" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticWarn", linehl = "", numhl = "" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DiagnosticError", linehl = "", numhl = "" })
      vim.fn.sign_define("DapLogPoint", { text = "✎", texthl = "DiagnosticInfo", linehl = "", numhl = "" })
      vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticWarn", linehl = "DapStoppedLine", numhl = "DapStoppedLine" })

      vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })

      -- VSCode launch.json support (universal format across all languages)
      local vscode = require("dap.ext.vscode")
      local ok_json, json = pcall(require, "plenary.json")
      if ok_json then
        vscode.json_decode = function(str)
          return vim.json.decode(json.json_strip_comments(str))
        end
      end
      if vim.fn.filereadable(".vscode/launch.json") == 1 then
        pcall(vscode.load_launchjs, nil, {
          codelldb = { "c", "cpp", "rust", "zig" },
          debugpy = { "python" },
        })
      end

      -- Adapter: CodeLLDB (C, C++, Rust, Zig)
      local mason_codelldb = vim.fn.stdpath("data") .. "/mason/bin/codelldb"
      local codelldb_cmd = vim.fn.executable(mason_codelldb) == 1 and mason_codelldb or "codelldb"
      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        host = "127.0.0.1",
        executable = {
          command = codelldb_cmd,
          args = { "--port", "${port}" },
        },
      }

      -- Adapter: GDB (Fallback)
      dap.adapters.gdb = {
        type = "executable",
        command = "gdb",
        args = { "--interpreter=dap", "--eval-command", "set print pretty on" },
      }

      -- Adapter: Python (debugpy)
      local mason_debugpy = vim.fn.stdpath("data") .. "/mason/bin/debugpy-adapter"
      local debugpy_cmd = vim.fn.executable(mason_debugpy) == 1 and mason_debugpy or "debugpy-adapter"
      dap.adapters.python = function(cb, config)
        if config.request == "attach" then
          local port = (config.connect or config).port
          local host = (config.connect or config).host or "127.0.0.1"
          cb({
            type = "server",
            port = assert(port, "`connect.port` is required for python attach configuration"),
            host = host,
            options = { source_filetype = "python" },
          })
        else
          cb({
            type = "executable",
            command = debugpy_cmd,
            options = { source_filetype = "python" },
          })
        end
      end

      -- Configurations: Python
      dap.configurations.python = {
        {
          type = "python",
          request = "launch",
          name = "Debug Current File",
          program = "${file}",
          pythonPath = get_python_path,
          console = "integratedTerminal",
        },
        {
          type = "python",
          request = "launch",
          name = "Debug Current File with Args",
          program = "${file}",
          args = function()
            local args_string = vim.fn.input("Arguments: ")
            return vim.split(args_string, " +")
          end,
          pythonPath = get_python_path,
          console = "integratedTerminal",
        },
        {
          type = "python",
          request = "attach",
          name = "Attach to Remote / Process",
          connect = function()
            local host = vim.fn.input("Host [127.0.0.1]: ")
            host = host ~= "" and host or "127.0.0.1"
            local port = tonumber(vim.fn.input("Port [5678]: ")) or 5678
            return { host = host, port = port }
          end,
        },
      }

      -- Configurations: C & C++
      local cpp_config = {
        {
          name = "Debug C/C++ (Auto Build & Launch)",
          type = "codelldb",
          request = "launch",
          program = get_c_cpp_executable,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          name = "Debug C/C++ with Args (Auto Build & Launch)",
          type = "codelldb",
          request = "launch",
          program = get_c_cpp_executable,
          args = function()
            local args_string = vim.fn.input("Arguments: ")
            return vim.split(args_string, " +")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          name = "Debug C/C++ (Select Binary)",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Path to binary: ", vim.fn.getcwd() .. "/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          name = "Debug C/C++ (GDB Fallback)",
          type = "gdb",
          request = "launch",
          program = get_c_cpp_executable,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          name = "Attach to Process",
          type = "codelldb",
          request = "attach",
          pid = require("dap.utils").pick_process,
          cwd = "${workspaceFolder}",
        },
      }
      dap.configurations.cpp = cpp_config
      dap.configurations.c = cpp_config

      -- Configurations: Rust
      dap.configurations.rust = {
        {
          name = "Debug Rust (Cargo Build & Launch)",
          type = "codelldb",
          request = "launch",
          program = get_rust_executable,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          name = "Debug Rust (Select Binary)",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Path to binary: ", vim.fn.getcwd() .. "/target/debug/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
      }
    end,
  },
}
