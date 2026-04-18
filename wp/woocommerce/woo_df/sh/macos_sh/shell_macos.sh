#!/bin/bash
echo "Loading env for macos..."

alias typora="open -a /Applications/Typora.app"
# 提高macos允许进程打开的文件数量,某些zsh插件对此数值要求较高(macos默认为256)
ulimit -n 4096