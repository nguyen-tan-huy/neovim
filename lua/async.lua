-- Shim gộp 2 plugin cùng tranh tên module toàn cục "async":
--  - refactoring.nvim cần require("async") trả về bảng kiểu plenary.async (có .void/.wrap/.run)
--  - nvim-ufo (qua promise-async) cần require("async") là 1 HÀM gọi được: async(function() ... end)
-- Không thể require("promise-async") theo tên "async" bình thường vì sẽ đệ quy lại chính file
-- này (nó cũng chiếm tên module "async") - phải nạp thẳng file thật bằng đường dẫn qua dofile(),
-- rồi gộp API của 2 bên vào 1 bảng vừa gọi được (__call, cho ufo) vừa có field (__index, cho
-- refactoring.nvim). Không trùng field: promise-async chỉ có .sync/.wait/._id, plenary.async chỉ
-- có .wrap/.run/.void/.util/... nên gộp an toàn.
local plenary_async = require("plenary.async")

local promise_async_path = vim.fn.stdpath("data") .. "/lazy/promise-async/lua/async.lua"
local ok, promise_async = pcall(dofile, promise_async_path)

if not ok or type(promise_async) ~= "table" then
  return plenary_async
end

return setmetatable({}, {
  __call = function(_, ...) return promise_async(...) end,
  __index = function(_, k)
    local v = promise_async[k]
    if v ~= nil then return v end
    return plenary_async[k]
  end,
})
