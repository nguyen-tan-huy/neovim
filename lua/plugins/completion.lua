return {
  "hrsh7th/nvim-cmp",
  dependencies = {
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path",
    "L3MON4D3/LuaSnip",
    "saadparwaiz1/cmp_luasnip",
    "rcarriga/cmp-dap",
    "rafamadriz/friendly-snippets",
  },
  config = function()
    local cmp = require("cmp")
    local luasnip = require("luasnip")

    -- Bộ snippet có sẵn (Java: psvm, sout, try/catch...) giống Live Templates của IntelliJ
    require("luasnip.loaders.from_vscode").lazy_load()

    cmp.setup({
      snippet = {
        expand = function(args) luasnip.lsp_expand(args.body) end,
      },
      mapping = cmp.mapping.preset.insert({
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<CR>"] = cmp.mapping.confirm({ select = true }),
        ["<Tab>"] = cmp.mapping.select_next_item(),
        ["<S-Tab>"] = cmp.mapping.select_prev_item(),
      }),
      sources = cmp.config.sources({
        { name = "nvim_lsp" },
        { name = "luasnip" },
      }, {
        { name = "buffer" },
        { name = "path" },
      }),
    })

    -- Gợi ý code (biến/thuộc tính) trong REPL debug và panel Watches, giống Evaluate Expression của IntelliJ
    require("cmp_dap")
    cmp.setup.filetype({ "dap-repl", "dapui_watches" }, {
      sources = {
        { name = "dap" },
      },
    })

    -- Gợi ý tên bảng/cột khi gõ SQL trong DBUI, giống code completion của Database tool window
    cmp.setup.filetype({ "sql", "mysql", "plsql" }, {
      sources = cmp.config.sources({
        { name = "vim-dadbod-completion" },
        { name = "luasnip" },
      }, {
        { name = "buffer" },
      }),
    })
  end,
}
