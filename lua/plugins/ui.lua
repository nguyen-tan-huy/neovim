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
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
		"MunifTanjim/nui.nvim",
		-- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
	},
	config = function()
			-- Neovim mặc định tự chia lại TẤT CẢ cửa sổ cho bằng nhau mỗi khi mở/đóng 1 split
			-- (option 'equalalways') - đây là nguyên nhân chính khiến neo-tree bị giãn to ra
			-- lộn xộn dù đã set width cố định, vì 'winfixwidth' của neo-tree cũng không chặn
			-- được hành vi này trong mọi trường hợp (vd đóng 1 split khác). Tắt hẳn để mọi split
			-- (kể cả code) giữ nguyên kích thước đang có, không bị auto-resize theo nhau.
			vim.o.equalalways = false

			require("neo-tree").setup({
				window = {
					width = 30,
					-- Không cho nội dung (tên file dài) tự đẩy rộng cửa sổ ra
					auto_expand_width = false,
				},
				filesystem = {
					-- Mặc định neo-tree tự đổi root theo :pwd (bind_to_cwd = true). Từ khi có
					-- auto-root ở init.lua (tự cd sang đúng module Maven của file đang mở, để
					-- Telescope tìm đúng phạm vi), :pwd đổi liên tục mỗi khi qua lại giữa
					-- product-web/product-core -> kéo theo neo-tree cũng đổi root loạn theo.
					-- Tắt để neo-tree đứng yên, chỉ đổi root khi tự tay bấm (vd phím "cd" trong
					-- cây) hoặc gọi lại ":Neotree reveal".
					bind_to_cwd = false,
					filtered_items = {
						hide_dotfiles = false,
						hide_gitignored = false,
					},
					window = {
						width = 30,
					},
				},
			})
			-- <leader>v: TOGGLE cây file bên trái - nếu buffer hiện tại nằm trong 1 project Maven
			-- mà java-debug-model hiểu được thì dùng Project Tree của nó (Project -> Module ->
			-- Source Root -> file, giống Project view của IntelliJ, thay cho cây filesystem thô
			-- của neo-tree); ngoài ra (project không phải Maven, hoặc plugin chưa load) fallback
			-- về neo-tree như cũ. Đang mở thì đóng, đang đóng thì mở - giống Alt+1 toggle của
			-- IntelliJ, không còn phím đóng riêng (<leader>vx đã bỏ - <leader>v tự lo cả 2 chiều).
			local function tree_win()
				local tree_bufnr = vim.fn.bufnr("java-debug-model://project-tree")
				if tree_bufnr ~= -1 then
					local winid = vim.fn.bufwinid(tree_bufnr)
					if winid ~= -1 then return winid end
				end
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
						return win
					end
				end
				return nil
			end
			local function close_tree()
				local winid = tree_win()
				if winid then
					vim.api.nvim_win_close(winid, false)
					return
				end
				vim.cmd("Neotree filesystem close")
			end
			local function open_tree()
				local ok_jdm, jdm = pcall(require, "java-debug-model")
				if ok_jdm then
					local root = jdm.find_root(0)
					if root and vim.fn.filereadable(root .. "/pom.xml") == 1 then
						vim.cmd("JavaProjectTree")
						return
					end
				end
				vim.cmd("Neotree filesystem reveal right")
			end
			vim.keymap.set("n", "<leader>v", function()
				if tree_win() then close_tree() else open_tree() end
			end, {})
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
