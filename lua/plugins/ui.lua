return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        flavour = "mocha", -- latte (sáng), frappe, macchiato, mocha (tối nhất)
        transparent_background = false,
        integrations = {
          cmp = true,
          gitsigns = true,
          neotree = true,
          telescope = true,
          treesitter = true,
          native_lsp = { enabled = true },
          dap = true,
          dap_ui = true,
          which_key = true,
          mason = true,
          indent_blankline = { enabled = true },
        },
      })
      vim.cmd.colorscheme("catppuccin")
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
		-- key map for neo tree
		vim.keymap.set("n", "<leader>v", ":Neotree filesystem reveal right<CR>", {})
		vim.keymap.set("n", "<leader>vx", ":Neotree filesystem close <CR>", {})
	end,
  },
  {
    "nvim-lualine/lualine.nvim",
    config = function()
      -- Hiện đang có bao nhiêu debug session chạy + tên, để biết ngay tắt xong thật chưa
      -- thay vì phải đoán (bấm <leader>dX xong không thấy gì báo là còn chạy hay đã tắt).
      local function dap_status()
        local ok, dap = pcall(require, "dap")
        if not ok then return "" end
        local sessions = dap.sessions()
        local names = {}
        for _, s in pairs(sessions) do table.insert(names, s.config.name:match("^[^:]+") or s.config.name) end
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
      require("bufferline").setup({
        options = {
          mode = "buffers",
          numbers = "none",
          show_buffer_close_icons = true,
          show_close_icon = true,
          show_tab_indicators = false,
          diagnostics = "nvim_lsp",
          separator_style = "slant",
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
