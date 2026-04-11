#! /bin/bash
# START (安全起见且为了方便复制粘贴运行,为每行后面增加;号和一个空行)
# 参数解析 (支持-f(覆盖nginx主配置),-h(--help)参数)
SCRIPT_ROOT='/repos/scripts'
REPO_SOURCE="github.com"
SH_SYM="/www/sh"
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
            --script-root)
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

parse_args "$@"
# 如果目录存在，则执行删除
[[ -d "$SCRIPT_ROOT" ]] && {
    echo "Removing old dir..."
    sudo rm -rf "$SCRIPT_ROOT"
}

# rm /repos/scripts -rf ;
git clone --depth 1 "$REPO_URL" "$SCRIPT_ROOT"

# 配置更新代码的脚本的符号链接(bsd的ln命令不支持-T)
ln -s  $SH_SCRIPT_DIR "$SH_SYM" -fv

# 使用简短的更新代码仓库的命令(记得检查fail2ban)
# 如果追加使用-f会覆盖/www/server/nginx/conf/nginx.conf
# bash "$SH_SYM"/update_repos.sh -g
if [[ $OVERWRITE_NGINX_CONF == "true" ]]; then
    bash "$SH_SYM"/update_repos.sh -g -f
else
    bash "$SH_SYM"/update_repos.sh -g
fi

# 向bash,zsh配置文件导入常用的shell函数,比如wp命令行等
bash "$SH_SYM"/shellrc_addition.sh
# END
