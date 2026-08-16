return {
  "numToStr/Comment.nvim",
  config = function()
    require("Comment").setup()

    -- Ctrl+/ giống VSCode/IntelliJ: toggle comment dòng hiện tại (normal)
    -- hoặc các dòng đang chọn (visual). Terminal thường gửi Ctrl+/ dưới dạng
    -- <C-_> nên map cả hai để chắc ăn.
    local api = require("Comment.api")

    for _, key in ipairs({ "<C-/>", "<C-_>" }) do
      vim.keymap.set("n", key, api.toggle.linewise.current, { desc = "Toggle comment" })
      vim.keymap.set("v", key, function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
        api.toggle.linewise(vim.fn.visualmode())
      end, { desc = "Toggle comment (selection)" })
    end
  end,
}
