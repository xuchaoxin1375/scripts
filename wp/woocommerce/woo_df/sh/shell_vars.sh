#!/bin/bash
# shellcheck source=/dev/null
# 兼容不同的类unix系统的shell变量定义和使用，主要是路径变量，适配linux,wsl,macos等环境
# 本文件由shellrc_addition.sh导入

# 相关变量基本用法：
# mkdir -p "$HOME/repos" && git clone --recursive --depth 1 --shallow-submodules https://gitee.com/xuchaoxin1375/scripts.git "$SCRIPT_ROOT"
#创建符号链接（sh),注意bsd（macos）的ln 不支持-T;
# if [[ -d $SH_SCRIPT_DIR ]]; then
#     ln -s "$SH_SCRIPT_DIR" "$SH_SYM" -fv
# fi

# shell 基本工具相关环境变量
export CLICOLOR=1    # 让ls的输出显示颜色
export PsPrompt=fast # 如果使用pwsh,此环境变量供参考
# bash prompt主题配置
export BASH_PROMPT="fast_ys"
export BASHRC_FILE="$HOME/.bashrc"
export BASH_PROMPTS_ROOT="$sh/bash_prompts"
# linuxbrew的基本环境变量
export _HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
export _HOMEBREW_PATH="$_HOMEBREW_PREFIX/bin/brew"
# macos brew(homebrew) 会自己注册HOMEBREW_PREFIX等环境变量
# HOMEBREW_PREFIX="$(brew --prefix)"
# brew镜像加速(以科大ustc源为例):
# Homebrew 源代码仓库,可以用来加速: brew update
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
# Homebrew 预编译二进制软件包与软件包元数据文件
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
# Homebrew 核心软件仓库(Brew 4.0 版本后默认使用元数据 JSON API 获取仓库信息，因此在大部分情况下都不再需要进行如下配置。可参考 homebrew-bottles 进行相关配置。)
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"


# 定义常用变量(路径变量为主)
echo "Loading pre-defined variables..."
# wsl 用户: 统一将使用wsl的设备设置桌面的统一别名目录C:/desktop->$desktop,使用符号链接可以在不改动的情况下优雅的实现这一点
# New-Item -ItemType Junction  -Path C:/desktop -Target $home/desktop -Verbose -Force #powershell执行
_REPO_BASE="repos/scripts"
_WOO_DF_RELATIVE="wp/woocommerce/woo_df"
# SCRIPT_ROOT_SERVER="/$_REPO_BASE"
uploader_files="/srv/uploads/uploader/files"
# 定义scripts 仓库clone 的保存路径
SCRIPT_ROOT="$HOME/$_REPO_BASE" # 默认以家目录为基础路径
#普通linux系统（假设有 root 权限）：
# SCRIPT_ROOT_LINUX="/$_REPO_BASE"
# SCRIPT_ROOT_WSL="/mnt/c/$_REPO_BASE"
# SCRIPT_ROOT_MSYS="/c/$_REPO_BASE"
woo_df="$SCRIPT_ROOT/$_WOO_DF_RELATIVE"
pys="$woo_df/pys"

desktop="/mnt/c/Users/Administrator/Desktop"
# pythonpath
PYTHONPATH="$woo_df:$pys/bt_api:$pys/cf_api:$pys/spaceship_api"
# sh="$wslsh"
# 根据不同的系统环境为变量sh配置不同的取值

# 符号链接SH_SYM的TARGET：
SH_SCRIPT_DIR="$SCRIPT_ROOT/wp/woocommerce/woo_df/sh"
sh="$SH_SYM"
macos_sh="$sh/macos_sh"
# 按需创建sh短路径(对于msys平台,可能有脚本缓存问题(脚本更改不生效的情况),必要时可以删除短路径重建)
# echo "sh=[$SH_SYM]"
# [[ -L "$SH_SYM" ]] || ln -s -fv "$SH_SCRIPT_DIR" "$SH_SYM"  
# 导入适用于macos的环境变量
if [[ $OSTYPE == "darwin"* ]]; then
    . "$macos_sh/shell_vars_macos.sh"
fi
# 宝塔nginx配置文件路径
# vhost
bt_nginx_vhost_conf_home="/www/server/panel/vhost/nginx"
bt_nginx_conf_home="/www/server/nginx/conf"

# 将定义的变量声明为环境变量
export desktop sh macos_sh omb_themes \
    bt_nginx_vhost_conf_home \
    bt_nginx_conf_home uploader_files woo_df pys \
    SH_SYM SCRIPT_ROOT SH_SCRIPT_DIR PYTHONPATH
