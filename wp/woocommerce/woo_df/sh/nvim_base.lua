-- ~/.config/nvim/lua/mine/settings.lua
local opt = vim.opt

-- 基本界面
opt.number = true          -- 显示行号
opt.relativenumber = true  -- 相对行号
opt.cursorline = true      -- 高亮光标行
opt.wrap = false           -- 不自动换行
opt.termguicolors = true   -- 支持真彩色

-- 编辑行为
opt.expandtab = true       -- 空格代替 tab
opt.shiftwidth = 2         -- 缩进 2 空格
opt.tabstop = 2
opt.smartindent = true
opt.clipboard = "unnamedplus" -- 系统剪贴板

-- 搜索
opt.ignorecase = true
opt.smartcase = true

-- 其他
opt.scrolloff = 8
opt.signcolumn = "yes"