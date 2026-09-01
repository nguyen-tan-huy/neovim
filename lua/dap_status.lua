-- State chia sẻ giữa dap.lua (bắt port từ console output) và ui.lua (hiện lên lualine),
-- tách riêng file để 2 plugin config không phải phụ thuộc thứ tự load lẫn nhau.
local M = {}

--- config.name (tên profile debug) -> port (string) đã bắt được từ log của chương trình.
M.ports = {}

--- config.name -> systemProcessId (số, lấy từ DAP event "process") của tiến trình JVM debuggee
--- thật sự. Dùng để force-kill (SIGKILL) khi terminate/disconnect gửi xong mà process vẫn còn
--- sống (port vẫn nghe) - xem <leader>dx/<leader>dX ở dap.lua.
M.pids = {}

--- config.name -> bufnr của console TERMINAL riêng cho session đó (dap.lua's
--- terminal_win_cmd tự tạo 1 buffer/session, xem comment ở đó). Chia sẻ ra đây để
--- java-debug-model/ui/session_manager.lua đọc được log console của từng session
--- mà không cần phụ thuộc trực tiếp vào biến closure riêng của dap.lua.
M.term_bufs = {}

return M
