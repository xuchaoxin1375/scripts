#!/usr/bin/env bash
# 将 VPS 配置成“单服务器多公网 IP、按管理员/租户分流”的反向代理。
# 方案文档: nginx_conf/nginx@单服务器多IP为分配给多个管理员反代方案.md
#
# 网络架构:
#   client -> Cloudflare(Flexible) -> P(tenant listen IP:80) -> 该租户 routes.map(Host->Backend) -> origin
#
# 和现有反代脚本的区别:
#   base.sh -G simple:
#     全机一个入口，所有 Host 转到同一台上游 (-i A_IP)。
#   base.sh -G hostmap:
#     全机一个入口(listen 80)，一张全局 Host->Backend map:
#       $NGINX_CONF_HOME/gateway/maps/routes.map.conf
#     所有管理员共用同一张表，Host 不按公网 IP 隔离。
#   vps_multi.sh:
#     一组 B_IP -> 一个 A_IP；进入该 IP 的所有 Host 都转到同一台后端。
#   本脚本:
#     一组 tenant_id -> 一个 listen IP，再按该租户自己的 routes.map 查 Host。
#     未知 Host 返回 444，不能串到别的租户。
#
# 生成文件(默认路径，可用 -c/-d/--tenants-dir 改):
#   $NGINX_CONFD/tenant-common.conf
#   $NGINX_CONFD/tenant-hostmap.conf
#   $NGINX_CONFD/tenant-server.conf
#   $NGINX_CONF_HOME/tenants/<id>/routes.map
#   $NGINX_CONF_HOME/tenants/proxy-pass-mode
#
# --proxy-pass-mode:
#   hostport (默认): map 写 ip:port，      proxy_pass http://$var
#   url:            map 写 http://ip:port，proxy_pass $var  (同 hostmap)
#
# 文件名不用 10-/20-/30- 编号:
#   conf.d 按字母顺序 include。这三个名字已经是
#   tenant-common -> tenant-hostmap -> tenant-server，
#   能保证 map_hash / log_format / map 先于 server 出现。
#
# Cloudflare 真实 IP 不在本脚本里重写，复用 nginx_conf/update_cf_ip_configs.sh
# (与 base.sh / vps_multi.sh 相同)。
#
# 示例:
#   bash tenants.sh \
#     -t 'a=203.0.113.10' \
#     -t 'b=203.0.113.11' \
#     -r 'a:site-a1.example.com->10.10.10.11:80' \
#     -r 'b:site-b1.example.net->10.20.20.11:80'
#
# 预览:
#   bash tenants.sh --dev \
#     -t 'a=203.0.113.10' \
#     -t 'b=203.0.113.11'
#
# 从文件读取:
#   bash tenants.sh --tenant-file ~/tenants.list --routes-file ~/routes.list
#
# 注意:
#   1. listen IP 必须已经配置在本机网卡上，否则 nginx listen 会失败。
#   2. Flexible 模式下不要在 P 上做 http->https 强制跳转。
#   3. 已存在的 tenants/<id>/routes.map 默认不会覆盖，方便管理员自己维护。
#   4. 仓库更新、CF IP 更新、nginx -t/reload 流程对齐 vps_multi.sh。

set -Eeuo pipefail

VERSION="20260910.22:20"

NGINX_CONF_HOME="/etc/nginx"
NGINX_CONFD="$NGINX_CONF_HOME/conf.d"
NGINX_LOG_DIR="/var/log/nginx/"
TENANTS_DIR=""
COMMON_CONF_NAME="tenant-common.conf"
MAPS_CONF_NAME="tenant-hostmap.conf"
GATEWAY_CONF_NAME="tenant-server.conf"
LEGACY_CONF="reverse_to_a.conf"
MULTI_IP_CONF="reverse_multi_ip.conf"
NUMBERED_LEGACY_CONFS=(
    "10-common-map.conf"
    "20-tenant-maps.conf"
    "30-tenant-gateways.conf"
)

UPDATE_CODE=true
UPDATE_CF=true
RELOAD_NGINX=true
DRY_RUN=false
DEV_MODE=false
PROXY_BIND=false
PROXY_PASS_MODE="hostport"
PROXY_PASS_MODE_CLI=false
EXTEND_MAP_HASH_SIZE=false
WRITE_MAP_HASH=true
MAP_HASH_BUCKET_SIZE=128
MAP_HASH_MAX_SIZE=65536
MAP_HASH_PLACE="common"
FORCE_ROUTES=false
CLEAN_LEGACY=false
SKIP_ROUTES_CHECK=false # --no-check-routes: 跳过 routes.map 格式检查(表很大时省时间)
# 端口检查:重载后检查的端口列表 / 询问放行时的操作对象 / 跳过开关 / 非交互自动确认
PORTS_CHECK_LIST="80"
PORTS_FIX_LIST="80,443"
SKIP_PORTS_CHECK=false
AUTO_YES=false

SYM_SH="/www/sh"
mkdir -pv /www/ >&2 || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || printf '%s' ".")"
TMP_WORKDIR=""

TENANT_SEP='|'
TENANT_IDS=()
declare -A TENANT_IP=()
declare -A TENANT_ROUTES=()

TENANT_FILE_ARGS=()
ROUTE_ARGS=()
ROUTES_FILE_ARGS=()
PARSED_HOST=""
PARSED_BACKEND=""

if ((BASH_VERSINFO[0] < 4)); then
    echo "[Error][$0]: 需要 bash 4+ (当前: $BASH_VERSION)" >&2
    exit 1
fi

usage() {
    cat << EOF
部署“单服务器多 IP / 多管理员租户”反向代理. [version:$VERSION]

Usage:
    $0 [options]

核心功能:
    为反向代理服务器 P 上的多个公网 IP 分别生成独立入口:
        tenant a -> listen IP a -> map \$host \$tenant_a_backend
        tenant b -> listen IP b -> map \$host \$tenant_b_backend

    Cloudflare Flexible:
        访客 HTTPS -> Cloudflare -> P:80 HTTP -> 租户 routes.map 中的后端

    每个租户只维护自己的 routes.map，未知 Host 返回 444，避免跨租户串路由。

Options:
    -c, --nginx-conf-dir <dir>
        nginx 配置文件家目录.
        常见值:
            /etc/nginx
            /www/server/nginx/conf

    -d, --nginx-confd-vhost <dir>
        nginx 自动 include 的 http 级目录(map/log_format/server 都写这里).
        常见值:
            /etc/nginx/conf.d
            /www/server/panel/vhost/nginx

    -l, --log-dir <dir>
        nginx 日志目录.
        常见值:
            /var/log/nginx
            /www/logs

    --tenants-dir <dir>
        租户 routes.map 根目录.
        默认:
            \$NGINX_CONF_HOME/tenants

    -t, --tenant <id=IP[,id=IP,...]>
        定义租户及其 listen IP. 可重复传入.
        支持:
            id=IP
            id->IP
            id IP
        示例:
            -t 'a=203.0.113.10'
            -t 'a=203.0.113.10,b=203.0.113.11'

    -T, --tenant-file <file>
        从文件读取租户. 支持空行和 # 注释.
        也支持进程替换: -T <(echo "a 203.0.113.10")

    -r, --route <id:host->backend>
        给指定租户增加一条 Host -> Backend.
        示例:
            -r 'a:site-a1.example.com->10.10.10.11:80'
            -r 'a:www.site-a1.example.com->10.10.10.11:80'

    -R, --routes-file <file|id=file>
        读取路由.
        1) 统一文件(三列): tenant host backend
        2) 指定租户文件: a=/path/to/a.routes
           文件内容为 nginx map 条目, 例如:
               site-a1.example.com  10.10.10.11:80;

    --proxy-bind
        在各租户 server 中启用 proxy_bind <listen_ip>.
        仅当后端防火墙要求“必须从该公网 IP 出站”时再打开.
        若公网 IP 实际是 NAT 而不是本机接口地址，不要启用.

    --proxy-pass-mode <hostport|url>
        控制 routes.map 和 proxy_pass 的搭配. 默认 hostport.

        hostport
            map:  10.10.10.11:80
            nginx: proxy_pass http://\$tenant_x_backend;
            现网 tenants/*/routes.map 已是这种，默认不要改.

        url
            map:  http://10.10.10.11:80
            nginx: proxy_pass \$tenant_x_backend;
            与 base.sh -G hostmap 相同，单站可写 https://.

        未传时，若 $TENANTS_DIR/proxy-pass-mode 已有记录则沿用.
        切换模式后必须把已有 routes.map 改成对应格式再 reload.

    --no-check-routes
        跳过已有 routes.map 的格式检查(表很大时可省几十秒).

    -E, --extend-map-hash-size
        把 map_hash_bucket_size / map_hash_max_size 提到 256 / 131072.
        域名特别多或仍然出现 map_hash 警告时再开.

    --no-map-hash
        不写入、不修补 map_hash_*.
        仅当 http{} 里已经有合适的 map_hash，且会和本脚本重复时使用.

    --force-routes
        覆盖已存在的 tenants/<id>/routes.map.
        默认: 已有文件且本次未给该租户提供新路由时，保留原文件.

    --clean, --clean-legacy-conf
        删除旧版 reverse_to_a.conf.

    --dry-run
        只把将要生成的配置打印到 stdout，不写文件、不 nginx -t、不 reload.

    --no-update-code
        不执行仓库拉取/更新(update_repos.sh).

    --no-update-cf
        不更新 Cloudflare real IP 配置.

    --no-reload
        写入配置并 nginx -t，但不 reload.

    --ports-check <list>
        部署后检查的端口列表,默认 80.

    --fix-ports <list>
        询问放行时的操作对象,默认 80,443.

    --skip-ports-check
        跳过部署后的端口与防火墙检查.

    --yes
        端口检查的交互询问一律按 yes 处理(自动尝试放行并继续).

    --dev
        开发/调试模式, 等价于:
            --dry-run --no-update-code --no-update-cf --no-reload

    -h, --help
        显示帮助.

Examples:
    # 标准 nginx
    bash $0 \\
      -t 'a=203.0.113.10' \\
      -t 'b=203.0.113.11'

    # 宝塔路径
    bash $0 \\
      -c /www/server/nginx/conf \\
      -d /www/server/panel/vhost/nginx \\
      -l /www/logs/ \\
      -t 'a=203.0.113.10' \\
      -t 'b=203.0.113.11' \\
      -r 'a:site-a1.example.com->10.10.10.11:80' \\
      -r 'b:site-b1.example.net->10.20.20.11:80'

    # 预览
    bash $0 --dev \\
      -t 'a=203.0.113.10' \\
      -t 'b=203.0.113.11'

    # 与 hostmap 相同的完整 URL
    bash $0 --proxy-pass-mode url \\
      -t 'a=203.0.113.10' \\
      -r 'a:site-a1.example.com->http://10.10.10.11:80'

    # 文件 + 进程替换
    bash $0 \\
      -T <(printf '%s\n' 'a 203.0.113.10' 'b 203.0.113.11') \\
      -R <(printf '%s\n' \\
          'a site-a1.example.com 10.10.10.11:80' \\
          'b site-b1.example.net 10.20.20.11:80')

    # 在线拉取并部署
    bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/nginx_conf/reverse_proxy/scripts/tenants.sh) \\
      -t 'a=P_IP_A' \\
      -t 'b=P_IP_B'

租户文件示例:
    # id  listen_ip
    a 203.0.113.10
    b=203.0.113.11

统一路由文件示例:
    # tenant host backend
    a site-a1.example.com 10.10.10.11:80
    a www.site-a1.example.com 10.10.10.11:80
    b site-b1.example.net -> 10.20.20.11:80

说明:
    1. 租户 id 只能是 [A-Za-z][A-Za-z0-9_]* ，会用于 nginx 变量名 tenant_<id>_backend.
    2. 默认 --proxy-pass-mode hostport: routes.map 写 ip:port，
       proxy_pass http://\$tenant_<id>_backend;
       --proxy-pass-mode url 则与 hostmap 相同: map 写 http://ip:port，
       proxy_pass \$tenant_<id>_backend;
    3. CF IP 列表更新复用 update_cf_ip_configs.sh，生成 cf-realip.conf.
    4. 不要和 reverse_multi_ip.conf / 全局 listen 80 default_server 同时抢同一 IP:80.

EOF
}

die() {
    echo "[Error][$0]: $*" >&2
    exit 1
}

info() {
    echo "[INFO] $*" >&2
}

warn() {
    echo "[WARN] $*" >&2
}

trim() {
    local s="$*"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

is_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    local IFS=.
    local -a parts
    read -r -a parts <<< "$ip"

    local p
    for p in "${parts[@]}"; do
        [[ "$p" =~ ^[0-9]+$ ]] || return 1
        ((p >= 0 && p <= 255)) || return 1
    done
}

_ipv6_count_hextets() {
    local s="$1"
    local IFS=:
    local -a parts
    local h

    if [[ -z "$s" ]]; then
        printf '0'
        return 0
    fi

    [[ "$s" != :* && "$s" != *: && "$s" != *::* ]] || return 1

    read -r -a parts <<< "$s"

    for h in "${parts[@]}"; do
        [[ "$h" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
    done

    printf '%d' "${#parts[@]}"
}

is_ipv6() {
    local ip="$1"
    local v4 left right n_left n_right

    [[ -n "$ip" ]] || return 1
    [[ "$ip" != *%* && "$ip" != \[* && "$ip" != *\]* ]] || return 1
    [[ "$ip" =~ ^[0-9A-Fa-f:.]+$ ]] || return 1

    if [[ "$ip" == *.* ]]; then
        v4=${ip##*:}
        is_ipv4 "$v4" || return 1
        [[ "$ip" == *:* ]] || return 1
        [[ "${ip%:*}" != *.* ]] || return 1
        ip="${ip%:*}:0:0"
    fi

    [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
    [[ "$ip" != *::*::* ]] || return 1

    if [[ "$ip" == *::* ]]; then
        left=${ip%%::*}
        right=${ip#*::}
        n_left=$(_ipv6_count_hextets "$left") || return 1
        n_right=$(_ipv6_count_hextets "$right") || return 1
        ((n_left + n_right < 8)) || return 1
    else
        n_left=$(_ipv6_count_hextets "$ip") || return 1
        ((n_left == 8)) || return 1
    fi
}

normalize_dir_slash() {
    local dir="$1"
    [[ -n "$dir" ]] || return 0
    dir="${dir%/}/"
    printf '%s' "$dir"
}

format_nginx_ip_port() {
    local ip="$1"
    local port="${2:-80}"

    if is_ipv6 "$ip"; then
        printf '[%s]:%s' "$ip" "$port"
    else
        printf '%s:%s' "$ip" "$port"
    fi
}

is_tenant_id() {
    local id="$1"
    [[ "$id" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || return 1
    case "$id" in
        default | http | https | on | off | host | server | listen | map)
            return 1
            ;;
    esac
}

tenant_backend_var() {
    printf 'tenant_%s_backend' "$1"
}

resolve_sym_sh() {
    local candidates=("$SYM_SH" "/www/sh" "${HOME}/sh" "$SCRIPT_DIR")
    local d
    for d in "${candidates[@]}"; do
        [[ -n "$d" ]] || continue
        if [[ -f "$d/nginx_conf/update_cf_ip_configs.sh" ]]; then
            SYM_SH="$d"
            return 0
        fi
    done
    return 1
}

check_local_ip() {
    local ip="$1"
    command -v ip >/dev/null 2>&1 || return 0
    if ! ip -o addr show 2>/dev/null | grep -F " ${ip}/" >/dev/null; then
        warn "本机网卡未看到 listen IP [${ip}]，nginx listen 可能会失败. 用 ip addr 确认后再 reload."
    fi
}

normalize_backend() {
    local raw="$1"
    local proto=""
    local rest=""

    raw="$(trim "$raw")"
    raw="${raw%;}"
    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 1

    if [[ "$raw" == https://* ]]; then
        proto="https"
        rest="${raw#https://}"
    elif [[ "$raw" == http://* ]]; then
        proto="http"
        rest="${raw#http://}"
    else
        rest="$raw"
    fi

    if is_ipv4 "$rest" || is_ipv6 "$rest"; then
        rest="$(format_nginx_ip_port "$rest" 80)"
    fi

    if [[ "$PROXY_PASS_MODE" == "url" ]]; then
        proto="${proto:-http}"
        printf '%s://%s' "$proto" "$rest"
        return 0
    fi

    if [[ "$proto" == "https" ]]; then
        warn "hostport 模式下 https:// 会被剥掉，P->源站仍是 HTTP。要保留协议请用 --proxy-pass-mode url"
    fi

    printf '%s' "$rest"
}

validate_host() {
    local host="$1"
    [[ -n "$host" ]] || return 1
    [[ "$host" != *[[:space:]]* ]] || return 1
    [[ "$host" != *";"* && "$host" != *"{"* && "$host" != *"}"* ]] || return 1
}

add_tenant_pair() {
    local raw="$1"
    local id=""
    local ip=""

    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 0
    raw="${raw%%#*}"
    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 0

    if [[ "$raw" == *"->"* ]]; then
        id="${raw%%->*}"
        ip="${raw#*->}"
    elif [[ "$raw" == *"=>"* ]]; then
        id="${raw%%=>*}"
        ip="${raw#*=>}"
    elif [[ "$raw" == *"="* ]]; then
        id="${raw%%=*}"
        ip="${raw#*=}"
    else
        # shellcheck disable=SC2206
        local parts=($raw)
        [[ ${#parts[@]} -ge 2 ]] || die "租户格式错误: [$raw], 期望 id=IP、id->IP 或 id IP"
        id="${parts[0]}"
        ip="${parts[1]}"
    fi

    id="$(trim "$id")"
    ip="$(trim "$ip")"

    is_tenant_id "$id" || die "租户 id 非法: [$id]. 仅允许 [A-Za-z][A-Za-z0-9_]*，且不能是 nginx 保留字."
    is_ipv4 "$ip" || is_ipv6 "$ip" || die "租户 [$id] 的 listen IP 非法: [$ip]"

    if [[ -n "${TENANT_IP[$id]+x}" ]]; then
        die "租户 id 重复: [$id]"
    fi

    local existing_id=""
    for existing_id in "${TENANT_IDS[@]+"${TENANT_IDS[@]}"}"; do
        if [[ "${TENANT_IP[$existing_id]}" == "$ip" ]]; then
            die "listen IP 重复: [$ip] 已被租户 [$existing_id] 使用"
        fi
    done

    TENANT_IDS+=("$id")
    TENANT_IP["$id"]="$ip"
}

add_tenant_arg() {
    local arg="$1"
    local pair=""
    local IFS=','
    local -a pairs
    read -r -a pairs <<< "$arg"
    for pair in "${pairs[@]}"; do
        add_tenant_pair "$pair"
    done
}

read_tenant_file() {
    local file="$1"
    local line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        add_tenant_pair "$line"
    done < "$file"
}

append_tenant_route() {
    local id="$1"
    local host="$2"
    local backend="$3"

    [[ -n "${TENANT_IP[$id]+x}" ]] || die "未知租户 [$id]，请先用 -t / --tenant-file 定义"
    validate_host "$host" || die "Host 非法: [$host]"
    backend="$(normalize_backend "$backend")" || die "Backend 为空: tenant=$id host=$host"

    if [[ -n "${TENANT_ROUTES[$id]:-}" ]]; then
        TENANT_ROUTES["$id"]="${TENANT_ROUTES[$id]}"$'\n'"${host}${TENANT_SEP}${backend}"
    else
        TENANT_ROUTES["$id"]="${host}${TENANT_SEP}${backend}"
    fi
}

parse_host_backend() {
    local raw="$1"
    local host=""
    local backend=""

    PARSED_HOST=""
    PARSED_BACKEND=""

    raw="$(trim "$raw")"
    raw="${raw%;}"
    raw="$(trim "$raw")"

    if [[ "$raw" == *"->"* ]]; then
        host="${raw%%->*}"
        backend="${raw#*->}"
    elif [[ "$raw" == *"=>"* ]]; then
        host="${raw%%=>*}"
        backend="${raw#*=>}"
    else
        # shellcheck disable=SC2206
        local parts=($raw)
        [[ ${#parts[@]} -ge 2 ]] || die "Host/Backend 格式错误: [$raw], 期望 host->backend 或 host backend"
        host="${parts[0]}"
        backend="${parts[1]}"
    fi

    PARSED_HOST="$(trim "$host")"
    PARSED_BACKEND="$(trim "$backend")"
}

add_route_pair() {
    local raw="$1"
    local id=""
    local rest=""

    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 0
    raw="${raw%%#*}"
    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 0

    if [[ "$raw" != *":"* ]]; then
        die "路由格式错误: [$raw], 期望 id:host->backend"
    fi

    id="${raw%%:*}"
    rest="${raw#*:}"
    id="$(trim "$id")"
    rest="$(trim "$rest")"

    parse_host_backend "$rest"
    append_tenant_route "$id" "$PARSED_HOST" "$PARSED_BACKEND"
}

add_unified_route_line() {
    local raw="$1"
    local id=""
    local rest=""

    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 0
    raw="${raw%%#*}"
    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 0

    # shellcheck disable=SC2206
    local parts=($raw)
    [[ ${#parts[@]} -ge 2 ]] || die "统一路由行格式错误: [$raw], 期望 tenant host backend"

    id="${parts[0]}"
    rest="$(trim "${raw#"${parts[0]}"}")"
    parse_host_backend "$rest"
    append_tenant_route "$id" "$PARSED_HOST" "$PARSED_BACKEND"
}

add_nginx_map_route_line() {
    local id="$1"
    local raw="$2"

    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 0
    raw="${raw%%#*}"
    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 0

    parse_host_backend "$raw"
    append_tenant_route "$id" "$PARSED_HOST" "$PARSED_BACKEND"
}

read_unified_routes_file() {
    local file="$1"
    local line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        add_unified_route_line "$line"
    done < "$file"
}

read_tenant_routes_file() {
    local id="$1"
    local file="$2"
    local line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        add_nginx_map_route_line "$id" "$line"
    done < "$file"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            -c | --nginx-conf-dir)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                NGINX_CONF_HOME="$2"
                shift
                ;;
            -d | --nginx-confd-vhost)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                NGINX_CONFD="$2"
                shift
                ;;
            -l | --log-home | --log-dir)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                NGINX_LOG_DIR="$2"
                shift
                ;;
            --tenants-dir)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                TENANTS_DIR="$2"
                shift
                ;;
            -t | --tenant)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                add_tenant_arg "$2"
                shift
                ;;
            -T | --tenant-file)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                TENANT_FILE_ARGS+=("$2")
                shift
                ;;
            -r | --route)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                ROUTE_ARGS+=("$2")
                shift
                ;;
            -R | --routes-file)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                ROUTES_FILE_ARGS+=("$2")
                shift
                ;;
            --proxy-bind)
                PROXY_BIND=true
                ;;
            --proxy-pass-mode)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                PROXY_PASS_MODE="$2"
                PROXY_PASS_MODE_CLI=true
                shift
                ;;
            --no-check-routes | --no-routes-check)
                SKIP_ROUTES_CHECK=true
                ;;            -E | --extend-map-hash-size)
                EXTEND_MAP_HASH_SIZE=true
                ;;
            --no-map-hash)
                WRITE_MAP_HASH=false
                ;;
            --force-routes)
                FORCE_ROUTES=true
                ;;
            --clean | --clean-legacy-conf)
                CLEAN_LEGACY=true
                ;;
            --dry-run)
                DRY_RUN=true
                RELOAD_NGINX=false
                ;;
            --dev)
                DEV_MODE=true
                DRY_RUN=true
                UPDATE_CODE=false
                UPDATE_CF=false
                RELOAD_NGINX=false
                ;;
            --no-update-code)
                UPDATE_CODE=false
                ;;
            --no-update-cf)
                UPDATE_CF=false
                ;;
            --no-reload)
                RELOAD_NGINX=false
                ;;
            --ports-check)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                PORTS_CHECK_LIST="$2"
                shift
                ;;
            --fix-ports)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                PORTS_FIX_LIST="$2"
                shift
                ;;
            --skip-ports-check)
                SKIP_PORTS_CHECK=true
                ;;
            --yes)
                AUTO_YES=true
                ;;
            --)
                shift
                break
                ;;
            -*)
                die "未知参数: $1. 使用 --help 查看帮助."
                ;;
            *)
                die "未知位置参数: $1. 使用 --help 查看帮助."
                ;;
        esac
        shift
    done
}

load_inputs() {
    local item=""
    local id=""
    local file=""

    for file in "${TENANT_FILE_ARGS[@]+"${TENANT_FILE_ARGS[@]}"}"; do
        read_tenant_file "$file"
    done

    [[ ${#TENANT_IDS[@]} -gt 0 ]] || {
        usage >&2
        die "必须提供至少一个租户. 示例: -t 'a=203.0.113.10'"
    }

    for item in "${ROUTES_FILE_ARGS[@]+"${ROUTES_FILE_ARGS[@]}"}"; do
        if [[ "$item" == *=* ]] && is_tenant_id "${item%%=*}"; then
            id="${item%%=*}"
            file="${item#*=}"
            [[ -n "$file" ]] || die "--routes-file 租户文件路径为空: [$item]"
            read_tenant_routes_file "$id" "$file"
        else
            read_unified_routes_file "$item"
        fi
    done

    for item in "${ROUTE_ARGS[@]+"${ROUTE_ARGS[@]}"}"; do
        add_route_pair "$item"
    done
}

should_write_routes() {
    local id="$1"
    local target="$2"

    if [[ "$FORCE_ROUTES" == true ]]; then
        return 0
    fi
    if [[ -n "${TENANT_ROUTES[$id]:-}" ]]; then
        return 0
    fi
    if [[ -f "$target" ]]; then
        return 1
    fi
    return 0
}

generate_common_map() {
    local generated_at="$1"
    local emit_hash="${2:-true}"
    local hash_block=""

    if [[ "$emit_hash" == true ]]; then
        hash_block="$(cat << EOF
# 必须出现在任何 map {} 之前，否则 nginx 仍用默认 2048/64，并警告:
#   could not build optimal map_hash ... ignoring map_hash_bucket_size
map_hash_bucket_size ${MAP_HASH_BUCKET_SIZE};
map_hash_max_size ${MAP_HASH_MAX_SIZE};
EOF
)"
    else
        hash_block="# map_hash_* 已放在 nginx.conf 的 http{} 开头，或按 --no-map-hash 跳过."
    fi

    cat << EOF
# ======================================================================
# AUTO GENERATED FILE - DO NOT EDIT MANUALLY
# ======================================================================
# 生成时间: ${generated_at}
# 生成脚本: tenants.sh
# 脚本版本: ${VERSION}
#
# 用途:
#   多租户网关公共 map / 日志格式.
#   Cloudflare Flexible 下，P 看到的是 HTTP，访客协议以 X-Forwarded-Proto 为准.
#
# Cloudflare 真实 IP:
#   由 update_cf_ip_configs.sh 生成 cf-realip.conf，本文件不重复维护 IP 段.
# ======================================================================

${hash_block}

# WebSocket / HTTP Upgrade
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

# Cloudflare Flexible: 访客可能是 HTTPS，P 收到的却是 HTTP.
# 有 X-Forwarded-Proto 时沿用；没有则回退 \$scheme.
map \$http_x_forwarded_proto \$proxy_x_forwarded_proto {
    default \$http_x_forwarded_proto;
    ''      \$scheme;
}

map \$http_x_forwarded_proto \$forwarded_port {
    default 80;
    https   443;
}

log_format tenant_gateway
    '\$remote_addr - \$remote_user [\$time_local] "\$request" '
    'status=\$status body=\$body_bytes_sent '
    'host="\$host" server_name="\$server_name" '
    'server_addr="\$server_addr" '
    'tenant="\$tenant_id" backend="\$tenant_backend" '
    'request_time=\$request_time '
    'upstream_addr="\$upstream_addr" '
    'upstream_status="\$upstream_status" '
    'upstream_response_time="\$upstream_response_time" '
    'cf_ray="\$http_cf_ray" '
    'cf_connecting_ip="\$http_cf_connecting_ip" '
    'xff="\$http_x_forwarded_for" '
    'xfp="\$http_x_forwarded_proto" '
    'realip_remote_addr="\$realip_remote_addr" '
    'referer="\$http_referer" '
    'ua="\$http_user_agent"';
EOF
}

generate_tenant_maps() {
    local generated_at="$1"
    local id=""
    local var_name=""
    local routes_file=""

    cat << EOF
# ======================================================================
# AUTO GENERATED FILE - DO NOT EDIT MANUALLY
# ======================================================================
# 生成时间: ${generated_at}
# 生成脚本: tenants.sh
# 脚本版本: ${VERSION}
#
# 每个租户一张 Host -> Backend map.
# 请求先按 listen IP 进入对应 server，再查这张表，因此 Host 不能跨租户命中.
# ======================================================================

EOF

    for id in "${TENANT_IDS[@]}"; do
        var_name="$(tenant_backend_var "$id")"
        routes_file="${TENANTS_DIR%/}/${id}/routes.map"
        cat << EOF
map \$host \$${var_name} {
    hostnames;
    default "";

    include ${routes_file};
}

EOF
    done
}

generate_gateways() {
    local generated_at="$1"
    local id=""
    local ip=""
    local listen_addr=""
    local var_name=""
    local bind_line=""

    cat << EOF
# ======================================================================
# AUTO GENERATED FILE - DO NOT EDIT MANUALLY
# ======================================================================
# 生成时间: ${generated_at}
# 生成脚本: tenants.sh
# 脚本版本: ${VERSION}
#
# 每个租户一个 server:
#   listen <tenant_ip>:80 default_server;
#   未知 Host -> 444
#   proxy-pass-mode: ${PROXY_PASS_MODE}
#
# Flexible 注意:
#   不要在这里做 http -> https 强制跳转，否则会和 Cloudflare 形成重定向环.
# ======================================================================

EOF

    for id in "${TENANT_IDS[@]}"; do
        ip="${TENANT_IP[$id]}"
        listen_addr="$(format_nginx_ip_port "$ip" 80)"
        var_name="$(tenant_backend_var "$id")"
        if [[ "$PROXY_BIND" == true ]]; then
            bind_line="        proxy_bind ${ip};"
        else
            bind_line="        # proxy_bind ${ip};"
        fi
        local pass_line=""
        if [[ "$PROXY_PASS_MODE" == "url" ]]; then
            pass_line="        proxy_pass \$${var_name};"
        else
            pass_line="        proxy_pass http://\$${var_name};"
        fi

        cat << EOF
# ----------------------------------------------------------------------
# 租户 ${id}  (listen ${listen_addr})
# ----------------------------------------------------------------------
server {
    listen ${listen_addr} default_server;
    server_name _;

    access_log ${NGINX_LOG_DIR}tenant-${id}-access.log tenant_gateway;
    error_log  ${NGINX_LOG_DIR}tenant-${id}-error.log warn;

    set \$tenant_id "${id}";
    set \$tenant_backend \$${var_name};

    location = /__tenant_health {
        access_log off;
        return 200 "tenant ${id} gateway ok\n";
        add_header Content-Type text/plain;
    }

    location / {
        # if 必须放在 location 内。map 未命中时变量为空，直接 proxy_pass 会 500。
        if (\$${var_name} = "") {
            return 444;
        }

${pass_line}

${bind_line}

        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto \$proxy_x_forwarded_proto;
        proxy_set_header X-Forwarded-Ssl \$proxy_x_forwarded_proto;
        proxy_set_header X-Forwarded-Port \$forwarded_port;
        proxy_set_header CF-Connecting-IP \$http_cf_connecting_ip;
        proxy_set_header CF-Ray \$http_cf_ray;
        proxy_set_header CF-Visitor \$http_cf_visitor;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        client_max_body_size 512m;
        proxy_connect_timeout 10s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        proxy_redirect off;
    }
}

EOF
    done
}

generate_routes_map() {
    local id="$1"
    local generated_at="$2"
    local line=""
    local host=""
    local backend=""
    local has_route=false

    cat << EOF
# 租户 ${id} 的 Host -> Backend 映射.
# 本文件给该租户日常维护，脚本默认不覆盖已有文件.
# 生成时间: ${generated_at}
#
# 格式:
#   host                          backend;
#
# 注意:
#   1. 每行末尾必须有分号.
#   2. 当前 proxy-pass-mode=${PROXY_PASS_MODE}
#   3. 根域 + 全部子域可用 .example.com
#   4. 未匹配 Host 不会转发到其他租户，对应入口会 444.
#
EOF

    if [[ "$PROXY_PASS_MODE" == "url" ]]; then
        cat << EOF
# url 模式 (与 hostmap 相同):
#   proxy_pass \$tenant_${id}_backend;
#   backend 必须写完整 URL.
#
# 示例:
#   site-${id}-1.example.com       http://10.10.10.11:80;
#   www.site-${id}-1.example.com   http://10.10.10.11:80;
#   .site-${id}-2.example.com      https://10.10.10.12:443;
EOF
    else
        cat << EOF
# hostport 模式 (默认，兼容现网 tenants map):
#   proxy_pass http://\$tenant_${id}_backend;
#   backend 写 ip:port，不要写 http:// 。
#
# 示例:
#   site-${id}-1.example.com       10.10.10.11:80;
#   www.site-${id}-1.example.com   10.10.10.11:80;
#   .site-${id}-2.example.com      10.10.10.12:8080;
EOF
    fi

    cat << EOF

EOF

    if [[ -n "${TENANT_ROUTES[$id]:-}" ]]; then
        has_route=true
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -n "$line" ]] || continue
            host="${line%%"${TENANT_SEP}"*}"
            backend="${line#*"${TENANT_SEP}"}"
            printf '%-40s %s;\n' "$host" "$backend"
        done <<< "${TENANT_ROUTES[$id]}"
    fi

    if [[ "$has_route" == false ]]; then
        cat << EOF
# 还没有有效条目时保持空表即可，对应租户入口会对未知 Host 返回 444.
EOF
    fi
}

print_banner() {
    printf '\n===== %s =====\n' "$1"
}

proxy_pass_mode_file() {
    printf '%s/proxy-pass-mode' "${TENANTS_DIR%/}"
}

normalize_proxy_pass_mode() {
    local mode="$1"
    case "$mode" in
        hostport | host-port | host_port)
            printf 'hostport'
            ;;
        url | hostmap | fullurl | full-url | full_url)
            printf 'url'
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_proxy_pass_mode() {
    local saved=""
    local file=""
    local normalized=""

    file="$(proxy_pass_mode_file)"
    if [[ -f "$file" ]]; then
        saved="$(trim "$(head -n 1 "$file")")"
        saved="$(normalize_proxy_pass_mode "$saved" || true)"
    fi

    if [[ "$PROXY_PASS_MODE_CLI" == true ]]; then
        normalized="$(normalize_proxy_pass_mode "$PROXY_PASS_MODE")"             || die "未知 --proxy-pass-mode: [$PROXY_PASS_MODE]. 使用 hostport 或 url"
        PROXY_PASS_MODE="$normalized"
        if [[ -n "$saved" && "$saved" != "$PROXY_PASS_MODE" ]]; then
            warn "proxy-pass-mode 从 [$saved] 改为 [$PROXY_PASS_MODE]. 现有 routes.map 必须改成对应格式再 reload."
        fi
        return 0
    fi

    if [[ -n "$saved" ]]; then
        PROXY_PASS_MODE="$saved"
        info "沿用 $(proxy_pass_mode_file) : $PROXY_PASS_MODE"
        return 0
    fi

    PROXY_PASS_MODE="hostport"
}

persist_proxy_pass_mode() {
    local file=""
    file="$(proxy_pass_mode_file)"
    mkdir -pv "$(dirname "$file")"
    printf '%s\n' "$PROXY_PASS_MODE" > "$file"
    info "记录 proxy-pass-mode=$PROXY_PASS_MODE -> $file"
}

warn_routes_mode_mismatch() {
    local file="$1"
    if [[ "$SKIP_ROUTES_CHECK" == true ]]; then
        info "跳过 routes.map 格式检查 (--no-check-routes)."
        return 0
    fi
    [[ -f "$file" ]] || return 0
    # 单进程 awk 检查:原 bash 逐行循环每行 fork 数次,几千行会卡几十秒.
    awk -v mode="$PROXY_PASS_MODE" -v mapfile="$file" '
        {
            line = $0
            sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
            if (line == "" || substr(line, 1, 1) == "#") next
            sub(/#.*$/, "", line)
            sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
            sub(/;[ \t]*$/, "", line); sub(/[ \t]+$/, "", line)
            if (line == "") next
            n = split(line, parts, /[ \t]+/)
            backend = parts[n]
            if (backend == "") next
            if (mode == "url") {
                if (backend ~ /^https?:\/\//) next
            } else {
                if (backend !~ /^https?:\/\//) next
            }
            mismatch++
            if (mismatch <= 3)
                printf "[WARN] %s: [%s] 与 proxy-pass-mode=%s 不符\n", mapfile, backend, mode > "/dev/stderr"
        }
        END {
            if (mismatch > 3)
                printf "[WARN] %s: 另有 %d 行格式不符. hostport 用 ip:port，url 用 http://ip:port\n", mapfile, mismatch - 3 > "/dev/stderr"
            else if (mismatch > 0)
                printf "[WARN] %s: 请改成 %s 格式后再 reload\n", mapfile, mode > "/dev/stderr"
        }
    ' "$file"
}

nginx_conf_file() {
    printf '%s/nginx.conf' "${NGINX_CONF_HOME%/}"
}

nginx_conf_has_map_hash() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    grep -Eq '^[[:space:]]*map_hash_(bucket_size|max_size)[[:space:]]+' "$file"
}

nginx_conf_includes_early_maps() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    grep -Eq 'include[[:space:]]+.*com_com\.conf' "$file"         || grep -Eq 'include[[:space:]]+.*com_ua_map\.conf' "$file"         || grep -Eq 'include[[:space:]]+.*com_country_map\.conf' "$file"
}

map_hash_snippet() {
    cat << EOF
    # map_hash: managed by tenants.sh
    map_hash_bucket_size ${MAP_HASH_BUCKET_SIZE};
    map_hash_max_size ${MAP_HASH_MAX_SIZE};
EOF
}

# 宝塔 nginx.conf 会先 include com_com.conf（里面已有 map）。
# map_hash_* 必须在那些 map 之前，写在 tenant-common.conf 里会被忽略，告警仍是 2048/64.
nginx_conf_map_hash_value() {
    local file="$1"
    local key="$2"
    sed -n -E "s/^[[:space:]]*${key}[[:space:]]+([0-9]+);.*/\1/p" "$file" | head -n 1
}

update_map_hash_in_nginx_conf() {
    local file="$1"
    local tmp=""
    tmp="$(mktemp)"
    sed -E         -e "s/^([[:space:]]*map_hash_bucket_size)[[:space:]]+[0-9]+;/\1 ${MAP_HASH_BUCKET_SIZE};/"         -e "s/^([[:space:]]*map_hash_max_size)[[:space:]]+[0-9]+;/\1 ${MAP_HASH_MAX_SIZE};/"         "$file" > "$tmp"
    install -m 0644 "$tmp" "$file" -v
    rm -f "$tmp"
}

insert_map_hash_into_nginx_conf() {
    local file="$1"
    local tmp=""
    tmp="$(mktemp)"

    if ! awk -v bucket="$MAP_HASH_BUCKET_SIZE" -v max="$MAP_HASH_MAX_SIZE" '
        BEGIN { inserted = 0 }
        {
            print
            if (!inserted && $0 ~ /^[[:space:]]*http[[:space:]]*\{[[:space:]]*$/) {
                print "    # map_hash: managed by tenants.sh"
                print "    map_hash_bucket_size " bucket ";"
                print "    map_hash_max_size " max ";"
                inserted = 1
            }
        }
        END { exit inserted ? 0 : 1 }
    ' "$file" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    install -m 0644 "$tmp" "$file" -v
    rm -f "$tmp"
}

configure_map_hash() {
    MAP_HASH_PLACE="common"
    MAP_HASH_BUCKET_SIZE=128
    MAP_HASH_MAX_SIZE=65536

    if [[ "$EXTEND_MAP_HASH_SIZE" == true ]]; then
        MAP_HASH_BUCKET_SIZE=256
        MAP_HASH_MAX_SIZE=131072
    fi

    if [[ "$WRITE_MAP_HASH" != true ]]; then
        MAP_HASH_PLACE="none"
        return 0
    fi

    local nginx_conf=""
    nginx_conf="$(nginx_conf_file)"

    if [[ -f "$nginx_conf" ]] && nginx_conf_has_map_hash "$nginx_conf"; then
        local cur_bucket cur_max
        cur_bucket="$(nginx_conf_map_hash_value "$nginx_conf" map_hash_bucket_size)"
        cur_max="$(nginx_conf_map_hash_value "$nginx_conf" map_hash_max_size)"
        cur_bucket="${cur_bucket:-0}"
        cur_max="${cur_max:-0}"
        if ((cur_bucket < MAP_HASH_BUCKET_SIZE || cur_max < MAP_HASH_MAX_SIZE)); then
            MAP_HASH_PLACE="nginx_conf_update"
            info "nginx.conf 已有 map_hash_* (${cur_bucket}/${cur_max})，将提高到 ${MAP_HASH_BUCKET_SIZE}/${MAP_HASH_MAX_SIZE}"
        else
            MAP_HASH_PLACE="none"
            info "nginx.conf 已有足够大的 map_hash_* (${cur_bucket}/${cur_max})，tenant-common.conf 不再重复写入"
        fi
        return 0
    fi

    if [[ -f "$nginx_conf" ]] && nginx_conf_includes_early_maps "$nginx_conf"; then
        MAP_HASH_PLACE="nginx_conf"
        return 0
    fi

    MAP_HASH_PLACE="common"
}

# 上一版脚本用 10-/20-/30- 编号。留下会和现文件重复 listen/map/log_format。
remove_numbered_legacy_confs() {
    local name=""
    local path=""
    for name in "${NUMBERED_LEGACY_CONFS[@]}"; do
        path="${NGINX_CONFD%/}/${name}"
        if [[ -f "$path" ]]; then
            info "删除旧版带编号配置: $path"
            rm -fv "$path"
        fi
    done
}

# ---- 端口与防火墙检查(复用同目录 check_ports.sh) ----
# 时机:nginx 重载成功后,确认检查列表端口的监听与防火墙放行状态.
# 未通过时先询问是否尝试放行(默认对象 80,443);放行失败或后端无法识别则
# 告警并询问是否继续部署.非交互环境(无法询问)默认告警并继续,不中断部署.
_ports_check_info() {
    printf '[INFO] %s\n' "$*" >&2
}

_ports_check_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

find_check_ports_script() {
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" >/dev/null 2>&1 && pwd || true)"
    local c
    for c in "${CHECK_PORTS_SCRIPT:-}" \
        "${here}/check_ports.sh" \
        "${HOME:-}/sh/nginx_conf/reverse_proxy/scripts/check_ports.sh" \
        "/www/sh/nginx_conf/reverse_proxy/scripts/check_ports.sh"; do
        if [[ -n "$c" && -f "$c" ]]; then
            printf '%s' "$c"
            return 0
        fi
    done
    return 1
}

ask_yes_no() {
    local prompt
    prompt="$1"
    if [[ "$AUTO_YES" == true ]]; then
        _ports_check_info "已按 --yes 自动确认: ${prompt}"
        return 0
    fi
    # 必须能真实打开 /dev/tty 才能交互;仅 test -r 不可靠
    # (无控终端时 test 可通过,但 open 报 ENXIO).
    if ! : < /dev/tty 2>/dev/null; then
        return 2
    fi
    local ans
    ans=""
    printf '%s [y/N] ' "$prompt" >&2
    read -r ans < /dev/tty 2>/dev/null || return 1
    case "$ans" in
        y | Y | yes | YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

run_ports_check() {
    if [[ "$SKIP_PORTS_CHECK" == true ]]; then
        _ports_check_info "已跳过端口检查 (--skip-ports-check)."
        return 0
    fi
    local checker
    checker=""
    if ! checker="$(find_check_ports_script)"; then
        _ports_check_warn "未找到 check_ports.sh,跳过端口检查.部署完成后可手工执行同目录 check_ports.sh --ports 80,443."
        return 0
    fi
    local check_list
    check_list="${PORTS_CHECK_LIST:-80}"
    local fix_list
    fix_list="${PORTS_FIX_LIST:-80,443}"
    _ports_check_info "检查端口监听与防火墙放行状态: [${check_list}] (执行 bash ${checker} --ports ${check_list})."
    if bash "$checker" --ports "$check_list" >&2; then
        _ports_check_info "端口检查通过."
        return 0
    fi
    _ports_check_warn "端口检查未通过,详见上方输出."
    local answer
    answer=0
    ask_yes_no "是否尝试放行端口 [${fix_list}]" || answer=$?
    if [[ "$answer" -eq 0 ]]; then
        if bash "$checker" --fix --ports "$fix_list" >&2; then
            _ports_check_info "端口放行成功."
        else
            _ports_check_warn "端口放行未完成(后端无法识别或执行失败)."
        fi
        if bash "$checker" --ports "$check_list" >&2; then
            _ports_check_info "复查通过."
            return 0
        fi
        _ports_check_warn "复查仍未通过."
    elif [[ "$answer" -eq 2 ]]; then
        _ports_check_warn "非交互环境,跳过自动放行."
    fi
    answer=0
    ask_yes_no "是否继续完成部署" || answer=$?
    if [[ "$answer" -eq 0 ]]; then
        _ports_check_warn "已确认继续完成部署,端口问题请后续自行处理."
        return 0
    elif [[ "$answer" -eq 2 ]]; then
        _ports_check_warn "非交互环境,无法确认,默认继续完成部署.端口问题请后续自行处理."
        return 0
    fi
    _ports_check_warn "用户取消部署(端口检查未通过)."
    return 1
}
# ---- 端口与防火墙检查结束 ----

main() {
    parse_args "$@"

    if [[ -z "$TENANTS_DIR" ]]; then
        TENANTS_DIR="${NGINX_CONF_HOME%/}/tenants"
    fi
    resolve_proxy_pass_mode
    load_inputs

    NGINX_LOG_DIR="$(normalize_dir_slash "$NGINX_LOG_DIR")"
    [[ -n "$NGINX_LOG_DIR" ]] || die "NGINX_LOG_DIR 为空，请通过 -l 指定"

    local generated_at=""
    generated_at="$(date '+%Y-%m-%d %H:%M:%S %z')"

    configure_map_hash
    local emit_common_hash=false
    if [[ "$MAP_HASH_PLACE" == "common" ]]; then
        emit_common_hash=true
    fi

    local common_file maps_file gw_file
    common_file="${NGINX_CONFD%/}/${COMMON_CONF_NAME}"
    maps_file="${NGINX_CONFD%/}/${MAPS_CONF_NAME}"
    gw_file="${NGINX_CONFD%/}/${GATEWAY_CONF_NAME}"

    TMP_WORKDIR="$(mktemp -d)"
    trap '[[ -n "${TMP_WORKDIR:-}" ]] && rm -rf "$TMP_WORKDIR"' EXIT

    generate_common_map "$generated_at" "$emit_common_hash" > "${TMP_WORKDIR}/${COMMON_CONF_NAME}"
    generate_tenant_maps "$generated_at" > "${TMP_WORKDIR}/${MAPS_CONF_NAME}"
    generate_gateways "$generated_at" > "${TMP_WORKDIR}/${GATEWAY_CONF_NAME}"

    local id=""
    local routes_target=""
    mkdir -p "${TMP_WORKDIR}/tenants"
    for id in "${TENANT_IDS[@]}"; do
        mkdir -p "${TMP_WORKDIR}/tenants/${id}"
        generate_routes_map "$id" "$generated_at" > "${TMP_WORKDIR}/tenants/${id}/routes.map"
        check_local_ip "${TENANT_IP[$id]}"
    done

    info "脚本版本: $VERSION"
    info "nginx 配置目录: $NGINX_CONF_HOME"
    info "nginx include 目录: $NGINX_CONFD"
    info "nginx 日志目录: $NGINX_LOG_DIR"
    info "租户目录: $TENANTS_DIR"
    info "proxy_bind: $PROXY_BIND"
    info "proxy-pass-mode: $PROXY_PASS_MODE"
    info "map_hash: place=$MAP_HASH_PLACE bucket=$MAP_HASH_BUCKET_SIZE max=$MAP_HASH_MAX_SIZE"
    info "租户数量: ${#TENANT_IDS[@]}"
    for id in "${TENANT_IDS[@]}"; do
        info "租户 ${id}: listen ${TENANT_IP[$id]} -> \$$(tenant_backend_var "$id")"
    done

    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$DEV_MODE" == true ]]; then
            info "--dev 模式: 仅输出生成配置，不更新仓库、不更新 CF IP、不写文件、不 reload"
        else
            info "--dry-run 模式: 仅输出生成配置，不写文件、不执行 nginx -t、不 reload"
        fi

        if [[ "$MAP_HASH_PLACE" == "nginx_conf" ]]; then
            print_banner "$(nginx_conf_file) (将在 http{} 开头插入 map_hash)"
            map_hash_snippet
        elif [[ "$MAP_HASH_PLACE" == "nginx_conf_update" ]]; then
            print_banner "$(nginx_conf_file) (将提高已有 map_hash_*)"
            map_hash_snippet
        fi

        print_banner "$common_file"
        cat "${TMP_WORKDIR}/${COMMON_CONF_NAME}"
        print_banner "$maps_file"
        cat "${TMP_WORKDIR}/${MAPS_CONF_NAME}"
        print_banner "$gw_file"
        cat "${TMP_WORKDIR}/${GATEWAY_CONF_NAME}"

        for id in "${TENANT_IDS[@]}"; do
            routes_target="${TENANTS_DIR%/}/${id}/routes.map"
            warn_routes_mode_mismatch "$routes_target"
            if should_write_routes "$id" "$routes_target"; then
                print_banner "$routes_target"
                cat "${TMP_WORKDIR}/tenants/${id}/routes.map"
            else
                print_banner "$routes_target (已存在, 将跳过写入)"
                cat "$routes_target"
            fi
        done
        exit 0
    fi

    if [[ "$UPDATE_CODE" == true ]]; then
        info "获取/更新仓库代码..."
        bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh)
    else
        info "跳过仓库更新 (--no-update-code 或 --dev)"
    fi

    mkdir -pv "$NGINX_CONFD"
    mkdir -pv "$NGINX_LOG_DIR"
    mkdir -pv "$TENANTS_DIR"
    persist_proxy_pass_mode
    ln -snfv "$NGINX_LOG_DIR" "$NGINX_CONF_HOME/log"

    if [[ "$UPDATE_CF" == true ]]; then
        if resolve_sym_sh; then
            info "更新 Cloudflare real IP 配置..."
            cp -fv "$SYM_SH/nginx_conf/update_cf_ip_configs.sh" "$NGINX_CONF_HOME/update_cf_ip_configs.sh"
            bash "$NGINX_CONF_HOME/update_cf_ip_configs.sh" -s "$NGINX_CONFD" -n
        else
            die "找不到 nginx_conf/update_cf_ip_configs.sh，无法更新 CF IP. 可加 --no-update-cf，或先跑 update_repos.sh"
        fi
    else
        info "跳过 Cloudflare real IP 更新 (--no-update-cf 或 --dev)"
    fi

    if [[ "$CLEAN_LEGACY" == true ]]; then
        local legacy_conf="${NGINX_CONFD%/}/${LEGACY_CONF}"
        [[ -f "$legacy_conf" ]] && rm -fv "$legacy_conf"
    fi

    local multi_conf="${NGINX_CONFD%/}/${MULTI_IP_CONF}"
    if [[ -f "$multi_conf" ]]; then
        warn "检测到 ${multi_conf}。它也会 listen IP:80，可能和本方案抢入口. 确认不再使用后请自行删除."
    fi

    remove_numbered_legacy_confs

    if [[ "$MAP_HASH_PLACE" == "nginx_conf" || "$MAP_HASH_PLACE" == "nginx_conf_update" ]]; then
        local nginx_conf=""
        nginx_conf="$(nginx_conf_file)"
        if [[ "$MAP_HASH_PLACE" == "nginx_conf_update" ]]; then
            info "提高 ${nginx_conf} 中的 map_hash_* 到 ${MAP_HASH_BUCKET_SIZE}/${MAP_HASH_MAX_SIZE}"
            update_map_hash_in_nginx_conf "$nginx_conf"
        else
            info "在 ${nginx_conf} 的 http{} 开头写入 map_hash_*，避免已有 map 先按 2048/64 建表"
            if ! insert_map_hash_into_nginx_conf "$nginx_conf"; then
                warn "无法改 nginx.conf，回退把 map_hash_* 写进 ${COMMON_CONF_NAME}"
                generate_common_map "$generated_at" true > "${TMP_WORKDIR}/${COMMON_CONF_NAME}"
            fi
        fi
    fi

    info "写入 ${common_file}"
    install -m 0644 "${TMP_WORKDIR}/${COMMON_CONF_NAME}" "$common_file" -v
    info "写入 ${maps_file}"
    install -m 0644 "${TMP_WORKDIR}/${MAPS_CONF_NAME}" "$maps_file" -v
    info "写入 ${gw_file}"
    install -m 0644 "${TMP_WORKDIR}/${GATEWAY_CONF_NAME}" "$gw_file" -v

    for id in "${TENANT_IDS[@]}"; do
        mkdir -pv "${TENANTS_DIR%/}/${id}"
        routes_target="${TENANTS_DIR%/}/${id}/routes.map"
        warn_routes_mode_mismatch "$routes_target"
        if should_write_routes "$id" "$routes_target"; then
            info "写入 ${routes_target}"
            install -m 0644 "${TMP_WORKDIR}/tenants/${id}/routes.map" "$routes_target" -v
        else
            info "保留已有路由文件: ${routes_target}"
        fi
    done

    info "展示网关配置:"
    nl -ba "$gw_file"

    info "检查 nginx 配置..."
    nginx -t

    if [[ "$RELOAD_NGINX" == true ]]; then
        info "重载 nginx..."
        nginx -s reload
        run_ports_check || exit 1
    else
        info "跳过 nginx reload (--no-reload 或 --dev)"
        info "跳过端口检查(未 reload).重载后可执行同目录 check_ports.sh --ports ${PORTS_CHECK_LIST:-80} 复查."
    fi

    info "完成. 各租户维护自己的 ${TENANTS_DIR}/<id>/routes.map 后执行: nginx -t && nginx -s reload"
}

main "$@"
