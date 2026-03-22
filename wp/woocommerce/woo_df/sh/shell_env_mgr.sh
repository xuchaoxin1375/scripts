#!/bin/bash
# shellcheck disable=SC1091
# 在这里可以手动维护一些常用的环境管理的程序的导入脚本,注意检查相关环境变量,避免重复导入;
if [[ -z $NVM_DIR ]]; then
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion
fi
