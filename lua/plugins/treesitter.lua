return {
  "nvim-treesitter/nvim-treesitter",
  branch = "master", -- BẮT BUỘC: nhánh "main" mới đã đổi hết API, không còn nvim-treesitter.configs
  build = ":TSUpdate",
  config = function()
    -- File quá lớn thì tắt highlight/indent treesitter để tránh đơ (vd file .java nhiều nghìn dòng)
    local function is_large_file(_, buf)
      local ok, stats = pcall(function()
        return vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
      end)
      return ok and stats and stats.size > 500 * 1024 -- > 500KB
    end

    require("nvim-treesitter.configs").setup({
      ensure_installed = { "java", "rust", "toml", "lua", "json", "yaml", "xml", "html", "markdown", "markdown_inline", "bash" },
      highlight = { enable = true, disable = is_large_file },
      indent = { enable = true, disable = is_large_file },
      fold = { enable = true },
    })

    -- .xhtml (view JSF/PrimeFaces) chưa có grammar riêng, dùng chung grammar "html"
    vim.treesitter.language.register("html", "xhtml")

    vim.opt.foldmethod = "expr"
    -- Dùng foldexpr native của Neovim (nhanh hơn nhiều so với nvim_treesitter#foldexpr() bản
    -- Vimscript cũ) - đây là nguyên nhân chính gây đơ khi mở file lớn.
    vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
    -- foldenable/foldlevel(start)/foldcolumn được set ở fold.lua (nvim-ufo) - không set trùng
    -- ở đây để tránh 2 nơi ghi đè lẫn nhau.
  end,
}

