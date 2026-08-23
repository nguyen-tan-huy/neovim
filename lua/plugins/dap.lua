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

    local dap_status = require("dap_status")

    dap.defaults.fallback.terminal_win_cmd = function(config)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].bufhidden = "hide"
      term_bufs[config.name] = buf
      last_session_name = config.name
      dap_status.ports[config.name] = nil

      -- Dò dòng kiểu "Tomcat/Netty/Jetty started on port(s): 8080 ..." (Spring Boot) trong log
      -- để biết port đang chạy, hiện lên statusline (🐛) + tiêu đề console nổi - đỡ phải mở
      -- console lên đọc log tìm tay. Tự gỡ theo dõi (return true) ngay khi bắt được port.
      vim.api.nvim_buf_attach(buf, false, {
        on_lines = function(_, b)
          if not vim.api.nvim_buf_is_valid(b) then return true end
          if dap_status.ports[config.name] then return true end
          for _, line in ipairs(vim.api.nvim_buf_get_lines(b, math.max(0, vim.api.nvim_buf_line_count(b) - 5), -1, false)) do
            local port = line:match("[Ss]tarted on port%(s%):%s*(%d+)")
            if port then
              dap_status.ports[config.name] = port
              vim.schedule(function()
                vim.notify(config.name .. ": đang chạy ở port " .. port, vim.log.levels.INFO)
                vim.cmd("redrawstatus")
              end)
              return true
            end
          end
        end,
      })
      return buf
    end

    local function close_float()
      if float_win and vim.api.nvim_win_is_valid(float_win) then
        vim.api.nvim_win_close(float_win, true)
      end
      float_win = nil
    end

    -- Buffer REPL của nvim-dap (dùng CHUNG cho mọi session, không phải per-session như
    -- term_bufs). Cần fallback về đây vì nhiều debug adapter (vd: Java debug adapter)
    -- KHÔNG dùng runInTerminal - chúng gửi log chương trình qua OutputEvent, và nvim-dap
    -- tự đổ thẳng vào REPL thay vì gọi terminal_win_cmd, nên term_bufs không bao giờ có
    -- gì cho các session đó (đây là lý do <leader>dt báo "chưa có console" suốt lúc chạy).
    local function get_repl_buf()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[b].buftype == "prompt" and vim.api.nvim_buf_get_name(b):match("dap%-repl%-%d+") then
          return b
        end
      end
      -- REPL chưa từng mở lần nào trong session nvim này -> mở rồi ẩn ngay để lấy bufnr.
      local replm = require("dap.repl")
      replm.open()
      local buf = vim.api.nvim_get_current_buf()
      replm.close({ mode = "toggle" })
      return buf
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
      local is_repl_fallback = false
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        buf = get_repl_buf()
        is_repl_fallback = true
      end
      close_float()
      local port = dap_status.ports[name]
      local width = math.floor(vim.o.columns * 0.85)
      local height = math.floor(vim.o.lines * 0.75)
      float_win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        border = "rounded",
        title = is_repl_fallback
            and " REPL (dùng chung mọi session - " .. name .. (session and "" or " đã tắt") .. ") "
          or (" Console: " .. name .. (port and (" :" .. port) or "") .. (session and "" or " (đã tắt)") .. " "),
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
        if session and session.config then
          dap_status.launching[session.config.name] = nil
          vim.notify("Đã tắt session debug: " .. session.config.name, vim.log.levels.INFO)
        end
        vim.cmd("redrawstatus")
      end)
    end
    dap.listeners.after.event_terminated["status_notify"] = on_session_ended
    dap.listeners.after.event_exited["status_notify"] = on_session_ended
    dap.listeners.after.event_initialized["status_notify"] = function(session)
      vim.schedule(function()
        if session and session.config then
          dap_status.launching[session.config.name] = nil
        end
        vim.cmd("redrawstatus")
      end)
    end

    -- Nhớ PID thật của JVM debuggee, phòng khi DAP event "process" (body.systemProcessId) có
    -- gửi - nhưng ĐÃ KIỂM TRA log TRACE (~/.local/state/nvim/dap.log): java-debug adapter của
    -- jdtls KHÔNG BAO GIỜ gửi event này, nên dict này thực tế luôn rỗng với Java. Giữ lại phòng
    -- adapter khác (vd node debug) có gửi thật.
    dap.listeners.after.event_process["status_notify"] = function(session, body)
      if session and session.config and body and body.systemProcessId then
        dap_status.pids[session.config.name] = body.systemProcessId
      end
    end

    --- Tra PID đang LISTEN 1 port TCP bằng lsof (đã cài sẵn, xem `command -v lsof`). Trả về
    --- mảng số PID (thường 1 phần tử, có thể rỗng nếu port đã đóng hoặc process không sở hữu bởi
    --- user hiện tại).
    local function pids_listening_on_port(port)
      if vim.fn.executable("lsof") == 0 then return {} end
      local out = vim.fn.systemlist({ "lsof", "-ti", ":" .. tostring(port) })
      local pids = {}
      for _, line in ipairs(out) do
        local pid = tonumber(vim.trim(line))
        if pid then table.insert(pids, pid) end
      end
      return pids
    end

    --- Poll mỗi 500ms (tối đa 5s) xem process cũ (PID từ event "process" nếu có + PID đang
    --- LISTEN port đã bắt được từ log) đã thoát thật chưa, rồi mới gọi cb(). ĐÃ XÁC NHẬN qua log
    --- TRACE (~/.local/state/nvim/dap.log): java-debug trả lời disconnect(terminateDebuggee=true)
    --- là success=true, bắn event "terminated", nhưng JVM thật KHÔNG thoát (bug/giới hạn của
    --- adapter, không phải do config này) - và adapter cũng không gửi event "process" nên không
    --- có PID trực tiếp. Vì vậy PHẢI tự tra PID qua port bằng lsof, giống hệt cách tự tay tìm &
    --- kill. Hết 5s vẫn còn sống thì SIGKILL thẳng trước khi gọi cb() - bắt buộc phải đợi port
    --- nhả ra thật rồi mới cho restart launch lại, không JVM mới sẽ bind lỗi "Address already
    --- in use" vì JVM cũ vẫn còn giữ port.
    local function wait_release_then(name, pid_from_event, port, cb)
      if not pid_from_event and not port then
        cb() -- không có manh mối gì để tra PID, tin theo DAP protocol là đã tắt
        return
      end
      local uv = vim.uv or vim.loop
      local elapsed = 0
      local interval = 500
      local max_wait = 5000
      local function check()
        local candidates = {}
        if pid_from_event then candidates[pid_from_event] = true end
        if port then
          for _, pid in ipairs(pids_listening_on_port(port)) do candidates[pid] = true end
        end
        local alive = {}
        for pid in pairs(candidates) do
          if uv.kill(pid, 0) then table.insert(alive, pid) end -- signal 0: chỉ kiểm tra, không giết
        end
        if #alive == 0 then
          dap_status.pids[name] = nil
          dap_status.ports[name] = nil
          cb()
          return
        end
        elapsed = elapsed + interval
        if elapsed >= max_wait then
          table.sort(alive)
          for _, pid in ipairs(alive) do uv.kill(pid, 9) end -- SIGKILL
          dap_status.pids[name] = nil
          dap_status.ports[name] = nil
          vim.notify(
            string.format("'%s' không tự tắt sau terminate - đã force-kill PID %s.",
              name, table.concat(alive, ", ")),
            vim.log.levels.WARN
          )
          cb()
          return
        end
        vim.defer_fn(check, interval)
      end
      vim.defer_fn(check, interval)
    end

    --- Gọi dap.terminate() cho 1 session, rồi tự force-kill nếu process cũ không thoát (xem
    --- wait_release_then).
    local function terminate_with_fallback_kill(s)
      local name = s.config.name
      local pid_from_event = dap_status.pids[name]
      local port = dap_status.ports[name]
      dap.set_session(s) -- dap.terminate() chỉ tác động session đang focus, nên focus nó trước
      dap.terminate()
      wait_release_then(name, pid_from_event, port, function() end)
    end

    -- ===== Rust (codelldb, cài qua Mason - xem lsp.lua) =====
    dap.adapters.codelldb = {
      type = "server",
      port = "${port}",
      executable = {
        command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
        args = { "--port", "${port}" },
      },
    }
    dap.configurations.rust = {
      {
        name = "Launch",
        type = "codelldb",
        request = "launch",
        -- Hỏi tay đường dẫn binary vì cargo có thể build ra nhiều target (bin/example/test) -
        -- gõ tab để autocomplete trong target/debug.
        program = function()
          return vim.fn.input("Đường dẫn binary debug: ", vim.fn.getcwd() .. "/target/debug/", "file")
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
      },
    }

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

    -- Restart session hiện tại (đang focus), giữ nguyên config. KHÔNG dùng dap.restart() mặc
    -- định: java-debug không hỗ trợ "restart" request (supportsRestartRequest=false) nên nó tự
    -- fallback terminate + chạy lại NGAY sau khi disconnect "success" - dính đúng bug ở
    -- terminate_with_fallback_kill (JVM cũ chưa thoát thật), nên JVM mới launch lại có thể bind
    -- lỗi "Address already in use" vì JVM cũ vẫn giữ port, hoặc tệ hơn là chạy chồng 2 tiến
    -- trình. Ở đây tự terminate rồi ĐỢI port nhả ra hẳn (force-kill nếu cần) mới launch lại.
    vim.keymap.set("n", "<leader>dR", function()
      local s = dap.session()
      if not s then
        vim.notify("Không có debug session đang chạy.", vim.log.levels.WARN)
        return
      end
      local config = s.config
      local name = config.name
      local pid_from_event = dap_status.pids[name]
      local port = dap_status.ports[name]
      vim.notify("Đang restart '" .. name .. "'...", vim.log.levels.INFO)
      dap.terminate()
      wait_release_then(name, pid_from_event, port, function()
        dap.run(config, { new = true })
      end)
    end, { desc = "Debug: restart session hiện tại" })

    -- Chạy thêm 1 profile debug mới SONG SONG với session đang chạy (không tắt session cũ),
    -- giống chạy nhiều Run/Debug Configuration cùng lúc của IntelliJ. Sửa main class/working
    -- directory/VM args/program args/biến môi trường qua 1 panel trước khi chạy - thay đổi được
    -- áp dụng thẳng vào profile đã chọn (trong dap.configurations.java) và tự lưu lại xuống đĩa
    -- luôn, để tắt/mở lại Neovim vẫn còn, không cần bấm thêm <leader>jps.
    vim.keymap.set("n", "<leader>dp", function()
      local root_dir = require("dap_profiles").resolve_root_dir()
      if not root_dir then return end
      require("dap_profiles").ensure_loaded(root_dir)
      local configs = dap.configurations.java
      if not configs or #configs == 0 then
        vim.notify("Không có debug configuration nào cho project này.", vim.log.levels.WARN)
        return
      end
      vim.ui.select(configs, {
        prompt = "Chạy profile debug mới (song song):",
        format_item = function(c) return c.name end,
      }, function(choice)
        if not choice then return end
        require("dap_profiles").edit_overrides(choice, function(result)
          if result then -- nil = huỷ panel, giữ nguyên profile gốc
            choice.mainClass = result.mainClass
            choice.cwd = result.cwd
            choice.vmArgs = result.vmArgs
            choice.args = result.args
            choice.env = next(result.env) and result.env or nil
            require("dap_profiles").save(root_dir, configs)
          end
          -- Đánh dấu "đang khởi động" ngay để statusline (🐛 ở lualine) hiện lên liền, không đợi
          -- session initialized xong mới biết - JVM start mất vài giây, không có dấu hiệu gì
          -- trong lúc đó thì dễ tưởng bấm không ăn. Timeout 30s để tự gỡ nếu launch treo/lỗi mà
          -- không bắn event_terminated/exited nào (vd sai adapter, JDWP không kết nối được).
          dap_status.launching[choice.name] = true
          vim.cmd("redrawstatus")
          vim.defer_fn(function()
            if dap_status.launching[choice.name] then
              dap_status.launching[choice.name] = nil
              vim.notify("Vẫn chưa thấy '" .. choice.name .. "' khởi động xong sau 30s - có thể launch đã treo/lỗi.",
                vim.log.levels.WARN)
              vim.cmd("redrawstatus")
            end
          end, 30000)
          dap.run(choice, { new = true }) -- new = true: luôn tạo session mới, không đụng session đang chạy
        end)
      end)
    end, { desc = "Debug: chạy thêm profile mới (song song)" })

    -- Quản lý danh sách debug profile (lưu ở <project_root>/.nvim/dap-profiles.json) - toàn cục,
    -- KHÔNG cần đang đứng trong buffer .java (chỉ <leader>jpc ở ftplugin/java.lua mới cần, vì nó
    -- dò package/class name từ chính file đang mở). Xem lua/dap_profiles.lua.
    local function jp_mainclass_hint()
      if vim.bo.filetype == "java" then
        return require("jdtls.util").resolve_classname()
      end
      return nil
    end

    -- Reload danh sách profile debug: nạp lại file đã lưu + cho jdtls dò thêm main class mới,
    -- rồi tự lưu lại xuống đĩa (giống F5 refresh danh sách Run/Debug Configuration của IntelliJ).
    vim.keymap.set("n", "<leader>jpl", function()
      local root_dir = require("dap_profiles").resolve_root_dir()
      if not root_dir then return end
      local dap_profiles = require("dap_profiles")
      dap.configurations.java = dap_profiles.load(root_dir)
      require("jdtls.dap").setup_dap_main_class_configs({
        on_ready = function()
          local configs = dap.configurations.java
          dap_profiles.save(root_dir, configs)
          vim.notify(string.format("Đã reload %d profile debug.", #configs), vim.log.levels.INFO)
        end,
      })
    end, { desc = "Debug profile: reload danh sách" })

    -- Lưu danh sách profile debug hiện tại (đã sửa tay bằng <leader>dp thêm session, hoặc để
    -- backup thủ công) xuống <project_root>/.nvim/dap-profiles.json.
    vim.keymap.set("n", "<leader>jps", function()
      local root_dir = require("dap_profiles").resolve_root_dir()
      if not root_dir then return end
      require("dap_profiles").save(root_dir, dap.configurations.java or {})
    end, { desc = "Debug profile: lưu danh sách hiện tại" })

    -- Thêm 1 profile debug mới (nhập tay tên/args/vmArgs), main class gợi ý sẵn theo
    -- package.class nếu đang đứng trong 1 file Java (vẫn sửa được nếu muốn trỏ tới class khác).
    vim.keymap.set("n", "<leader>jpa", function()
      local root_dir = require("dap_profiles").resolve_root_dir()
      if not root_dir then return end
      require("dap_profiles").add("java", root_dir, {
        mainClass = jp_mainclass_hint(),
        projectName = vim.fn.fnamemodify(root_dir, ":p:h:t"),
      })
    end, { desc = "Debug profile: thêm mới" })

    -- Sửa 1 profile debug có sẵn (chọn từ danh sách), tự lưu lại xuống đĩa. Field nào profile
    -- đang thiếu (vd chưa có mainClass/projectName) thì gợi ý sẵn theo file Java đang mở (nếu có),
    -- giống <leader>jpa, đỡ phải gõ tay lại từ đầu.
    vim.keymap.set("n", "<leader>jpe", function()
      local root_dir = require("dap_profiles").resolve_root_dir()
      if not root_dir then return end
      require("dap_profiles").edit("java", root_dir, {
        mainClass = jp_mainclass_hint(),
        projectName = vim.fn.fnamemodify(root_dir, ":p:h:t"),
      })
    end, { desc = "Debug profile: sửa" })

    -- Xoá 1 profile debug (chọn từ danh sách), tự lưu lại xuống đĩa.
    vim.keymap.set("n", "<leader>jpd", function()
      local root_dir = require("dap_profiles").resolve_root_dir()
      if not root_dir then return end
      require("dap_profiles").delete("java", root_dir)
    end, { desc = "Debug profile: xoá" })

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
        terminate_with_fallback_kill(choice)
      end)
    end, { desc = "Debug: tắt 1 session theo profile" })

    -- Tắt toàn bộ session debug đang chạy song song.
    vim.keymap.set("n", "<leader>dX", function()
      for _, s in pairs(dap.sessions()) do
        terminate_with_fallback_kill(s)
      end
    end, { desc = "Debug: tắt tất cả session debug" })

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
