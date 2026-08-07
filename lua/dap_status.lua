-- State chia sẻ giữa dap.lua (bắt port từ console output) và ui.lua (hiện lên lualine),
-- tách riêng file để 2 plugin config không phải phụ thuộc thứ tự load lẫn nhau.
local M = {}

--- config.name (tên profile debug) -> port (string) đã bắt được từ log của chương trình.
M.ports = {}

return M
