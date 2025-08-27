#!/bin/bash

# 用法说明
usage() {
    echo "用法: $0 [--src <源文件>] [--workdir <工作目录>] [--user <用户名>] [--dry-run] [--blacklist <黑名单文件>] [--whitelist <白名单文件>] [--log <日志文件>]"
    echo "参数说明："
    echo "  --src <源文件>           要覆盖/补充的 functions.php 文件，默认为 /www/wwwroot/functions.php"
    echo "  --workdir <工作目录>     网站根目录，默认为 /www/wwwroot"
    echo "  --user <用户名>          仅处理指定用户名下的网站"
    echo "  --dry-run                预览操作，不实际执行"
    echo "  --blacklist <文件>       黑名单文件（每行一个域名）"
    echo "  --whitelist <文件>       白名单文件（每行一个域名，只操作这些域名）"
    echo "  --log <日志文件>         日志文件"
    exit 1
}

# 参数解析
SRC_FILE="/www/wwwroot/functions.php"
WORKDIR="/www/wwwroot"
USER_NAME=""
DRY_RUN=false
BLACKLIST_FILE=""
WHITELIST_FILE=""
LOG_FILE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --src) SRC_FILE="$2"; shift ;;
        --workdir) WORKDIR="$2"; shift ;;
        --user) USER_NAME="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --blacklist) BLACKLIST_FILE="$2"; shift ;;
        --whitelist) WHITELIST_FILE="$2"; shift ;;
        --log) LOG_FILE="$2"; shift ;;
        *) usage ;;
    esac
    shift
done

if [[ ! -f "$SRC_FILE" ]]; then
    echo "源文件不存在: $SRC_FILE"
    exit 1
fi

# 读取黑白名单
BLACKLIST=()
WHITELIST=()
if [[ -n "$WHITELIST_FILE" && -n "$BLACKLIST_FILE" ]]; then
    echo "不能同时指定白名单和黑名单！"
    exit 1
fi
if [[ -n "$BLACKLIST_FILE" ]]; then
    [[ -f "$BLACKLIST_FILE" ]] || { echo "黑名单文件不存在: $BLACKLIST_FILE"; exit 1; }
    mapfile -t BLACKLIST < "$BLACKLIST_FILE"
fi
if [[ -n "$WHITELIST_FILE" ]]; then
    [[ -f "$WHITELIST_FILE" ]] || { echo "白名单文件不存在: $WHITELIST_FILE"; exit 1; }
    mapfile -t WHITELIST < "$WHITELIST_FILE"
fi

is_blacklisted() {
    local domain="$1"
    for b in "${BLACKLIST[@]}"; do [[ "$domain" == "$b" ]] && return 0; done
    return 1
}
is_whitelisted() {
    local domain="$1"
    for w in "${WHITELIST[@]}"; do [[ "$domain" == "$w" ]] && return 0; done
    return 1
}
log_action() {
    local msg="$1"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

# 查找所有 WordPress 站点
if [[ -n "$USER_NAME" ]]; then
    SITE_PATHS="$WORKDIR/${USER_NAME}/*/wordpress"
else
    SITE_PATHS="$WORKDIR/*/*/wordpress"
fi

for site in $SITE_PATHS; do
    [[ -d "$site" ]] || continue
    DOMAIN=$(basename "$(dirname "$site")")
    # 白名单优先
    if [[ -n "$WHITELIST_FILE" ]] && ! is_whitelisted "$DOMAIN"; then
        log_action "跳过未在白名单中的域名: $DOMAIN"
        continue
    elif [[ -n "$BLACKLIST_FILE" ]] && is_blacklisted "$DOMAIN"; then
        log_action "跳过黑名单域名: $DOMAIN"
        continue
    fi

    THEME_DIR="$site/wp-content/themes"
    [[ -d "$THEME_DIR" ]] || { log_action "主题目录不存在: $THEME_DIR"; continue; }
    for theme in "$THEME_DIR"/*; do
        [[ -d "$theme" ]] || continue
        TARGET="$theme/functions.php"
        if $DRY_RUN; then
            log_action "[DRY RUN] 将覆盖 $SRC_FILE 到 $TARGET"
        else
            if cp -f "$SRC_FILE" "$TARGET"; then
                log_action "已覆盖 $SRC_FILE 到 $TARGET"
            else
                log_action "覆盖失败: $TARGET"
            fi
        fi
    done
done

$DRY_RUN && log_action "Dry run 完成，未做任何更改。" || log_action "操作已完成。"