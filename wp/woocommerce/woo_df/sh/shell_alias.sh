#!/bin/bash

echo "Loading pre-defined aliases..."
# 常用内置命令缩写
alias bashrc='source ~/.bashrc'
alias zshrc='source ~/.zshrc'
alias cls=clear
# 第三方程序缩写
alias vim=nvim
alias vi=vim
# fail2ban系列命令缩写f2b或fb
alias fbc='fail2ban-client'
alias fbcs='fail2ban-client status'
alias fbregex='fail2ban-regex'
alias fbt='fail2ban-testcases'
# windows端wsl的shell脚本目录快速跳转
# alias wslsh="cd $wslsh"