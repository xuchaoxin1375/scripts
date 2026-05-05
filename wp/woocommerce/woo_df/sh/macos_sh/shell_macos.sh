#!/bin/bash
echo "Loading env for macos..."
# 提高macos允许进程打开的文件数量,某些zsh插件对此数值要求较高(macos默认为256)
ulimit -n 4096

# alias typora="open -a /Applications/Typora.app"
typora() {
    if [ -t 0 ]; then
        # 正常模式：直接打开文件或应用
        if [ $# -eq 0 ]; then
            open -a /Applications/Typora.app
        else
            open -a /Applications/Typora.app "$@"
        fi
    else
        # 管道模式：读取路径并逐个打开
        # 使用 xargs 确保路径中的空格被正确处理
        xargs -I {} open -a /Applications/Typora.app "{}"
    fi
}
[[ -e /opt/homebrew/opt/curl/bin ]] && export PATH="/opt/homebrew/opt/curl/bin:$PATH"

activate_copyq() {
    #软件github https://github.com/hluk/CopyQ
    # 使用brew安装(由于认证问题,将来可能不能通过brew安装,需要从github下载安装)
    if [ ! -d /Applications/CopyQ.app ]; then
        echo "CopyQ not found, please install it first."
        return 1
    fi
    # brew install copyq
    
    xattr -d com.apple.quarantine /Applications/CopyQ.app
    codesign --force --deep --sign - /Applications/CopyQ.app
}
