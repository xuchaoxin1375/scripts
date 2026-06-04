#!/usr/bin/env bash
# 将vps配置成反向代理服务器(反代网关),基于nginx(openresty).
# 测试系统为ubuntu,nginx版本为标准安装(或者通过仓库中的nginx_conf/upgrade-nginx-ubt.sh安装较新版本)
#
# bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos_vps.sh) #  -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ -i <upstream_ip>
#
# 对于使用过本仓库的早期版本的宝塔用户,注意,如果早期的网站的/www/server/panel/vhost/nginx/目录中的网站配置
# 包含了include com.conf的引用语句,请考虑全部移除,或者情况com.conf的内容,
# 或者更新到最新的版本,使用此命令进行更新: bash /www/sh/nginx_conf/update_nginx_vhosts_conf.sh -m old --force

VERSION="20260603.1043"

NGINX_CONF_HOME="/etc/nginx"
NGINX_CONFD="$NGINX_CONF_HOME/conf.d" # nginx自动include运行的配置文件目录
NGINX_LOG_DIR=""                      # /var/log/nginx
IP=""
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

# 获取仓库代码,优先尝试幂等的克隆脚本(默认从github获取,gitee适合国内服务器):
bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh)

# 确保NGINX_LOG_DIR末尾有且仅有一个斜杠:
shopt -s extglob
NGINX_LOG_DIR="${NGINX_LOG_DIR%%+(/)}/"
echo "检查当前日志路径取值: [$NGINX_LOG_DIR]"
echo "指定的IP=[$IP]"

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

# cf_realip.conf的更新脚本映射到/etc/nginx/conf.d/cf_realip.conf
ln -snfv "$sh/nginx_conf/update_cf_ip_configs.sh" "$NGINX_CONF_HOME/update_cf_ip_configs.sh"

# 运行一次脚本 cf_realip.conf的更新脚本(不主动重载,后续一并重载)
bash "$NGINX_CONF_HOME/update_cf_ip_configs.sh" -n

echo "将反代服务器nginx配置文件复制一份到:[$NGINX_CONFD]..."
# 不要用ln 创建链接,因为这里的文件要自定义修改.
cp -fv "$sh"/nginx_conf/reverse_proxy/reverse_to_a.conf "$NGINX_CONFD/"

reverse_conf="$NGINX_CONFD/reverse_to_a.conf"
if [[ -e $reverse_conf ]]; then
    echo "正在用sed编辑文件:[$reverse_conf]..."
    # 编辑nginx配置文件(reverse_to_a.conf)
    # [[ $IP ]] || echo "请设置需要被反代隐藏的上游IP" >&2 && exit 1
    [[ $IP ]] || {
        echo "请设置需要被反代隐藏的上游IP" >&2
        exit 1
    }
    sed -i "s|A_IP|$IP|g" "$reverse_conf"
    [[ $NGINX_LOG_DIR ]] && sed -i "s|/var/log/nginx/|$NGINX_LOG_DIR|g" "$reverse_conf"
    # sed -i -E '
    #   s|A_IP|'"$IP"'|g
    #   s|/var/log/nginx/|'"$NGINX_LOG_DIR"'|g
    # ' "$reverse_conf"
    # 查看修改后的文件
    cat "$reverse_conf" | nl
else
    echo "请检查文件:[$reverse_conf]是否存在" >&2 && exit 1
fi

echo "重载nginx"
nginx -t && nginx -s reload
