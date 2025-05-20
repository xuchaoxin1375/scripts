
#!/bin/bash

# === 配置参数 ===
# CURRENT_DIR=$(pwd)                    # 当前工作目录
CURRENT_DIR="/srv/uploads/uploader/files"  
TARGET_ROOT="/www/wwwroot"           # WordPress 网站根目录
# STOP_EDITING_LINE="stop editing"     # wp-config.php 中的关键提示行
STOP_EDITING_LINE='Add any custom values between this line and the "stop editing" line'
HTTPS_CONFIG_LINE="\$_SERVER['HTTPS'] = 'on'; define('FORCE_SSL_LOGIN', true); define('FORCE_SSL_ADMIN', true);"  # 要插入的配置项

DB_HOST="localhost"                  # 数据库主机
DB_USER="root"                        # MySQL 用户名
DB_PASS="15a58524d3bd2e49"   # MySQL 密码（建议使用安全方式处理）

# === 函数：插入 HTTPS 配置到 wp-config.php 的正确位置 ===
insert_https_config() {
    local wp_config_path="$1"

    if [ -f "$wp_config_path" ]; then
        echo "正在修改 $wp_config_path ..."

        # 使用 awk 查找包含 "stop editing" 的那一行号(第一次出现)
        STOP_LINE=$(awk -v search="$STOP_EDITING_LINE" '$0 ~ search {print NR}' "$wp_config_path" | head -n 1)

        if [ -n "$STOP_LINE" ]; then
            sed -i "${STOP_LINE}a\\\n$HTTPS_CONFIG_LINE" "$wp_config_path" 
            # echo "已尝试插入 HTTPS 配置。"
        else
            echo "⚠️ 未找到 'stop editing' 行，无法插入配置。请手动检查 wp-config.php。"
        fi
    else
        echo "❌ 错误：找不到 wp-config.php 文件：$wp_config_path"
    fi
}

# === 函数：导入 SQL 文件到对应数据库 ===
import_sql_file() {
    local domain="$1"
    local username="$2"
    local sql_file="$3"

    # 构造数据库名：保留域名中的点 "."
    db_name="${username}_${domain}"

    echo "📦 正在处理数据库: $db_name"

    # 创建数据库（如果不存在）
    echo "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;" | mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS"

    # 可选：清空数据库（谨慎使用）
    # echo "DROP TABLES FROM \`${db_name}\`;" &>/dev/null || true
    # echo "TRUNCATE TABLE \`${db_name}\`.*;" &>/dev/null || true

    # 导入 SQL 文件
    echo "🚚 正在导入 SQL 文件: $sql_file 到数据库 $db_name"
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$db_name" < "$sql_file"

    if [ $? -eq 0 ]; then
        echo "✅ 数据库 $db_name 成功导入。"
    else
        echo "❌ 导入失败，请检查 SQL 文件或数据库权限。"
    fi
}

# === 函数：写入伪静态规则到指定文件 ===
write_rewrite_rules() {
    local domain="$1"
    local rewrite_file="/www/server/panel/vhost/rewrite/${domain}.conf"

    # 写入伪静态规则
    cat <<EOF > "$rewrite_file"
location /
{
    try_files \$uri \$uri/ /index.php?\$args;
}

rewrite /wp-admin\$ \$scheme://\$host\$uri/ permanent;
EOF

    if [ $? -eq 0 ]; then
        echo "✅ 伪静态规则已成功写入到 $rewrite_file"
    else
        echo "❌ 写入伪静态规则失败，请检查权限或路径。"
    fi
}

# === 主程序开始 ===

echo "🚀 开始部署 WordPress 站点和数据库..."

# 进入指定目录
cd "$CURRENT_DIR" || { echo "❌ 无法进入目录: $CURRENT_DIR"; exit 1; }

# 遍历当前目录下的所有子目录（假设是拼音首字母缩写）
for user_dir in */; do
    # 去掉末尾斜杠，得到用户名缩写
    username="${user_dir%/}"

    echo "📂 正在处理站点人员名所属目录: $username"

    # 进入用户目录
    cd "$CURRENT_DIR/$username" || continue

    # 查找所有 .zip 或 .7z 文件
    for archive_file in *.zip *.7z; do
        if [[ ! -f "$archive_file" ]]; then
            echo "⚠️ 在目录 $username 中没有找到有效的压缩包。跳过..."
            continue
        fi

        # 获取不带扩展名的域名（例如 lumadepot.com.zip -> lumadepot.com）
        domain_name="${archive_file%.*}"
        echo "📦 正在处理网站: $domain_name"

        # === 解压操作 ===
        extracted_dir="$CURRENT_DIR/$username/$domain_name"

        if [[ "$archive_file" == *.zip ]]; then
            echo "🔍 正在解压 ZIP 文件: $archive_file"
            unzip -q "$archive_file" -d "$extracted_dir"
        elif [[ "$archive_file" == *.7z ]]; then
            echo "🔍 正在解压 7z 文件: $archive_file"
            7z x "$archive_file" -o"$extracted_dir" # > /dev/null
        fi

        if [ ! -d "$extracted_dir" ]; then
            echo "❌ 解压失败或目录不存在: $extracted_dir"
            continue
        fi

        # === 创建目标目录并移动内容 ===
        target_dir="$TARGET_ROOT/$username/$domain_name/wordpress"
        mkdir -p "$target_dir"

        echo "🚚 移动解压后的内容到目标路径: $target_dir"
        # cp -r "$extracted_dir"/. "$target_dir/"
        mv "$extracted_dir"/* "$target_dir/"

        # === 修改 wp-config.php 文件 ===
        wp_config_path="$target_dir/wp-config.php"
        insert_https_config "$wp_config_path"

        # === 检查并导入对应的 SQL 文件 ===
        sql_file="$CURRENT_DIR/$username/$domain_name.sql"
        if [ -f "$sql_file" ]; then
            import_sql_file "$domain_name" "$username" "$sql_file"
        else
            echo "⚠️ 未找到 SQL 文件: $sql_file"
        fi

        # === 写入伪静态规则 ===
        write_rewrite_rules "$domain_name"

        echo "✅ 完成站点部署: $domain_name"
    done

    # 返回上级目录
    cd "$CURRENT_DIR"
done

echo "🎉 所有站点和数据库部署完成！"