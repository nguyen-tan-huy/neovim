-- Cấu hình jdtls trực tiếp qua mfussenegger/nvim-jdtls + Mason (không qua nvim-java),
-- để tự chủ version java-debug-adapter/java-test (nvim-java pin version cũ có bug NPE
-- khi lấy stack trace: https://github.com/redhat-developer/vscode-java/issues/4285).
if vim.b.did_ftplugin_java then return end
vim.b.did_ftplugin_java = true

local ok_registry, mason_registry = pcall(require, "mason-registry")
if not ok_registry then
  vim.notify("mason-registry chưa sẵn sàng, không thể khởi động jdtls.", vim.log.levels.ERROR)
  return
end

local function mason_install_path(name)
  local ok, pkg = pcall(mason_registry.get_package, name)
  if ok and pkg:is_installed() then
    return pkg:get_install_path()
  end
  return nil
end

-- LƯU Ý: KHÔNG dùng bản jdtls mới nhất của Mason (v1.60.0) - nó đóng gói ASM 9.10.1,
-- trong khi bundle "java-test" của Mason (com.microsoft.java.test.plugin) yêu cầu
-- ASM trong khoảng [9.9.0, 9.10.0) -> bundle test không load được (OSGi BundleException),
-- khiến "No LSP client found that supports resolving possible test cases".
-- Dùng lại bản jdtls 1.54.0 (đóng gói đúng ASM 9.9.0, đã test tương thích với java-test)
-- còn cache lại từ nvim-java trước khi migrate.
local jdtls_path = vim.fn.stdpath("data") .. "/nvim-java/packages/jdtls/1.54.0"
if vim.fn.isdirectory(jdtls_path) == 0 then
  jdtls_path = mason_install_path("jdtls")
  if jdtls_path then
    vim.notify(
      "Không thấy jdtls 1.54.0 cache cũ, dùng bản Mason mới nhất - có thể lỗi debug/run test do " ..
      "xung đột version ASM với java-test.", vim.log.levels.WARN)
  end
end
if not jdtls_path then
  vim.notify("Không tìm thấy jdtls. Chạy :Mason rồi cài 'jdtls', 'java-debug-adapter', 'java-test'.",
    vim.log.levels.ERROR)
  return
end

local jdtls = require("jdtls")
local jdk = require("jdk")
local dap_profiles = require("dap_profiles")

-- Bundle DAP (debug) + test runner (JUnit/TestNG) + spring-boot jdtls extension
local bundles = {}
local debug_path = mason_install_path("java-debug-adapter")
if debug_path then
  vim.list_extend(bundles,
    vim.split(vim.fn.glob(debug_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar"), "\n"))
end
-- LƯU Ý: java-test bản Mason (0.43.1) gọi CoreTestSearchEngine.hasJUnit6TestAnnotation() -
-- method này chỉ có ở jdt.ls bản mới, KHÔNG có trong jdtls 1.54.0 đang dùng (để tương thích
-- ASM với chính plugin java-test, xem comment ở jdtls_path) -> NoSuchMethodError khi tìm test.
-- Dùng lại bản java-test 0.43.2 cache từ nvim-java (không đụng JUnit 6, khớp với jdtls 1.54.0).
local test_path = vim.fn.stdpath("data") .. "/nvim-java/packages/java-test/0.43.2"
if vim.fn.isdirectory(test_path) == 0 then
  test_path = mason_install_path("java-test")
  if test_path then
    vim.notify(
      "Không thấy java-test 0.43.2 cache cũ, dùng bản Mason mới nhất - có thể lỗi " ..
      "'hasJUnit6TestAnnotation' do không khớp version với jdtls 1.54.0.", vim.log.levels.WARN)
  end
end
if test_path then
  vim.list_extend(bundles, vim.split(vim.fn.glob(test_path .. "/extension/server/*.jar"), "\n"))
end
local ok_spring, spring_boot = pcall(require, "spring_boot")
if ok_spring then
  vim.list_extend(bundles, spring_boot.java_extensions())
end

local root_dir = require("jdtls.setup").find_root({ "mvnw", "gradlew", "settings.gradle", "settings.gradle.kts", ".git" })
if not root_dir then
  local found = vim.fs.find({ "pom.xml", "build.gradle" }, { upward = true, path = vim.fn.expand("%:p:h") })[1]
  root_dir = found and vim.fs.dirname(found)
end
if not root_dir then
  vim.notify("Không tìm thấy project root (pom.xml/build.gradle/.git) cho file này.", vim.log.levels.WARN)
  return
end

-- project_name (tên thư mục cuối, KHÔNG hash) dùng làm gợi ý field "projectName" cho profile
-- debug - phải giữ đúng tên Maven/Eclipse project thật, không được đụng vào, nếu không jdtls
-- sẽ không tra được classpath/java executable ("Could not resolve java executable for ...").
local project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")

-- workspace_dir dùng tên RIÊNG (project_name + hash root_dir) để tránh 2 root_dir KHÁC NHAU
-- nhưng trùng tên thư mục cuối (vd repo gốc "product-service" và module con cũng tên
-- "product-service" có mvnw riêng) bị chung 1 workspace_dir -> 2 tiến trình jdtls tranh nhau
-- khoá workspace Eclipse -> tiến trình sau bị kill ngay (exit code 13).
local workspace_id = project_name .. "-" .. vim.fn.sha256(root_dir):sub(1, 8)
local workspace_dir = vim.fn.stdpath("cache") .. "/jdtls-workspace/" .. workspace_id

--- Tìm các module con có pom.xml riêng nhưng KHÔNG khai báo trong <modules> của pom cha
--- (và không có mvnw riêng - loại đó tự tách root_dir/workspace riêng rồi, xem tìm root_dir
--- ở trên). jdtls không tự import những module "mồ côi" này -> gd/resolve classpath/debug
--- không hoạt động cho chúng dù vẫn chung root_dir với các module khác.
---@param dir string
---@return string[]
local function find_orphan_maven_modules(dir)
  local root_pom = dir .. "/pom.xml"
  if vim.fn.filereadable(root_pom) == 0 then return {} end
  local content = table.concat(vim.fn.readfile(root_pom), "\n")
  local declared = {}
  for m in content:gmatch("<module>%s*([^<%s]+)%s*</module>") do
    declared[m] = true
  end
  local orphans = {}
  for _, entry in ipairs(vim.fn.readdir(dir) or {}) do
    local sub = dir .. "/" .. entry
    if not declared[entry] and vim.fn.isdirectory(sub) == 1
      and vim.fn.filereadable(sub .. "/pom.xml") == 1
      and vim.fn.filereadable(sub .. "/mvnw") == 0 then
      table.insert(orphans, sub)
    end
  end
  return orphans
end

local capabilities = require("cmp_nvim_lsp").default_capabilities()

-- Dùng path tuyệt đối, KHÔNG gọi "jdtls" theo PATH - trên PATH là bản Mason mới nhất
-- (bị lỗi ASM ở trên), còn đây trỏ thẳng launcher của bản 1.54.0 đang dùng.
local cmd = { jdtls_path .. "/bin/jdtls" }
local lombok_jar = jdtls_path .. "/lombok.jar"
if vim.fn.filereadable(lombok_jar) == 0 then
  -- cache jdtls 1.54.0 của nvim-java không kèm lombok.jar trong cùng thư mục, lombok nằm riêng
  lombok_jar = vim.fn.stdpath("data") .. "/nvim-java/packages/lombok/1.18.42/lombok-1.18.42.jar"
end
if vim.fn.filereadable(lombok_jar) == 1 then
  -- launcher jdtls.py của Mason dùng argparse, JVM arg PHẢI theo dạng --jvm-arg=-Dxxx (có dấu =),
  -- truyền bare "-javaagent:..." sẽ bị coi là leftover arg và không áp dụng javaagent
  table.insert(cmd, "--jvm-arg=-javaagent:" .. lombok_jar)
end
vim.list_extend(cmd, { "-data", workspace_dir })

local config = {
  cmd = cmd,
  root_dir = root_dir,
  capabilities = capabilities,
  settings = {
    java = {
      configuration = {
        updateBuildConfiguration = "interactive",
        -- Danh sách JDK phát hiện được trên máy; đổi JDK dùng để compile/debug bằng <leader>jv
        runtimes = jdk.runtimes_for_jdtls(),
      },
      saveActions = { organizeImports = true },
      completion = {
        favoriteStaticMembers = {
          "org.junit.jupiter.api.Assertions.*",
          "org.mockito.Mockito.*",
          "java.util.Objects.requireNonNull",
        },
        importOrder = { "java", "javax", "org", "com", "" },
      },
      sources = {
        organizeImports = { starThreshold = 5, staticStarThreshold = 3 },
      },
      format = { enabled = true },
    },
  },
  init_options = {
    bundles = bundles,
  },
  on_attach = function(_, bufnr)
    jdtls.setup_dap({ hotcodereplace = "manual" })

    -- Import các module "mồ côi" (pom.xml riêng, không có trong <modules> pom cha) như workspace
    -- folder riêng, KHÔNG đụng vào pom.xml của project - jdtls vẫn coi chúng là project đầy đủ
    -- (resolve classpath/java executable hoạt động), đồng thời vẫn chung 1 client với các module
    -- khác nên gd/Ctrl+B qua lại các module vẫn hoạt động (khác với cách tự tách root_dir riêng).
    do
      local existing = {}
      for _, wf in ipairs(vim.lsp.buf.list_workspace_folders()) do existing[wf] = true end
      for _, dir in ipairs(find_orphan_maven_modules(root_dir)) do
        if not existing[dir] then
          vim.lsp.buf.add_workspace_folder(dir)
          vim.notify("jdtls: import thêm module mồ côi vào workspace: " .. dir, vim.log.levels.INFO)
        end
      end
    end

    -- Nạp profile debug đã lưu của project trước, rồi mới để jdtls tự dò thêm main class mới
    -- (jdtls chỉ merge thêm/update theo tên+cwd, không xoá profile đã có sẵn trong danh sách).
    require("dap").configurations.java = dap_profiles.load(root_dir)
    require("jdtls.dap").setup_dap_main_class_configs({
      on_ready = function()
        dap_profiles.save(root_dir, require("dap").configurations.java)
      end,
    })

    -- KHÔNG tự redefineClasses nữa. Chỉ báo khi code đã biên dịch xong, chờ Ctrl+\ (xem dap.lua)
    -- để áp dụng thủ công.
    require("dap").listeners.before["event_hotcodereplace"]["jdtls"] = function(_, body)
      if body.changeType == "BUILD_COMPLETE" then
        vim.notify("Code đã biên dịch xong. Nhấn Ctrl+\\ để áp dụng (hot reload).", vim.log.levels.INFO)
      elseif (body.changeType == "ERROR" or body.changeType == "WARNING") and body.message then
        vim.notify("Hot reload: " .. body.message, vim.log.levels.WARN)
      end
    end

    -- Reformat code khi lưu file, giống "Reformat on Save" của IntelliJ
    vim.api.nvim_create_autocmd("BufWritePre", {
      buffer = bufnr,
      callback = function(args)
        vim.lsp.buf.format({ bufnr = args.buf, async = false })
      end,
    })

    local opts = { buffer = bufnr }

    -- Debug unit test (JUnit/TestNG) qua java-test bundle, tự set breakpoint là dừng đúng chỗ
    vim.keymap.set("n", "<leader>tdc", function()
      require("jdtls.dap").test_class()
    end, vim.tbl_extend("force", opts, { desc = "Test: debug class hiện tại" }))
    vim.keymap.set("n", "<leader>tdm", function()
      require("jdtls.dap").test_nearest_method()
    end, vim.tbl_extend("force", opts, { desc = "Test: debug method gần cursor" }))
    -- Chạy test (không debug, không dừng ở breakpoint)
    vim.keymap.set("n", "<leader>trc", function()
      require("jdtls.dap").test_class({ config_overrides = { noDebug = true } })
    end, vim.tbl_extend("force", opts, { desc = "Test: run class hiện tại (không debug)" }))
    vim.keymap.set("n", "<leader>trm", function()
      require("jdtls.dap").test_nearest_method({ config_overrides = { noDebug = true } })
    end, vim.tbl_extend("force", opts, { desc = "Test: run method gần cursor (không debug)" }))
    vim.keymap.set({ "n", "x" }, "<leader>jev", jdtls.extract_variable,
      vim.tbl_extend("force", opts, { desc = "Java: extract variable" }))
    vim.keymap.set({ "n", "x" }, "<leader>jec", jdtls.extract_constant,
      vim.tbl_extend("force", opts, { desc = "Java: extract constant" }))
    vim.keymap.set({ "n", "x" }, "<leader>jem", jdtls.extract_method,
      vim.tbl_extend("force", opts, { desc = "Java: extract method" }))
    vim.keymap.set("n", "<leader>joi", jdtls.organize_imports,
      vim.tbl_extend("force", opts, { desc = "Java: organize imports" }))

    -- Reload project config (giống "Reload Maven Project" của IntelliJ)
    vim.keymap.set("n", "<leader>ju", jdtls.update_project_config,
      vim.tbl_extend("force", opts, { desc = "Java: reload project config (module hiện tại)" }))
    vim.keymap.set("n", "<leader>jU", function()
      jdtls.update_projects_config({ select_mode = "all" })
    end, vim.tbl_extend("force", opts, { desc = "Java: reload project config (toàn bộ project)" }))

    -- Xoá sạch workspace cache + restart jdtls (giống Invalidate Caches/Restart của IntelliJ)
    vim.keymap.set("n", "<leader>jR", function()
      vim.ui.select({ "Huỷ", "Xoá cache + restart jdtls" }, {
        prompt = "Xoá workspace cache tại " .. workspace_dir .. " ?",
      }, function(choice)
        if choice ~= "Xoá cache + restart jdtls" then return end
        require("jdtls.setup").wipe_data_and_restart()
      end)
    end, vim.tbl_extend("force", opts, { desc = "Java: xoá cache + reimport project sạch" }))

    -- Reload danh sách profile debug: nạp lại file đã lưu + cho jdtls dò thêm main class mới,
    -- rồi tự lưu lại xuống đĩa (giống F5 refresh danh sách Run/Debug Configuration của IntelliJ).
    vim.keymap.set("n", "<leader>jpl", function()
      require("dap").configurations.java = dap_profiles.load(root_dir)
      require("jdtls.dap").setup_dap_main_class_configs({
        on_ready = function()
          local configs = require("dap").configurations.java
          dap_profiles.save(root_dir, configs)
          vim.notify(string.format("Đã reload %d profile debug.", #configs), vim.log.levels.INFO)
        end,
      })
    end, vim.tbl_extend("force", opts, { desc = "Debug profile: reload danh sách" }))

    -- Lưu danh sách profile debug hiện tại (đã sửa tay bằng <leader>dp thêm session, hoặc để
    -- backup thủ công) xuống <project_root>/.nvim/dap-profiles.json.
    vim.keymap.set("n", "<leader>jps", function()
      dap_profiles.save(root_dir, require("dap").configurations.java or {})
    end, vim.tbl_extend("force", opts, { desc = "Debug profile: lưu danh sách hiện tại" }))

    -- Thêm 1 profile debug mới (nhập tay tên/args/vmArgs), main class gợi ý sẵn theo
    -- package.class của file Java đang mở (vẫn sửa được nếu muốn trỏ tới class khác).
    vim.keymap.set("n", "<leader>jpa", function()
      dap_profiles.add("java", root_dir, {
        mainClass = require("jdtls.util").resolve_classname(),
        projectName = project_name,
      })
    end, vim.tbl_extend("force", opts, { desc = "Debug profile: thêm mới" }))

    -- Thêm profile debug từ CHÍNH file Java đang xem: tự dò "package ...;" + tên class trong
    -- buffer hiện tại (require("jdtls.util").resolve_classname(), giống cách jdtls tự xác định
    -- mainClass khi bấm "Run" ngay trên file) để điền sẵn tên profile + mainClass.
    vim.keymap.set("n", "<leader>jpc", function()
      local main_class = require("jdtls.util").resolve_classname()
      if not main_class then
        vim.notify("Không dò được package/class name của file hiện tại.", vim.log.levels.WARN)
        return
      end
      local class_name = main_class:match("([^.]+)$") or main_class
      dap_profiles.add("java", root_dir, {
        name = class_name,
        mainClass = main_class,
        projectName = project_name,
      })
    end, vim.tbl_extend("force", opts, { desc = "Debug profile: thêm từ file hiện tại" }))

    -- Sửa 1 profile debug có sẵn (chọn từ danh sách), tự lưu lại xuống đĩa. Field nào profile
    -- đang thiếu (vd chưa có mainClass/projectName) thì gợi ý sẵn theo file Java đang mở,
    -- giống <leader>jpa, đỡ phải gõ tay lại từ đầu.
    vim.keymap.set("n", "<leader>jpe", function()
      dap_profiles.edit("java", root_dir, {
        mainClass = require("jdtls.util").resolve_classname(),
        projectName = project_name,
      })
    end, vim.tbl_extend("force", opts, { desc = "Debug profile: sửa" }))

    -- Xoá 1 profile debug (chọn từ danh sách), tự lưu lại xuống đĩa.
    vim.keymap.set("n", "<leader>jpd", function()
      dap_profiles.delete("java", root_dir)
    end, vim.tbl_extend("force", opts, { desc = "Debug profile: xoá" }))

    -- Đổi JDK dùng để compile/debug project hiện tại (giống Project SDK của IntelliJ)
    vim.keymap.set("n", "<leader>jv", function()
      local client = vim.lsp.get_clients({ bufnr = bufnr, name = "jdtls" })[1]
      if not client then
        vim.notify("jdtls chưa attach.", vim.log.levels.WARN)
        return
      end
      local runtimes = vim.tbl_get(client.config, "settings", "java", "configuration", "runtimes") or {}
      if #runtimes == 0 then
        vim.notify("Không có JDK nào được cấu hình sẵn.", vim.log.levels.WARN)
        return
      end
      vim.ui.select(runtimes, {
        prompt = "Chọn JDK cho project (compile/debug):",
        format_item = function(rt) return rt.name .. " :: " .. rt.path end,
      }, function(choice)
        if not choice then return end
        for _, rt in ipairs(client.config.settings.java.configuration.runtimes) do
          rt.default = (rt.path == choice.path) or nil
        end
        client:notify("workspace/didChangeConfiguration", { settings = client.config.settings })
        vim.notify("Đã đổi JDK project sang " .. choice.name .. " (" .. choice.path .. ")", vim.log.levels.INFO)
      end)
    end, vim.tbl_extend("force", opts, { desc = "Java: chọn JDK version cho project (compile/debug)" }))
  end,
}

jdtls.start_or_attach(config)
