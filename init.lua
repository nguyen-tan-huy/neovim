-- ~/.config/nvim/init.lua
-- Neovim config hướng tới trải nghiệm giống IntelliJ cho Java

-- ===== Options cơ bản =====
vim.g.mapleader = " "

-- JDTLS cần JDK 17+, dùng JDK 21 làm mặc định khi mở Neovim.
-- Muốn đổi JDK cho terminal/Maven lúc đang chạy: <leader>mv
-- Muốn đổi JDK dùng để compile/debug project (jdtls): <leader>jv
require("jdk").set_java_home("/usr/lib/jvm/java-21-openjdk")
vim.g.maplocalleader = " "

local o = vim.opt
o.number = true
o.relativenumber = true
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.smartindent = true
o.wrap = false
o.ignorecase = true
o.smartcase = true
o.termguicolors = true
o.signcolumn = "yes"
o.updatetime = 250
o.timeoutlen = 300
o.splitright = true
o.splitbelow = true
o.scrolloff = 8
o.clipboard = "unnamedplus"
o.cursorline = true

-- ===== Auto-root: chỉ đổi cwd ĐÚNG 1 LẦN lúc khởi động, không đổi lại nữa =====
-- Trước đây tự đổi cwd theo project của TỪNG file khi qua lại (BufEnter) để Telescope tìm đúng
-- phạm vi - nhưng đổi liên tục theo buffer làm neo-tree/telescope "nhảy" loạn giữa các module
-- (vd product-web <-> product-core). Giờ chỉ dò root 1 LẦN khi Neovim khởi động, dựa theo file
-- đầu tiên được mở (nếu có) hoặc :pwd hiện tại, rồi CỐ ĐỊNH - dùng lệnh :cd tay nếu muốn đổi.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local path = vim.api.nvim_buf_get_name(0)
    if path == "" or vim.bo.buftype ~= "" then return end
    local root_markers = { ".git", "pom.xml", "build.gradle", "build.gradle.kts", "mvnw", "gradlew", "settings.gradle" }
    local found = vim.fs.find(root_markers, { upward = true, path = vim.fs.dirname(path) })[1]
    local root = found and vim.fs.dirname(found)
    if root and root ~= vim.fn.getcwd() then
      vim.fn.chdir(root)
    end
  end,
})

-- ===== Bootstrap lazy.nvim =====
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
  install = { colorscheme = { "tokyonight" } },
  change_detection = { notify = false },
})

-- ===== Keymap chung (giống IntelliJ) =====
local map = vim.keymap.set

-- Project explorer (Alt+1)
map("n", "<A-1>", "<cmd>Neotree toggle<CR>", { desc = "Toggle file explorer" })

-- Navigate Back/Forward (giống Shift+Alt+Left/Right của IntelliJ)
-- Ctrl-O/Ctrl-I có sẵn trong Neovim (jumplist), chỉ cần gán thêm phím tắt quen tay
map("n", "<A-S-Left>", "<C-o>", { desc = "Navigate back" })
map("n", "<A-S-Right>", "<C-i>", { desc = "Navigate forward" })

-- Di chuyển nhanh giữa các panel/window (vd: các panel của debug UI - Scopes/Breakpoints/Stacks/Watches)
-- Dùng Alt thay vì Ctrl vì Ctrl-h/Ctrl-j trùng mã ASCII với Backspace/Enter ở hầu hết terminal,
-- nên Neovim không bao giờ nhận được đúng phím Ctrl-h/Ctrl-j (không phải lỗi cấu hình, do giới hạn terminal).
map("n", "<A-h>", "<C-w>h", { desc = "Window: sang trái" })
map("n", "<A-j>", "<C-w>j", { desc = "Window: xuống dưới" })
map("n", "<A-k>", "<C-w>k", { desc = "Window: lên trên" })
map("n", "<A-l>", "<C-w>l", { desc = "Window: sang phải" })

-- Search everywhere (Shift+Shift trong IntelliJ -> dùng <leader>ff ở đây)
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "Find file" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { desc = "Find in files" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Buffers" })
map("n", "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", { desc = "Symbols in file" })
map("n", "<leader>fw", "<cmd>Telescope lsp_workspace_symbols<CR>", { desc = "Symbols in project" })
map("n", "<leader>fc", "<cmd>Telescope lsp_workspace_symbols<CR>", { desc = "Go to class (Ctrl+N)" })
map("n", "<leader>fr", "<cmd>Telescope oldfiles<CR>", { desc = "Recent files (Ctrl+E)" })

-- Show errors/warnings (Problems panel)
map("n", "<leader>xx", "<cmd>TroubleToggle<CR>", { desc = "Toggle diagnostics list" })

-- Copy Path (giống chuột phải > Copy Path/Copy Relative Path của IntelliJ). Vào thẳng clipboard
-- hệ thống vì 'clipboard=unnamedplus' đã map thanh ghi mặc định "" sang "+ rồi.
map("n", "<leader>cp", function()
  local path = vim.fn.expand("%:p")
  vim.fn.setreg("+", path)
  vim.notify("Đã copy: " .. path, vim.log.levels.INFO)
end, { desc = "Copy Path (đường dẫn tuyệt đối)" })
map("n", "<leader>cP", function()
  local path = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
  vim.fn.setreg("+", path)
  vim.notify("Đã copy: " .. path, vim.log.levels.INFO)
end, { desc = "Copy Relative Path (từ project root)" })

-- ===== Debug helpers (Java) =====

-- Tìm profile Spring Boot có thật trong project (application-<profile>.yml/properties),
-- fallback về danh sách mặc định nếu không tìm thấy file nào.
local function detect_spring_profiles()
  local patterns = {
    "**/src/main/resources/application-*.yml",
    "**/src/main/resources/application-*.yaml",
    "**/src/main/resources/application-*.properties",
  }
  local seen, profiles = {}, {}
  for _, pat in ipairs(patterns) do
    for _, f in ipairs(vim.fn.globpath(vim.fn.getcwd(), pat, false, true)) do
      local name = f:match("application%-([%w%-_]+)%.%a+$")
      if name and not seen[name] then
        seen[name] = true
        table.insert(profiles, name)
      end
    end
  end
  table.insert(profiles, "custom")
  if #profiles == 1 then
    return { "dev", "prod", "staging", "custom" }
  end
  return profiles
end

-- Đảm bảo dap.configurations.java đã được populate (main class detection qua jdtls.dap).
-- jdtls.dap.setup_dap_main_class_configs tự dedupe theo (name, cwd) và có callback on_ready,
-- không cần tự polling như trước.
local function ensure_java_dap_configs(callback)
  local dap = require("dap")
  local configs = dap.configurations.java or {}
  if #configs > 0 then
    callback(configs)
    return
  end
  local ok, jdtls_dap = pcall(require, "jdtls.dap")
  if not ok then
    callback({})
    return
  end
  vim.notify("Đang quét main class (jdtls)...", vim.log.levels.INFO)
  jdtls_dap.setup_dap_main_class_configs({
    on_ready = function()
      local found = require("dap").configurations.java or {}
      -- Lưu ngay profile tự dò được xuống đĩa, để tắt/mở lại Neovim vẫn còn mà không cần
      -- phải mở đúng file .java qua ftplugin (nơi vốn cũng tự lưu ở bước attach jdtls).
      local root_dir = require("dap_profiles").resolve_root_dir()
      if root_dir and #found > 0 then
        require("dap_profiles").save(root_dir, found)
      end
      callback(found)
    end,
  })
end

-- IntelliJ-style Run/Debug: chọn config -> chọn Spring profile -> VM args -> program args -> working dir
local function run_java_debug()
  local dap = require("dap")

  local function launch(cfg)
    local profiles = detect_spring_profiles()
    vim.ui.select(profiles, { prompt = "Spring profile:" }, function(profile)
      if not profile then return end
      local baseVmArgs = cfg.vmArgs or ""
      if profile ~= "custom" then
        baseVmArgs = (baseVmArgs ~= "" and baseVmArgs .. " " or "") .. "-Dspring.profiles.active=" .. profile
      end

      vim.ui.input({ prompt = "Extra VM args (vd: -Xmx1g -Dport=8080):", default = baseVmArgs }, function(vmArgs)
        if vmArgs == nil then return end
        cfg.vmArgs = vmArgs

        vim.ui.input({ prompt = "Program args (vd: --server.port=9090):", default = cfg.args or "" }, function(args)
          if args == nil then return end
          cfg.args = args

          vim.ui.input({
            prompt = "Working dir (Enter = project root):",
            default = cfg.cwd or vim.fn.getcwd(),
          }, function(cwd)
            if cwd == nil then return end
            if cwd ~= "" then cfg.cwd = cwd end
            _G._last_dap_run_cfg = cfg

            -- Lưu luôn xuống <project_root>/.nvim/dap-profiles.json (giống IntelliJ tự cập nhật
            -- Run Configuration mỗi lần Run), để tắt/mở lại Neovim vẫn còn - khác với chỉ giữ ở
            -- _G._last_dap_run_cfg (mất khi restart Neovim).
            local dap_profiles = require("dap_profiles")
            local root_dir = dap_profiles.resolve_root_dir()
            if root_dir then
              local configs = dap.configurations.java or {}
              local existing
              for _, c in ipairs(configs) do
                if c.name == cfg.name then
                  existing = c
                  break
                end
              end
              if existing then
                existing.mainClass = cfg.mainClass
                existing.cwd = cfg.cwd
                existing.vmArgs = cfg.vmArgs
                existing.args = cfg.args
              else
                table.insert(configs, cfg)
                dap.configurations.java = configs
              end
              dap_profiles.save(root_dir, dap.configurations.java)
            end

            dap.run(cfg)
          end)
        end)
      end)
    end)
  end

  ensure_java_dap_configs(function(configs)
    if #configs == 0 then
      vim.ui.input({
        prompt = "Không tìm thấy main class. Nhập tay (vd: com.example.Application, Enter=bỏ):",
      }, function(main)
        if not main or main == "" then return end
        launch({ type = "java", request = "launch", name = main, mainClass = main })
      end)
      return
    end

    if #configs == 1 then
      launch(vim.deepcopy(configs[1]))
      return
    end

    vim.ui.select(configs, {
      prompt = "Select config to run:",
      format_item = function(c) return c.name end,
    }, function(choice)
      if not choice then return end
      launch(vim.deepcopy(choice))
    end)
  end)
end

-- Run/Debug (giống Shift+F10): nếu đang debug thì continue, nếu không thì chạy lại config gần nhất,
-- lần đầu chưa có config nào thì mở wizard chọn config/profile/cwd.
map("n", "<F5>", function()
  local dap = require("dap")
  if dap.session() then
    dap.continue()
    return
  end
  if vim.bo.filetype ~= "java" then
    -- Rust (và các filetype khác có dap.configurations riêng): dùng thẳng dap.continue(),
    -- nvim-dap tự hỏi chọn config nếu có nhiều configuration cho filetype đó.
    dap.continue()
    return
  end
  if _G._last_dap_run_cfg then
    dap.run(_G._last_dap_run_cfg)
    return
  end
  run_java_debug()
end, { desc = "Debug: continue / run last config" })

-- Chạy nhanh main class của file hiện tại, không hỏi profile/cwd (giống Ctrl+Shift+F10)
map("n", "<leader>jr", function()
  local bufnr = vim.api.nvim_get_current_buf()
  ensure_java_dap_configs(function(configs)
    if #configs == 0 then
      vim.notify("Không tìm thấy main class trong project. jdtls có thể chưa import xong, hoặc project chưa được nhận diện đúng (kiểm tra :LspInfo).",
        vim.log.levels.WARN)
      return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 200, false)
    local package_name
    for _, l in ipairs(lines) do
      local pkg = l:match("^%s*package%s+([%w%.]+)%s*;")
      if pkg then
        package_name = pkg
        break
      end
    end
    local class_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t:r")
    local target = package_name and (package_name .. "." .. class_name) or class_name

    local match
    for _, c in ipairs(configs) do
      if c.mainClass == target then
        match = c
        break
      end
    end
    if not match and #configs == 1 then match = configs[1] end
    if not match then
      vim.notify("Không tìm thấy main class cho file hiện tại (" .. target .. "). Dùng <leader>dr để chọn thủ công.",
        vim.log.levels.WARN)
      return
    end

    local cfg = vim.deepcopy(match)
    _G._last_dap_run_cfg = cfg
    require("dap").run(cfg)
  end)
end, { desc = "Debug: run main of current file (Ctrl+Shift+F10)" })

-- Resume program (giống F9 của IntelliJ). Bấm khi chưa có session sẽ không làm gì -
-- dùng F5 để bắt đầu debug lần đầu.
map("n", "<F9>", function() require("dap").continue() end, { desc = "Resume program" })
-- Step over/into/out/toggle breakpoint giờ nằm ở F8/F7/Shift-F8/Ctrl-F8 (xem dap.lua)

-- IntelliJ-style: chọn config, chọn Spring profile, sửa VM args/program args/working dir trước khi run
map("n", "<leader>dr", run_java_debug, { desc = "Debug: run with custom config (profile + cwd)" })

-- (Không còn "Edit Configurations" đã lưu như trước - dùng <leader>dr mỗi lần run để sửa
-- profile/VM args/program args/cwd. Các phím Java khác (<leader>ju/jU/jR/jv/jev/jec/jem/joi)
-- giờ nằm ở ftplugin/java.lua, gắn theo buffer khi jdtls attach.)

-- ===== Terminal & Maven (giống terminal trong IntelliJ) =====
local Terminal = require("toggleterm.terminal").Terminal

function _G.run_maven(cmd)
  local terminal = Terminal:new({
    cmd = "mvn " .. cmd,
    direction = "horizontal",
    dir = vim.fn.getcwd(),
    close_on_exit = false, -- chạy xong giữ nguyên panel để xem log/kết quả build
  })
  terminal:toggle()
end

-- Chọn JDK cho terminal/Maven (áp dụng cho các lệnh mvn chạy SAU khi chọn, không ảnh hưởng
-- terminal đã mở sẵn). Đổi JDK dùng để compile/debug project trong jdtls thì dùng <leader>jv.
map("n", "<leader>mv", function()
  local jdk = require("jdk")
  local jdks = jdk.list()
  if #jdks == 0 then
    vim.notify("Không tìm thấy JDK nào trong /usr/lib/jvm hoặc ~/.sdkman/candidates/java", vim.log.levels.WARN)
    return
  end
  vim.ui.select(jdks, {
    prompt = "Chọn JDK cho terminal/Maven (hiện tại: " .. (vim.env.JAVA_HOME or "?") .. "):",
    format_item = function(d)
      local major = jdk.major_version(d)
      return vim.fn.fnamemodify(d, ":t") .. (major and (" (Java " .. major .. ")") or "")
    end,
  }, function(choice)
    if not choice then return end
    jdk.set_java_home(choice)
    vim.notify("JAVA_HOME = " .. choice .. " (áp dụng cho terminal/Maven mới)", vim.log.levels.INFO)
  end)
end, { desc = "Maven: chọn JDK version" })

map("n", "<A-2>", "<cmd>ToggleTerm<CR>", { desc = "Toggle terminal" })
map("n", "<leader>mc", ":lua run_maven('clean')<CR>", { desc = "Maven: clean" })
map("n", "<leader>mC", ":lua run_maven('compile')<CR>", { desc = "Maven: compile" })
map("n", "<leader>mt", ":lua run_maven('test')<CR>", { desc = "Maven: test" })
map("n", "<leader>mp", ":lua run_maven('package -DskipTests')<CR>", { desc = "Maven: package" })
map("n", "<leader>mi", ":lua run_maven('install -DskipTests')<CR>", { desc = "Maven: install" })
map("n", "<leader>msb", ":lua run_maven('spring-boot:run')<CR>", { desc = "Maven: spring-boot:run" })
map("n", "<leader>mdt", ":lua run_maven('dependency:tree')<CR>", { desc = "Maven: dependency tree" })
