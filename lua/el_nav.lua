-- Nhảy từ EL expression (#{bean.action}) trong file .xhtml (JSF/PrimeFaces) sang định
-- nghĩa Java tương ứng, giống Ctrl+B của IntelliJ. lemminx (XML LSP) không hiểu EL nên
-- không tự làm được việc này -> tự viết bằng cách grep theo convention đặt tên bean của
-- project (@Component("Bean")/@Named("Bean")/@ManagedBean(name="Bean")).
local M = {}

--- Trả về { bean = "ProductTag", member = "keyword" | nil } nếu cursor đang đứng trong 1
--- EL expression ở dòng hiện tại, ngược lại trả về nil.
--- member = nil nghĩa là cursor đang đứng ngay trên tên bean (chưa tới phần .field/.method).
function M.el_token_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-indexed để so với string.find

  local search_from = 1
  while true do
    local s, e = line:find("[#%$]{[^}]*}", search_from)
    if not s then return nil end
    if col >= s and col <= e then
      local inner_start = s + 2 -- bỏ qua "#{" / "${"
      local inner = line:sub(inner_start, e - 1)
      local rel = col - inner_start + 1

      local tokens = {}
      for tok_s, tok, tok_e in inner:gmatch("()([%a_][%w_]*)()") do
        table.insert(tokens, { s = tok_s, e = tok_e - 1, text = tok })
      end
      if #tokens == 0 then return nil end

      local hit_idx = nil
      for i, t in ipairs(tokens) do
        if rel >= t.s and rel <= t.e then
          hit_idx = i
          break
        end
      end
      if not hit_idx then return nil end

      if hit_idx == 1 then
        return { bean = tokens[1].text, member = nil }
      end
      return { bean = tokens[1].text, member = tokens[hit_idx].text }
    end
    search_from = e + 1
  end
end

local function rg_first_match(args)
  local ok, res = pcall(vim.system, args, { text = true })
  if not ok then return nil end
  local out = res:wait()
  if out.code ~= 0 or not out.stdout or out.stdout == "" then return nil end
  local file, lnum = out.stdout:match("^([^\n]-):(%d+):")
  if not file then return nil end
  return file, tonumber(lnum)
end

--- Tìm file Java khai báo bean có tên EL `bean_name` (qua @Component/@Named/@ManagedBean
--- đặt tên tường minh) trong `root`. Trả về đường dẫn file, hoặc nil nếu không thấy.
local function find_bean_file(root, bean_name)
  local pattern = string.format(
    [[@(Component|Named|ManagedBean)\(\s*(name\s*=\s*)?"%s"\s*\)]],
    bean_name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "\\%1")
  )
  local file = rg_first_match({ "rg", "--type", "java", "-n", "-P", "-m", "1", pattern, root })
  return file
end

--- Tìm dòng khai báo field/method `member` bên trong `file`. Trả về lnum (1-indexed) hoặc nil.
local function find_member_line(file, member)
  local m = member:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "\\%1")
  local cap = member:sub(1, 1):upper() .. member:sub(2)
  local patterns = {
    -- field: `private String keyword;` hoặc `= keyword`
    string.format("\\b(private|public|protected)\\b[^;{]*\\b%s\\s*[;=]", m),
    -- method: `public void onload()`
    string.format("\\b(private|public|protected)\\b[^\\(]*\\b%s\\s*\\(", m),
    -- getter tường minh (không dùng Lombok)
    string.format("\\b(get|is)%s\\s*\\(", cap),
    -- fallback: chỉ cần xuất hiện thôi
    string.format("\\b%s\\b", m),
  }
  for _, pat in ipairs(patterns) do
    local _, lnum = rg_first_match({ "rg", "-n", "-H", "-P", "-m", "1", pat, file })
    if lnum then return lnum end
  end
  return nil
end

--- Nhảy từ EL expression dưới cursor sang file/định nghĩa Java tương ứng.
--- Trả về true nếu nhảy được, false nếu cursor không đứng trong EL expression nào cả
--- (để caller fallback sang hành vi khác, vd LSP definition bình thường).
function M.jump_from_cursor()
  local token = M.el_token_at_cursor()
  if not token then return false end

  local root = vim.fs.root(vim.api.nvim_buf_get_name(0), ".git")
  if not root then
    vim.notify("Không tìm thấy git root cho project", vim.log.levels.WARN)
    return true
  end

  local file = find_bean_file(root, token.bean)
  if not file then
    vim.notify("Không tìm thấy bean Java cho '" .. token.bean .. "'", vim.log.levels.WARN)
    return true
  end

  local lnum = 1
  if token.member then
    lnum = find_member_line(file, token.member) or 1
  end

  vim.cmd.edit(vim.fn.fnameescape(file))
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  vim.cmd("normal! zz")
  return true
end

return M
