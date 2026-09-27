-- Dùng local checkout ĐANG SỬA (~/Git-projects/java-debug-model) nếu có sẵn trên máy này (dev
-- workflow: sửa file ở đó, load lại nvim là thấy ngay, không cần commit+push+lazy sync mỗi lần) -
-- máy khác không có thư mục này thì lazy.nvim tự clone thẳng từ GitHub, KHÔNG cần dòng dir= nào
-- cả. Đây chính là điều kiện để "chỉ cần thêm block plugin này vào 1 máy sạch" hoạt động được:
-- trước đây dir= luôn trỏ cứng vào local path, máy không có sẵn thư mục đó sẽ lỗi ngay từ bước
-- cài plugin (lazy.nvim không tự clone khi đã có dir=).
local java_debug_model_local_dir = vim.fn.expand("~/Git-projects/java-debug-model")

return {
  {
    -- TOÀN BỘ trải nghiệm Java (không chỉ Project Model / Run-Debug Configurations / Maven
    -- Lifecycle / JUnit runner kiểu IntelliJ) giờ do java-debug-model quản lý MỘT CHỖ, kể cả:
    --   - khởi động jdtls (pin version jdtls/ASM, chọn bundle debug/test, keymap refactor/JDK
    --     switcher...) - xem lua/java-debug-model/jdtls_launcher.lua.
    --   - TỰ TẢI bản jdtls 1.54.0 đã patch sẵn (2 fix thật của jdt.ls) từ GitHub Release của
    --     chính plugin nếu máy chưa có - không cần tự chạy Tycho build (JDK 21 + p2
    --     target-platform resolution nặng, có lần mất hơn 1 giờ) - xem
    --     java-debug-model/init.lua's DEFAULT_JDTLS_PREBUILT_URL + bootstrap.lua's
    --     ensure_jdtls_prebuilt. Không cần truyền gì thêm ở setup() dưới đây, đã là default sẵn
    --     trong chính plugin - đúng nghĩa "cài 1 plugin này là chạy được luôn".
    --   - cài Mason packages cần thiết (jdtls/java-debug-adapter/java-test, fallback khi bản
    --     prebuilt tải lỗi) - xem bootstrap.lua, KHÔNG còn nằm riêng ở plugins/lsp.lua's
    --     mason-lspconfig config nữa.
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
    "nguyen-tan-huy/java-project-model",
    -- Trong app ChoRachIDE (CHORACHIDE=1) luôn dùng bản trên GitHub, không dùng checkout local.
    dir = vim.env.CHORACHIDE == nil and vim.fn.isdirectory(java_debug_model_local_dir) == 1
      and java_debug_model_local_dir or nil,
    name = "java-debug-model",
    event = "VeryLazy",
    dependencies = {
      "mfussenegger/nvim-jdtls",
      "mfussenegger/nvim-dap",
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio", -- dap-ui's own hard dependency (require("dapui") errors without it)
      "JavaHello/spring-boot.nvim",
      "MunifTanjim/nui.nvim", -- toolbar của java-debug-model (trước đi kèm neo-tree)
      "williamboman/mason.nvim", -- bootstrap.lua's ensure_mason_packages/ensure_jdtls_prebuilt fallback need mason-registry
    },
    config = function()
      require("java-debug-model").setup({
        auto_attach = true,
        -- Run/Debug/Restart config đang active bằng ĐÚNG phím IntelliJ (Shift+F10 / Shift+F9 /
        -- Ctrl+F5), để <leader>jr (chạy main file hiện tại) và <leader>jd (Dependency Tree) ở
        -- init.lua dùng lại được - trước đây plugin map đè 2 phím đó. Mỗi hành động map 2 mã
        -- phím vì terminal kiểu xterm gửi Shift+F10 thành <F22>, Shift+F9 -> <F21>, Ctrl+F5 -> <F29>.
        run_debug_keymaps = {
          run = { "<S-F10>", "<F22>" },
          debug = { "<S-F9>", "<F21>" },
          restart = { "<C-F5>", "<F29>" },
          restart_debug = "<leader>jD",
          select = "<leader>jc",
          select_module = "<leader>jm",
        },
      })
    end,
  },
}
