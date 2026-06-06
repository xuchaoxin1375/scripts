#!/usr/bin/env bash
# 将vps配置成反向代理服务器(反代网关),基于nginx(openresty).
# 测试系统为ubuntu,nginx版本为标准安装(或者通过仓库中的nginx_conf/upgrade-nginx-ubt.sh安装较新版本)
#
# bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos_vps.sh) #  -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ -i <upstream_ip>
#
# 对于使用过本仓库的早期版本的宝塔用户,注意,如果早期的网站的/www/server/panel/vhost/nginx/目录中的网站配置
# 包含了include com.conf的引用语句,请考虑全部移除,或者情况com.conf的内容,
# 或者更新到最新的版本,使用此命令进行更新: bash /www/sh/nginx_conf/update_nginx_vhosts_conf.sh -m old --force

VERSION="20260606.0903"

NGINX_CONF_HOME="/etc/nginx"
NGINX_CONFD="$NGINX_CONF_HOME/conf.d" # nginx自动include运行的配置文件目录
NGINX_LOG_DIR=""                      # /var/log/nginx
IP=""
DEV_MODE=false      # 调试模式,不拉取远程代码,使用本地代码
GATEWAY_MODE=simple # hostmap
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
EXAMPLES:
$0 -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx
# 非宝塔方案(apt安装的情况)
bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos_vps.sh) -i <upstream_ip>

# 宝塔方案
bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos_vps.sh) -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/  -i <upstream_ip>
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
                NGINX_CONF_HOME="$2"
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
if [[ $DEV_MODE == true ]]; then
    echo "[debug]:开发者模式,跳过拉取远程代码,使用本地代码..."
else
    # 获取仓库代码,优先尝试幂等的克隆脚本(默认从github获取,gitee适合国内服务器):
    bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh)
fi
# 确保NGINX_LOG_DIR末尾有且仅有一个斜杠:
shopt -s extglob
NGINX_LOG_DIR="${NGINX_LOG_DIR%%+(/)}/"
echo "检查当前日志路径取值: [$NGINX_LOG_DIR]"
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

# cf_realip.conf的更新脚本update_cf_ip_configs.sh映射到$NGINX_CONF_HOME
ln -snfv "$sh/nginx_conf/update_cf_ip_configs.sh" "$NGINX_CONF_HOME/update_cf_ip_configs.sh"
# 创建/etc/nginx/log,包含nginx日志,例如# ln -snfv /var/log/nginx /etc/nginx/log
ln -snfv "$NGINX_LOG_DIR" "$NGINX_CONF_HOME/log"

# 运行一次脚本 cf_realip.conf的更新脚本(不主动重载,后续一并重载)
# 其生成的配置将位于$NGINX_CONFD/cf_realip.conf
bash "$NGINX_CONF_HOME/update_cf_ip_configs.sh" -s "$NGINX_CONFD" -n

echo "将反代服务器nginx配置文件复制一份到:[$NGINX_CONFD]..."
# 不要用ln 创建链接,因为这里的文件要自定义修改.
if [[ $GATEWAY_MODE == "simple" ]]; then
    cp -fv "$sh"/nginx_conf/reverse_proxy/reverse_to_a.conf "$NGINX_CONFD/"
    reverse_conf="$NGINX_CONFD/reverse_to_a.conf"
elif [[ $GATEWAY_MODE == "hostmap" ]]; then
    # 情况特殊一点,建议放到配置总目录NGINX_CONF_HOME

    # cp -rfv "$sh"/nginx_conf/reverse_proxy/gateway/ "$NGINX_CONF_HOME/"
    gateway_dir_tpl="$sh"/nginx_conf/reverse_proxy/gateway
    gateway_dir="$NGINX_CONF_HOME/gateway"
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

        # [[ $NGINX_LOG_DIR ]] && sed -i "s|/etc/nginx/|$NGINX_CONF_HOME|g" "$reverse_conf"

    fi
    # 公共配置
    [[ $NGINX_LOG_DIR ]] && sed -i "s|/var/log/nginx/|$NGINX_LOG_DIR|g" "$reverse_conf"
    # 查看修改后的文件
    cat "$reverse_conf" | nl
else
    echo "请检查文件:[$reverse_conf]是否存在" >&2 && exit 1
fi

echo "重载nginx"
nginx -t && nginx -s reload
