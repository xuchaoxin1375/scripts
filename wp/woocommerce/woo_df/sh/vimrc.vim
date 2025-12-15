" ------------------------------------
" 基础设置
" ------------------------------------
set nocompatible        " 禁用 Vi 兼容模式
set encoding=utf-8      " 设置编码
set backspace=indent,eol,start " 更好的 Backspace 行为

" ------------------------------------
" 缩进和 Tab 设置 (使用 4 个空格)
" ------------------------------------
set autoindent
set smartindent
set tabstop=4           " Tab 宽度
set shiftwidth=4        " 自动缩进宽度
set expandtab           " Tab 键输入空格

" ------------------------------------
" 界面和导航
" ------------------------------------
syntax enable           " 开启语法高亮
set number              " 显示绝对行号
"set relativenumber      " 显示相对行号（建议配合 number 使用）
set showmatch           " 匹配括号
set ruler               " 在右下角显示光标位置
set mouse=a             " 启用鼠标支持

" ------------------------------------
" 搜索增强
" ------------------------------------
set ignorecase          " 搜索不区分大小写
set smartcase           " 智能大小写匹配
set hlsearch            " 高亮搜索结果
set incsearch           " 渐进搜索