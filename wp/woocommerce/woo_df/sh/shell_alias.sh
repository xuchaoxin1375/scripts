#!/bin/bash

echo "Loading pre-defined aliases..."

# fail2ban系列命令缩写f2b或fb
alias fbc='fail2ban-client'
alias fbcs='fail2ban-client status'
alias fbregex='fail2ban-regex'
alias fbt='fail2ban-testcases'
# windows端wsl的shell脚本目录快速跳转
alias wslsh='cd /mnt/c/repos/scripts/wp/woocommerce/woo_df/sh'