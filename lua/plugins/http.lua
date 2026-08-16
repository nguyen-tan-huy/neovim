return {
  -- HTTP client (giống HTTP Client của IntelliJ, chạy request từ file .http)
  {
    "mistweaverco/kulala.nvim",
    ft = "http",
    config = function()
      require("kulala").setup({})
      vim.keymap.set("n", "<leader>hr", function() require("kulala").run() end, { desc = "HTTP: run request dưới cursor" })
      vim.keymap.set("n", "<leader>ha", function() require("kulala").run_all() end, { desc = "HTTP: run all requests" })
      vim.keymap.set("n", "<leader>ht", function() require("kulala").toggle_view() end, { desc = "HTTP: toggle panel kết quả" })
    end,
  },
}
