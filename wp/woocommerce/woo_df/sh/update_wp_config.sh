#!/bin/bash
HTTPS_CONFIG_LINE="\$_SERVER['HTTPS'] = 'on'; define('FORCE_SSL_LOGIN', true); define('FORCE_SSL_ADMIN', true);"
wp_config_path='/mnt/c/repos/scripts/wp/woocommerce/woo_df/sh/wp-config.demo.php'
STOP_EDITING_LINE='Add any custom values between this line and the "stop editing" line'
# 使用awk查找位置
STOP_LINE=$(awk -v search="$STOP_EDITING_LINE" '$0 ~ search {print NR}' "$wp_config_path" | head -n 1)

# 在指定行后添加配置
sed -i "${STOP_LINE}a\\
\\
\\$HTTPS_CONFIG_LINE" "$wp_config_path
" 
# echo $STOP_LINE