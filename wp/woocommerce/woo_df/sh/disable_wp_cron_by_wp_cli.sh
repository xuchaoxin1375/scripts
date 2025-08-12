#!/bin/bash

# 根路径
BASE_DIR="/www/wwwroot"

# 遍历所有 wordpress 目录 (限制最大深度有利于提高处理效率)
find "$BASE_DIR" -type d -path "*/wordpress" -maxdepth 3 | while read -r wpdir; do
    echo "正在处理: $wpdir"
    cd "$wpdir"
    # 确保 wp-cli 能找到 wp-config.php
    if [ -f "$wpdir/wp-config.php" ]; then
        # 禁用 wp-cron
    #    sudo -u www  wp config set DISABLE_WP_CRON true --raw --path="$wpdir"
        # 禁用自动更新
        sudo -u www wp config set AUTOMATIC_UPDATER_DISABLED true --raw
        sudo -u www wp config set WP_AUTO_UPDATE_CORE false --raw

        if [ $? -eq 0 ]; then
            echo "  ✅ 成功禁用 wp-cron"
        else
            echo "  ❌ 设置失败，请检查该目录的权限或 WP 安装情况"
        fi
    else
        echo "  ⚠️ 未找到 wp-config.php，跳过"
    fi
done
