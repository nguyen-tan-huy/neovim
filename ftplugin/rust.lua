-- Lệnh cargo giống nhóm Maven cho Java (chạy trong terminal panel) - chỉ gắn khi đang đứng
-- trong buffer .rs (ftplugin tự buffer-local), dùng namespace <leader>c (cargo) khác với
-- <leader>m (maven) đã dùng cho Java.
local Terminal = require("toggleterm.terminal").Terminal

local function nearest_cargo_dir()
  local start = vim.fn.expand("%:p:h")
  local found = vim.fs.find("Cargo.toml", { path = start, upward = true })[1]
  return found and vim.fn.fnamemodify(found, ":h") or vim.fn.getcwd()
end

local function run_cargo(cmd)
  Terminal:new({
    cmd = "cargo " .. cmd,
    direction = "horizontal",
    dir = nearest_cargo_dir(),
    close_on_exit = false, -- chạy xong giữ nguyên panel để xem log/kết quả build
  }):toggle()
end

local map = vim.keymap.set
map("n", "<leader>cb", function() run_cargo("build") end, { buffer = true, desc = "Cargo: build" })
map("n", "<leader>cr", function() run_cargo("run") end, { buffer = true, desc = "Cargo: run" })
map("n", "<leader>ct", function() run_cargo("test") end, { buffer = true, desc = "Cargo: test" })
map("n", "<leader>cC", function() run_cargo("clippy") end, { buffer = true, desc = "Cargo: clippy" })
