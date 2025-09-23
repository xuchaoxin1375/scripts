#!/bin/bash

BASE_DIR="/www/wwwroot"

process_wpdir() {
    wpdir="$1"
    echo "正在处理: $wpdir"
    cd "$wpdir"
    if [ -f "$wpdir/wp-config.php" ]; then
        # 这里写你的 wp-cli 命令
        # sudo -u www wp config set DISABLE_WP_CRON true --raw --path="$wpdir"
        if [ $? -eq 0 ]; then
            echo "  ✅ 成功执行wp命令"
        else
            echo "  ❌ 设置失败，请检查该目录的权限或 WP 安装情况"
        fi
    else
        echo "  ⚠️ 未找到 wp-config.php，跳过"
    fi
}

export -f process_wpdir

find "$BASE_DIR" -type d -path "*/wordpress" -maxdepth 3 | parallel -j 8 process_wpdir {}