
# === 函数：写入伪静态规则到指定文件 ===
# write_rewrite_rules() {
#     local domain="$1"
#     local rewrite_file="/www/server/panel/vhost/rewrite/${domain}.conf"

#     # 确保目录存在
#     local rewrite_dir="$(dirname "$rewrite_file")"
#     if [ ! -d "$rewrite_dir" ]; then
#         echo "⚠️ 伪静态规则目录不存在，尝试创建: $rewrite_dir"
#         mkdir -p "$rewrite_dir" || {
#             echo "❌ 无法创建目录: $rewrite_dir"
#             return 1
#         }
#     fi

#     # 写入伪静态规则
#     cat <<EOF >"$rewrite_file"
# location /
# {
#   try_files \$uri \$uri/ /index.php?\$args;
# }

# rewrite /wp-admin\$ \$scheme://\$host\$uri/ permanent;
# EOF

#     if [ $? -eq 0 ]; then
#         echo "✅ 伪静态规则已成功写入到 $rewrite_file"
#         return 0
#     else
#         echo "❌ 写入伪静态规则失败，请检查权限或路径。"
#         return 1
#     fi
# }