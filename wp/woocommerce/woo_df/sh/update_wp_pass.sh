#!/bin/bash

# =============================
# WordPress 批量重置 admin 密码 - 交互式版本(次脚本不会存储密码,需要你执行的时候交互式输入,以提高安全性,也便于共享此脚本)
# 支持网站根目录形如路径: /www/wwwroot/<user_dir>/<domain_dir>/wordpress/格式的情况

# 注意 wp-cli(即wp命令)工具对于权限比较敏感和谨慎,通常要运行于非root用户或权限下,比如使用普通用户www的角色来执行wp命令
#   考虑到执行在root用户下调用wp默认会报警并不会执行有效操作),因此这里针对root用户使用sudo -u www wp来代替wp 来调用wp-cli的功能
#   (这里假设你有一个www用户,专门用来管理网站的,对于宝塔用户,这是默认的用户)
# =============================

# 日志文件
LOG_FILE="/tmp/wp_admin_password_update_$(date +%Y%m%d_%H%M%S).log"

# 提示用户输入新密码（隐藏输入）
echo "🔐 请输入要设置的新密码（将用于所有站点的 admin 用户）："
read -s -p "密码: " NEW_PASSWORD
echo
echo

# 二次确认
read -s -p "请再次输入密码以确认: " CONFIRM_PASSWORD
echo
echo

# 验证两次输入是否一致
if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
    echo "❌ 两次密码不一致，操作已取消。"
    exit 1
fi

if [ -z "$NEW_PASSWORD" ]; then
    echo "❌ 密码不能为空！"
    exit 1
fi

echo "✅ 密码确认成功，开始处理..."

echo "=== 开始批量更新 admin 密码 ===" >> "$LOG_FILE"
echo "时间: $(date)" >> "$LOG_FILE"
echo "目标目录模式: /www/wwwroot/*/域名/wordpress" >> "$LOG_FILE"
echo "更新用户: admin" >> "$LOG_FILE"
echo "----------------------------------------" >> "$LOG_FILE"

# 统计计数器
success_count=0
fail_count=0
not_found_count=0
not_wp_count=0

# 遍历 /www/wwwroot 下所有用户 -> 域名 -> wordpress 目录
for WP_DIR in /www/wwwroot/*/*/wordpress/; do
    # 跳过不存在的路径（防止 glob 匹配失败）
    [ ! -d "$WP_DIR" ] && continue

    # 获取完整绝对路径（去掉末尾斜杠）
    SITE_PATH=$(realpath "$WP_DIR")

    # 提取站点标识：比如 zw/domina1.com
    RELATIVE_PATH=${SITE_PATH#/www/wwwroot/}  # 去掉前缀
    SITE_ID="${RELATIVE_PATH%/wordpress}"     # 去掉后缀

    echo "🔍 正在处理站点: $SITE_ID"
    echo "   路径: $SITE_PATH"

    # 切换到该目录
    cd "$SITE_PATH" || {
        echo "❌ 无法进入目录: $SITE_PATH"
        echo "ERROR: cd failed - $SITE_ID" >> "$LOG_FILE"
        ((fail_count++))
        continue
    }

    # 检查是否是有效的 WordPress 站点
    if [ ! -f wp-config.php ]; then
        echo "⚠️  不是 WordPress 站点（缺少 wp-config.php），跳过"
        echo "SKIP_NOT_WP: $SITE_ID ($SITE_PATH)" >> "$LOG_FILE"
        ((not_wp_count++))
        continue
    fi

    # 使用 WP-CLI 检查是否存在 'admin' 用户🎈
    if ! sudo -u www wp user get admin --field=ID >/dev/null 2>&1; then
        echo "❌ 不存在用户名为 'admin' 的用户"
        echo "MISSING_ADMIN: $SITE_ID" >> "$LOG_FILE"
        ((not_found_count++))
        continue
    fi

    # 获取当前站点名称（可选）
    # SITE_TITLE=$(sudo -u www wp option get blogname 2>/dev/null || echo "Unknown Site")

    # 执行密码更新🎈
    if sudo -u www wp user update admin --user_pass="$NEW_PASSWORD" --quiet; then
        echo "✅ 【成功】'$SITE_ID' ($SITE_TITLE) 的 admin 密码已更新"
        echo "SUCCESS: $SITE_ID | $SITE_TITLE" >> "$LOG_FILE"
        ((success_count++))
    else
        echo "❌ 【失败】无法更新 '$SITE_ID' 的密码"
        echo "FAILED: $SITE_ID | $SITE_TITLE" >> "$LOG_FILE"
        ((fail_count++))
    fi

    echo ""
done

# 清理密码变量
unset NEW_PASSWORD CONFIRM_PASSWORD

# === 最终统计 ===
echo "========================================"
echo "✅ 完成！统计结果："
echo "  成功更新: $success_count 个站点"
echo "  更新失败: $fail_count 个站点"
echo "  缺少 admin 用户: $not_found_count 个站点"
echo "  非 WordPress 站点: $not_wp_count 个站点"
echo ""
echo "📝 详细日志已保存至: $LOG_FILE"