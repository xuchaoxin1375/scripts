#!/usr/bin/env bash
# 将vps配置成反向代理服务器(反代网关),基于nginx(openresty).
# 测试系统为ubuntu,nginx版本为标准安装(或者通过仓库中的nginx_conf/upgrade-nginx-ubt.sh安装较新版本)
#
# bash  <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos_vps.sh) # -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx

VERSION="20260603.1043"

NGINX_CONF_HOME="/etc/nginx"
NGINX_CONFD="$NGINX_CONF_HOME/conf.d" # nginx自动include运行的配置文件目录
# 参数解析
args_pos=()
parse_args() {
    usage="
部署反代服务器的shell脚本.[version:$VERSION]
Usage: $0 [options]
Options:
    -c, --nginx-home <dir>         nginx配置文件家目录(常见目录:/etc/nginx/,/www/server/nginx/conf)
    -d, --nginx-confd-vhost <dir>   nginx自动include运行的配置文件目录(常见目录:/etc/nginx/conf.d/,/www/server/panel/vhost/nginx)
    -h, --help                  显示帮助信息
EXAMPLES:
$0 -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx
    "
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            -c | --nginx-home)
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
                LOG_DIR="$2"
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
# 确保相关目录存在:
mkdir -pv "$NGINX_CONFD"
mkdir -pv "$LOG_DIR"

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

# 运行一次脚本 cf_realip.conf的更新脚本
bash "$NGINX_CONF_HOME/update_cf_ip_configs.sh"

# 将反代服务器nginx配置文件映射到/etc/nginx/conf.d/
cp -fv "$sh"/nginx_conf/reverse_proxy/reverse_to_a.conf "$NGINX_CONFD/"

reverse_conf="$NGINX_CONFD/reverse_to_a.conf"

# 编辑nginx配置文件(reverse_to_a.conf)
sed -i -E '
  s|A_IP|'"$IP"'|g
  s|/var/log/nginx/|'"$NGINX_LOG_DIR"'|g
' "$reverse_conf"

# 重载nginx
nginx -t && nginx -s reload
