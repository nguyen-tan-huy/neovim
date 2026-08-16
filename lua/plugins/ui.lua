return {
  {
    "ellisonleao/gruvbox.nvim",
    priority = 1000,
    config = function()
      require("gruvbox").setup({
        contrast = "hard", -- "hard", "soft" hoặc "" (mặc định)
        transparent_mode = false,
      })
      vim.o.background = "dark"
      vim.cmd.colorscheme("gruvbox")
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
			-- key map for neo tree
			vim.keymap.set("n", "<leader>v", ":Neotree filesystem reveal right<CR>", {})
			vim.keymap.set("n", "<leader>vx", ":Neotree filesystem close <CR>", {})
		end,
  },
  {
    "nvim-lualine/lualine.nvim",
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
        if #names == 0 then return "" end
        return "🐛 " .. table.concat(names, ", ")
      end

      require("lualine").setup({
        sections = {
          lualine_x = { dap_status, "encoding", "fileformat", "filetype" },
        },
      })
    end,
  },
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local function url_decode(s)
        return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
      end

      -- File mở từ .class trong jar (gd/references vào lib) có buffer name dạng URI
      -- "jdt://contents/<jar hoặc project ref>/<package>/<Class>.class?<query>" - đặt tên tab
      -- MẶC ĐỊNH của bufferline (basename) ra cả URI encode dài dòng, khó đọc (vd
      -- "%3Cvn.longvan.crm..."). Tự parse ra tên class + tên lib kèm version, giống IntelliJ
      -- hiện "ClassName (library-1.2.3.jar)" ở tab khi mở file decompile từ dependency.
      local function jdt_class_tab_name(path)
        if not path or not path:match("^jdt://") then return nil end
        local jar, _pkg, classfile = path:match("contents/([^/]+)/([%a%d._%-]+)/([^?]+)")
        if not classfile then
          jar, classfile = path:match("contents/([^/]+)/([^?]+)")
        end
        if not classfile then return nil end
        classfile = url_decode(classfile):gsub("%.class$", ""):gsub("%.java$", "")
        local class_name = classfile:match("([^/]+)$") or classfile
        if not jar then return class_name end
        local lib_label = url_decode(jar):gsub("^<", ""):gsub(">$", "")
        -- Rút gọn dạng "maven:groupId:artifactId:version" -> "artifactId:version"
        local parts = {}
        for p in lib_label:gmatch("[^:]+") do table.insert(parts, p) end
        if #parts >= 2 then
          lib_label = parts[#parts - 1] .. ":" .. parts[#parts]
        end
        return class_name .. "  [" .. lib_label .. "]"
      end

      require("bufferline").setup({
        options = {
          mode = "buffers",
          numbers = "none",
          show_buffer_close_icons = true,
          show_close_icon = true,
          show_tab_indicators = false,
          diagnostics = "nvim_lsp",
          separator_style = "slant",
          name_formatter = function(buf) return jdt_class_tab_name(buf.path) end,
        },
      })
      vim.keymap.set("n", "<A-Left>", "<cmd>BufferLineCyclePrev<CR>", { desc = "Previous buffer" })
      vim.keymap.set("n", "<A-Right>", "<cmd>BufferLineCycleNext<CR>", { desc = "Next buffer" })
      vim.keymap.set("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Close buffer" })
    end,
  },
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
