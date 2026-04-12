#!/bin/bash
# shellcheck disable=SC1091
# shellcheck source=/dev/null
# 注意,由于shellcheck如果要扫描nvm等第三方脚本库会占用大量资源
# 因此这里在脚本开头设置相关指令阻止分析外部文件,避免(source或者.执行外部文件)内存泄露;

# 在这里可以手动维护一些常用的环境管理的程序的导入脚本,注意检查相关环境变量,避免重复导入;
echo "Loading common env mgr..."
# DON'T EXPORT *LOADED ENV VARIABLES
_NVM_LOADED=""
# $(type -t nvm) == "function"  # type -t 不适用于zsh
# && [[ -z $_NVM_LOADED ]]
export NVM_DIR="$HOME/.nvm"
if is_darwin; then
    nvm_sh=$HOMEBREW_PREFIX/opt/nvm/nvm.sh
else
    nvm_sh=$HOME/.nvm/nvm.sh
fi
if [[ -e "$nvm_sh" ]]; then
    if ! command -v nvm &> /dev/null; then
        _NVM_LOADED="1"
        echo  "Loading nvm ..."
        if ! is_darwin; then
            # linux等非macos系统
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
            [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion
        elif [[ -e $HOMEBREW_PREFIX/opt/nvm/nvm.sh ]]; then
            # for macos brew
            # 检查xz命令是否可用,否则如果包是xz会安装失败
            if command -v xz &> /dev/null; then
                export NVM_DIR="$HOME/.nvm"
            else
                echo "[warning]: To use nvm install node, 'xz' command not found, please install xz command first"
                exit 1
            fi
            # export NVM_DIR="$HOME/.nvm"
            [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"                                       # This loads nvm
            [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" # This loads nvm bash_completion
        fi
    fi
fi
