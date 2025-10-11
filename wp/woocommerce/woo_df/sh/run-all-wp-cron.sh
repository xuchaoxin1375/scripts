#!/bin/bash

ROOT_PATH="/www/wwwroot"

# 遍历所有用户名目录
for USERNAME_DIR in "$ROOT_PATH"/*/; do
  # 去除路径末尾的斜杠
  USERNAME_DIR=${USERNAME_DIR%/}

  # 遍历该用户目录下所有站点目录（域名）
  for DOMAIN_DIR in "$USERNAME_DIR"/*/; do
    DOMAIN_DIR=${DOMAIN_DIR%/}
    WP_PATH="$DOMAIN_DIR/wordpress"

    if [ -d "$WP_PATH" ]; then
      echo "触发 $WP_PATH 的 WP-Cron 任务"
      wp cron event run --due-now --path="$WP_PATH" > /dev/null 2>&1

      # 记录成功（可选）
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Success - $WP_PATH" >> /var/log/wp_cron_run.log
    else
      echo "未发现wordpress目录：$WP_PATH"
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Missed wordpress dir - $WP_PATH" >> /var/log/wp_cron_run.log
    fi
  done
done
