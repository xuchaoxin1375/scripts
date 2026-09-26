#!/usr/bin/env bash
# 将vps配置成反向代理服务器(反代网关),基于nginx(openresty).
# 测试系统为ubuntu,nginx版本为标准安装(或者通过仓库中的nginx_conf/upgrade-nginx-ubt.sh安装较新版本)
#
# bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/nginx_conf/reverse_proxy/scripts/base.sh) #  -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ -i <upstream_ip>
#
# 对于使用过本仓库的早期版本的宝塔用户,注意,如果早期的网站的/www/server/panel/vhost/nginx/目录中的网站配置
# 包含了include com.conf的引用语句,请考虑全部移除,或者情况com.conf的内容,
# 或者更新到最新的版本,使用此命令进行更新: bash /www/sh/nginx_conf/update_nginx_vhosts_conf.sh -m old --force

VERSION="20260910.2230"

NGINX_CONF_DIR="/etc/nginx"
NGINX_CONFD="$NGINX_CONF_DIR/conf.d" # nginx自动include运行的配置文件目录
NGINX_LOG_DIR="/var/log/nginx"       # 默认值为标准安装的nginx的默认路径 /var/log/nginx
IP=""
DEV_MODE=false      # 调试模式,不拉取远程代码,使用本地代码
GATEWAY_MODE=simple # hostmap
# hostmap 下的 proxy_pass 形态: url (默认, 与现网 gateway map 一致) 或 hostport
PROXY_PASS_MODE="url"
PROXY_PASS_MODE_CLI=false
SKIP_ROUTES_CHECK=false # --no-check-routes: 跳过 routes.map 格式检查(表很大时省时间)
# 端口检查:重载后检查的端口列表 / 询问放行时的操作对象 / 跳过开关 / 非交互自动确认
PORTS_CHECK_LIST="80"
PORTS_FIX_LIST="80,443"
SKIP_PORTS_CHECK=false
AUTO_YES=false

# UPDATE_CODE=false
# 参数解析
args_pos=()
parse_args() {
    usage="
部署反代服务器的shell脚本.[version:$VERSION]
Usage: $0 [options]
Options:
    -c, --nginx-conf-dir <dir>         nginx配置文件家目录(常见目录:/etc/nginx/,/www/server/nginx/conf)
    -d, --nginx-confd-vhost <dir>   nginx自动include运行的配置文件目录(常见目录:/etc/nginx/conf.d/,/www/server/panel/vhost/nginx)
    -l, --log-home <dir>           日志文件家目录(常见目录:/var/log/nginx/,/www/server/nginx/logs)
    -i, --ip <ip>                 指定反代的上游ip(需要对外隐藏的后端服务器ip),而不是反代服务器本身的ip
    -h, --help                  显示帮助信息
    -D, --debug                   开发者模式,跳过拉取远程代码,使用本地代码,并打印调试信息
    -G, --gateway <mode>           反代模式,可选值:simple,hostmap,默认为simple
    --proxy-pass-mode <hostport|url>
                                   仅 hostmap 有效. 控制 routes.map 与 proxy_pass 的搭配.
                                   url (hostmap 默认): map 写 http://ip:port ，proxy_pass \$backend_origin;
                                   hostport:           map 写 ip:port        ，proxy_pass http://\$backend_origin;
                                   与 tenants.sh 的同名选项含义一致.
                                    未传时沿用 $NGINX_CONF_DIR/gateway/proxy-pass-mode ；没有记录则 url.
                                    simple 模式会忽略此选项.
    --no-check-routes            跳过 routes.map.conf 格式检查(表很大时可省几十秒).
    --ports-check <list>         部署后检查的端口列表,默认 80
    --fix-ports <list>             询问放行时的操作对象,默认 80,443
    --skip-ports-check             跳过部署后的端口与防火墙检查
    --yes                          端口检查的交互询问一律按 yes 处理
EXAMPLES:

# 非宝塔方案(apt或标准脚本安装的情况)

## simple
bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/nginx_conf/reverse_proxy/scripts/base.sh) -i <upstream_ip> # -G hostmap 
## hostmap (默认 url: map 里写 http://ip:port)
bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/nginx_conf/reverse_proxy/scripts/base.sh)  -G hostmap

## hostmap + hostport (map 里写 ip:port，和 tenants 默认相同)
bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/nginx_conf/reverse_proxy/scripts/base.sh)  -G hostmap --proxy-pass-mode hostport

# 宝塔方案

## simple
bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/nginx_conf/reverse_proxy/scripts/base.sh) -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/  -i <upstream_ip>

## hostmap

bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/nginx_conf/reverse_proxy/scripts/base.sh) -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/  -G hostmap 

    "
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            # -u | --update-code)
            #     UPDATE_CODE=true
            #     ;;
            -c | --nginx-conf-dir)
                NGINX_CONF_DIR="$2"
                shift
                ;;
            -d | --nginx-confd-vhost)
                NGINX_CONFD="$2"
                shift
                ;;
            -i | --ip)
                IP="$2"
                shift
                ;;
            -l | --log-dir)
                NGINX_LOG_DIR="$2"
                shift
                ;;
            -D | --debug)
                DEV_MODE=true
                # DRY_RUN=true
                # UPDATE_CODE=false
                # UPDATE_CF=false
                # RELOAD_NGINX=false
                ;;
            -G | --gateway)
                GATEWAY_MODE="$2"
                shift
                ;;
            --proxy-pass-mode)
                PROXY_PASS_MODE="$2"
                PROXY_PASS_MODE_CLI=true
                shift
                ;;
            --no-check-routes | --no-routes-check)
                SKIP_ROUTES_CHECK=true
                ;;
            --ports-check)
                PORTS_CHECK_LIST="$2"
                shift
                ;;
            --fix-ports)
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
            -?*)
                echo "Unknown option:$1" >&2 #输出错误信息到标准错误
                echo "$usage" >&2
                exit 2 #直接退出脚本
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    # 参数解析并调整完毕
}
parse_args "$@"
set -- "${args_pos[@]}"

trim() {
    local s="$*"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
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
    local saved="" file="" normalized=""
    file="$NGINX_CONF_DIR/gateway/proxy-pass-mode"

    if [[ "$GATEWAY_MODE" != "hostmap" ]]; then
        if [[ "$PROXY_PASS_MODE_CLI" == true ]]; then
            echo "[WARN] --proxy-pass-mode 只对 -G hostmap 有效，simple 模式已忽略." >&2
        fi
        return 0
    fi

    if [[ -f "$file" ]]; then
        saved="$(trim "$(head -n 1 "$file")")"
        saved="$(normalize_proxy_pass_mode "$saved" || true)"
    fi

    if [[ "$PROXY_PASS_MODE_CLI" == true ]]; then
        normalized="$(normalize_proxy_pass_mode "$PROXY_PASS_MODE")" || {
            echo "[Error] 未知 --proxy-pass-mode: [$PROXY_PASS_MODE]. 使用 hostport 或 url" >&2
            exit 1
        }
        PROXY_PASS_MODE="$normalized"
        if [[ -n "$saved" && "$saved" != "$PROXY_PASS_MODE" ]]; then
            echo "[WARN] proxy-pass-mode 从 [$saved] 改为 [$PROXY_PASS_MODE]. 请把 gateway/maps/routes.map.conf 改成对应格式再 reload." >&2
        fi
        return 0
    fi

    if [[ -n "$saved" ]]; then
        PROXY_PASS_MODE="$saved"
        echo "[INFO] 沿用 $file : $PROXY_PASS_MODE"
        return 0
    fi

    PROXY_PASS_MODE="url"
}

apply_gateway_proxy_pass_mode() {
    local conf="$1"
    if [[ "$PROXY_PASS_MODE" == "hostport" ]]; then
        sed -i -E             -e 's|^[[:space:]]*proxy_pass[[:space:]]+\$backend_origin;|# proxy_pass $backend_origin;|'             -e 's|^[[:space:]]*#[[:space:]]*proxy_pass[[:space:]]+http://\$backend_origin;|        proxy_pass http://$backend_origin;|'             "$conf"
        echo "[INFO] gateway.conf: proxy_pass http://\$backend_origin;  (hostport)"
    else
        # 模板默认已是 url；若上次改成了 hostport，这里再拷过模板后仍是 url。
        echo "[INFO] gateway.conf: proxy_pass \$backend_origin;  (url)"
    fi
}

persist_proxy_pass_mode() {
    local dir="$NGINX_CONF_DIR/gateway"
    mkdir -pv "$dir"
    printf '%s
' "$PROXY_PASS_MODE" > "$dir/proxy-pass-mode"
    echo "[INFO] 记录 proxy-pass-mode=$PROXY_PASS_MODE -> $dir/proxy-pass-mode"
}

warn_hostmap_routes_mode() {
    local file="$1"
    if [[ "$SKIP_ROUTES_CHECK" == true ]]; then
        echo "[INFO] 跳过 routes.map 格式检查 (--no-check-routes)."
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
                printf "[WARN] %s: 另有 %d 行格式不符. url 用 http://ip:port，hostport 用 ip:port\n", mapfile, mismatch - 3 > "/dev/stderr"
            else if (mismatch > 0)
                printf "[WARN] %s: 请改成 %s 格式后再 reload\n", mapfile, mode > "/dev/stderr"
        }
    ' "$file"
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

# main
if [[ $DEV_MODE == true ]]; then
    echo "[debug]:开发者模式,跳过拉取远程代码,使用本地代码..."
else
    # 获取仓库代码,优先尝试幂等的克隆脚本(默认从github获取,gitee适合国内服务器):
    bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh) # -U
fi
# 确保NGINX_LOG_DIR末尾有且仅有一个斜杠:
shopt -s extglob
NGINX_LOG_DIR="${NGINX_LOG_DIR%%+(/)}/"
echo "检查当前日志路径取值: [$NGINX_LOG_DIR]"
resolve_proxy_pass_mode
echo "GATEWAY_MODE=[$GATEWAY_MODE] proxy-pass-mode=[$PROXY_PASS_MODE]"
# echo "指定的IP=[$IP]"

# 确保相关目录存在:
mkdir -pv "$NGINX_CONFD"
mkdir -pv "$NGINX_LOG_DIR"

SH_SYM="$HOME/sh"
sh="$SH_SYM"
# 直接clone也行,但是缺乏幂等性,反复运行会出错.
# repos="$HOME/repos"
# scripts="$repos/scripts"
# repo_source="gitee.com" # 根据需要可以切换为github.com
# mkdir -p "$repos"
# # clone代码
# git clone --recursive --depth 1 --shallow-submodules https://"$repo_source"/xuchaoxin1375/scripts.git "$scripts"

# cf_realip.conf的更新脚本update_cf_ip_configs.sh映射到$NGINX_CONF_DIR
cp -fv "$sh/nginx_conf/update_cf_ip_configs.sh" "$NGINX_CONF_DIR/update_cf_ip_configs.sh"
# 创建/etc/nginx/log,包含nginx日志,例如# ln -snfv /var/log/nginx /etc/nginx/log
ln -snfv "$NGINX_LOG_DIR" "$NGINX_CONF_DIR/log"

# 运行一次脚本 cf_realip.conf的更新脚本(不主动重载,后续一并重载)
# 其生成的配置将位于$NGINX_CONFD/cf_realip.conf
bash "$NGINX_CONF_DIR/update_cf_ip_configs.sh" -s "$NGINX_CONFD" -n

echo "将反代服务器nginx配置文件复制一份到:[$NGINX_CONFD]..."
# 不要用ln 创建链接,因为这里的文件要自定义修改.
if [[ $GATEWAY_MODE == "simple" ]]; then
    cp -fv "$sh"/nginx_conf/reverse_proxy/reverse_to_a.conf "$NGINX_CONFD/"
    reverse_conf="$NGINX_CONFD/reverse_to_a.conf"
elif [[ $GATEWAY_MODE == "hostmap" ]]; then
    # 情况特殊一点,建议放到配置总目录NGINX_CONF_DIR

    # cp -rfv "$sh"/nginx_conf/reverse_proxy/gateway/ "$NGINX_CONF_DIR/"
    gateway_dir_tpl="$sh"/nginx_conf/reverse_proxy/gateway
    gateway_dir="$NGINX_CONF_DIR/gateway"
    gateway_conf="$sh"/nginx_conf/reverse_proxy/gateway.conf
    echo "复制[$gateway_conf]配置文件到[$NGINX_CONFD]..."
    cp -fv "$sh"/nginx_conf/reverse_proxy/gateway.conf "$NGINX_CONFD/" || {
        echo "复制失败,退出" >&2
        exit 1
    }
    mkdir -pv "$gateway_dir"
    # 更新时覆盖的部分
    cp -rfv "$gateway_dir_tpl"/snippets "$gateway_dir/"
    # 更新时要跳过的部分(用户自定义的映射地图)
    echo "检查maps目录[$gateway_dir/maps]是否已存在"
    if [[ -d $gateway_dir/maps ]]; then
        echo "检测到maps目录已存在,跳过更新"
    else
        echo "检测到maps目录不存在,创建对于maps模板目录"
        cp -rfv "$gateway_dir_tpl/maps" "$gateway_dir/maps/"
    fi

    reverse_conf="$NGINX_CONFD/gateway.conf"
    apply_gateway_proxy_pass_mode "$reverse_conf"
    persist_proxy_pass_mode
    warn_hostmap_routes_mode "$gateway_dir/maps/routes.map.conf"
else
    echo "请指定正确的GATEWAY_MODE参数." >&2
    exit 1
fi

if [[ -e $reverse_conf ]]; then
    echo "正在用sed编辑文件:[$reverse_conf]..."
    # 编辑nginx配置文件(reverse_to_a.conf)
    if [[ $GATEWAY_MODE == "simple" ]]; then
        # [[ $IP ]] || echo "请设置需要被反代隐藏的上游IP" >&2 && exit 1
        [[ $IP ]] || {
            echo "请设置需要被反代隐藏的上游IP" >&2
            exit 1
        }
        #
        sed -i "s|A_IP|$IP|g" "$reverse_conf"

    elif [[ $GATEWAY_MODE == "hostmap" ]]; then

        echo "[$GATEWAY_MODE]:采用map映射,可跳过上游IP设置"

        # [[ $NGINX_LOG_DIR ]] && sed -i "s|/etc/nginx/|$NGINX_CONF_DIR|g" "$reverse_conf"

    fi
    # 公共配置
    ## 如果默认路径被改动,则需要修改
    [[ $NGINX_LOG_DIR != '/var/log/nginx/' ]] && sed -i "s|/var/log/nginx/|$NGINX_LOG_DIR|g" "$reverse_conf"
    # 查看修改后的文件
    cat "$reverse_conf" | nl
else
    echo "请检查文件:[$reverse_conf]是否存在" >&2 && exit 1
fi

echo "重载nginx"
nginx -t && nginx -s reload

run_ports_check || exit 1

bash ~/sh/shellrc_addition.sh && exec bash # 激活bash样式和环境
