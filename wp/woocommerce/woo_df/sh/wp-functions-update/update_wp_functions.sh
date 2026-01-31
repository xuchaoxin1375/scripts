#!/bin/bash
# 更新重点日志(todo):251204
# 1.为参数WORKDIR提供接收单个或多个路径的支持,即允许指定1个或多个工作目录,默认为 /www/wwwroot,/wwwdata/wwwroot
# 2.改进查找WordPress站点的逻辑,使用find命令提高灵活性
# 用法说明
usage() {
    echo "用法: $0 [--src <源文件>] [--workdir <工作目录>] [--user <用户名>] [--dry-run] [--blacklist <黑名单文件>] [--whitelist <白名单文件>] [--log <日志文件>]"
    echo "参数说明："
    echo "  --src <源文件>           要覆盖/补充的 functions.php 文件，默认为 /www/wwwroot/functions.php"
    echo "  --workdir <工作目录>     网站根目录,可指定多个" #(改进此参数及其使用逻辑)
    echo "  --user <用户名>          仅处理指定用户名称(不要求系统上真实存在此用户)下的网站"
    echo "  --dry-run                预览操作，不实际执行"
    echo "  --install-mode           指定安装模式(copy,symlink)"
    echo "  --blacklist <文件>       黑名单文件（每行一个域名）"
    echo "  --whitelist <文件>       白名单文件（每行一个域名，只操作这些域名）"
    echo "  --log <日志文件>         日志文件"
    exit 1
}

# 参数解析
HOSTNAME=$(hostname)
SRC_FILE="/www/functions.php"
WORKDIR="/www/wwwroot,/wwwdata/wwwroot"
USER_NAME=""
INSTALL_MODE="copy"
DRY_RUN=false
BLACKLIST_FILE=""
WHITELIST_FILE=""
LOG_FILE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --src) SRC_FILE="$2"; shift ;;
        --workdir) WORKDIR="$2"; shift ;;
        --user) USER_NAME="$2"; shift ;;
        --install-mode) INSTALL_MODE="$2"; shift ;;
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
    # local msg="$*"
    local msg="[$HOSTNAME] $*"
    echo "$msg"
    # 根据需要写入到日志文件中.
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
# 老版本wordpress站路径匹配
# if [[ -n "$USER_NAME" ]]; then
#     SITE_PATHS="$WORKDIR/${USER_NAME}/*/wordpress"
# else
#     SITE_PATHS="$WORKDIR/*/*/wordpress"
# fi

# 使用find命令查找所有 WordPress 站点

# 支持多个WORKDIR路径，逗号分隔
IFS=',' read -ra WORKDIRS <<< "$WORKDIR"
SITE_PATHS=()
for dir in "${WORKDIRS[@]}"; do
    # 若指定USER_NAME，则只查找该用户目录下的wordpress
    if [[ -n "$USER_NAME" ]]; then
        while IFS= read -r site; do
            SITE_PATHS+=("$site")
        done < <(find "$dir/$USER_NAME" -type d -maxdepth 2  -name wordpress 2>/dev/null)
    else
        while IFS= read -r site; do
            SITE_PATHS+=("$site")
        done < <(find "$dir" -type d -maxdepth 3 -name wordpress  2>/dev/null)
    fi
done

for site in "${SITE_PATHS[@]}"; do
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
            if [[ $INSTALL_MODE = "copy" ]]; then
                [[ -f "$TARGET" ]] && rm -f "$TARGET"
                if cp -f "$SRC_FILE" "$TARGET"; then
                    log_action "已覆盖 $SRC_FILE 到 $TARGET"
                else
                    log_action "覆盖失败: $TARGET"
                fi
            elif [[ $INSTALL_MODE = "symlink" ]]; then 
                if ln -sf "$SRC_FILE" "$TARGET"; then
                    log_action "已强制创建软链接 $SRC_FILE 到 $TARGET"
                else
                    log_action "创建软链接失败: $TARGET"
                fi
            fi
        fi
    done
done

$DRY_RUN && log_action "Dry run 完成，未做任何更改。" || log_action "操作已完成。"