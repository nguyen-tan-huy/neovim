return {
  {
    -- TOÀN BỘ trải nghiệm Java (không chỉ Project Model / Run-Debug Configurations / Maven
    -- Lifecycle / JUnit runner kiểu IntelliJ) giờ do java-debug-model quản lý MỘT CHỖ, kể cả:
    --   - khởi động jdtls (pin version jdtls/ASM, chọn bundle debug/test, keymap refactor/JDK
    --     switcher...) - xem lua/java-debug-model/jdtls_launcher.lua.
    --   - cài Mason packages cần thiết (jdtls/java-debug-adapter/java-test) - xem bootstrap.lua,
    --     KHÔNG còn nằm riêng ở plugins/lsp.lua's mason-lspconfig config nữa.
    --   - wiring JavaHello/spring-boot.nvim (autocomplete application.yml/properties) - xem
    --     bootstrap.lua, KHÔNG còn cần block plugin riêng với config thủ công ở đây nữa.
    -- Chỉ còn setup() dưới đây là đủ có toàn bộ tính năng Java - mfussenegger/nvim-jdtls và
    -- JavaHello/spring-boot.nvim giờ chỉ là dependencies (lazy.nvim tự cài + load trước khi
    -- config() này chạy), không cần block riêng.
    -- auto_attach = true: tự đăng ký autocmd FileType java gọi start_or_attach() khi mở buffer.
    -- event = "VeryLazy" (thay vì ft = "java"): nạp ngay sau khi nvim khởi động, không cần mở
    -- file .java trước - setup() chỉ dò cwd tìm pom.xml (rẻ, không gọi mvn) nên xác định được
    -- project ngay khi mở nvim vào đó, và autocmd FileType đã sẵn sàng trước khi buffer .java
    -- đầu tiên mở ra.
    dir = vim.fn.expand("~/Git-projects/java-debug-model"),
    name = "java-debug-model",
    event = "VeryLazy",
    dependencies = {
      "mfussenegger/nvim-jdtls",
      "mfussenegger/nvim-dap",
      "rcarriga/nvim-dap-ui",
      "JavaHello/spring-boot.nvim",
    },
    config = function()
      require("java-debug-model").setup({
        auto_attach = true,
        -- Khi đã publish GitHub Release cho branch local-patches của
        -- ~/Git-projects/eclipse.jdt.ls-build (tar.gz build sẵn), điền URL asset vào đây - máy
        -- mới mở nvim lần đầu sẽ tự tải+giải nén, không cần tự chạy Tycho build. Để nil (như
        -- hiện tại) thì rơi về Mason (bản jdtls MỚI HƠN, KHÔNG có patch) khi thiếu cache cũ.
        -- jdtls_prebuilt_url = "https://github.com/<fork>/eclipse.jdt.ls/releases/download/<tag>/jdt-language-server-1.54.0.tar.gz",
      })
    end,
  },
}
