#!/bin/bash

echo "Loading pre-defined aliases..."
# 重新加载别名配置(从外部引入sh环境变量)
# shellcheck disable=SC2154
# shellcheck disable=SC2139
alias update_alias="source '$sh/shell_alias.sh'"
# 常用内置命令缩写
alias bashrc='source ~/.bashrc'
alias zshrc='source ~/.zshrc'
alias cls=clear
# man手册(macos bsd版本的命令)
# 例如,使用 bman ln 即可查看bsd版本的ln的原生帮助
alias bman='man -M /usr/share/man'
# 第三方程序缩写(尽可能用neovim(nvim)代替vim)
command -v nvim &> /dev/null && alias vim=nvim
command -v neovim &> /dev/null && alias vim=neovim
command -v vim &> /dev/null && alias vi=vim
# fail2ban系列命令缩写f2b或fb
alias fbc='fail2ban-client'
alias sfbc='sudo fail2ban-client' #非root用户使用,也兼容root用户使用

alias curl='curl --proto-default https'
alias fbcs='fail2ban-client status'
alias fbregex='fail2ban-regex'
alias fbt='fail2ban-testcases'
# windows端wsl的shell脚本目录快速跳转
# python
alias python=python3
alias py=python3
alias pip=pip3
