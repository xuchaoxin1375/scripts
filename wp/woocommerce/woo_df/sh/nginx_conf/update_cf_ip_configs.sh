#!/bin/bash
set -e


# === 可配置保存路径 ===
# SAVE_DIR="/etc/nginx/conf.d"   # 可根据需要修改
SAVE_DIR="/www/server/nginx/conf"   # 保存路径
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
  for ip in $(cat "$CF_IPV4_FILE"); do
    echo "set_real_ip_from $ip;"
  done
  for ip in $(cat "$CF_IPV6_FILE"); do
    echo "set_real_ip_from $ip;"
  done
  echo "real_ip_header CF-Connecting-IP;"
} > "$CF_REALIP_CONF"

# 检查配置 & 重载 Nginx
# nginx -t && systemctl reload nginx
nginx -t && nginx -s reload
