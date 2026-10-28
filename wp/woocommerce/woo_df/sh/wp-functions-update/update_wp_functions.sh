#!/bin/bash
# 更新重点日志(todo):251204
# - 为参数WORKDIR提供接收单个或多个路径的支持,即允许指定1个或多个工作目录,默认为 /www/wwwroot,/wwwdata/wwwroot
# - 改进查找WordPress站点的逻辑,使用find命令提高灵活性
# - 新增 --dest-name 参数: 允许指定写入主题目录时使用的文件名或符号链接名,不必与源文件名同名
#   例如源文件为 /www/functions-a.php 时,仍可写入 <主题目录>/functions.php

# 用法说明
usage() {
    cat << EOF
用法: $0 [选项]

选项:
  -s, --src <源文件>        要写入主题目录的源文件,默认为 /www/functions.php
  -n, --dest-name <文件名>  写入主题目录时使用的文件名或符号链接名,默认为 functions.php
                            仅接受纯文件名(不含目录部分),例如源文件为 functions-a.php 时可指定为 functions.php
  -w, --workdir <目录>      网站根目录,多个目录用逗号分隔,默认为 /www/wwwroot,/wwwdata/wwwroot
  -u, --user <用户名>       仅处理指定用户名称(不要求系统上真实存在此用户)下的网站
  -m, --install-mode <模式> 安装模式: copy(复制,默认) 或 symlink(软链接)
  -d, --dry-run             预览操作,不实际执行
      --blacklist <文件>    黑名单文件(每行一个域名)
      --whitelist <文件>    白名单文件(每行一个域名,只操作这些域名)
      --log <日志文件>      日志文件
  -h, --help                显示本帮助并退出
EOF
    exit "${1:-1}"
}

die() {
    echo "$*" >&2
    exit 1
}

# 校验需要取值的选项,避免漏写取值时被误判为其它选项
require_arg() {
    [[ -n "${2:-}" ]] || die "参数 $1 缺少取值,可用 --help 查看用法"
}

# 目标文件名校验: 只允许纯文件名,避免被当成路径拼接到主题目录之外
validate_dest_name() {
    local name="$1"
    [[ -n "$name" ]] || die "目标文件名不能为空"
    [[ "$name" != */* ]] || die "目标文件名只能是纯文件名,不能包含目录部分: $name"
    [[ "$name" != "." && "$name" != ".." ]] || die "目标文件名不合法: $name"
}

# 参数解析
HOSTNAME=$(hostname)
SRC_FILE="/www/functions.php"
DEST_NAME="functions.php"
WORKDIR="/www/wwwroot,/wwwdata/wwwroot"
USER_NAME=""
INSTALL_MODE="copy"
DRY_RUN=false
BLACKLIST_FILE=""
WHITELIST_FILE=""
LOG_FILE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
    -s | --src)
        require_arg "$1" "${2:-}"
        SRC_FILE="$2"
        shift
        ;;
    -n | --dest-name)
        require_arg "$1" "${2:-}"
        DEST_NAME="$2"
        shift
        ;;
    -w | --workdir)
        require_arg "$1" "${2:-}"
        WORKDIR="$2"
        shift
        ;;
    -u | --user)
        require_arg "$1" "${2:-}"
        USER_NAME="$2"
        shift
        ;;
    -m | --install-mode)
        require_arg "$1" "${2:-}"
        INSTALL_MODE="$2"
        shift
        ;;
    -d | --dry-run) DRY_RUN=true ;;
    --blacklist)
        require_arg "$1" "${2:-}"
        BLACKLIST_FILE="$2"
        shift
        ;;
    --whitelist)
        require_arg "$1" "${2:-}"
        WHITELIST_FILE="$2"
        shift
        ;;
    --log)
        require_arg "$1" "${2:-}"
        LOG_FILE="$2"
        shift
        ;;
    -h | --help) usage 0 ;;
    *) usage ;;
    esac
    shift
done

if [[ ! -f "$SRC_FILE" ]]; then
    die "源文件不存在: $SRC_FILE"
fi

validate_dest_name "$DEST_NAME"

case $INSTALL_MODE in
copy | symlink) ;;
*) die "不支持的安装模式: $INSTALL_MODE(可选: copy, symlink)" ;;
esac

# 统一解析为绝对路径: symlink 模式下的软链接目标需为绝对路径,否则相对路径会相对主题目录解析而失效
if command -v realpath > /dev/null 2>&1; then
    RESOLVED_SRC=$(realpath -- "$SRC_FILE" 2> /dev/null)
    [[ -n "$RESOLVED_SRC" ]] && SRC_FILE="$RESOLVED_SRC"
elif command -v readlink > /dev/null 2>&1; then
    RESOLVED_SRC=$(readlink -f -- "$SRC_FILE" 2> /dev/null)
    [[ -n "$RESOLVED_SRC" ]] && SRC_FILE="$RESOLVED_SRC"
fi

# 读取黑白名单
BLACKLIST=()
WHITELIST=()
if [[ -n "$WHITELIST_FILE" && -n "$BLACKLIST_FILE" ]]; then
    die "不能同时指定白名单和黑名单！"
fi
if [[ -n "$BLACKLIST_FILE" ]]; then
    [[ -f "$BLACKLIST_FILE" ]] || {
        die "黑名单文件不存在: $BLACKLIST_FILE"
    }
    mapfile -t BLACKLIST < "$BLACKLIST_FILE"
fi
if [[ -n "$WHITELIST_FILE" ]]; then
    [[ -f "$WHITELIST_FILE" ]] || {
        die "白名单文件不存在: $WHITELIST_FILE"
    }
    mapfile -t WHITELIST < "$WHITELIST_FILE"
fi
# 集中对黑白名单中的域名进行规范化,避免后续判断函数中反复执行这部分规范化,提高性能(全部小写处理,去除域名后缀,例如: Domain.com -> domain)
BLACKLIST=("${BLACKLIST[@],,}")
BLACKLIST=("${BLACKLIST[@]%.*}")

WHITELIST=("${WHITELIST[@],,}")
WHITELIST=("${WHITELIST[@]%.*}")

is_blacklisted() {
    local domain="$1"
    domain="${domain,,}"
    domain="${domain%.*}"
    for b in "${BLACKLIST[@]}"; do [[ "${domain}" == "${b}" ]] && return 0; done
    return 1
}
is_whitelisted() {
    local domain="$1"
    domain="${domain,,}"
    domain="${domain%.*}"
    for w in "${WHITELIST[@]}"; do [[ "${domain}" == "${w}" ]] && return 0; done
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
        done < <(find -L "$dir/$USER_NAME" -type d -maxdepth 2 -name wordpress 2> /dev/null)
    else
        while IFS= read -r site; do
            SITE_PATHS+=("$site")
        done < <(find -L "$dir" -type d -maxdepth 3 -name wordpress 2> /dev/null)
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
    [[ -d "$THEME_DIR" ]] || {
        log_action "主题目录不存在: $THEME_DIR"
        continue
    }
    for theme in "$THEME_DIR"/*; do
        [[ -d "$theme" ]] || continue
        # 目标名由 --dest-name 指定,默认 functions.php,可与源文件名不同
        TARGET="$theme/$DEST_NAME"
        if $DRY_RUN; then
            log_action "[DRY RUN] 将写入 $SRC_FILE 到 $TARGET($INSTALL_MODE)"
        else
            if [[ $INSTALL_MODE = "copy" ]]; then
                # 先删除既有目标(含指向其它文件的软链接),避免 cp 透过软链接改写其指向的文件
                rm -f -- "$TARGET"
                if cp -f -- "$SRC_FILE" "$TARGET"; then
                    log_action "已覆盖 $SRC_FILE 到 $TARGET"
                else
                    log_action "覆盖失败: $TARGET"
                fi
            elif [[ $INSTALL_MODE = "symlink" ]]; then
                if ln -sfn -- "$SRC_FILE" "$TARGET"; then
                    log_action "已强制创建软链接 $SRC_FILE 到 $TARGET"
                else
                    log_action "创建软链接失败: $TARGET"
                fi
            fi
        fi
    done
done

if [[ $DRY_RUN == "true" ]]; then
    log_action "Dry run 完成，未做任何更改。"
else
    log_action "操作已完成。"
fi
