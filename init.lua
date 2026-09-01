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
-- Config Java (main class, VM args, program args, working dir, profile Maven) giờ do
-- java-debug-model quản lý hẳn (:JavaDebugConfigAdd/:JavaDebugConfigEdit/:JavaDebugConfigScan/
-- :JavaDebugConfigFromFile/:JavaDebugConfigRun) - cơ chế cũ ở đây (tự dò main class qua
-- nvim-jdtls + lưu vào lua/dap_profiles.lua) đã bỏ hẳn (file đó đã xoá): nó không đi qua
-- jdtls_bridge.resolve_classpath/resolve_sourcepaths của java-debug-model nên bước vào code của
-- 1 module khác trong CÙNG project (sibling module, kể cả module không khai báo <module> trong
-- pom cha - vd product-web phụ thuộc product-core nhưng product-core không phải <module> của
-- product-web) luôn ra decompile từ .m2 jar thay vì nhảy thẳng vào source thật.
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
  local jdm = require("java-debug-model")
  local root = jdm._find_root(0)
  if not root then
    vim.notify("java-debug-model: không tìm thấy project root (pom.xml) cho file này.", vim.log.levels.WARN)
    return
  end
  local configs = jdm.config_store.list(root)
  if #configs == 0 then
    vim.notify(
      "Chưa có debug config nào cho project này. Dùng :JavaDebugConfigScan (dò main class có sẵn) " ..
      "hoặc :JavaDebugConfigFromFile (tạo từ file đang mở) trước.", vim.log.levels.WARN)
    return
  end
  if #configs == 1 then
    jdm.debug_config_run(root, configs[1].name)
    return
  end
  vim.ui.select(configs, {
    prompt = "Chạy debug config:",
    format_item = function(c) return c.name .. " (" .. c.main_class .. ")" end,
  }, function(choice)
    if choice then jdm.debug_config_run(root, choice.name) end
  end)
end, { desc = "Debug: continue / chạy debug config (java-debug-model)" })

-- Chạy nhanh main class của file hiện tại (giống Ctrl+Shift+F10): tìm 1 config đã lưu khớp đúng
-- class hiện tại - qua jdtls.util.resolve_classname() (đọc "package" thật trong file, giống
-- java-debug-model.debug_config_from_file), KHÔNG đoán qua tên file - rồi chạy thẳng qua
-- java-debug-model (có sourcePaths cho sibling module). Chưa có config sẵn thì báo tạo bằng
-- :JavaDebugConfigFromFile thay vì tự dựng 1 config tạm không qua sourcePaths như trước.
map("n", "<leader>jr", function()
  local jdm = require("java-debug-model")
  local root = jdm._find_root(0)
  if not root then
    vim.notify("java-debug-model: không tìm thấy project root (pom.xml) cho file này.", vim.log.levels.WARN)
    return
  end
  local ok_util, jdtls_util = pcall(require, "jdtls.util")
  local current_class = nil
  if ok_util then
    local ok_call, result = pcall(jdtls_util.resolve_classname)
    if ok_call then current_class = result end
  end
  if not current_class then
    vim.notify("Không xác định được class hiện tại (jdtls chưa attach xong?).", vim.log.levels.WARN)
    return
  end
  for _, cfg in ipairs(jdm.config_store.list(root)) do
    if cfg.main_class == current_class then
      jdm.debug_config_run(root, cfg.name)
      return
    end
  end
  vim.notify(
    "Chưa có debug config cho '" .. current_class .. "'. Dùng :JavaDebugConfigFromFile để tạo.",
    vim.log.levels.WARN)
end, { desc = "Debug: run main of current file (Ctrl+Shift+F10)" })

-- Resume program (giống F9 của IntelliJ). Bấm khi chưa có session sẽ không làm gì -
-- dùng F5 để bắt đầu debug lần đầu.
map("n", "<F9>", function() require("dap").continue() end, { desc = "Resume program" })
-- Step over/into/out/toggle breakpoint giờ nằm ở F8/F7/Shift-F8/Ctrl-F8 (xem dap.lua)

-- Sửa VM args/program args/working dir/profile Maven của 1 config đã lưu (chọn từ danh sách) -
-- thay cho wizard <leader>dr cũ. Tạo config mới: :JavaDebugConfigAdd/:JavaDebugConfigScan/
-- :JavaDebugConfigFromFile. Các phím Java khác (<leader>ju/jU/jR/jv/jev/jec/jem/joi) nằm ở
-- java-debug-model/jdtls_launcher.lua, gắn theo buffer khi jdtls attach.
map("n", "<leader>dr", function()
  local jdm = require("java-debug-model")
  local root = jdm._find_root(0)
  if not root then
    vim.notify("java-debug-model: không tìm thấy project root (pom.xml) cho file này.", vim.log.levels.WARN)
    return
  end
  local configs = jdm.config_store.list(root)
  if #configs == 0 then
    vim.notify("Chưa có debug config nào. Dùng :JavaDebugConfigScan hoặc :JavaDebugConfigFromFile trước.",
      vim.log.levels.WARN)
    return
  end
  vim.ui.select(configs, {
    prompt = "Sửa debug config:",
    format_item = function(c) return c.name .. " (" .. c.main_class .. ")" end,
  }, function(choice)
    if choice then jdm.debug_config_edit(root, choice.name) end
  end)
end, { desc = "Debug: sửa config đã lưu (VM args/program args/cwd/profile)" })

-- ===== Terminal & Maven (giống terminal trong IntelliJ) =====

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

-- Maven Lifecycle giờ qua java-debug-model (giống tool window Maven của IntelliJ) - scope đúng
-- theo TỪNG module thay vì chạy `mvn` thô trên cwd hiện tại, có toggle Skip Tests. Thay hẳn cho
-- <leader>mc/mC/mt/mp/mi/mdt/msb cũ (gọi mvn thô qua toggleterm, không phân biệt module).
map("n", "<leader>mm", "<cmd>JavaMavenPanel<CR>", { desc = "Maven: mở Lifecycle panel (chọn module)" })
map("n", "<leader>ml", "<cmd>JavaMavenLifecycle<CR>", { desc = "Maven: chạy nhanh 1 phase (chọn module + phase)" })

-- ===== Java project model (java-debug-model) =====
-- "Reload Maven Project" giống IntelliJ - resolve lại effective pom + classpath, không cần
-- restart jdtls. Dùng khi vừa sửa pom.xml (thêm dependency/module) mà chưa thấy cập nhật.
map("n", "<leader>jl", "<cmd>JavaModelReload<CR>", { desc = "Java model: reload (giống Reload Maven Project)" })
map("n", "<leader>ji", "<cmd>JavaModelInspect<CR>", { desc = "Java model: inspect (xem module/dependency đã resolve)" })

-- Dependency Tree (giống Maven "Dependency Analyzer"/Diagram của IntelliJ) - chọn module, hiện
-- `mvn dependency:tree -Dverbose` với dòng "omitted for conflict" tô đỏ, để tra library nào kéo
-- vào version nào, version nào thắng - dùng khi debug NoSuchMethodError/ClassNotFoundException
-- do xung đột version giữa các dependency chung.
map("n", "<leader>jd", "<cmd>JavaDependencyTree<CR>", { desc = "Java: xem dependency tree của 1 module" })

-- Chạy JUnit qua jdtls (giống Ctrl+Shift+F9 debug test của IntelliJ) - LUÔN qua DEBUG (không phải
-- run thường), để breakpoint đặt sẵn trong test/code đang test có tác dụng. Panel kết quả riêng
-- (pass/fail, rerun-failed). KHÔNG đụng <leader>tr/tf/ta/ts/to của neotest (dùng chung ngôn ngữ khác).
map("n", "<leader>jtm", "<cmd>TestDebugNearestMethod<CR>", { desc = "Java test: debug method gần cursor" })
map("n", "<leader>jtc", "<cmd>TestDebugClass<CR>", { desc = "Java test: debug cả class" })
map("n", "<leader>jto", "<cmd>JavaTestResults<CR>", { desc = "Java test: mở panel kết quả (rerun-failed)" })

-- Quản lý nhiều debug session Java cùng lúc (module+profile) - riêng với <leader>ds/dx/dX chung
-- của nvim-dap (vẫn cần cho Rust/ngôn ngữ khác).
--
-- <leader>jsm: panel thường trực (danh sách session + phím tắt ngay trong đó: s start mới,
-- f focus, l xem log, r restart, x stop, d xoá, R reload) - thay cho việc gọi lệnh :Java* rời
-- rạc từng cái một (mỗi lệnh lại tự mở 1 vim.ui.select riêng, chọn xong đóng lại, muốn làm việc
-- khác phải gọi lệnh khác). Các lệnh :JavaSession* cũ (jsp/jss/jsx/jsr) vẫn giữ - dùng nhanh
-- 1 thao tác đơn lẻ không cần mở cả panel thì tiện hơn.
map("n", "<leader>jsm", "<cmd>JavaSessionUI<CR>", { desc = "Java session: panel quản lý (start/focus/log/restart/stop/xoá)" })
map("n", "<leader>jsp", "<cmd>JavaSessionPicker<CR>", { desc = "Java session: chọn/focus session (nhanh)" })
map("n", "<leader>jss", "<cmd>JavaSessionStatus<CR>", { desc = "Java session: xem trạng thái (nhanh)" })
map("n", "<leader>jsx", "<cmd>JavaSessionStop<CR>", { desc = "Java session: tắt 1 session (nhanh)" })
map("n", "<leader>jsr", "<cmd>JavaSessionRestart<CR>", {
  desc = "Java session: restart (nhanh, resolve lại classPaths/sourcePaths)",
})
