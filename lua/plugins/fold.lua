-- Gom/thu code block giống IntelliJ: gutter có icon [+]/[-] để bấm chuột, fold text hiện
-- gọn "{...}" kèm số dòng bị ẩn, và có phím tắt tương đương Ctrl+Plus/Minus của IntelliJ.
return {
  "kevinhwang91/nvim-ufo",
  dependencies = { "kevinhwang91/promise-async" },
  event = "BufReadPost",
  config = function()
    local o = vim.opt
    -- foldenable=true nhưng foldlevelstart cao để KHÔNG tự gom hết khi mở file (giữ hành vi
    -- cũ), đồng thời vẫn hiện icon fold ở gutter (giống thanh gutter [-]/[+] của IntelliJ),
    -- bấm chuột trực tiếp vào đó để gom/mở cũng hoạt động luôn (mousemodel mặc định).
    o.foldenable = true
    o.foldlevel = 99
    o.foldlevelstart = 99
    o.foldcolumn = "1"

    require("ufo").setup({
      -- Ưu tiên fold theo treesitter (đã cấu hình ở treesitter.lua), fallback sang indent
      -- cho các filetype chưa có grammar/không parse được.
      provider_selector = function(_, _, _)
        return { "treesitter", "indent" }
      end,
      -- Fold text kiểu IntelliJ: "{ ... }" kèm số dòng bị gom, thay vì hiện thô "12 lines folded".
      fold_virt_text_handler = function(virtText, lnum, endLnum, width, truncate)
        local newVirtText = {}
        local suffix = ("  ⋯ %d dòng"):format(endLnum - lnum)
        local sufWidth = vim.fn.strdisplaywidth(suffix)
        local targetWidth = width - sufWidth
        local curWidth = 0
        for _, chunk in ipairs(virtText) do
          local chunkText = chunk[1]
          local chunkWidth = vim.fn.strdisplaywidth(chunkText)
          if targetWidth > curWidth + chunkWidth then
            table.insert(newVirtText, chunk)
          else
            chunkText = truncate(chunkText, targetWidth - curWidth)
            table.insert(newVirtText, { chunkText, chunk[2] })
            chunkWidth = vim.fn.strdisplaywidth(chunkText)
            if curWidth + chunkWidth < targetWidth then
              suffix = suffix .. (" "):rep(targetWidth - curWidth - chunkWidth)
            end
            break
          end
          curWidth = curWidth + chunkWidth
        end
        table.insert(newVirtText, { suffix, "Comment" })
        return newVirtText
      end,
    })

    -- Gom TẤT CẢ method/function trong class lại (dựa theo danh sách symbol của LSP - kind
    -- Method/Function/Constructor), còn class/interface/khai báo ngoài thì vẫn giữ mở - khác với
    -- zM/closeAllFolds gom luôn cả class. Giống việc thu gọn danh sách method trong Structure
    -- view (Alt+7) của IntelliJ.
    local SYMBOL_KIND_METHOD = 6
    local SYMBOL_KIND_CONSTRUCTOR = 9
    local SYMBOL_KIND_FUNCTION = 12

    local function fold_all_functions()
      local bufnr = vim.api.nvim_get_current_buf()
      if #vim.lsp.get_clients({ bufnr = bufnr }) == 0 then
        vim.notify("Chưa có LSP client cho buffer này.", vim.log.levels.WARN)
        return
      end
      local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
      vim.lsp.buf_request(bufnr, "textDocument/documentSymbol", params, function(err, result)
        if err or not result or #result == 0 then
          vim.notify("Không lấy được danh sách symbol từ LSP.", vim.log.levels.WARN)
          return
        end
        local folded = 0
        local function visit(sym)
          local kind = sym.kind
          if kind == SYMBOL_KIND_METHOD or kind == SYMBOL_KIND_FUNCTION or kind == SYMBOL_KIND_CONSTRUCTOR then
            -- SymbolInformation (flat, cũ) dùng sym.location.range, DocumentSymbol (lồng nhau,
            -- phổ biến hơn) dùng thẳng sym.range.
            local range = sym.range or (sym.location and sym.location.range)
            if range then
              local ok = pcall(vim.cmd, (range.start.line + 1) .. "foldclose")
              if ok then folded = folded + 1 end
            end
          end
          if sym.children then
            for _, child in ipairs(sym.children) do visit(child) end
          end
        end
        for _, sym in ipairs(result) do visit(sym) end
        if folded == 0 then
          vim.notify("Không tìm thấy method/function nào để gom.", vim.log.levels.INFO)
        end
      end)
    end

    local map = vim.keymap.set
    map("n", "<leader>zf", fold_all_functions, { desc = "Fold: gom tất cả method/function (giữ class mở)" })

    -- Ctrl+Minus / Ctrl+Plus: gom/mở 1 block dưới con trỏ (giống IntelliJ)
    map("n", "<C-->", "za", { desc = "Fold: toggle block dưới con trỏ" })
    map("n", "<C-=>", "za", { desc = "Fold: toggle block dưới con trỏ" })
    -- Ctrl+Shift+Minus / Ctrl+Shift+Plus: gom/mở TẤT CẢ block (giống IntelliJ Collapse/Expand All)
    map("n", "<C-S-->", function() require("ufo").closeAllFolds() end, { desc = "Fold: gom tất cả (Collapse All)" })
    map("n", "<C-S-=>", function() require("ufo").openAllFolds() end, { desc = "Fold: mở tất cả (Expand All)" })
    -- Fallback bằng <leader>, phòng khi terminal không gửi được Ctrl+Shift+Ký hiệu ở trên
    map("n", "<leader>z-", function() require("ufo").closeAllFolds() end, { desc = "Fold: gom tất cả (Collapse All)" })
    map("n", "<leader>z=", function() require("ufo").openAllFolds() end, { desc = "Fold: mở tất cả (Expand All)" })
    map("n", "<leader>za", "za", { desc = "Fold: toggle block dưới con trỏ" })
    -- Xem trước nội dung đang bị gom mà không cần mở fold ra (giống hover preview của IntelliJ)
    map("n", "zK", function()
      local winid = require("ufo").peekFoldedLinesUnderCursor()
      if not winid then vim.lsp.buf.hover() end
    end, { desc = "Fold: xem trước block đang gom" })
  end,
}
