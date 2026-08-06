-- Tiện ích quản lý nhiều JDK cài trên máy (Arch: /usr/lib/jvm, SDKMAN: ~/.sdkman/candidates/java)
local M = {}

--- Danh sách đường dẫn các JDK tìm thấy trên máy
function M.list()
  local dirs = {}
  vim.list_extend(dirs, vim.fn.glob("/usr/lib/jvm/*", false, true))
  vim.list_extend(dirs, vim.fn.glob(vim.fn.expand("~/.sdkman/candidates/java/*"), false, true))

  local jdks, seen = {}, {}
  for _, dir in ipairs(dirs) do
    -- bỏ symlink kiểu /usr/lib/jvm/default trỏ vào một java-*-openjdk khác, tránh trùng lặp
    local real = vim.fn.resolve(dir)
    if not seen[real] and vim.fn.executable(real .. "/bin/java") == 1 then
      seen[real] = true
      table.insert(jdks, real)
    end
  end
  table.sort(jdks)
  return jdks
end

--- Lấy major version (8, 11, 17, 21, ...) từ tên thư mục, fallback đọc file "release"
function M.major_version(path)
  local name = vim.fn.fnamemodify(path, ":t")
  local v = name:match("java%-(%d+)") or name:match("^(%d+)")
  if v then return tonumber(v) end

  local release = path .. "/release"
  if vim.fn.filereadable(release) == 1 then
    for _, line in ipairs(vim.fn.readfile(release)) do
      local ver = line:match('JAVA_VERSION="(%d+)')
      if ver then return tonumber(ver) end
    end
  end
  return nil
end

--- Tên Execution Environment theo chuẩn Eclipse (jdtls dùng tên này trong java.configuration.runtimes)
function M.ee_name(major)
  if not major then return "JavaSE" end
  if major <= 8 then return "JavaSE-1.8" end
  return "JavaSE-" .. major
end

--- Danh sách "java.configuration.runtimes" cho jdtls; JDK trùng JAVA_HOME hiện tại sẽ là default
function M.runtimes_for_jdtls()
  local runtimes = {}
  for _, path in ipairs(M.list()) do
    table.insert(runtimes, {
      name = M.ee_name(M.major_version(path)),
      path = path,
      default = (path == vim.env.JAVA_HOME) or nil,
    })
  end
  return runtimes
end

--- Đổi JAVA_HOME/PATH cho các terminal/process mới spawn từ Neovim (mvn, gradle, java ...)
--- Không ảnh hưởng terminal đã mở từ trước, chỉ áp dụng cho lệnh chạy sau khi gọi hàm này.
function M.set_java_home(path)
  local old_bin = vim.env.JAVA_HOME and (vim.env.JAVA_HOME .. "/bin") or nil
  local parts = {}
  for p in vim.env.PATH:gmatch("[^:]+") do
    if p ~= old_bin then table.insert(parts, p) end
  end
  vim.env.JAVA_HOME = path
  vim.env.PATH = path .. "/bin:" .. table.concat(parts, ":")
end

return M
