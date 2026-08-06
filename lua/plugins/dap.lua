return {
  "mfussenegger/nvim-dap",
  dependencies = {
    "rcarriga/nvim-dap-ui",
    "nvim-neotest/nvim-nio",
    "theHamsta/nvim-dap-virtual-text",
  },
  config = function()
    local dap, dapui = require("dap"), require("dapui")
    dap.set_log_level("TRACE") -- TẠM để chẩn đoán lỗi launch profile ở product-web

    -- Hiện value biến ngay bên cạnh code khi debug (giống inline debugger value của IntelliJ)
    require("nvim-dap-virtual-text").setup({
      commented = true, -- hiện dạng "-- x = 5" cho ngôn ngữ có comment style // (Java vẫn nhận đúng)
      virt_text_pos = "eol",
    })

    dapui.setup({
      mappings = {
        expand = { "<CR>", "<2-LeftMouse>", "o" }, -- Enter/double-click/o để mở rộng biến
        open = "o",
        remove = "d",
        edit = "e",
        repl = "r",
        toggle = "t",
      },
      render = {
        max_type_length = nil, -- không cắt tên kiểu dữ liệu
        max_value_lines = 100, -- mặc định chỉ 3 dòng, dễ nhìn nhầm là "không expand được"
      },
    })

    -- dapui.setup() ở trên tự set dap.defaults.fallback.terminal_win_cmd = hàm dùng CHUNG
    -- 1 buffer "DAP Console" làm terminal chạy chương trình debug (để gộp console + REPL
    -- vào 1 tab). Vấn đề: đây là buffer DUY NHẤT dùng chung cho MỌI session, nên chạy 2
    -- session song song (<leader>dp) sẽ đụng độ - session sau cố mở terminal vào đúng
    -- buffer session trước đang chạy dở (đang "modified" vì có output chảy vào) -> lỗi
    -- "jobstart(...,{term=true}) requires unmodified buffer".
    --
    -- Thay vào đó: mỗi session có 1 buffer terminal RIÊNG, KHÔNG tự mở cửa sổ nào khi
    -- launch (tránh chiếm chỗ màn hình / xé layout code đang xem). Buffer được hiện ra
    -- qua cửa sổ NỔI (float) bấm-tắt bằng <leader>dt, và cửa sổ nổi đó luôn "đi theo" đúng
    -- session đang được focus (đổi focus bằng <leader>ds thì nổi cũng tự đổi log theo).
    local term_bufs = {} -- config.name -> bufnr, mỗi profile debug 1 buffer console riêng
    local float_win = nil -- winid đang mở (nil nếu đang ẩn)
    local last_session_name = nil -- tên session GẦN NHẤT (kể cả đã tắt), để <leader>dt vẫn
    -- xem được log lúc chương trình chạy xong/crash quá nhanh, session đã biến mất khỏi
    -- dap.sessions() trước khi kịp bấm xem console.

    dap.defaults.fallback.terminal_win_cmd = function(config)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].bufhidden = "hide"
      term_bufs[config.name] = buf
      last_session_name = config.name
      return buf
    end

    local function close_float()
      if float_win and vim.api.nvim_win_is_valid(float_win) then
        vim.api.nvim_win_close(float_win, true)
      end
      float_win = nil
    end

    --- Mở/refresh cửa sổ nổi hiện log của session đang focus; nếu không còn session nào đang
    --- chạy (đã tắt/crash) thì fallback về log của session GẦN NHẤT, để không bị mất log.
    local function show_float_for_focused_session()
      local session = dap.session()
      local name = session and session.config.name or last_session_name
      if not name then
        vim.notify("Chưa chạy debug session nào.", vim.log.levels.WARN)
        return
      end
      local buf = term_bufs[name]
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        vim.notify("Session '" .. name .. "' chưa có console (chưa launch xong?).", vim.log.levels.WARN)
        return
      end
      close_float()
      local width = math.floor(vim.o.columns * 0.85)
      local height = math.floor(vim.o.lines * 0.75)
      float_win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        border = "rounded",
        title = " Console: " .. name .. (session and "" or " (đã tắt)") .. " ",
        title_pos = "center",
      })
      vim.wo[float_win].number = false
      vim.wo[float_win].relativenumber = false
      vim.keymap.set("t", "q", [[<C-\><C-n>:close<CR>]], { buffer = buf, nowait = true })
      vim.keymap.set("n", "q", close_float, { buffer = buf, nowait = true })
    end

    -- Bật/tắt console nổi của session đang focus.
    vim.keymap.set("n", "<leader>dt", function()
      if float_win and vim.api.nvim_win_is_valid(float_win) then
        close_float()
      else
        show_float_for_focused_session()
      end
    end, { desc = "Debug: bật/tắt console nổi (theo session đang focus)" })

    -- Tự mở/đóng UI debug (variables, watch, call stack) giống IntelliJ.
    -- Chỉ đóng khi KHÔNG còn session nào khác đang chạy (hỗ trợ nhiều profile song song):
    -- tắt 1 profile không được đóng UI nếu các profile khác vẫn đang debug.
    local function close_dapui_if_no_sessions()
      vim.schedule(function()
        if vim.tbl_isempty(dap.sessions()) then dapui.close() end
      end)
    end
    dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
    dap.listeners.before.event_terminated["dapui_config"] = close_dapui_if_no_sessions
    dap.listeners.before.event_exited["dapui_config"] = close_dapui_if_no_sessions

    -- Báo rõ ràng lúc session THỰC SỰ tắt xong (không phải lúc bấm <leader>dx/dX - đó chỉ là
    -- gửi lệnh terminate, còn tắt xong hẳn hay chưa phải đợi debug adapter phản hồi) + refresh
    -- ngay statusline (mục 🐛 ở lualine) thay vì đợi lualine tự làm mới theo chu kỳ.
    local function on_session_ended(session)
      vim.schedule(function()
        vim.cmd("redrawstatus")
        if session and session.config then
          vim.notify("Đã tắt session debug: " .. session.config.name, vim.log.levels.INFO)
        end
      end)
    end
    dap.listeners.after.event_terminated["status_notify"] = on_session_ended
    dap.listeners.after.event_exited["status_notify"] = on_session_ended
    dap.listeners.after.event_initialized["status_notify"] = function()
      vim.schedule(function() vim.cmd("redrawstatus") end)
    end

    -- Scheme phím debug giống IntelliJ
    vim.keymap.set("n", "<F8>", function() dap.step_over() end, { desc = "Step over" })
    vim.keymap.set("n", "<F7>", function() dap.step_into() end, { desc = "Step into" })
    vim.keymap.set("n", "<S-F8>", function() dap.step_out() end, { desc = "Step out" })
    vim.keymap.set("n", "<F10>", function() dap.toggle_breakpoint() end, { desc = "Toggle breakpoint" })
    vim.keymap.set("n", "<leader>du", function() dapui.toggle() end, { desc = "Toggle debug UI" })

    -- Run to cursor (giống Alt+F9 của IntelliJ)
    vim.keymap.set("n", "<leader>dc", function() dap.run_to_cursor() end, { desc = "Debug: run to cursor" })

    -- Hot reload code thủ công (Compile and Reload): jdtls tự biên dịch nền khi lưu file,
    -- bấm Ctrl+\ để nạp bytecode mới vào JVM đang debug (không tự động, xem ftplugin/java.lua)
    vim.keymap.set("n", "<C-\\>", function()
      local session = dap.session()
      if not session then
        vim.notify("Không có debug session đang chạy.", vim.log.levels.WARN)
        return
      end
      vim.notify("Đang áp dụng thay đổi code (redefineClasses)...", vim.log.levels.INFO)
      session:request("redefineClasses", nil, function(err)
        if err then
          vim.notify("Hot reload thất bại: " .. vim.inspect(err), vim.log.levels.ERROR)
        else
          vim.notify("Hot reload thành công - đã áp dụng thay đổi code.", vim.log.levels.INFO)
        end
      end)
    end, { desc = "Debug: hot reload code (redefineClasses)" })

    -- Restart session hiện tại (đang focus), giữ nguyên config: nếu adapter hỗ trợ "restart"
    -- request thì restart tại chỗ, không thì tự fallback terminate + chạy lại từ đầu.
    vim.keymap.set("n", "<leader>dR", function() dap.restart() end, { desc = "Debug: restart session hiện tại" })

    -- Chạy thêm 1 profile debug mới SONG SONG với session đang chạy (không tắt session cũ),
    -- giống chạy nhiều Run/Debug Configuration cùng lúc của IntelliJ. Trước khi chạy, cho sửa
    -- lại biến môi trường (chỉ áp dụng cho LẦN CHẠY NÀY, không đụng vào profile đã lưu trên
    -- đĩa - muốn lưu luôn thì sửa profile bằng <leader>jpe hoặc lưu tay bằng <leader>jps).
    vim.keymap.set("n", "<leader>dp", function()
      local configs = dap.configurations[vim.bo.filetype]
      if not configs or #configs == 0 then
        vim.notify("Không có debug configuration nào cho filetype '" .. vim.bo.filetype .. "'.", vim.log.levels.WARN)
        return
      end
      vim.ui.select(configs, {
        prompt = "Chạy profile debug mới (song song):",
        format_item = function(c) return c.name end,
      }, function(choice)
        if not choice then return end
        require("dap_profiles").edit_env(choice.env, function(env)
          local run_config = choice
          if env ~= nil then -- nil = huỷ popup env, giữ nguyên env cũ của profile
            run_config = vim.tbl_extend("force", {}, choice, { env = next(env) and env or nil })
          end
          dap.run(run_config, { new = true }) -- new = true: luôn tạo session mới, không đụng session đang chạy
        end)
      end)
    end, { desc = "Debug: chạy thêm profile mới (song song)" })

    -- Chuyển session đang "focus" (session bị step/continue/breakpoint tác động) sang 1 session
    -- khác trong số các session/profile đang chạy song song.
    vim.keymap.set("n", "<leader>ds", function()
      local items = vim.tbl_values(dap.sessions())
      if #items == 0 then
        vim.notify("Không có debug session nào đang chạy.", vim.log.levels.WARN)
        return
      end
      vim.ui.select(items, {
        prompt = "Chuyển sang session:",
        format_item = function(s)
          local focused = dap.session()
          local mark = (focused and focused.id == s.id) and " (đang focus)" or ""
          return s.config.name .. " #" .. s.id .. mark
        end,
      }, function(choice)
        if not choice then return end
        dap.set_session(choice)
        vim.notify("Đang focus session: " .. choice.config.name, vim.log.levels.INFO)
        -- Console nổi đang mở thì đổi theo session mới luôn, khỏi phải bấm <leader>dt lại.
        if float_win and vim.api.nvim_win_is_valid(float_win) then
          show_float_for_focused_session()
        end
      end)
    end, { desc = "Debug: chuyển session focus (giữa các profile đang chạy song song)" })

    -- Tắt 1 session cụ thể theo profile, không ảnh hưởng các session/profile khác đang chạy song song.
    vim.keymap.set("n", "<leader>dx", function()
      local items = vim.tbl_values(dap.sessions())
      if #items == 0 then
        vim.notify("Không có debug session nào đang chạy.", vim.log.levels.WARN)
        return
      end
      vim.ui.select(items, {
        prompt = "Tắt session:",
        format_item = function(s) return s.config.name .. " #" .. s.id end,
      }, function(choice)
        if not choice then return end
        dap.set_session(choice) -- dap.terminate() chỉ tác động session đang focus, nên focus nó trước
        dap.terminate()
      end)
    end, { desc = "Debug: tắt 1 session theo profile" })

    -- Tắt toàn bộ session debug đang chạy song song.
    vim.keymap.set("n", "<leader>dX", function() dap.terminate({ all = true }) end,
      { desc = "Debug: tắt tất cả session debug" })

    -- Evaluate nhanh (popup nổi): dòng lệnh dưới cursor (normal) hoặc vùng chọn (visual)
    vim.keymap.set({ "n", "x" }, "<leader>de", function() dapui.eval() end, { desc = "Debug: evaluate expression dưới cursor" })
    -- Evaluate Expression dạng panel (giống Alt+F8 của IntelliJ): mở REPL trong split, gõ nhiều
    -- biểu thức liên tiếp, có gợi ý code (biến/thuộc tính) nhờ cmp-dap, giữ lại lịch sử.
    vim.keymap.set("n", "<leader>dE", function() dap.repl.open() end, { desc = "Debug: Evaluate Expression (panel)" })

    -- Chặn thoát Neovim (:q, :qa, :wqa...) trong lúc còn debug session đang chạy, tránh lỡ tay
    -- :qa làm chết ngang tiến trình đang debug dở (mất breakpoint/state, JVM debuggee bị kill
    -- đột ngột). Muốn thoát thật thì tắt hết session trước (<leader>dX) hoặc dùng ":qa!"/":q!".
    vim.api.nvim_create_autocmd("QuitPre", {
      callback = function()
        local sessions = dap.sessions()
        if vim.tbl_isempty(sessions) then return end
        local names = {}
        for _, s in pairs(sessions) do table.insert(names, s.config.name) end
        vim.notify(
          "Đang debug: " .. table.concat(names, ", ")
          .. ".\nTắt hết session (<leader>dX) rồi thoát, hoặc dùng :qa! để thoát bất chấp.",
          vim.log.levels.WARN)
        error("Đang có debug session chạy, chặn thoát Neovim (xem :messages).")
      end,
    })

    -- Breakpoint sign
    vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticSignError", linehl = "", numhl = "" })
    vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticSignWarn", linehl = "", numhl = "" })
    vim.fn.sign_define("DapStopped", { text = "→", texthl = "DiagnosticSignInfo", linehl = "Visual", numhl = "" })
  end,
}
