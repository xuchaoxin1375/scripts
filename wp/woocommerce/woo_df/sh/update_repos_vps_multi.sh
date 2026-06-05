#!/usr/bin/env bash
# 将 VPS 配置成多出口 IP 反向代理服务器，基于 nginx/openresty.
# 关于此脚本的设计说明和图解,参考nginx_conf中的文档.
# 网络架构:
#   client -> Cloudflare -> B(reverse proxy server) -> A(origin server)
#
# 本脚本适用于反代服务器 B 拥有多个公网/内网出口 IP 的情况:
#   B1_IP -> A1_IP
#   B2_IP -> A2_IP
#   B3_IP -> A3_IP
#   ...
#
# 每一组映射含义:
#   B_IP:A_IP
#
# 其中:
#   B_IP = 当前反代服务器上用于 listen/proxy_bind 的 IP
#   A_IP = 被反代隐藏的后端源站服务器 IP
#
# 示例:
#   bash update_repos_vps_multi.sh \
#     -c /www/server/nginx/conf \
#     -d /www/server/panel/vhost/nginx \
#     -l /www/logs/ \
#     -m '10.0.0.11:203.0.113.11' \
#     -m '10.0.0.12:203.0.113.12' \
#     -m '10.0.0.13:203.0.113.13'
#
# 预览生成结果，不写文件、不 reload:
#   bash update_repos_vps_multi.sh --dev \
#     -l /www/logs/ \
#     -m '10.0.0.11:203.0.113.11' \
#     -m '10.0.0.12:203.0.113.12'
#
# 映射文件示例:
#   cat > ~/reverse_multi_ip.maps <<'MAPS'
#   # 格式: B_IP:A_IP，可带注释
#   10.0.0.11:203.0.113.11
#   10.0.0.12:203.0.113.12
#   10.0.0.13 203.0.113.13
#   MAPS
#
#   bash update_repos_vps_multi.sh --map-file ~/reverse_multi_ip.maps
#
# 注意:
#   1. B_IP 必须是当前反代服务器 B 上已经配置好的本机 IP，否则 nginx listen/proxy_bind 会失败。
#   2. A_IP 是后端源站服务器 IP，脚本默认反代到 A_IP:80。
#   3. 生成文件默认写入: $NGINX_CONFD/reverse_multi_ip.conf
#   4. 脚本会复用 update_repos_vps.sh 中更新仓库和更新 Cloudflare real IP 配置的流程。
#   5. --dev 仅用于调试输出，不进行任何写入或 reload(如果要输出到文件中查看,可以用shell的重定向功能保存到指定文件中)。
#

set -Eeuo pipefail

VERSION="20260604.15:40"

NGINX_CONF_HOME="/etc/nginx"
NGINX_CONFD="$NGINX_CONF_HOME/conf.d"
NGINX_LOG_DIR="/var/log/nginx/"

CONF_NAME="reverse_multi_ip.conf"
MAP_FILE=""
LEGACY_CONF="reverse_to_a.conf"
UPDATE_CODE=true
UPDATE_CF=true
RELOAD_NGINX=true
DRY_RUN=false
DEV_MODE=false
# FORCE=false

MAPPINGS=()

usage() {
    cat << EOF
部署多出口 IP 反向代理服务器的 shell 脚本. [version:$VERSION]

Usage:
    $0 [options]

核心功能:
    根据 N 组 B_IP:A_IP 映射关系，生成一个 nginx 配置文件:
        B1_IP -> A1_IP
        B2_IP -> A2_IP
        B3_IP -> A3_IP
        ...

    其中:
        B_IP = 当前反代服务器 B 上的本机 IP，用于 listen 和 proxy_bind
        A_IP = 后端源站服务器 A 的 IP，默认反代到 A_IP:80

Options:
    -c, --nginx-conf-dir <dir>
        nginx 配置文件家目录.
        常见值:
            /etc/nginx
            /www/server/nginx/conf

    -d, --nginx-confd-vhost <dir>
        nginx 自动 include 运行的配置文件目录.
        常见值:
            /etc/nginx/conf.d
            /www/server/panel/vhost/nginx

    -l, --log-dir <dir>
        nginx 日志文件家目录.
        常见值:
            /var/log/nginx
            /www/logs

    -m, --mapping <B_IP:A_IP[,B_IP:A_IP,...]>
        从命令行指定一组或多组映射(同一行内不同组间隔用逗号分隔).
        可以重复传入多次 -m.

        示例:
            -m '10.0.0.11:203.0.113.11'
            -m '10.0.0.11:203.0.113.11,10.0.0.12:203.0.113.12'

    -f, -M, --map-file <file>
        从文件读取映射关系.
        支持格式:
            B_IP:A_IP
            B_IP A_IP

        支持空行和 # 注释.
    --clean, --clean-legacy-conf 
        尝试删除旧配置文件.(老版本脚本产生的reverse_to_a.conf);
        也可以在重载nginx后自行删除引起错误的老文件.
        

    --conf-name <name>
        生成的 nginx 配置文件名.
        默认:
            reverse_multi_ip.conf

    --dry-run
        只输出即将生成的 nginx 配置到 stdout，不写文件、不执行 nginx -t、不 reload.


    --no-update-code
        不执行仓库拉取/更新逻辑.

    --no-update-cf
        不更新 Cloudflare real IP 配置.

    --no-reload
        生成配置并执行 nginx -t，但不执行 nginx -s reload.

    --dev
        开发/调试模式.
        跳过远程仓库拉去,直接使用本地仓库中的版本,临时修改测试比较合适
        等价于:
            --dry-run --no-update-code --no-update-cf --no-reload
    --force
        预留参数. 当前版本不强制覆盖额外文件，仅保留兼容入口.

    -h, --help
        显示帮助信息.

Examples:

    # 非宝塔 nginx 默认路径
    bash $0 \\
      -m '10.0.0.11:203.0.113.11' \\
      -m '10.0.0.12:203.0.113.12'

    # 宝塔路径
    bash $0 \\
      -c /www/server/nginx/conf \\
      -d /www/server/panel/vhost/nginx \\
      -l /www/logs/ \\
      -m '10.0.0.11:203.0.113.11' \\
      -m '10.0.0.12:203.0.113.12' \\
      -m '10.0.0.13:203.0.113.13'

    # 预览生成配置
    bash $0 --dev \\
      -l /www/logs/ \\
      -m '10.0.0.11:203.0.113.11' \\
      -m '10.0.0.12:203.0.113.12'

    # 从文件读取映射
    bash $0 \\
      -c /www/server/nginx/conf \\
      -d /www/server/panel/vhost/nginx \\
      -l /www/logs/ \\
      --map-file ~/reverse_multi_ip.maps
    
    #在线拉取脚本并一键部署(要求事先安装好nginx),下面的-c,-d,-l适合于宝塔安装的nginx
    bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos_vps_multi.sh) \\
    -c /www/server/nginx/conf \\
    -d /www/server/panel/vhost/nginx \\
    -l /www/wwwlogs/ \\
    -M <(
    echo "
    # 一行一个映射关系,修改为真实映射组
    B1_IP:A1_IP
    B2_IP:A2_IP
"
    )\\
    # --dev #预览

映射文件示例:
    默认使用分号':' 作为分隔符,也支持空格.
    # B_IP:A_IP
    10.0.0.11:203.0.113.11
    10.0.0.12:203.0.113.12

    # 也支持空格分隔
    10.0.0.13 203.0.113.13

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

normalize_dir_slash() {
    local dir="$1"
    [[ -n "$dir" ]] || return 0
    dir="${dir%/}/"
    printf '%s' "$dir"
}

add_mapping_pair() {
    local raw="$1"
    local b_ip=""
    local a_ip=""

    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 0

    # 去掉行尾注释: 10.0.0.11:203.0.113.11 # comment
    raw="${raw%%#*}"
    raw="$(trim "$raw")"
    [[ -n "$raw" ]] || return 0

    # 支持:
    #   B:A
    #   B A
    #   B=>A
    #   B->A
    raw="${raw//=>/:}"
    raw="${raw//->/:}"

    if [[ "$raw" == *:* ]]; then
        b_ip="${raw%%:*}"
        a_ip="${raw#*:}"
    else
        # shellcheck disable=SC2206
        local parts=($raw)
        [[ ${#parts[@]} -ge 2 ]] || die "映射格式错误: [$raw], 期望 B_IP:A_IP 或 B_IP A_IP"
        b_ip="${parts[0]}"
        a_ip="${parts[1]}"
    fi

    b_ip="$(trim "$b_ip")"
    a_ip="$(trim "$a_ip")"

    [[ -n "$b_ip" ]] || die "映射中的 B_IP 为空: [$raw]"
    [[ -n "$a_ip" ]] || die "映射中的 A_IP 为空: [$raw]"

    is_ipv4 "$b_ip" || die "B_IP 不是合法 IPv4: [$b_ip], 原始映射: [$raw]"
    is_ipv4 "$a_ip" || die "A_IP 不是合法 IPv4: [$a_ip], 原始映射: [$raw]"

    MAPPINGS+=("${b_ip}:${a_ip}")
}

add_mapping_arg() {
    local arg="$1"
    local pair=""

    IFS=',' read -r -a pairs <<< "$arg"
    for pair in "${pairs[@]}"; do
        add_mapping_pair "$pair"
    done
}

read_map_file() {
    local file="$1"
    # 考虑到用户可能通过进程替换<(echo ...)的方式指定,不按照普通方式检查文件存在性
    # [[ -f "$file" ]] || die "映射文件不存在: $file"

    local line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        add_mapping_pair "$line"
    done < "$file"
}
# 命令行参数解析
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

            -m | --mapping)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                add_mapping_arg "$2"
                shift
                ;;

            -f | -M | --map-file)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                MAP_FILE="$2"
                shift
                ;;
            --clean | --clean-legacy-conf)
                LEGACY_CONF="$2"

                shift
                ;;
            --conf-name)
                [[ $# -ge 2 ]] || die "$1 需要参数"
                CONF_NAME="$2"
                shift
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

            # --force)
            #     FORCE=true
            #     ;;

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

generate_nginx_conf() {
    local generated_at="$1"
    local mapping_count="${#MAPPINGS[@]}"
    local idx=""
    local item=""
    local b_ip=""
    local a_ip=""

    cat << EOF
# ======================================================================
# AUTO GENERATED FILE - DO NOT EDIT MANUALLY
# ======================================================================
# 生成日期时间(本配置更新时间):
#   ${generated_at}
#
# 文件用途:
#   多出口 IP 反向代理配置.
#
#
# 生成脚本:
#   update_repos_vps_multi.sh
#
# 脚本版本:
#   ${VERSION}
#
# 配置文件:
#   ${CONF_NAME}
#
# 映射数量:
#   ${mapping_count}
#
# 映射含义:
#   B_IP:A_IP
#
#   B_IP = 当前反代服务器 B 上的本机 IP，用于 listen 和 proxy_bind.
#   A_IP = 后端源站服务器 A 的 IP，默认代理到 A_IP:80.
#
# 网络链路:
#   client -> Cloudflare -> B(reverse proxy gateway) -> A(origin server)
#
# 重要说明:
#   1. 本文件由脚本自动生成，不建议手动修改。
#   2. 若需修改映射关系，请调整脚本参数 -m 或 --map-file 后重新生成。
#   3. B_IP 必须已经配置在当前服务器网卡上。
#   4. proxy_bind 会强制 B 访问对应 A 时使用指定 B_IP 作为源 IP。
#   5. 每组映射会生成一个 upstream 和一个 server 块。
#   6. 当前配置默认只监听 HTTP 80，如需 HTTPS/443，可在脚本中扩展生成逻辑。
#
# 当前映射表:
EOF

    idx=1
    for item in "${MAPPINGS[@]}"; do
        b_ip="${item%%:*}"
        a_ip="${item#*:}"
        cat << EOF
#   b${idx}: ${b_ip} -> a${idx}: ${a_ip}
EOF
        idx=$((idx + 1))
    done

    cat << 'EOF'
#
# ======================================================================


# ----------------------------------------------------------------------
# WebSocket / HTTP Upgrade 连接头处理
# ----------------------------------------------------------------------
# 当客户端请求包含 Upgrade 头时，Connection 设为 upgrade；
# 否则设为 close。用于兼容 WebSocket、SSE 等长连接场景。
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}


# ----------------------------------------------------------------------
# X-Forwarded-Proto 兼容处理
# ----------------------------------------------------------------------
# Cloudflare Flexible 模式下，B 收到的请求可能是 HTTP，
# 但客户端访问 Cloudflare 时可能是 HTTPS。
#
# 如果 Cloudflare 已传入 X-Forwarded-Proto，则沿用它；
# 如果没有，则回退到当前 nginx 看到的 $scheme。
map $http_x_forwarded_proto $proxy_x_forwarded_proto {
    default $http_x_forwarded_proto;
    ''      $scheme;
}


# ----------------------------------------------------------------------
# 详细日志格式
# ----------------------------------------------------------------------
# 用于排查:
#   - 客户端真实 IP
#   - Cloudflare IP
#   - upstream 地址
#   - upstream 状态码
#   - 响应耗时
#   - Host/server_name/server_addr
#   - CF-Ray 等 Cloudflare 调试字段
log_format cf_proxy_main
    '$remote_addr - $remote_user [$time_local] "$request" '
    'status=$status body=$body_bytes_sent '
    'host="$host" server_name="$server_name" '
    'server_addr="$server_addr" '
    'request_time=$request_time '
    'upstream_addr="$upstream_addr" '
    'upstream_status="$upstream_status" '
    'upstream_response_time="$upstream_response_time" '
    'cf_ray="$http_cf_ray" '
    'cf_connecting_ip="$http_cf_connecting_ip" '
    'xff="$http_x_forwarded_for" '
    'realip_remote_addr="$realip_remote_addr" '
    'referer="$http_referer" '
    'ua="$http_user_agent"';

EOF

    idx=1
    for item in "${MAPPINGS[@]}"; do
        b_ip="${item%%:*}"
        a_ip="${item#*:}"

        cat << EOF

# ======================================================================
# 映射组 b${idx} -> a${idx}
# ======================================================================
#
# B 侧出口/监听 IP:
#   ${b_ip}
#
# A 侧后端源站 IP:
#   ${a_ip}
#
# 请求路径:
#   client -> Cloudflare -> ${b_ip}:80 -> ${a_ip}:80
#
# 设计意图:
#   1. 监听 ${b_ip}:80。
#   2. 将访问 ${b_ip}:80 的请求转发到 ${a_ip}:80。
#   3. 使用 proxy_bind ${b_ip}，确保 B 连接 A 时的源 IP 为 ${b_ip}。
#   4. 保留 Host 头，使后端 A 上的宝塔/OpenResty/nginx 可继续按域名分发站点。
#   5. 传递 Cloudflare 与真实访客 IP 相关请求头，便于后端日志分析。
#

upstream a${idx}_backend {
    # 后端源站服务器 a${idx}.
    # 当前默认代理到 HTTP 80 端口。
    server ${a_ip}:80;

    # 复用 B->A 的 TCP 连接，降低频繁握手带来的开销。
    keepalive 32;
}


server {
    # 只监听当前映射组指定的 B_IP.
    # 注意: ${b_ip} 必须已经绑定在当前 VPS/服务器网卡上。
    listen ${b_ip}:80 default_server;

    # 通配所有 Host.
    # 后端 A 仍然会收到原始 Host，并由 A 自己按域名分发站点。
    server_name _;

    # 每组映射单独记录 access/error 日志，便于按出口 IP 排查问题。
    access_log ${NGINX_LOG_DIR}b${idx}_to_a${idx}_access.log cf_proxy_main;
    error_log  ${NGINX_LOG_DIR}b${idx}_to_a${idx}_error.log warn;

    # 健康检查路径.
    # 可用于确认当前 b${idx}->a${idx} 映射对应的 nginx server 块已命中。
    location = /__b_health {
        access_log off;
        return 200 "b${idx} -> a${idx} gateway ok\n";
        add_header Content-Type text/plain;
    }

    location / {
        # 将请求转发到当前映射组的 upstream.
        proxy_pass http://a${idx}_backend;

        # 关键配置:
        # 强制 B 连接 A 时使用当前 B_IP 作为源 IP。
        proxy_bind ${b_ip};

        # 保留原始 Host，让后端 A 按域名识别站点。
        proxy_set_header Host \$host;

        # 真实访客 IP 链路.
        # 若前面已经通过 cf_realip.conf 正确恢复 Cloudflare 访客 IP，
        # 则 \$remote_addr 通常就是客户真实 IP。
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        # Cloudflare Flexible/Full 等模式下的协议透传.
        # 不直接写 \$scheme，避免 B 收到 HTTP 时误导后端。
        proxy_set_header X-Forwarded-Proto \$proxy_x_forwarded_proto;
        proxy_set_header X-Forwarded-Ssl \$proxy_x_forwarded_proto;

        # Cloudflare 调试和溯源头.
        proxy_set_header CF-Connecting-IP \$http_cf_connecting_ip;
        proxy_set_header CF-Ray \$http_cf_ray;
        proxy_set_header CF-Visitor \$http_cf_visitor;

        # WebSocket / SSE / HTTP Upgrade 兼容.
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        # 上传大小和超时设置，可按业务需要调整。
        client_max_body_size 512m;
        proxy_connect_timeout 10s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;

        # 调试响应头.
        # 稳定运行后可按需删除或在脚本中做成开关。
        add_header X-Debug-Gateway "b${idx}-to-a${idx}" always;
        add_header X-Debug-Server-Addr \$server_addr always;
        add_header X-Debug-Upstream-Addr \$upstream_addr always;
        add_header X-Debug-Upstream-Status \$upstream_status always;
    }
}

EOF

        idx=$((idx + 1))
    done
}

main() {
    parse_args "$@"
    # 尝试清理旧配置(可能会影响到新生成的配置.)
    local legacy_conf="$NGINX_CONFD/$LEGACY_CONF"
    [[ -f $legacy_conf ]] && rm -fv "$legacy_conf"

    if [[ -n "$MAP_FILE" ]]; then
        read_map_file "$MAP_FILE"
    fi

    [[ ${#MAPPINGS[@]} -gt 0 ]] || {

        usage >&2
        die "必须提供至少一组映射关系. 示例: -m '10.0.0.11:203.0.113.11'"
    }

    NGINX_LOG_DIR="$(normalize_dir_slash "$NGINX_LOG_DIR")"

    [[ -n "$NGINX_LOG_DIR" ]] || die "NGINX_LOG_DIR 为空，请通过 -l 指定日志目录，或使用默认值 /var/log/nginx/"

    local generated_at=""
    generated_at="$(date '+%Y-%m-%d %H:%M:%S %z')"

    local conf_file=""
    conf_file="${NGINX_CONFD%/}/${CONF_NAME}"

    local tmp_file=""
    tmp_file="$(mktemp)"

    info "脚本版本: $VERSION"
    info "nginx 配置目录: $NGINX_CONF_HOME"
    info "nginx include 目录: $NGINX_CONFD"
    info "nginx 日志目录: $NGINX_LOG_DIR"
    info "目标配置文件: $conf_file"
    info "映射数量: ${#MAPPINGS[@]}"

    local idx=1
    local item=""
    for item in "${MAPPINGS[@]}"; do
        info "映射 b${idx}->a${idx}: ${item%%:*} -> ${item#*:}"
        idx=$((idx + 1))
    done

    generate_nginx_conf "$generated_at" > "$tmp_file"

    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$DEV_MODE" == true ]]; then
            info "--dev 模式: 仅输出生成配置，不更新仓库、不更新 CF IP、不写文件、不 reload"
        else
            info "--dry-run 模式: 仅输出生成配置，不写文件、不执行 nginx -t、不 reload"
        fi

        cat "$tmp_file"
        rm -f "$tmp_file"
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
    # 这会创建/etc/nginx/log,包含nginx日志,例如# ln -snfv /var/log/nginx /etc/nginx/log
    ln -snfv "$NGINX_LOG_DIR" "$NGINX_CONF_HOME/log"

    if [[ "$UPDATE_CF" == true ]]; then
        info "更新 Cloudflare real IP 配置..."
        ln -snfv "$HOME/sh/nginx_conf/update_cf_ip_configs.sh" "$NGINX_CONF_HOME/update_cf_ip_configs.sh"
        bash "$NGINX_CONF_HOME/update_cf_ip_configs.sh" -s "$NGINX_CONFD" -n
    else
        info "跳过 Cloudflare real IP 更新 (--no-update-cf 或 --dev)"
    fi

    info "写入 nginx 配置文件: $conf_file"
    install -m 0644 "$tmp_file" "$conf_file"
    rm -f "$tmp_file"

    info "展示生成后的配置文件:"
    nl -ba "$conf_file"

    info "检查 nginx 配置..."
    nginx -t

    if [[ "$RELOAD_NGINX" == true ]]; then
        info "重载 nginx..."
        nginx -s reload
    else
        info "跳过 nginx reload (--no-reload 或 --dev)"
    fi

    info "完成."
}

main "$@"
