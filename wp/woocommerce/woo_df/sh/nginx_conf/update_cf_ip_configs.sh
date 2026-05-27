#!/bin/bash
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
args_pos=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      echo "$usage"
      exit 0
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
# === 可配置保存路径 ===
# SAVE_DIR="/etc/nginx/conf.d"   # 可根据需要修改
SAVE_DIR="/www/server/nginx/conf" # 保存路径
# 如果路径不存在,则创建此目录
if [ ! -d "$SAVE_DIR" ]; then
  mkdir -p "$SAVE_DIR"
fi
CF_IPV4_FILE="$SAVE_DIR/cf-ips-v4.txt"
CF_IPV6_FILE="$SAVE_DIR/cf-ips-v6.txt"
# 生成nginx配置文件
CF_REALIP_CONF="$SAVE_DIR/cf-realip.conf"

# 下载 Cloudflare IP 列表
curl -s https://www.cloudflare.com/ips-v4 -o "$CF_IPV4_FILE"
curl -s https://www.cloudflare.com/ips-v6 -o "$CF_IPV6_FILE"

# 生成 Nginx 配置
{
  echo "# Cloudflare IPs [update at $(date +"%Y-%m-%d %H:%M:%S %Z")]"
  # todo:To read lines rather than words, pipe/redirect to a 'while read' loop.
  for ip in $(cat "$CF_IPV4_FILE"); do
    echo "set_real_ip_from $ip;"
  done
  for ip in $(cat "$CF_IPV6_FILE"); do
    echo "set_real_ip_from $ip;"
  done
  echo "real_ip_header CF-Connecting-IP;"
} > "$CF_REALIP_CONF"

# 检查配置 & 重载 Nginx
if [[ $reload_nginx == true ]]; then
  # nginx -t && systemctl reload nginx
  if command -v nginx > /dev/null; then
    echo "Nginx is installed. Reloading nginx config."
    nginx -t && nginx -s reload
  else
    echo "Nginx is not installed. Skipping nginx -t and nginx -s reload." >&2
  fi
else
  echo "Please reload nginx configuration to make the changes take effect.(nginx -t && nginx -s reload)"
fi
