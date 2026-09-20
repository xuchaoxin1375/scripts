#!/usr/bin/env bash
# 一键清理/取消部署反向代理配置,防止不同脚本残留文件冲突.
#
# 覆盖范围(默认路径,可用 -c/-d/--tenants-dir 改):
#   base.sh -G simple : $NGINX_CONFD/reverse_to_a.conf
#   base.sh -G hostmap: $NGINX_CONFD/gateway.conf
#                       $NGINX_CONF_HOME/gateway/snippets/
#                       $NGINX_CONF_HOME/gateway/maps/routes.map.conf
#                       $NGINX_CONF_HOME/gateway/proxy-pass-mode
#   multi.sh          : $NGINX_CONFD/reverse_multi_ip.conf (可用 --conf-name 指定自定义名)
#   tenants.sh        : $NGINX_CONFD/tenant-common.conf
#                       $NGINX_CONFD/tenant-hostmap.conf
#                       $NGINX_CONFD/tenant-server.conf
#                       $NGINX_CONF_HOME/tenants/<id>/routes.map
#                       $NGINX_CONF_HOME/tenants/proxy-pass-mode
#                       旧版编号: 10-common-map.conf / 20-tenant-maps.conf / 30-tenant-gateways.conf
#                       $NGINX_CONF_HOME/nginx.conf 中 tenants.sh 插入的 map_hash 块(带标记才回退)
#   三者公共副作用   : $NGINX_CONFD/cf-realip.conf, cf-ips-v4/v6.txt (默认保留,加 --with-cf 才删)
#                       $NGINX_CONF_HOME/update_cf_ip_configs.sh (默认保留,加 --with-helper 才删)
#                       $NGINX_CONF_HOME/log -> $NGINX_LOG_DIR 软链接(默认保留,加 --with-symlink 才删)
#                       日志文件 (默认保留,加 --with-logs 才删)
#
# 设计原则:
#   1. 默认只删 D(被 include 目录)里的冲突源,保留用户 map 数据/CF/helper/日志,切换模式最安全.
#   2. 彻底下线再加 --purge-data / --with-cf / --with-helper / --with-symlink / --with-logs.
#   3. 先备份再删,删完 nginx -t,显式 --reload 才 reload(默认只 test 不 reload,避免误操作).
#
# 示例:
#   # 只看现状,不删:
#   bash clean.sh --status
#   bash clean.sh --dry-run
#   # 切换模式前(标准路径):清掉所有 D 侧冲突文件,保留 map 数据:
#   bash clean.sh --mode all --force
#   # 彻底下线(含用户 map 数据):
#   bash clean.sh --mode all --purge-data --force
#   # 宝塔路径:
#   bash clean.sh -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ --mode all --force
#   # 只清 tenants 的某一个租户(不碰共享 conf,删后需手工从 tenant-hostmap/server 中摘掉该租户并 reload):
#   bash clean.sh --mode tenants --tenant a --force
#   # 在线拉取执行:
#   bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/nginx_conf/reverse_proxy/scripts/clean.sh) --status
#
# 详细说明见 docs/clean@清理说明.md

set -Eeuo pipefail

VERSION="20260920.01"

NGINX_CONF_HOME="/etc/nginx"
NGINX_CONFD=""
NGINX_CONFD_EXPLICIT=false
NGINX_LOG_DIR="/var/log/nginx/"
TENANTS_DIR=""

MODES=()
CONF_NAMES=()
ONLY_TENANTS=()
STATUS_ONLY=false
DRY_RUN=false
FORCE=false
NO_BACKUP=false
BACKUP_DIR=""
NO_TEST=false
RELOAD=false
PURGE_DATA=false
WITH_CF=false
WITH_HELPER=false
WITH_SYMLINK=false
WITH_LOGS=false
NO_NGINX_CONF=false

usage() {
    cat << EOF
清理反向代理残留配置,防止 base/multi/tenants 切换冲突. [version:$VERSION]

Usage:
    $0 [options]

Paths:
    -c, --nginx-conf-dir <dir>   nginx 配置家目录. 默认 /etc/nginx,宝塔 /www/server/nginx/conf
    -d, --nginx-confd-vhost <dir> 被 include 的目录. 默认 \$NGINX_CONF_HOME/conf.d,宝塔 /www/server/panel/vhost/nginx
    -l, --log-dir <dir>          日志目录. 默认 /var/log/nginx/,宝塔 /www/logs/
    --tenants-dir <dir>          租户根目录. 默认 \$NGINX_CONF_HOME/tenants

Scope:
    -m, --mode <mode>            清理范围,可重复或逗号分隔. 默认 all.
                                 simple | hostmap | multi | tenants | all
    --conf-name <name>           multi 生成的自定义文件名,可重复. 默认 reverse_multi_ip.conf
    --tenant <id>                仅裁剪 tenants 下该租户的数据目录,可重复.
                                 单租户模式下不碰 D 侧共享 conf 与 nginx.conf.
                                 不传则处理整个 tenants 范围.
    --purge-data                 连用户 map 数据一起删(C/gateway, C/tenants).
                                 默认只删 D 侧 conf,保留 map 数据.
    --with-cf                    另删 D/cf-realip.conf, cf-ips-v4/v6.txt (含下划线旧名兼容)
    --with-helper                另删 C/update_cf_ip_configs.sh
    --with-symlink               另删 C/log 软链接(仅当它指向 -l 时才删)
    --with-logs                  另删 L 下 b_to_a*/b*_to_a*/tenant-* 日志(不碰 access/error.log)
    --no-nginx-conf              跳过 nginx.conf 中 tenants map_hash 块回退

Safety:
    --status                     只检测现状并退出,不删任何文件
    --dry-run                    只预览将要删除/回退的内容,不写盘
    --force, --yes               跳过交互确认直接执行(默认会确认)
    --no-backup                  不备份(默认自动备份到 --backup-dir)
    --backup-dir <dir>           备份目录. 默认 /root/nginx-reverse-backup/<时间>,无权限时落 /tmp
    --no-test                    跳过 nginx -t (默认只要有 nginx 就测)
    --reload                     测过之后再 nginx -s reload (默认不 reload,只 test)

Examples:
    $0 --status
    $0 --dry-run
    $0 --mode all --force
    $0 -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ --mode all --force
    $0 --mode tenants --tenant a --force
    $0 --mode all --purge-data --with-cf --force --reload
EOF
}

die() { echo "[Error][$0]: $*" >&2; exit 1; }
info() { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }

trim() {
    local s="$*"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

normalize_dir_slash() {
    local dir="$1"
    [[ -n "$dir" ]] || return 0
    dir="${dir%/}/"
    printf '%s' "$dir"
}

add_mode_arg() {
    local arg="$1" part=""
    local IFS=','
    local -a parts
    read -r -a parts <<< "$arg"
    for part in "${parts[@]}"; do
        part="$(trim "$part")"
        [[ -n "$part" ]] || continue
        case "$part" in
            simple | hostmap | multi | tenants | all) MODES+=("$part") ;;
            *) die "未知 --mode: [$part], 可选 simple|hostmap|multi|tenants|all" ;;
        esac
    done
}

add_conf_name_arg() {
    local arg="$1"
    arg="$(trim "$arg")"
    [[ -n "$arg" ]] || die "--conf-name 不能为空"
    CONF_NAMES+=("$(basename "$arg")")
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help) usage; exit 0 ;;
            -c | --nginx-conf-dir)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                NGINX_CONF_HOME="$2"; shift ;;
            -d | --nginx-confd-vhost)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                NGINX_CONFD="$2"; NGINX_CONFD_EXPLICIT=true; shift ;;
            -l | --log-home | --log-dir)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                NGINX_LOG_DIR="$2"; shift ;;
            --tenants-dir)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                TENANTS_DIR="$2"; shift ;;
            -m | --mode)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                add_mode_arg "$2"; shift ;;
            --conf-name | --multi-conf-name)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                add_conf_name_arg "$2"; shift ;;
            --tenant)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                ONLY_TENANTS+=("$(trim "$2")"); shift ;;
            --status | --list-only) STATUS_ONLY=true ;;
            --dry-run) DRY_RUN=true ;;
            --force | --yes) FORCE=true ;;
            --no-backup) NO_BACKUP=true ;;
            --backup-dir)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                BACKUP_DIR="$2"; shift ;;
            --no-test | --no-nginx-test) NO_TEST=true ;;
            --reload) RELOAD=true ;;
            --purge-data | --with-maps | --with-data) PURGE_DATA=true ;;
            --with-cf) WITH_CF=true ;;
            --with-helper) WITH_HELPER=true ;;
            --with-symlink) WITH_SYMLINK=true ;;
            --with-logs) WITH_LOGS=true ;;
            --no-nginx-conf) NO_NGINX_CONF=true ;;
            --) shift; break ;;
            -*) die "未知参数: $1. 用 --help 查看" ;;
            *) die "未知位置参数: $1. 用 --help 查看" ;;
        esac
        shift
    done
}

mode_enabled() {
    local want="$1" m=""
    [[ ${#MODES[@]} -eq 0 ]] && return 0
    for m in "${MODES[@]}"; do
        [[ "$m" == "all" || "$m" == "$want" ]] && return 0
    done
    return 1
}

print_status() {
    info "nginx 家目录: $NGINX_CONF_HOME"
    info "include 目录: $NGINX_CONFD"
    info "日志目录: $NGINX_LOG_DIR"
    info "租户目录: $TENANTS_DIR"
    local f=""
    echo "---- D($NGINX_CONFD) 反代相关文件 ----" >&2
    for f in reverse_to_a.conf gateway.conf reverse_multi_ip.conf \
        tenant-common.conf tenant-hostmap.conf tenant-server.conf \
        10-common-map.conf 20-tenant-maps.conf 30-tenant-gateways.conf \
        cf-realip.conf cf_realip.conf cf-ips-v4.txt cf-ips-v6.txt; do
        if [[ -e "${NGINX_CONFD%/}/$f" ]]; then echo "  [存在] $f" >&2
        else echo "  [无]     $f" >&2; fi
    done
    if [[ ${#CONF_NAMES[@]} -gt 0 ]]; then
        for f in "${CONF_NAMES[@]}"; do
            if [[ "$f" == "reverse_multi_ip.conf" ]]; then continue; fi
            if [[ -e "${NGINX_CONFD%/}/$f" ]]; then echo "  [存在] $f (自定义)" >&2
            else echo "  [无]     $f (自定义)" >&2; fi
        done
    fi
    echo "---- C($NGINX_CONF_HOME) 数据目录 ----" >&2
    for f in "gateway/snippets/proxy-common.conf" "gateway/maps/routes.map.conf" \
        "gateway/proxy-pass-mode" "tenants/proxy-pass-mode" \
        "update_cf_ip_configs.sh" "nginx.conf"; do
        if [[ -e "${NGINX_CONF_HOME%/}/$f" ]]; then echo "  [存在] $f" >&2
        else echo "  [无]     $f" >&2; fi
    done
    if [[ -d "${TENANTS_DIR%/}" ]]; then
        echo "  [目录] tenants/:" >&2
        local d=""
        for d in "${TENANTS_DIR%/}"/*/; do
            [[ -d "$d" ]] || continue
            echo "    - $(basename "$d")/routes.map $([[ -f "$d/routes.map" ]] && echo '[存在]' || echo '[无 routes.map]')" >&2
        done
    else
        echo "  [无] tenants/ 目录" >&2
    fi
    if [[ -L "${NGINX_CONF_HOME%/}/log" ]]; then
        echo "  [软链] log -> $(readlink "${NGINX_CONF_HOME%/}/log")" >&2
    else
        echo "  [无] log 软链接" >&2
    fi
    if [[ -f "${NGINX_CONF_HOME%/}/nginx.conf" ]] && grep -q 'managed by tenants.sh' "${NGINX_CONF_HOME%/}/nginx.conf"; then
        echo "  [注意] nginx.conf 含 tenants.sh 插入的 map_hash 块" >&2
    fi
}

main() {
    parse_args "$@"

    if [[ "$NGINX_CONFD_EXPLICIT" != true || -z "$NGINX_CONFD" ]]; then
        if [[ "$NGINX_CONFD_EXPLICIT" != true ]]; then
            NGINX_CONFD="${NGINX_CONF_HOME%/}/conf.d"
        fi
    fi
    [[ -n "$NGINX_CONF_HOME" ]] || die "NGINX_CONF_HOME 为空"
    [[ -n "$NGINX_CONFD" ]] || die "NGINX_CONFD 为空"
    if [[ -z "$TENANTS_DIR" ]]; then
        TENANTS_DIR="${NGINX_CONF_HOME%/}/tenants"
    fi
    NGINX_LOG_DIR="$(normalize_dir_slash "$NGINX_LOG_DIR")"
    if [[ ${#CONF_NAMES[@]} -eq 0 ]]; then
        CONF_NAMES=("reverse_multi_ip.conf")
    fi
    local id=""
    for id in ${ONLY_TENANTS[@]+"${ONLY_TENANTS[@]}"}; do
        [[ "$id" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die "--tenant id 非法: [$id]"
    done

    if [[ "$STATUS_ONLY" == true ]]; then
        print_status
        exit 0
    fi

    # ---- 收集待删目标 ----
    local -a files_rm=() dirs_rm=()
    local f=""

    if mode_enabled simple; then
        files_rm+=("${NGINX_CONFD%/}/reverse_to_a.conf")
    fi
    if mode_enabled hostmap; then
        files_rm+=("${NGINX_CONFD%/}/gateway.conf")
    fi
    if mode_enabled multi; then
        for f in "${CONF_NAMES[@]}"; do
            files_rm+=("${NGINX_CONFD%/}/$f")
        done
    fi
    if mode_enabled tenants; then
        if [[ ${#ONLY_TENANTS[@]} -gt 0 ]]; then
            # 单租户裁剪:只删该租户数据目录,不碰 D 侧共享 conf(否则会中断其余租户)
            info "单租户模式:仅处理 tenants/${ONLY_TENANTS[*]},保留 D 侧 tenant-*.conf 与 nginx.conf"
        else
            files_rm+=("${NGINX_CONFD%/}/tenant-common.conf")
            files_rm+=("${NGINX_CONFD%/}/tenant-hostmap.conf")
            files_rm+=("${NGINX_CONFD%/}/tenant-server.conf")
            files_rm+=("${NGINX_CONFD%/}/10-common-map.conf")
            files_rm+=("${NGINX_CONFD%/}/20-tenant-maps.conf")
            files_rm+=("${NGINX_CONFD%/}/30-tenant-gateways.conf")
        fi
    fi
    if [[ "$WITH_CF" == true ]]; then
        files_rm+=("${NGINX_CONFD%/}/cf-realip.conf")
        files_rm+=("${NGINX_CONFD%/}/cf_realip.conf")
        files_rm+=("${NGINX_CONFD%/}/cf-ips-v4.txt")
        files_rm+=("${NGINX_CONFD%/}/cf-ips-v6.txt")
    fi
    if [[ "$WITH_HELPER" == true ]]; then
        files_rm+=("${NGINX_CONF_HOME%/}/update_cf_ip_configs.sh")
    fi

    # 数据目录: 默认保留, --purge-data 才删;但 --tenant 单租户裁剪不受此限
    local gateway_dir="${NGINX_CONF_HOME%/}/gateway"
    local tenants_root="${TENANTS_DIR%/}"
    if [[ ${#ONLY_TENANTS[@]} -gt 0 ]] && mode_enabled tenants; then
        for id in "${ONLY_TENANTS[@]}"; do
            dirs_rm+=("${tenants_root}/${id}")
        done
    elif [[ "$PURGE_DATA" == true ]]; then
        if mode_enabled hostmap; then
            if [[ ${#ONLY_TENANTS[@]} -gt 0 ]]; then
                : # hostmap 无租户概念,忽略 --tenant
            else
                [[ -e "$gateway_dir" ]] && dirs_rm+=("$gateway_dir")
            fi
        fi
        if mode_enabled tenants; then
            if [[ ${#ONLY_TENANTS[@]} -gt 0 ]]; then
                for id in "${ONLY_TENANTS[@]}"; do
                    dirs_rm+=("${tenants_root}/${id}")
                done
            else
                [[ -e "$tenants_root" ]] && dirs_rm+=("$tenants_root")
            fi
        fi
    fi

    # 软链接与日志
    local log_link="${NGINX_CONF_HOME%/}/log"
    local do_unlink=false
    if [[ "$WITH_SYMLINK" == true && -L "$log_link" ]]; then
        local target=""
        target="$(readlink "$log_link")"
        local want="${NGINX_LOG_DIR%/}/"
        local want_noslash="${NGINX_LOG_DIR%/}"
        if [[ "$target" == "$NGINX_LOG_DIR" || "$target" == "$want_noslash" || "$target" == "$want" ]]; then
            do_unlink=true
        else
            warn "log 软链指向 [$target],与 -l [$NGINX_LOG_DIR] 不一致,跳过删除"
        fi
    fi

    local -a logs_rm=()
    if [[ "$WITH_LOGS" == true && -d "${NGINX_LOG_DIR%/}" ]]; then
        local pat=""
        for pat in b_to_a_access.log b_to_a_error.log \
            b*_to_a*_access.log b*_to_a*_error.log \
            tenant-*-access.log tenant-*-error.log; do
            local hit=""
            for hit in "${NGINX_LOG_DIR%/}"/$pat; do
                [[ -e "$hit" ]] || continue
                logs_rm+=("$hit")
            done
        done
    fi

    local nginx_conf="${NGINX_CONF_HOME%/}/nginx.conf"
    local do_nginx_rollback=false
    if [[ "$NO_NGINX_CONF" != true ]] && mode_enabled tenants \
        && [[ ${#ONLY_TENANTS[@]} -eq 0 ]] \
        && [[ -f "$nginx_conf" ]] && grep -q 'managed by tenants.sh' "$nginx_conf"; then
        do_nginx_rollback=true
    fi

    # ---- 预览 ----
    info "nginx 家目录: $NGINX_CONF_HOME"
    info "include 目录: $NGINX_CONFD"
    info "purge-data=$PURGE_DATA with-cf=$WITH_CF with-helper=$WITH_HELPER with-symlink=$WITH_SYMLINK with-logs=$WITH_LOGS"
    local hit_count=0
    echo "将删除的文件:" >&2
    for f in "${files_rm[@]}"; do
        if [[ -e "$f" ]]; then echo "  [删] $f" >&2; hit_count=$((hit_count + 1)); else echo "  [无] $f" >&2; fi
    done
    echo "将删除的目录:" >&2
    local d=""
    if [[ ${#dirs_rm[@]} -eq 0 ]]; then echo "  (无)" >&2; fi
    for d in ${dirs_rm[@]+"${dirs_rm[@]}"}; do
        if [[ -e "$d" ]]; then echo "  [删] $d/" >&2; hit_count=$((hit_count + 1)); else echo "  [无] $d/" >&2; fi
    done
    if [[ "$do_unlink" == true ]]; then
        echo "  [删软链] $log_link -> $(readlink "$log_link")" >&2; hit_count=$((hit_count + 1))
    fi
    if [[ ${#logs_rm[@]} -gt 0 ]]; then
        echo "将删除的日志:" >&2
        for f in "${logs_rm[@]}"; do echo "  [删] $f" >&2; done
        hit_count=$((hit_count + ${#logs_rm[@]}))
    fi
    if [[ "$do_nginx_rollback" == true ]]; then
        echo "  [回退] $nginx_conf 中的 tenants map_hash 块" >&2; hit_count=$((hit_count + 1))
    fi
    if [[ "$PURGE_DATA" != true ]] && mode_enabled tenants && [[ ${#ONLY_TENANTS[@]} -eq 0 ]] && [[ -d "$tenants_root" ]]; then
        info "tenants 数据目录默认保留: $tenants_root (加 --purge-data 才删)"
    fi
    if mode_enabled hostmap && [[ "$PURGE_DATA" != true ]] && [[ -d "$gateway_dir" ]]; then
        info "gateway 数据目录默认保留: $gateway_dir (加 --purge-data 才删)"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "--dry-run: 仅预览,不做任何删除/回退"
        exit 0
    fi
    if [[ $hit_count -eq 0 && "$do_nginx_rollback" != true ]]; then
        info "无命中目标,无需清理"
    fi

    if [[ "$FORCE" != true ]]; then
        local ans=""
        printf '确认执行清理? [y/N] ' >&2
        read -r ans < /dev/tty || ans=""
        case "$ans" in
            y | Y | yes | YES) : ;;
            *) die "已取消" ;;
        esac
    fi

    # ---- 备份 ----
    local backup_dir="$BACKUP_DIR"
    if [[ "$NO_BACKUP" != true ]]; then
        if [[ -z "$backup_dir" ]]; then
            backup_dir="/root/nginx-reverse-backup/$(date +%Y%m%d-%H%M%S)"
            if ! mkdir -p "$backup_dir" 2>/dev/null; then
                backup_dir="/tmp/nginx-reverse-backup-$(date +%Y%m%d-%H%M%S)"
                mkdir -p "$backup_dir"
            fi
        else
            mkdir -p "$backup_dir"
        fi
        info "备份到: $backup_dir"
        for f in "${files_rm[@]}"; do
            [[ -e "$f" ]] || continue
            mkdir -p "$backup_dir/D"
            cp -av "$f" "$backup_dir/D/" >&2 || true
        done
        for d in ${dirs_rm[@]+"${dirs_rm[@]}"}; do
            [[ -e "$d" ]] || continue
            mkdir -p "$backup_dir/C"
            cp -arv "$d" "$backup_dir/C/" >&2 || true
        done
        if [[ -f "$nginx_conf" ]]; then
            cp -av "$nginx_conf" "$backup_dir/nginx.conf.bak" >&2 || true
        fi
        if [[ "$do_unlink" == true ]]; then
            readlink "$log_link" > "$backup_dir/log.symlink.txt" 2>/dev/null || true
        fi
    fi

    # ---- 执行删除 ----
    for f in "${files_rm[@]}"; do
        if [[ -e "$f" ]]; then rm -fv "$f" >&2; fi
    done
    for d in ${dirs_rm[@]+"${dirs_rm[@]}"}; do
        if [[ -e "$d" ]]; then rm -rfv "$d" >&2; fi
    done
    if [[ "$do_unlink" == true ]]; then
        rm -fv "$log_link" >&2
    fi
    if [[ ${#logs_rm[@]} -gt 0 ]]; then
        for f in "${logs_rm[@]}"; do rm -fv "$f" >&2; done
    fi

    if [[ "$do_nginx_rollback" == true ]]; then
        local tmp=""
        tmp="$(mktemp)"
        awk '
            /managed by tenants\.sh/ { skip_next = 2; next }
            skip_next > 0 && /^[[:space:]]*map_hash_(bucket_size|max_size)[[:space:]]+[0-9]+;/ {
                skip_next--; next
            }
            { print }
        ' "$nginx_conf" > "$tmp"
        install -m 0644 "$tmp" "$nginx_conf" -v >&2
        rm -f "$tmp"
        info "已回退 nginx.conf 中的 tenants map_hash 块(原文件见备份)"
    fi

    # 单租户删除后,tenants 根下 proxy-pass-mode 若已无租户可提示
    if [[ ${#ONLY_TENANTS[@]} -gt 0 ]]; then
        warn "单租户裁剪后 D 侧 tenant-hostmap/server.conf 仍引用已删租户的 include,nginx -t 会失败."
        warn "正确收尾:用剩余租户重跑 tenants.sh 重生配置,或手工从 D 侧两文件中删掉该租户段落后再 nginx -t."
        if [[ -d "$tenants_root" ]] && [[ -z "$(ls -A "$tenants_root" 2>/dev/null)" ]]; then
            warn "$tenants_root 已空,可手工 rmdir 或下次 --purge-data 清理"
        fi
    fi

    if [[ "$NO_TEST" != true ]] && command -v nginx >/dev/null 2>&1; then
        info "检查 nginx 配置..."
        nginx -t >&2
    else
        info "跳过 nginx -t (无 nginx 命令或 --no-test)"
    fi

    if [[ "$RELOAD" == true ]]; then
        if ! command -v nginx >/dev/null 2>&1; then
            die "无 nginx 命令,无法 reload"
        fi
        info "重载 nginx..."
        nginx -s reload >&2
    else
        info "未 reload (按需执行 nginx -t && nginx -s reload,或加 --reload)"
    fi

    info "完成. 残留自查: ls ${NGINX_CONFD%/}/ | grep -E 'reverse|gateway|tenant|^cf-|^10-|^20-|^30-' || echo 无残留"
}

main "$@"
