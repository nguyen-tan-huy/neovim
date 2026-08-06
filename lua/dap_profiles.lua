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

local function profiles_path(root_dir)
  return root_dir .. "/.nvim/dap-profiles.json"
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

--- Mở 1 cửa sổ nổi để xem/sửa biến môi trường của profile, dạng KEY=VALUE mỗi dòng.
--- Nếu profile đã có biến môi trường thì hiện đúng những gì đang có; nếu chưa có gì thì
--- hiện sẵn vài dòng gợi ý (comment, không bật) để người dùng biết định dạng và tên biến hay dùng.
---@param current_env table<string, string>?
---@param on_done fun(env: table<string, string>?) gọi lại khi đóng, env = nil nếu huỷ (không đổi gì)
local function edit_env(current_env, on_done)
  local lines
  if current_env and next(current_env) then
    lines = {}
    local keys = vim.tbl_keys(current_env)
    table.sort(keys)
    for _, k in ipairs(keys) do
      table.insert(lines, k .. "=" .. tostring(current_env[k]))
    end
  else
    lines = vim.list_extend({
      "# Biến môi trường cho profile này, mỗi dòng 1 biến dạng KEY=VALUE.",
      "# Dòng bắt đầu bằng # bị bỏ qua. Xoá dấu # để bật gợi ý bên dưới, hoặc tự thêm dòng mới.",
    }, ENV_SUGGESTIONS)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "sh"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_name(buf, "dap-profile-env://" .. buf)

  local width = math.min(80, math.floor(vim.o.columns * 0.6))
  local height = math.max(#lines + 1, 6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " Env vars (:w lưu, :q / q huỷ) ",
    title_pos = "center",
  })

  local done = false
  local function finish(save)
    if done then return end
    done = true
    local env = nil
    if save then
      env = {}
      for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not vim.startswith(trimmed, "#") then
          local key, value = trimmed:match("^([%w_][%w_%.]*)=(.*)$")
          if key then env[key] = value end
        end
      end
    end
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    on_done(env)
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = buf, callback = function() finish(true) end })
  vim.keymap.set("n", "q", function() finish(false) end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function() finish(false) end, { buffer = buf, nowait = true })
end

--- Thêm 1 profile mới (hỏi từng field qua vim.ui.input), rồi lưu lại luôn xuống đĩa.
---@param filetype string
---@param root_dir string
---@param defaults table? giá trị mặc định gợi ý sẵn, vd { name = "...", mainClass = "...", projectName = "..." }
function M.add(filetype, root_dir, defaults)
  defaults = defaults or {}
  local dap = require("dap")
  vim.ui.input({ prompt = "Tên profile: ", default = defaults.name or "" }, function(name)
    if not name or name == "" then return end
    -- Main class gợi ý sẵn theo package của file đang mở (nếu có), vẫn sửa/xoá được nếu muốn
    -- trỏ tới class khác.
    vim.ui.input({ prompt = "Main class: ", default = defaults.mainClass or "" }, function(main_class)
      if main_class == nil then return end
      -- Working directory của tiến trình Java khi chạy. Gợi ý sẵn = root_dir (project gốc),
      -- vì các profile jdtls tự dò cũng dùng đúng giá trị này - sửa nếu module con nằm khác chỗ.
      vim.ui.input({ prompt = "Working directory: ", default = defaults.cwd or root_dir }, function(cwd)
        if cwd == nil then return end
        vim.ui.input({ prompt = "VM args (để trống nếu không có): " }, function(vm_args)
          vim.ui.input({ prompt = "Program args (để trống nếu không có): " }, function(prog_args)
            if prog_args == nil then return end
            edit_env(nil, function(env)
              local profile = {
                type = "java",
                request = "launch",
                name = name,
                mainClass = main_class,
                projectName = defaults.projectName,
                cwd = cwd ~= "" and cwd or nil,
              }
              if vm_args and vm_args ~= "" then profile.vmArgs = vm_args end
              if prog_args and prog_args ~= "" then profile.args = prog_args end
              if env and next(env) then profile.env = env end

              dap.configurations[filetype] = dap.configurations[filetype] or {}
              table.insert(dap.configurations[filetype], profile)
              M.save(root_dir, dap.configurations[filetype])
            end)
          end)
        end)
      end)
    end)
  end)
end

--- Sửa 1 profile có sẵn (chọn từ danh sách), rồi lưu lại xuống đĩa.
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
    vim.ui.input({ prompt = "Main class: ", default = choice.mainClass or defaults.mainClass or "" },
      function(main_class)
      if main_class == nil then return end
      vim.ui.input({ prompt = "Working directory: ", default = choice.cwd or defaults.cwd or root_dir },
        function(cwd)
        if cwd == nil then return end
        vim.ui.input({ prompt = "VM args: ", default = choice.vmArgs or defaults.vmArgs or "" }, function(vm_args)
          vim.ui.input({ prompt = "Program args: ", default = choice.args or defaults.args or "" }, function(prog_args)
            if prog_args == nil then return end
            -- Hiện đúng biến môi trường profile đang có; nếu chưa có gì thì hiện gợi ý.
            edit_env(choice.env, function(env)
              choice.mainClass = main_class ~= "" and main_class or nil
              choice.cwd = cwd ~= "" and cwd or nil
              choice.vmArgs = vm_args ~= "" and vm_args or nil
              choice.args = prog_args ~= "" and prog_args or nil
              choice.projectName = choice.projectName or defaults.projectName
              if env then choice.env = next(env) and env or nil end
              M.save(root_dir, configs)
            end)
          end)
        end)
      end)
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

-- Expose để chỗ khác (vd chạy 1 profile mới song song) tái dùng đúng popup sửa env này,
-- không cần đi kèm luồng thêm/sửa profile lưu xuống đĩa.
M.edit_env = edit_env

return M
