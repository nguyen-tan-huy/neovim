-- Quản lý danh sách debug profile (dap.configurations[filetype]) lưu lại trên đĩa, khác với
-- jdtls chỉ tự dò main class trong bộ nhớ và mất khi tắt Neovim. File lưu tại
-- <project_root>/.nvim/dap-profiles.json để mỗi project có 1 danh sách riêng, add/sửa/xoá được
-- và không phụ thuộc phải mở lại đúng buffer để jdtls dò lại.
local M = {}

-- Gợi ý mặc định khi profile CHƯA có biến môi trường nào, để người dùng đỡ phải nhớ tên biến
-- hay dùng cho app Java/Spring Boot. Chỉ là comment, không tự bật.
local ENV_SUGGESTIONS = {
  "# SPRING_PROFILES_ACTIVE=dev",
  "# JAVA_TOOL_OPTIONS=-Xmx512m",
  "# LOG_LEVEL=debug",
}

-- Field nào của profile được sửa qua khối "key=value" đầu panel (khác biến môi trường ở dưới).
local KNOWN_FIELDS = { "mainClass", "cwd", "vmArgs", "args" }

local function profiles_path(root_dir)
  return root_dir .. "/.nvim/dap-profiles.json"
end

-- Marker dùng để dò project root khi chưa có buffer Java nào được jdtls attach trong session,
-- giống danh sách marker ở ftplugin/java.lua.
local ROOT_MARKERS = { "mvnw", "gradlew", "settings.gradle", "settings.gradle.kts", "pom.xml", "build.gradle", ".git" }

--- Xác định root_dir của project hiện tại KHÔNG phụ thuộc buffer đang focus có phải file Java
--- hay không - để các thao tác quản lý profile (jpl/jps/jpa/jpe/jpd, <leader>dp) dùng được ở
--- bất kỳ buffer nào trong project, không chỉ khi đứng đúng trong 1 file .java.
---@return string?
function M.resolve_root_dir()
  if vim.g.dap_profiles_last_root_dir then
    return vim.g.dap_profiles_last_root_dir
  end
  -- Dò ngược từ đường dẫn buffer ĐANG MỞ trước (không phải getcwd()) - bắt buộc với reactor
  -- Maven nhiều module (mỗi module có mvnw/pom.xml riêng, module cha chỉ có .git): dò từ getcwd()
  -- khi mở Neovim ngay tại thư mục reactor cha sẽ ăn nhầm marker ".git" của module cha thay vì
  -- mvnw của đúng module đang làm việc, khiến profile lưu sai chỗ so với nơi jdtls tự lưu sau này.
  local buf_name = vim.api.nvim_buf_get_name(0)
  local search_path = buf_name ~= "" and vim.fs.dirname(buf_name) or vim.fn.getcwd()
  local found = vim.fs.find(ROOT_MARKERS, { upward = true, path = search_path })[1]
  if found then
    return vim.fs.dirname(found)
  end
  vim.notify(
    "Không xác định được project root cho debug profile. Mở tạm 1 file .java hoặc cd vào đúng thư mục project.",
    vim.log.levels.WARN)
  return nil
end

--- Nạp profile từ đĩa vào dap.configurations.java nếu chưa có sẵn trong bộ nhớ (vd session
--- chưa từng mở qua file .java nào).
---@param root_dir string
function M.ensure_loaded(root_dir)
  local dap = require("dap")
  if not dap.configurations.java or #dap.configurations.java == 0 then
    dap.configurations.java = M.load(root_dir)
  end
end

--- Đọc danh sách profile đã lưu của project.
---@param root_dir string
---@return table[]
function M.load(root_dir)
  local path = profiles_path(root_dir)
  if vim.fn.filereadable(path) == 0 then return {} end
  local ok_read, lines = pcall(vim.fn.readfile, path)
  if not ok_read then return {} end
  local ok_decode, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok_decode or type(decoded) ~= "table" then
    vim.notify("File profile debug lỗi định dạng JSON: " .. path, vim.log.levels.ERROR)
    return {}
  end
  return decoded
end

--- Ghi danh sách profile hiện tại xuống đĩa.
---@param root_dir string
---@param profiles table[]
function M.save(root_dir, profiles)
  local dir = root_dir .. "/.nvim"
  vim.fn.mkdir(dir, "p")
  local ok_encode, encoded = pcall(vim.json.encode, profiles)
  if not ok_encode then
    vim.notify("Không thể lưu profile debug: " .. tostring(encoded), vim.log.levels.ERROR)
    return
  end
  vim.fn.writefile({ encoded }, profiles_path(root_dir))
  vim.notify(string.format("Đã lưu %d profile debug vào %s", #profiles, profiles_path(root_dir)),
    vim.log.levels.INFO)
end

--- Mở 1 cửa sổ nổi DUY NHẤT để sửa toàn bộ thông tin của profile: tên (tuỳ chọn), main class,
--- working directory, VM args, program args và biến môi trường - thay vì hỏi từng field riêng
--- lẻ qua nhiều popup vim.ui.input nối tiếp nhau.
---@param profile table giá trị hiện có: { name?, mainClass?, cwd?, vmArgs?, args?, env? }
---@param opts table? { include_name?: boolean = hiện thêm dòng "name=", default_cwd?: string = gợi ý cwd khi profile chưa có }
---@param on_done fun(result: table?) result = nil nếu huỷ (không đổi gì); ngược lại là
---  { name?, mainClass?, cwd?, vmArgs?, args?, env: table<string,string> } - field nào để trống
---  trên panel thì trả về nil (env luôn là 1 table, có thể rỗng nếu người dùng xoá hết)
local function edit_profile(profile, opts, on_done)
  opts = opts or {}
  profile = profile or {}

  local lines = {
    "# Sửa thông tin profile (:w lưu, q hoặc <Esc> huỷ). Để trống field nghĩa là bỏ field đó.",
  }
  if opts.include_name then
    table.insert(lines, "name=" .. (profile.name or ""))
  end
  table.insert(lines, "mainClass=" .. (profile.mainClass or ""))
  table.insert(lines, "cwd=" .. (profile.cwd or opts.default_cwd or ""))
  table.insert(lines, "vmArgs=" .. (profile.vmArgs or ""))
  table.insert(lines, "args=" .. (profile.args or ""))
  table.insert(lines, "#")
  table.insert(lines, "# Biến môi trường cho profile này, mỗi dòng 1 biến dạng KEY=VALUE.")
  table.insert(lines, "# Dòng bắt đầu bằng # bị bỏ qua.")
  if profile.env and next(profile.env) then
    local keys = vim.tbl_keys(profile.env)
    table.sort(keys)
    for _, k in ipairs(keys) do
      table.insert(lines, k .. "=" .. tostring(profile.env[k]))
    end
  else
    vim.list_extend(lines, ENV_SUGGESTIONS)
  end

  local known = {}
  for _, f in ipairs(KNOWN_FIELDS) do known[f] = true end
  if opts.include_name then known.name = true end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "sh"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_name(buf, "dap-profile://" .. buf)

  local width = math.min(90, math.floor(vim.o.columns * 0.6))
  local height = math.max(#lines + 1, 12)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " Debug profile (:w lưu, q huỷ) ",
    title_pos = "center",
  })

  local done = false
  local function finish(save)
    if done then return end
    done = true
    local result = nil
    if save then
      result = { env = {} }
      for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not vim.startswith(trimmed, "#") then
          local key, value = trimmed:match("^([%w_][%w_%.]*)=(.*)$")
          if key then
            if known[key] then
              result[key] = value ~= "" and value or nil
            else
              result.env[key] = value
            end
          end
        end
      end
    end
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    on_done(result)
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = buf, callback = function() finish(true) end })
  vim.keymap.set("n", "q", function() finish(false) end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function() finish(false) end, { buffer = buf, nowait = true })
end

--- Thêm 1 profile mới qua panel sửa toàn bộ thông tin 1 lần, rồi lưu lại luôn xuống đĩa.
---@param filetype string
---@param root_dir string
---@param defaults table? giá trị mặc định gợi ý sẵn, vd { name = "...", mainClass = "...", projectName = "..." }
function M.add(filetype, root_dir, defaults)
  defaults = defaults or {}
  local dap = require("dap")
  edit_profile({
    name = defaults.name,
    mainClass = defaults.mainClass,
    cwd = defaults.cwd or root_dir,
  }, { include_name = true, default_cwd = root_dir }, function(result)
    if not result then return end
    if not result.name then
      vim.notify("Tên profile không được để trống.", vim.log.levels.WARN)
      return
    end
    local profile = {
      type = "java",
      request = "launch",
      name = result.name,
      mainClass = result.mainClass,
      projectName = defaults.projectName,
      cwd = result.cwd,
      vmArgs = result.vmArgs,
      args = result.args,
    }
    if next(result.env) then profile.env = result.env end

    dap.configurations[filetype] = dap.configurations[filetype] or {}
    table.insert(dap.configurations[filetype], profile)
    M.save(root_dir, dap.configurations[filetype])
  end)
end

--- Sửa 1 profile có sẵn (chọn từ danh sách) qua panel sửa toàn bộ thông tin 1 lần, rồi lưu lại xuống đĩa.
---@param filetype string
---@param root_dir string
---@param defaults table? giá trị gợi ý khi field của profile đang chọn CHƯA có sẵn (vd main
--- class/project name dò được từ file đang mở) - giống defaults của M.add
function M.edit(filetype, root_dir, defaults)
  defaults = defaults or {}
  local dap = require("dap")
  local configs = dap.configurations[filetype] or {}
  if #configs == 0 then
    vim.notify("Không có profile nào để sửa.", vim.log.levels.WARN)
    return
  end
  vim.ui.select(configs, {
    prompt = "Sửa profile:",
    format_item = function(c) return c.name end,
  }, function(choice)
    if not choice then return end
    edit_profile({
      mainClass = choice.mainClass or defaults.mainClass,
      cwd = choice.cwd or defaults.cwd,
      vmArgs = choice.vmArgs,
      args = choice.args,
      env = choice.env,
    }, { default_cwd = root_dir }, function(result)
      if not result then return end
      choice.mainClass = result.mainClass
      choice.cwd = result.cwd
      choice.vmArgs = result.vmArgs
      choice.args = result.args
      choice.projectName = choice.projectName or defaults.projectName
      choice.env = next(result.env) and result.env or nil
      M.save(root_dir, configs)
    end)
  end)
end

--- Xoá 1 profile (chọn từ danh sách), rồi lưu lại xuống đĩa.
---@param filetype string
---@param root_dir string
function M.delete(filetype, root_dir)
  local dap = require("dap")
  local configs = dap.configurations[filetype] or {}
  if #configs == 0 then
    vim.notify("Không có profile nào để xoá.", vim.log.levels.WARN)
    return
  end
  vim.ui.select(configs, {
    prompt = "Xoá profile:",
    format_item = function(c) return c.name end,
  }, function(choice, idx)
    if not choice then return end
    table.remove(configs, idx)
    dap.configurations[filetype] = configs
    M.save(root_dir, configs)
  end)
end

--- Sửa main class/working directory/VM args/program args/env của 1 profile trước khi chạy song
--- song (xem <leader>dp trong dap.lua) - dùng đúng panel với M.add/M.edit. Việc lưu xuống đĩa
--- do caller tự quyết định (xem <leader>dp: áp thẳng vào profile + gọi M.save sau khi có result).
---@param profile table profile gốc (không bị sửa trực tiếp), lấy làm giá trị gợi ý ban đầu
---@param on_done fun(result: table?) xem edit_profile - result = nil nếu huỷ
function M.edit_overrides(profile, on_done)
  edit_profile({
    mainClass = profile.mainClass,
    cwd = profile.cwd,
    vmArgs = profile.vmArgs,
    args = profile.args,
    env = profile.env,
  }, {}, on_done)
end

return M
