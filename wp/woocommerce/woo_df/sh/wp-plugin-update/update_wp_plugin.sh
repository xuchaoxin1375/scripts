#!/bin/bash

# 显示脚本用法
usage() {
    echo "用法: $0 [--source <插件目录>] [--remove <插件名1,插件名2,...>] [--user <用户名>] [--workdir <工作目录>] [--dry-run] [--blacklist <黑名单文件>] [--whitelist <白名单文件>] [--log <日志文件>]"
    echo "参数说明："
    echo "  --source <插件目录>      要覆盖的插件目录"
    echo "  --remove <插件名列表>    要移除的插件名，多个用逗号分隔"
    echo "  --user <用户名>          WordPress 站点所属用户名（可选，不指定则处理所有用户）"
    echo "  --workdir <工作目录>     网站根工作目录，默认为 /www/wwwroot"
    echo "  --plugin-type           插件类型(如果是must类型,则将被处理的插件视为强制执行插件),放到wp-content目录下;默认为common类型,普通插件,放到wp-content/plugins目录下"
    echo "  --dry-run                预览操作，不实际执行"
    echo "  --blacklist <文件>       指定黑名单文件（每行一个域名）"
    echo "  --whitelist <文件>       指定白名单文件（每行一个域名，只操作这些域名）"
    echo "  --log <日志文件>         指定日志文件保存操作日志"
    exit 1
}

# 解析命令行参数
SOURCE_DIR=""
REMOVE_PLUGINS=""
USER_NAME=""
WORKDIR="/www/wwwroot"
DRY_RUN=false
COMMON_PLUGINS_HOME="wp-content/plugins"
MUST_PLUGINS_HOME="wp-content"
BLACKLIST_FILE=""
WHITELIST_FILE=""
LOG_FILE=""

PLUGIN_TYPE="common"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --source) SOURCE_DIR="$2"; shift ;;
        --remove) REMOVE_PLUGINS="$2"; shift ;;
        --user) USER_NAME="$2"; shift ;;
        --workdir) WORKDIR="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --blacklist) BLACKLIST_FILE="$2"; shift ;;
        --whitelist) WHITELIST_FILE="$2"; shift ;;
        --plugin-type)
            if [[ "$2" == "must" ]]; then
                PLUGIN_TYPE="must"
            else
                PLUGIN_TYPE="common"
            fi
            shift
            ;;
        --log) LOG_FILE="$2"; shift ;;
        *) usage ;;
    esac
    shift
done

if [[ -z "$SOURCE_DIR" && -z "$REMOVE_PLUGINS" ]]; then
    usage
fi

# 读取黑名单或白名单文件到数组
BLACKLIST=()
WHITELIST=()
if [[ -n "$WHITELIST_FILE" && -n "$BLACKLIST_FILE" ]]; then
    echo "不能同时指定白名单和黑名单！"
    exit 1
fi
if [[ -n "$BLACKLIST_FILE" ]]; then
    if [[ ! -f "$BLACKLIST_FILE" ]]; then
        echo "黑名单文件不存在: $BLACKLIST_FILE"
        exit 1
    fi
    mapfile -t BLACKLIST < "$BLACKLIST_FILE"
fi
if [[ -n "$WHITELIST_FILE" ]]; then
    if [[ ! -f "$WHITELIST_FILE" ]]; then
        echo "白名单文件不存在: $WHITELIST_FILE"
        exit 1
    fi
    mapfile -t WHITELIST < "$WHITELIST_FILE"
fi

# 判断域名是否在黑名单
is_blacklisted() {
    local domain="$1"
    for blacklisted in "${BLACKLIST[@]}"; do
        if [[ "$domain" == "$blacklisted" ]]; then
            return 0
        fi
    done
    return 1
}

# 判断域名是否在白名单
is_whitelisted() {
    local domain="$1"
    for whitelisted in "${WHITELIST[@]}"; do
        if [[ "$domain" == "$whitelisted" ]]; then
            return 0
        fi
    done
    return 1
}


# 记录日志函数
log_action() {
    local msg="$1"
    echo "$msg"
    if [[ -n "$LOG_FILE" ]]; then
        echo "$msg" >> "$LOG_FILE"
    fi
}

# 查找所有 WordPress 站点目录
if [[ -n "$USER_NAME" ]]; then
    SITE_PATHS="$WORKDIR/${USER_NAME}/*/wordpress"
else
    SITE_PATHS="$WORKDIR/*/*/wordpress"
fi

for site in $SITE_PATHS; do
    # 检查目录是否存在
    if [[ ! -d "$site" ]]; then
        continue
    fi

    # 获取域名（父目录名）
    DOMAIN=$(basename "$(dirname "$site")")

    # 白名单优先，只处理白名单中的域名
    if [[ -n "$WHITELIST_FILE" ]]; then
        if ! is_whitelisted "$DOMAIN"; then
            log_action "跳过未在白名单中的域名: $DOMAIN"
            continue
        fi
    # 黑名单模式，跳过黑名单中的域名
    elif [[ -n "$BLACKLIST_FILE" ]]; then
        if is_blacklisted "$DOMAIN"; then
            log_action "跳过黑名单域名: $DOMAIN"
            continue
        fi
    fi

    # 覆盖插件模式
    if [[ -n "$SOURCE_DIR" ]]; then
        PLUGIN_BASENAME="$(basename "$SOURCE_DIR")"
        if [[ "$PLUGIN_TYPE" == "must" ]]; then
            TARGET_DIR="$site/$MUST_PLUGINS_HOME/$PLUGIN_BASENAME"
            # 确保 mu-plugins 目录存在
            if ! $DRY_RUN; then
                mkdir -p "$site/$MUST_PLUGINS_HOME"
            fi
            TYPE_DESC="(must-use plugin)"
        else
            TARGET_DIR="$site/$COMMON_PLUGINS_HOME/$PLUGIN_BASENAME"
            TYPE_DESC="(common plugin)"
        fi
        if $DRY_RUN; then
            log_action "[DRY RUN] 将覆盖 $SOURCE_DIR 到 $TARGET_DIR $TYPE_DESC"
        else
            if [[ -e "$TARGET_DIR" ]]; then
                log_action "删除已存在: $TARGET_DIR"
                rm -rf "$TARGET_DIR"
            fi
            log_action "覆盖 $SOURCE_DIR 到 $TARGET_DIR $TYPE_DESC"
            cp -r "$SOURCE_DIR" "$TARGET_DIR"
        fi
    fi

    # 移除插件模式
    if [[ -n "$REMOVE_PLUGINS" ]]; then
        IFS=',' read -ra PLUGIN_LIST <<< "$REMOVE_PLUGINS"
        for plugin in "${PLUGIN_LIST[@]}"; do
            REMOVE_DIR="$site/$COMMON_PLUGINS_HOME/$plugin"
            if [[ -d "$REMOVE_DIR" ]]; then
                if $DRY_RUN; then
                    log_action "[DRY RUN] 将移除插件目录: $REMOVE_DIR"
                else
                    log_action "移除插件目录: $REMOVE_DIR"
                    rm -rf "$REMOVE_DIR"
                fi
            else
                log_action "插件目录不存在，无需移除: $REMOVE_DIR"
            fi
        done
    fi
done

if $DRY_RUN; then
    log_action "Dry run 完成，未做任何更改。"
else
    log_action "操作已完成。"
fi