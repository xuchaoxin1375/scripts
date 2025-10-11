#!/bin/bash

BASE_DIR="/www/wwwroot"
MAX_JOBS=8
job_count=0

for wpdir in $(find "$BASE_DIR" -type d -path "*/wordpress" -maxdepth 3); do
    (
        echo "正在处理: $wpdir"
        cd "$wpdir"
        if [ -f "$wpdir/wp-config.php" ]; then
            # 在下面定义需要执行的wp_cli命令行
            # 禁用 wp-cron
            # sudo -u www  wp config set DISABLE_WP_CRON true --raw --path="$wpdir"

            # 禁用自动更新
            # sudo -u www wp config set AUTOMATIC_UPDATER_DISABLED true --raw
            # sudo -u www wp config set WP_AUTO_UPDATE_CORE false --raw
            
            # 重置astra主题中woocommerce购物车按钮文本(关闭文件自定义使用模板语言的默认值)
            sudo -u www wp eval '
            $settings = get_option("astra-settings", array());
            unset($settings["woo-cart-button-text"]);
            update_option("astra-settings", $settings);
            '
            
            if [ $? -eq 0 ]; then
                echo "  ✅ 成功执行wp命令"
            else
                echo "  ❌ 设置失败，请检查该目录的权限或 WP 安装情况"
            fi
        else
            echo "  ⚠️ 未找到 wp-config.php，跳过"
        fi
    ) &
    job_count=$((job_count+1))
    if [ "$job_count" -ge "$MAX_JOBS" ]; then
        wait
        job_count=0
    fi
done
wait