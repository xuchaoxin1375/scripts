#! /bin/bash
# 适用于服务器(有root权限的情况),有许多针对服务器软件的配置,因此不建议用于个人电脑
# 注意:执行此代码会覆盖掉原来的代码仓库,因此执行前确保指定的代码仓库目录中自定义的文件或脚本已经备份好(例如一些定时执行的脚本)!
# 此脚本先clone相应代码仓库,然后调用仓库中的update_repos.sh脚本部署环境;
# 参数解析 (支持-f(覆盖nginx主配置),-h(--help)参数)
SCRIPT_ROOT="$HOME/repos/scripts"
REPO_SOURCE="github.com"
SH_SYM="/www/sh" # 假设服务器上有root权限,并能够创建/www/sh 目录
SH_SYM_HOME="$HOME/sh"
OVERWRITE_NGINX_CONF=false
parse_args() {

    while [ $# -gt 0 ]; do
        case "$1" in
            -f)
                OVERWRITE_NGINX_CONF=true
                ;;
            -h | --help)
                show_help
                exit 0
                ;;
            -r | --source)
                REPO_SOURCE="$2"
                shift
                ;;
            -s | --script-root)
                SCRIPT_ROOT="$2"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
}
parse_args "$@"

# 根据解析的参数定义关键变量(定义在参数解析语句之后!)
SH_SCRIPT_DIR="$SCRIPT_ROOT/wp/woocommerce/woo_df/sh"
REPO_URL="https://$REPO_SOURCE/xuchaoxin1375/scripts.git"

show_help() {
    cat << EOF
    Usage: $0 [-f] [ -h,--help]
    Options
    -f      覆盖nginx主配置(默认情况下仅部署代码仓库,添加一些配置文件,但是不会覆盖主nginx.conf)
    -h,--help       显示帮助
EOF
    # exit 0
}

# 确保scrits仓库父目录(repos)存在(纯shell计算父目录)
repos_dir="${SCRIPT_ROOT%/}"
repos_dir="${repos_dir%/*}"
# echo $repos_dir
mkdir -p -v "$repos_dir"

# 如果指定仓库目录已经存在，则执行删除
[[ -d "$SCRIPT_ROOT" ]] && {
    echo "覆盖旧目录..."
    echo "Removing old dir..."
    sudo rm -rf "$SCRIPT_ROOT"
}
# 进行全新的干净clone
git clone --depth 1 "$REPO_URL" "$SCRIPT_ROOT"
# 覆盖式创建指定路径的符号链接(兼容gnu ln和bsd ln)
# 效果在路径sym_path创建指向target的符号链接(如果sym_path已存在(无论是什么类型文件或目录)，则覆盖)
ln_update_sym() {
    local target="$1"
    local sym_path="$2"
    [[ -e $sym_path ]] && rm -rf "$sym_path"
    # 单纯使用-nf仍然和gnu ln的 -T选项效果有差别
    ln -snfv "$target" "$sym_path" ||{
        echo "[error]:创建符号链接[$sym_path]->[$target] 失败" >&2
        exit 1
    }
}
# 配置更新代码的脚本的符号链接(bsd的ln命令不支持-T)
ln_update_sym "$SH_SCRIPT_DIR" "$SH_SYM"
ln_update_sym "$SH_SCRIPT_DIR" "$SH_SYM_HOME"
# 家目录也放置一份符号链接


# 使用简短的更新代码仓库的命令(记得检查fail2ban)
# 如果追加使用-f会覆盖/www/server/nginx/conf/nginx.conf
# bash "$SH_SYM"/update_repos.sh -g
if [[ $OVERWRITE_NGINX_CONF == "true" ]]; then
    bash "$SH_SYM"/update_repos.sh -g -f
else
    bash "$SH_SYM"/update_repos.sh -g
fi

# 向bash,zsh配置文件导入常用的shell函数,比如wp命令行等
bash "$SH_SYM"/shellrc_addition.sh && exec bash
# END
