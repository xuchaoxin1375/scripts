#!/bin/bash

wp_config_path='/mnt/c/repos/scripts/wp/woocommerce/woo_df/sh/wp-config.demo.php'

STOP_EDITING_LINE='.*Add any custom values between this line and the.*'

# .*Add any custom values.*
# 在指定行后添加配置
sed -i.bak "/$STOP_EDITING_LINE/a\\
\\
define('DISABLE_WP_CRON', true);#禁用wp-cron任务,使用系统定时任务代替 \\
" $wp_config_path

# echo $STOP_LINE