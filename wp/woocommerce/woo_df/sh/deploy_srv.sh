#! /bin/bash
# 适用于服务器(有root权限的情况),有许多针对服务器软件的配置,因此不建议用于个人电脑
# 注意:执行此代码会覆盖掉原来的代码仓库(内容会被移除),因此执行前确保指定的代码仓库目录中自定义的文件或脚本已经备份好(例如一些定时执行的脚本)!
# 此脚本先clone相应代码仓库,然后调用仓库中的update_repos.sh脚本部署环境;
# 参数解析 (支持-f(覆盖nginx主配置),-h(--help)参数)
# 
# 部署到服务器:
# bash <(curl -SfL https://github.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/deploy_srv.sh) # 参数自行选用,通过 -h 获取帮助.
SCRIPT_ROOT="$HOME/repos/scripts"
REPO_SOURCE="github.com"
SH_SYM="/www/sh" # 假设服务器上有root权限,并能够创建/www/sh 目录
SH_SYM_HOME="$HOME/sh"
OVERWRITE_NGINX_CONF=false
UPDATE_CONFIG_FORCE=false
REAL_CDN_IP="cf" # 非默认模式将被记为all

# 确保目录SH_SYM存在
mkdir -pv /www/sh

show_help() {
    cat << EOF
    Usage: $0 [-f] [ -h,--help]
    Options
    -g      按照宝塔的nginx目录创建服务软件相关配置文件到相关目录中.(nginx,fail2ban等)
    -f      覆盖nginx主配置(默认情况下仅部署代码仓库,添加一些配置文件,但是不会覆盖主nginx.conf)
    -F      同时启用 -g,-f
    -R, --real_cdn_ip    使用非默认的客户ip解析.
    -h,--help       显示帮助
EOF
    # exit 0
}
parse_args() {

    while [ $# -gt 0 ]; do
        case "$1" in
            -g)
                UPDATE_CONFIG=true
                ;;
            -f)
                OVERWRITE_NGINX_CONF=true
                ;;
            -F)
                UPDATE_CONFIG_FORCE=true
                ;;
            -h | --help)
                show_help
                exit 0
                ;;
            -r | --source)
                REPO_SOURCE="$2"
                shift
                ;;
            -R | --real_cdn_ip)
                REAL_CDN_IP="all"
                # log "已启用使用非默认客户IP解析的选项"
                shift
                ;;
            -s | --script-root)
                SCRIPT_ROOT="$2"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_help >&2
                exit 1
                ;;
        esac
        shift
    done
}
parse_args "$@"

[[ $UPDATE_CONFIG_FORCE ]] && {
    UPDATE_CONFIG=true
    OVERWRITE_NGINX_CONF=true
}

# 根据解析的参数定义关键变量(定义在参数解析语句之后!)
SH_SCRIPT_DIR="$SCRIPT_ROOT/wp/woocommerce/woo_df/sh"
REPO_URL="https://$REPO_SOURCE/xuchaoxin1375/scripts.git"

# 确保scrits仓库父目录(repos)存在(纯shell计算父目录)
repos_dir="${SCRIPT_ROOT%/}"
repos_dir="${repos_dir%/*}"
# echo $repos_dir
mkdir -p -v "$repos_dir"

# 如果指定仓库目录已经存在，则执行删除
[[ -d "$SCRIPT_ROOT" ]] && {
    echo "覆盖旧目录..."
    echo "Removing old dir..."
    # 执行删除前询问用户是否继续(确保仓库目录中的没有自定义文件,如果有已经备份好,或者退出执行并先将原目录重命名备份后继续.)
    # sudo rm -rf "$SCRIPT_ROOT"
    # =====================================================================
    # 执行删除前询问用户是否继续
    # (确保仓库目录中没有自定义文件，或者已经备份好)
    # =====================================================================

    # 1. 检查目标目录是否存在，如果不存在则无需删除
    if [ -d "$SCRIPT_ROOT" ]; then
        # 使用 Heredoc 打印提示信息
        cat << EOF
⚠️  警告: 即将删除目录: [$SCRIPT_ROOT]
请确保该目录中没有自定义文件，或者重要数据已经备份！
--------------------------------------------------
请选择操作 [1/2/3]:
 1) 确认无误，直接删除
 2) 先将原目录重命名备份 (加上 .bak 后缀)，然后继续
 3) 终止执行 (默认)
--------------------------------------------------
EOF

        # 读取用户输入
        read -rp "请输入选项序号: " USER_CHOICE

        case "$USER_CHOICE" in
            1)
                echo "正在删除原目录..."
                sudo rm -rf "$SCRIPT_ROOT"
                ;;
            2)
                # 获取当前时间戳防止备份文件名冲突，形如 SCRIPT_ROOT_20260603_0538
                BACKUP_PATH="${SCRIPT_ROOT}_bak_$(date +%Y%m%d_%H%M%S)"
                echo "正在备份: $SCRIPT_ROOT -> $BACKUP_PATH"
                sudo mv "$SCRIPT_ROOT" "$BACKUP_PATH"
                ;;
            *)
                echo "❌ 操作已取消，脚本退出。"
                exit 1
                ;;
        esac
    else
        echo "目录 $SCRIPT_ROOT 尚不存在，跳过清除步骤..."
    fi
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
    ln -snfv "$target" "$sym_path" || {
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
[[ $UPDATE_CONFIG == true ]] && params=("-g")
if [[ $OVERWRITE_NGINX_CONF == "true" ]]; then
    params+=("-f")
fi
if [[ $REAL_CDN_IP == "all" ]]; then
    params+=("-R")
fi

# 开发(维护)者注意:这里的代码是云端克隆的,如果本地的版本修改后没立即推送云端,那么后续update_repos.sh的代码会是滞后的(旧版本)
bash "$SH_SYM"/update_repos.sh "${params[@]}"

# 向bash,zsh配置文件导入常用的shell函数,比如wp命令行等
bash "$SH_SYM"/shellrc_addition.sh && exec bash
# END
