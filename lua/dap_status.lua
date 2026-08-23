-- State chia sẻ giữa dap.lua (bắt port từ console output) và ui.lua (hiện lên lualine),
-- tách riêng file để 2 plugin config không phải phụ thuộc thứ tự load lẫn nhau.
local M = {}

--- config.name (tên profile debug) -> port (string) đã bắt được từ log của chương trình.
M.ports = {}

--- config.name -> true, trong khoảng từ lúc bấm <leader>dp (gọi dap.run) tới lúc session
--- thực sự sẵn sàng (event_initialized) hoặc launch thất bại (event_terminated/exited/timeout).
--- Dùng để hiện "⏳ đang khởi động" lên statusline - không thì khoảng này JVM đang start
--- (vài giây) mà không có gì báo, dễ tưởng bấm không ăn.
M.launching = {}

--- config.name -> systemProcessId (số, lấy từ DAP event "process") của tiến trình JVM debuggee
--- thật sự. Dùng để force-kill (SIGKILL) khi terminate/disconnect gửi xong mà process vẫn còn
--- sống (port vẫn nghe) - xem <leader>dx/<leader>dX ở dap.lua.
M.pids = {}

return M
