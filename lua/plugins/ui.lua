-- Theme của toàn hệ thống (sway/waybar/fuzzel/mako/kitty/btop) chọn qua settings-ui,
-- lưu tên ở ~/.config/sway/theme/state. Neovim đọc file này 1 LẦN lúc khởi động để
-- chọn đúng colorscheme tương ứng (đổi theme lúc đang mở Neovim thì lần mở kế tiếp
-- mới áp dụng - giống cách kitty xử lý theme, không có hot-reload).
local function paper_theme_name()
  local f = io.open(vim.fn.expand("~/.config/sway/theme/state"), "r")
  if not f then return nil end
  local name = f:read("*l")
  f:close()
  return name
end
local PAPER_THEME = paper_theme_name()

-- Giữ lại 3 keymap cũ của akinsho/bufferline.nvim (đã gỡ - xem comment ở chỗ plugin đó từng
-- nằm) bằng lệnh gốc của Neovim, không cần plugin nào cả.
vim.keymap.set("n", "<A-Left>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
vim.keymap.set("n", "<A-Right>", "<cmd>bnext<CR>", { desc = "Next buffer" })
vim.keymap.set("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Close buffer" })

return {
  {
    "rebelot/kanagawa.nvim",
    priority = 1000,
    config = function()
      require("kanagawa").setup({
        background = { dark = "wave", light = "lotus" },
      })
      -- kanagawa là colorscheme mặc định/fallback: áp dụng khi theme hệ thống là
      -- "light"/"dark" (paper gốc), hoặc khi chưa nhận ra theme nào (an toàn, luôn có
      -- 1 colorscheme hợp lệ dù chạy Neovim này ở máy khác không có theme state).
      if PAPER_THEME == "light" then
        vim.o.background = "light"
        vim.cmd.colorscheme("kanagawa")
      elseif PAPER_THEME == nil or PAPER_THEME == "dark" then
        vim.o.background = "dark"
        vim.cmd.colorscheme("kanagawa")
      end
    end,
  },
  {
    "gbprod/nord.nvim",
    priority = 1000,
    config = function()
      require("nord").setup({})
      if PAPER_THEME == "nord" then
        vim.cmd.colorscheme("nord")
      end
    end,
  },
  {
    "ellisonleao/gruvbox.nvim",
    priority = 1000,
    config = function()
      require("gruvbox").setup({})
      if PAPER_THEME == "gruvbox-dark" then
        vim.o.background = "dark"
        vim.cmd.colorscheme("gruvbox")
      elseif PAPER_THEME == "gruvbox-light" then
        vim.o.background = "light"
        vim.cmd.colorscheme("gruvbox")
      end
    end,
  },
  {
    "maxmx03/solarized.nvim",
    priority = 1000,
    config = function()
      require("solarized").setup({})
      if PAPER_THEME == "solarized-dark" then
        vim.o.background = "dark"
        vim.cmd.colorscheme("solarized")
      end
    end,
  },
  {
    "Mofiqul/dracula.nvim",
    priority = 1000,
    config = function()
      require("dracula").setup({})
      if PAPER_THEME == "dracula" then
        vim.cmd.colorscheme("dracula")
      end
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    -- Disabled (not deleted - flip back to true, or drop this line, to revert): "bỏ plugin
    -- statusline, java-project-model tự tạo statusline riêng chỉ nằm dưới cùng của màn hình như
    -- intellij" (drop the statusline plugin, java-debug-model builds its own status bar, living
    -- only at the very bottom of the screen, like IntelliJ) - java-debug-model/lua/java-debug-
    -- model/ui/statusline.lua now owns `&statusline`/`&laststatus` (opts.statusline_enabled)
    -- instead, and ported over both signals this config's own lualine section fed it: the
    -- Maven-resolving/jdtls-starting/debug-launching text (java_debug_model_status below,
    -- ui/statusline.lua's own M.right()) and the running-DAP-sessions + port list (dap_status
    -- below, same M.right()).
    enabled = false,
    config = function()
      -- Hiện đang có bao nhiêu debug session chạy + tên (+ port nếu đã bắt được từ log Spring
      -- Boot), để biết ngay tắt xong thật chưa thay vì phải đoán, và khỏi mở console tìm port.
      local function dap_status()
        local ok, dap = pcall(require, "dap")
        if not ok then return "" end
        local ok_status, dap_status_mod = pcall(require, "dap_status")
        local sessions = dap.sessions()
        local names = {}
        for _, s in pairs(sessions) do
          local nm = s.config.name:match("^[^:]+") or s.config.name
          local port = ok_status and dap_status_mod.ports[s.config.name]
          if port then nm = nm .. ":" .. port end
          table.insert(names, nm)
        end
        local parts = {}
        if #names > 0 then table.insert(parts, "🐛 " .. table.concat(names, ", ")) end
        return table.concat(parts, " ")
      end

      -- java-debug-model đang resolve Maven / chạy Maven Lifecycle / khởi động debug session
      -- (xem lua/java-debug-model/status.lua) - mvn có thể mất 10-60s, không có báo gì thì
      -- tưởng nhầm Neovim bị đứng.
      local function java_debug_model_status()
        local ok, jdm = pcall(require, "java-debug-model")
        if not ok then return "" end
        local ok_call, text = pcall(jdm.statusline)
        return ok_call and text or ""
      end

      require("lualine").setup({
        -- Mặc định lualine chỉ vẽ lại theo sự kiện gõ phím/di chuyển con trỏ - trong lúc mvn
        -- resolve/chạy lifecycle/khởi động debug thì người dùng thường chỉ ngồi chờ, không gõ
        -- gì cả, nên phải tự poll định kỳ thì thanh loading mới cập nhật (VD: biến mất đúng
        -- lúc mvn xong) thay vì bị kẹt lại trạng thái cũ tới khi có phím tiếp theo.
        refresh = { statusline = 500 },
        sections = {
          lualine_x = { java_debug_model_status, dap_status, "encoding", "fileformat", "filetype" },
        },
      })
    end,
  },
  -- akinsho/bufferline.nvim removed - java-debug-model now owns the tabline itself
  -- (ui/bufferline.lua, opts.bufferline_enabled), including the same "ClassName
  -- [artifactId:version]" label for a decompiled jdt:// dependency source this plugin's own
  -- config used to provide. The 3 keymaps below are kept (Neovim's own :bnext/:bprevious/
  -- :bdelete instead of BufferLineCycle*/bdelete, functionally the same).
  {
    "lewis6991/gitsigns.nvim",
    config = function() require("gitsigns").setup({}) end,
  },
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<CR>", desc = "Git: visual diff" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", desc = "Git: local history của file" },
      { "<leader>gc", "<cmd>DiffviewClose<CR>", desc = "Git: đóng diffview" },
    },
  },
  {
    "folke/trouble.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function() require("trouble").setup({}) end,
  },
  {
    "folke/which-key.nvim",
    config = function() require("which-key").setup({}) end,
  },
  {
    "akinsho/toggleterm.nvim",
    config = function()
      require("toggleterm").setup({
        size = 15,
        open_mapping = nil,
        direction = "horizontal",
        start_in_insert = true,
      })

      -- Chạy mvn theo đúng pom.xml gần nhất tính từ file đang mở (thư mục hiện tại/module
      -- con), KHÔNG phải root reactor - để build đúng module đang đứng thay vì build lại
      -- hết cả project. Đi ngược thư mục lên tới khi gặp pom.xml đầu tiên.
      local function nearest_pom_dir()
        local start = vim.fn.expand("%:p:h")
        if start == "" then start = vim.fn.getcwd() end
        local found = vim.fs.find("pom.xml", { path = start, upward = true })[1]
        return found and vim.fn.fnamemodify(found, ":h") or nil
      end

      vim.keymap.set("n", "<leader>mb", function()
        local dir = nearest_pom_dir()
        if not dir then
          vim.notify("Không tìm thấy pom.xml từ thư mục hiện tại trở lên.", vim.log.levels.WARN)
          return
        end
        vim.ui.input({ prompt = "mvn goal (tại " .. dir .. "): ", default = "clean install -DskipTests" }, function(goal)
          if not goal or goal == "" then return end
          require("toggleterm.terminal").Terminal
            :new({ cmd = "mvn " .. goal, dir = dir, close_on_exit = false })
            :toggle()
        end)
      end, { desc = "Maven: build theo pom.xml gần nhất" })
    end,
  },
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "rcasia/neotest-java",
    },
    config = function()
      local neotest = require("neotest")
      neotest.setup({
        adapters = { require("neotest-java") },
      })

      vim.keymap.set("n", "<leader>tr", function() neotest.run.run() end, { desc = "Test: run nearest" })
      vim.keymap.set("n", "<leader>tf", function() neotest.run.run(vim.fn.expand("%")) end, { desc = "Test: run file" })
      vim.keymap.set("n", "<leader>ta", function() neotest.run.run(vim.uv.cwd()) end, { desc = "Test: run all" })
      vim.keymap.set("n", "<leader>ts", function() neotest.summary.toggle() end, { desc = "Test: summary" })
      vim.keymap.set("n", "<leader>to", function() neotest.output.open() end, { desc = "Test: output" })
    end,
  },
  {
    "ThePrimeagen/refactoring.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    config = function()
      local ok = pcall(require, "refactoring")
      if not ok then return end
      require("refactoring").setup({})
      vim.keymap.set("x", "<leader>rv", function() require("refactoring").refactor("Extract Variable") end, { desc = "Extract variable" })
      vim.keymap.set("x", "<leader>rc", function() require("refactoring").refactor("Extract Constant") end, { desc = "Extract constant" })
      vim.keymap.set("x", "<leader>rm", function() require("refactoring").refactor("Extract Function") end, { desc = "Extract function" })
      vim.keymap.set("x", "<leader>ri", function() require("refactoring").refactor("Inline Variable") end, { desc = "Inline variable" })
      vim.keymap.set("n", "<leader>ri", function() require("refactoring").refactor("Inline Variable") end, { desc = "Inline variable" })
    end,
  },
  {
    "crusj/bookmarks.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    config = function()
      require("bookmarks").setup({
        sign_priority = 1,
        save_file = vim.fn.stdpath("data") .. "/bookmarks",
        default_mappings = false,
      })
      vim.keymap.set("n", "<leader>bm", function() require("bookmarks").toggle() end, { desc = "Toggle bookmark" })
      vim.keymap.set("n", "<leader>bn", function() require("bookmarks").next() end, { desc = "Next bookmark" })
      vim.keymap.set("n", "<leader>bp", function() require("bookmarks").prev() end, { desc = "Prev bookmark" })
      vim.keymap.set("n", "<leader>bl", function() require("bookmarks").list() end, { desc = "List bookmarks" })
    end,
  },
}
