return {
  -- Database tools (giống Database tool window của IntelliJ)
  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      "tpope/vim-dadbod",
      { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } },
    },
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
    end,
    keys = {
      { "<leader>Du", "<cmd>DBUIToggle<CR>", desc = "DB: toggle DBUI" },
      { "<leader>Df", "<cmd>DBUIFindBuffer<CR>", desc = "DB: tìm buffer query đang mở" },
    },
  },
}
