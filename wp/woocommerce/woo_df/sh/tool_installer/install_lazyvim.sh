#! /usr/bin/env bash
# 安装依赖:https://www.lazyvim.org/
# 1.允许单独执行neovim的安装操作
# 2.允许指定是否使用github镜像
# 建议安装后运行 :LazyHealth 命令。这将加载所有插件并检查一切是否正常运行。
# neovim安装最新版
# 如果有brew可用,则使用brew安装
# 考虑到服务器上可能直接就是root用户,需要包装一下brew命令而不是直接用原本的brew命令

# 参数解析
args_pos=()
parse_args() {
    usage="
    安装lazevim;
    如果neovim尚未安装或者版本过旧,考虑运行:
    bash ~/sh/tool_installer/install_neovim.sh
    
    或在线安装脚本(选择合适的参数运行,-h可以提供帮助)
    bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/tool_installer/install_neovim.sh) 
    
    "
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            
            --)
                shift
                break 
                ;;
            -?*)
                echo "Unknown option:$1" >&2 #输出错误信息到标准错误
                echo "$usage" >&2
                exit 2 #直接退出脚本
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    # 参数解析并调整完毕
}
parse_args "$@"
set -- "${args_pos[@]}"

# 检查neovim要求,如果尚未安装,则报错并退出(为了控制脚本规模,这里不内置安装neovim的代码)
# 考虑使用专门的neovim安装脚本.
if ! command -v nvim &> /dev/null; then
    echo "Neovim is not installed. Please install it first."
    exit 1
fi

# 参考文档:https://www.lazyvim.org/
# 快捷键:https://www.lazyvim.org/keymaps
# required
test -e ~/.config/nvim &&
    mv ~/.config/nvim{,.bak}

# optional but recommended
{
    mv ~/.local/share/nvim{,.bak}
    mv ~/.local/state/nvim{,.bak}
    mv ~/.cache/nvim{,.bak}
} &> /dev/null
github_mirror="https://gh-proxy.com/"
# 建议使用github镜像加速或国内代码仓库托管平台代替(脚本下载+仓库clone,注意第二阶段的clone加速设置)
git clone "$github_mirror"https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git
nvim
