return {
  -- Quản lý cài đặt LSP/DAP/formatter (giống Plugin Manager của IntelliJ)
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        -- "jdtls" chỉ để Mason tải về, KHÔNG để mason-lspconfig tự khởi động (jdtls cần
        -- start_or_attach thủ công theo từng project, xem ftplugin/java.lua)
        ensure_installed = { "lua_ls", "lemminx", "jdtls", "rust_analyzer" },
        -- CHẶN mason-lspconfig tự bật LSP server → tránh xung đột với nvim-jdtls
        automatic_enable = false,
      })

      -- Cài thêm qua Mason: java-debug-adapter/java-test (DAP + JUnit runner cho Java) và
      -- codelldb (DAP cho Rust, xem dap.lua) - không phải LSP server nên mason-lspconfig
      -- không tự tải, phải gọi registry trực tiếp.
      local ok_registry, registry = pcall(require, "mason-registry")
      if ok_registry then
        for _, name in ipairs({ "java-debug-adapter", "java-test", "codelldb" }) do
          local ok_pkg, pkg = pcall(registry.get_package, name)
          if ok_pkg and not pkg:is_installed() then
            vim.notify("Đang cài " .. name .. " qua Mason...", vim.log.levels.INFO)
            pkg:install()
          end
        end
      end
    end,
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = { "mason-lspconfig.nvim", "hrsh7th/cmp-nvim-lsp" },
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      vim.lsp.config("lua_ls", { capabilities = capabilities })
      vim.lsp.enable("lua_ls")

      vim.lsp.config("lemminx", {
        capabilities = capabilities,
        -- xhtml (view JSF/PrimeFaces) vẫn là XML nên dùng chung lemminx để có completion/hover/definition
        filetypes = { "xml", "xhtml" },
      })
      vim.lsp.enable("lemminx")

      -- rust-analyzer: bật check bằng clippy (nhiều gợi ý hơn cargo check mặc định), giống
      -- IntelliJ-Rust mặc định bật Clippy trong External Linters.
      vim.lsp.config("rust_analyzer", {
        capabilities = capabilities,
        settings = {
          ["rust-analyzer"] = {
            check = { command = "clippy" },
          },
        },
      })
      vim.lsp.enable("rust_analyzer")

      -- Format .xhtml/.xml qua lemminx (chỉ reformat khoảng trắng/thụt lề của thẻ, không đụng
      -- vào nội dung bên trong attribute value nên EL expression #{bean.action} vẫn giữ nguyên)
      -- và .rs qua rust-analyzer (rustfmt) - auto-format khi lưu để khỏi phải nhớ gọi tay.
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = { "*.xhtml", "*.xml", "*.rs" },
        callback = function(args)
          vim.lsp.buf.format({ bufnr = args.buf, async = false, timeout_ms = 3000 })
        end,
      })

      -- Keymap LSP dùng chung cho mọi ngôn ngữ (Java sẽ nhận qua jdtls.lua)
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local buf = args.buf
          local function map(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
          end
          map("n", "gd", vim.lsp.buf.definition, "Go to definition")
          map("n", "gr", vim.lsp.buf.references, "Find references")
          map("n", "gi", vim.lsp.buf.implementation, "Go to implementation")

          -- Giống Ctrl+B của IntelliJ: đứng ở nơi gọi hàm -> nhảy tới code implement
          -- (nếu là method của interface thì nhảy thẳng vào class implement, không dừng
          -- ở khai báo trừu tượng của interface); đứng ngay tại khai báo -> nhảy tới
          -- danh sách nơi hàm được dùng (usages)
          map("n", "<C-b>", function()
            -- File xhtml (JSF/PrimeFaces): nếu cursor đang đứng trong EL expression
            -- (#{bean.action}) thì nhảy sang Java backing bean, lemminx không hiểu EL
            -- nên không tự làm được (xem lua/el_nav.lua).
            if vim.bo[buf].filetype == "xhtml" and require("el_nav").jump_from_cursor() then
              return
            end
            local params = vim.lsp.util.make_position_params(0, "utf-16")
            vim.lsp.buf_request(buf, "textDocument/definition", params, function(_, result)
              if not result or vim.tbl_isempty(result) then
                vim.notify("Không tìm thấy khai báo", vim.log.levels.WARN)
                return
              end
              local loc = result[1] or result
              local range = loc.range or loc.targetSelectionRange
              local uri = loc.uri or loc.targetUri
              local cur_line = vim.api.nvim_win_get_cursor(0)[1] - 1
              local cur_uri = vim.uri_from_bufnr(buf)

              if uri == cur_uri and range and range.start.line == cur_line then
                vim.lsp.buf.references()
                return
              end

              -- Không đứng tại khai báo: thử textDocument/implementation trước.
              -- Với method của interface, server trả về class implement thật;
              -- nếu server không hỗ trợ hoặc không có implementation nào thì
              -- rơi về definition như cũ.
              vim.lsp.buf_request(buf, "textDocument/implementation", params, function(_, impl_result)
                if impl_result and not vim.tbl_isempty(impl_result) then
                  vim.lsp.buf.implementation()
                else
                  vim.lsp.buf.definition()
                end
              end)
            end)
          end, "Go to implementation / usages (Ctrl+B)")
          map("n", "K", vim.lsp.buf.hover, "Hover doc")
          map("n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
          map("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("n", "<leader>lf", function() vim.lsp.buf.format({ async = true }) end, "Format buffer")
          map("n", "<leader>e", vim.diagnostic.open_float, "Show diagnostic")
          map("n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
          map("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
        end,
      })
    end,
  },
}
