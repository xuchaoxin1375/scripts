#!/bin/bash
# update_cf_ip_configs.sh
# 适用于定时任务中自动更新CF IP列表的脚本.
# 生成`cf-realip.conf`配置文件.可以通过命令行选项指定保存位置,默认保存到`/www/server/nginx/conf/cf-realip.conf`(宝塔用户的默认路径).
# 其他情况(非宝塔环境,例如轻量的vps环境),可以指定保存到其他路径,例如ubuntu(debian)系统,可以放到`/etc/nginx/conf.d/cf-realip.conf`中.
set -e
# 参数解析
usage="
拉取Cloudflare IP列表并生成Nginx配置文件
Usage:
  $(basename "$0") [options]
Options:
  -h, --help      显示帮助信息
  -n, --no-reload-nginx  更新cf的ip列表配置后不主动重载nginx
"
reload_nginx=true
# === 可配置保存路径 ===
# SAVE_DIR="/etc/nginx/conf.d"   # 可根据需要修改
SAVE_DIR="/www/server/nginx/conf" # 保存路径
# 获取命令行参数
args_pos=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      echo "$usage"
      exit 0
      ;;
    -s | --save-dir)
      SAVE_DIR="$2"
      shift
      ;;
    -n | --no-reload-nginx)
      reload_nginx=false
      ;;
    --)
      shift
      break
      ;;
    -?*)
      echo "Unknown option: " >&2
      echo "$usage"
      exit 2
      ;;
    *)
      args_pos+=("$1")
      ;;
  esac
  shift
done
set -- "${args_pos[@]}"
# 参数解析并调整完毕
# 如果路径不存在,则创建此目录
if [ ! -d "$SAVE_DIR" ]; then
  mkdir -p "$SAVE_DIR"
fi
CF_IPV4_FILE="$SAVE_DIR/cf-ips-v4.txt"
CF_IPV6_FILE="$SAVE_DIR/cf-ips-v6.txt"
# 生成nginx配置文件
CF_REALIP_CONF="$SAVE_DIR/cf-realip.conf"

# 下载 Cloudflare IP 列表(保存到普通文本文件中)
curl -s https://www.cloudflare.com/ips-v4 -o "$CF_IPV4_FILE"
curl -s https://www.cloudflare.com/ips-v6 -o "$CF_IPV6_FILE"

# 生成 Nginx 配置(读取 Cloudflare IP 列表文件)
{
  echo "# Cloudflare IPs [update at $(date +"%Y-%m-%d %H:%M:%S %Z")]"
  
  echo "# Cloudflare IPv4"
  while IFS= read -r ip; do
    echo "set_real_ip_from $ip;"
  done < "$CF_IPV4_FILE"

  echo "# Cloudflare IPv6"
  while IFS= read -r ip; do
    echo "set_real_ip_from $ip;"
  done < "$CF_IPV6_FILE"
  echo "# 末尾nginx配置行:real_ip_header语句."
  echo "real_ip_header CF-Connecting-IP;"

} > "$CF_REALIP_CONF" # 将符合语句中的两个循环中产生的标准输出内容重定向到指定文件中.
echo "[INFO]:Cloudflare IPs have been updated."
# 检查配置 & 重载 Nginx
if [[ $reload_nginx == true ]]; then
  # nginx -t && systemctl reload nginx
  if command -v nginx > /dev/null; then
    echo "Nginx is installed. Reloading nginx config."
    nginx -t && nginx -s reload
  else
    echo "Nginx is not installed. Skipping nginx -t and nginx -s reload." >&2
  fi
  echo "Nginx configuration has been reloaded."
else
  echo "Please reload nginx configuration to make the changes take effect.(nginx -t && nginx -s reload)"
fi
