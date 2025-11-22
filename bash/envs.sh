#!/bin/bash

# 不同于aliases.sh
# 本文件中的内容的右值可能涉及到相互引用,而不仅仅是纯粹的字符串赋值,如果顺序不对,会导致达不到预期效果
# 被引用这需要往前写(被频繁引用需要写在文件头部.)
echo "setting the global envs!"
# 环境变量其实能够嵌套多次,但是环境变量名需要注意,某些变量名会引起报错:inconsistent type for assignment;这不是赋值语法的问题,而是冲突问题
#注意,指派新的环境变量注意别名环境变量名不是随便取的,要避免某些特殊值,比如aliases这个词不可以直接作为左值: attempt to set associative array to scalar
# export test_env_permanent="permanent!@cxxu"
# 没有空格的时候,下列的引号都可以取消,而且source 字符串命令容易报错!(至少在source 的时候不要有""包裹)
# export 可以批量导出(,但是处理换行比较麻烦)
# export 可以导出变量的名字(变量的赋值可以在导出进行)
# e这个export的别名仅在此处有效,其余地方会被其他`exit`覆盖!
alias e=export
# ----------------under---------------
#定义batcat彩色文件查看工具的主题(目前--theme 参数有问题,没反应)
e BAT_THEME=GitHub

# e P=$PATH
e P=/usr/node/node-v\*-linux-x64/bin/:$P
e P="$HOME/.local/bin":$P
e P=".":$P
e PATH=$P:$PATH
# e path=$PATH

e ZDOTDIR=$home
e bin=/usr/bin
e vimrc="~/.vimrc"
e vimrcGlobal="/etc/vim/vimrc"
# 为man着色的阅读器,需要安装most
# e PAGER="most"

e d="/mnt/d"
e c="/mnt/c"
# -------------under---------

# INFO[0000] Mixed(http+socks) proxy listening at: [::]:7897
# 测试代理是否可以加速:
# curl https://duckduckgo.com/
# wget www.google.com
# 通过别名/bash函数来配置,方便控制开关.
# e https_proxy=127.0.0.1:7897
# e http_proxy=127.0.0.1:7897

e zsh_plugins=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins
e zsh_syntax_highlighting=$zsh_plugins/zsh_syntax_highlighting
e zsh_autosuggestions=$zsh_plugins/zsh_autosuggestions
e userProfile=$c/users/cxxu
e home=$userProfile
e desktop=$userProfile/desktop
e djangoProjects=~/djangoProjects
#basic dirs
e exes="$d/exes"
e repos="$d/repos"
#middle level dirS

e blogs="$repos/blogs"
e userProfile="$c/users/cxxu"
e downloads="$userProfile/downloads"
e compressed="$downloads/compressed"
e importer="$linuxShellScripts/importer.sh"
e imp="$linuxShellScripts/importer.sh"
e aliasesConfig="$scripts/linuxShellScripts/aliases.sh"
e aliases_jumper="$linuxShellScripts/aliases_jumper.sh"

# export aliases="$linuxShellScripts/.aliases.sh"
# export  c d home