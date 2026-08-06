return {
  -- Cấu hình jdtls thật sự nằm ở ftplugin/java.lua (chạy mỗi khi mở buffer .java),
  -- đây chỉ khai plugin để lazy.nvim cài về.
  {
    "mfussenegger/nvim-jdtls",
  },
  {
    "JavaHello/spring-boot.nvim",
    ft = "java",
    dependencies = { "mfussenegger/nvim-jdtls" },
    config = function()
      -- Dùng lại bản spring-boot-tools đã tải sẵn từ trước (không có gói tương đương trên Mason).
      -- Không tự cập nhật version nữa vì không còn nvim-java quản lý tải về.
      local ls_path = vim.fn.stdpath("data") ..
          "/nvim-java/packages/spring-boot-tools/1.55.1/extension/language-server"
      if vim.fn.isdirectory(ls_path) == 1 then
        require("spring_boot").setup({ ls_path = ls_path })
        require("spring_boot").init_lsp_commands()
      else
        vim.notify(
          "spring-boot.nvim: không thấy language-server tại " .. ls_path ..
          " -> autocomplete application.yml/properties sẽ không hoạt động.",
          vim.log.levels.WARN)
      end
    end,
  },
}
