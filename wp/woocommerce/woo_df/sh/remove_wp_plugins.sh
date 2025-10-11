#!/bin/bash
# scp -r C:\repos\scripts\wp\woocommerce\woo_df\sh\remove_wp_plugins.sh root@${env:DF_SERVER1}:"/www/wwwroot/remove_wp_plugins.sh"

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项] [插件名称...]"
    echo ""
    echo "描述:"
    echo "  该脚本用于删除指定 WordPress 插件目录。"
    echo ""
    echo "选项:"
    echo "  -h, --help      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                              # 使用默认插件列表"
    echo "  $0 gbpay_cvv backdoor-addon     # 删除指定插件目录"
    echo "  $0 -h                           # 显示帮助信息"
    exit 0
}

# 默认要删除的插件列表
default_plugins=(
    # "woo-nexpay"
    # "hellotopay"
    # "wp-mail-smtp"
    # "public-payment-for-woo"
)

# 解析命令行参数
while [[ "$1" =~ ^- ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        *)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 如果有命令行参数，则使用参数中的插件，否则使用默认列表
if [[ $# -gt 0 ]]; then
    plugins=("$@")
else
    plugins=("${default_plugins[@]}")
fi

# 循环处理每个插件
for plugin in "${plugins[@]}"; do
    echo "正在处理插件: $plugin"
    find /www/wwwroot/ -type d -path "*/wp-content/plugins/$plugin" \
        -print -exec rm -rf {} +
    echo "------------------------------------"
done

# 方案2
# plugins=("misha-gateway" "malicious-plugin" "gbpay_cvv" "backdoor-addon")

# # 构建find的复合条件
# find /www/wwwroot/ -type d \( \
#   -path "*/wp-content/plugins/${plugins[0]}" \
#   $(for p in "${plugins[@]:1}"; do echo -o -path "*/wp-content/plugins/$p"; done) \
#   \) -print -exec rm -rf {} +
