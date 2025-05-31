#!/bin/bash

# === 配置参数 ===
# 默认值
DEFAULT_PACK_ROOT="/srv/uploads/uploader/files"
DEFAULT_DB_USER="root"
DEFAULT_DB_PASSWORD="15a58524d3bd2e49"
SERVER_SITE_HOME="/www/wwwroot"
DB_HOST="localhost"                  # 数据库主机
# PACK_ROOT="/www/wwwroot"           # WordPress 网站根目录
STOP_EDITING_LINE='Add any custom values between this line and the "stop editing" line'
HTTPS_CONFIG_LINE="\$_SERVER['HTTPS'] = 'on'; define('FORCE_SSL_LOGIN', true); define('FORCE_SSL_ADMIN', true);"

# === 函数：显示帮助信息 ===
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  --pack-root DIR   设置压缩包根目录 (默认: $DEFAULT_PACK_ROOT)"
    echo "  --db-user USER    设置数据库用户名 (默认: $DEFAULT_DB_USER)"
    echo "  --db-pass PASS    设置数据库密码"
    echo "  --user-dir DIR    仅处理指定用户目录"
    echo "  --help            显示此帮助信息"
    exit 0
}

# 命令行参数解析
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --pack-root) PACK_ROOT="$2"; shift ;;
        --db-user) DB_USER="$2"; shift ;;
        --db-pass) DB_PASSWORD="$2"; shift ;;
        --user-dir) USER_DIR="$2"; shift ;;  # 指定用户目录,则将工作范围缩小到该目录下
        --help) show_help ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
    shift
done

# 使用默认值或用户提供的值
PACK_ROOT=${PACK_ROOT:-$DEFAULT_PACK_ROOT}
DB_USER=${DB_USER:-$DEFAULT_DB_USER}
DB_PASSWORD=${DB_PASSWORD:-$DEFAULT_DB_PASSWORD}

# 提示用户当前使用的 PACK_ROOT
echo "使用 PACK_ROOT: $PACK_ROOT"

# === 函数：检查必要的命令是否存在 ===
check_commands() {
    local commands=("mysql" "unzip" "7z")
    local missing_commands=()
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        echo "❌ 错误: 以下命令未找到: ${missing_commands[*]}"
        echo "请安装缺少的命令后再运行此脚本。"
        exit 1
    fi
}

# === 函数：修改wp-config.php ===
update_wp_config() {
    local wp_config_path="$1"

    if [ ! -f "$wp_config_path" ]; then
        echo "❌ 错误：找不到 wp-config.php 文件：$wp_config_path"
        return 1
    fi
    
    echo "正在修改 $wp_config_path ..."
    
    # 检查配置是否已存在
    # if grep -q "FORCE_SSL_ADMIN" "$wp_config_path"; then
    #     echo "ℹ️ HTTPS 配置已存在，跳过修改。"
    #     return 0
    # fi

    # 使用 awk 查找包含 "stop editing" 的那一行号(第一次出现)
    
    local STOP_LINE
    STOP_LINE=$(awk -v search="$STOP_EDITING_LINE" '$0 ~ search {print NR}' "$wp_config_path" | head -n 1)
    if [ -n "$STOP_LINE" ]; then

        sed -i "${STOP_LINE}a$HTTPS_CONFIG_LINE" "$wp_config_path" 

        sed -ri   "s/(define\(\s*'DB_HOST',)(.*)\)/\1'${DB_HOST}')/" "$wp_config_path" 
        sed -ri   "s/(define\(\s*'DB_NAME',)(.*)\)/\1'$db_name')/" "$wp_config_path" 
        sed -ri   "s/(define\(\s*'DB_USER',)(.*)\)/\1'${DB_USER}')/" "$wp_config_path" 
        sed -ri   "s/(define\(\s*'DB_PASSWORD',)(.*)\)/\1'${DB_PASSWORD}')/" "$wp_config_path" 
        echo "✅ wp-config.php 配置已插入。"
        return 0
    else
        echo "⚠️ 未找到 'stop editing' 行，无法插入配置。请手动检查 wp-config.php。"
        return 1
    fi
}

# === 函数：导入 SQL 文件到对应数据库 ===
import_sql_file() {
    local domain="$1"
    local username="$2"
    local sql_file="$3"

    # 构造数据库名：保留域名中的点 "."
    local db_name="${username}_${domain}"

    echo "📦 正在处理数据库: $db_name"

    # 创建数据库（如果不存在）
    if ! echo "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;" | mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD"; then
        echo "❌ 创建数据库失败，请检查数据库连接和权限。"
        return 1
    fi

    # 导入 SQL 文件
    echo "🚚 正在导入 SQL 文件: $sql_file 到数据库 $db_name"
    if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$db_name" < "$sql_file"; then
        echo "✅ 数据库 $db_name 成功导入。"
        return 0
    else
        echo "❌ 导入失败，请检查 SQL 文件或数据库权限。"
        return 1
    fi
}

# === 函数：写入伪静态规则到指定文件 ===
write_rewrite_rules() {
    local domain="$1"
    local rewrite_file="/www/server/panel/vhost/rewrite/${domain}.conf"

    # 确保目录存在
    local rewrite_dir="$(dirname "$rewrite_file")"
    if [ ! -d "$rewrite_dir" ]; then
        echo "⚠️ 伪静态规则目录不存在，尝试创建: $rewrite_dir"
        mkdir -p "$rewrite_dir" || {
            echo "❌ 无法创建目录: $rewrite_dir"
            return 1
        }
    fi

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
        return 0
    else
        echo "❌ 写入伪静态规则失败，请检查权限或路径。"
        return 1
    fi
}



# === 函数：解压压缩文件 ===
extract_archive() {
    local archive_file="$1"
    local target_dir="$2"
    
    # 确保目标目录存在
    mkdir -p "$target_dir"
    
    echo "🔍 正在解压文件: $archive_file -> $target_dir/..."
    # 使用7z解压，支持各种格式
    if ! 7z x -y "$archive_file" -o"$target_dir"; then
        echo "❌ 解压失败: $archive_file"
        return 1
    fi
    # 修改后的完整片段
    # if [[ "$archive_file" == *.zip ]]; then
    #     echo "🔍 正在解压 ZIP 文件: $archive_file"
    #     # 统一使用7z解压
    #     if ! 7z x -y "$archive_file" -o"$target_dir"; then
    #         echo "❌ 解压 ZIP 文件失败: $archive_file"
    #         return 1
    #     fi
    # elif [[ "$archive_file" == *.7z ]]; then
    #     echo "🔍 正在解压 7z 文件: $archive_file"
    #     # 添加 -bsp1 参数以显示进度
    #     if ! 7z x -y -bsp1 "$archive_file" -o"$target_dir"; then
    #         echo "❌ 解压 7z 文件失败: $archive_file"
    #         return 1
    #     fi
    # elif [[ "$archive_file" == *.tar ]]; then
    #     echo "🔍 正在解压 TAR 文件: $archive_file"
    #     if ! tar xf "$archive_file" -C "$target_dir"; then
    #         echo "❌ 解压 TAR 文件失败: $archive_file"
    #         return 1
    #     fi
    # elif [[ "$archive_file" == *.tar.gz || "$archive_file" == *.tgz ]]; then
    #     echo "🔍 正在解压 TAR.GZ 文件: $archive_file"
    #     if ! tar zxf "$archive_file" -C "$target_dir"; then
    #         echo "❌ 解压 TAR.GZ 文件失败: $archive_file"
    #         return 1
    #     fi
    # elif [[ "$archive_file" == *.tar.bz2 ]]; then
    #     echo "🔍 正在解压 TAR.BZ2 文件: $archive_file"
    #     if ! tar jxf "$archive_file" -C "$target_dir"; then
    #         echo "❌ 解压 TAR.BZ2 文件失败: $archive_file"
    #         return 1
    #     fi
    # else
    #     echo "❌ 不支持的压缩文件格式: $archive_file"
    #     return 1
    # fi
    
    return 0
}

# === 函数：部署单个站点 ===
deploy_site() {
    local username="$1"
    local archive_file="$2"
    
    # 获取不带扩展名的域名，处理可能包含 .sql 的情况
    # 先去掉 .zip 或 .7z 扩展名
    local domain_name="${archive_file%.*}"
    
    # 分析sql文件是属于哪一个域名站点(检查是否以 .sql 结尾，如果是则去掉 .sql 后缀,获得sql所属的域名信息)
    if [[ "$domain_name" == *.sql ]]; then
        echo "⚠️ 检测到文件名包含 .sql 后缀，将其从域名中移除"
        domain_name="${domain_name%.sql}"
    fi
    
    echo "📦 正在处理网站: $domain_name"
    
    # === 解压站点压缩包 ===
    # local extracted_domain_dir="$PACK_ROOT/$username/$domain_name"
    local site_dir_archive="$PACK_ROOT/$username/$archive_file"
    
    local site_domain_home="$SERVER_SITE_HOME/$username/$domain_name" #例如:/www/wwwroot/zsh/domain.com #对于用7z打包domain.com为目录名的7z包,解压后得到domain.com目录 7z x $site_dir_archive -o$site_domain_home 执行结果得到目录$site_domain_home/domain.com,为了便于引用,将其赋值给变量$site_expanded_dir,表示解压后得到的目录
    local site_expanded_dir="$site_domain_home/$domain_name"
    local target_dir="$site_domain_home/wordpress"
    # 尝试清空目标目录,以便后续干净插入新内容
    # mkdir -p "$target_dir"
    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir" # 删除网站根目录
    else
        mkdir -p "$target_dir" # 创建网站根目录
    fi
    #如果存在同名目录,则询问用户是否覆盖
    if [ -d "$site_expanded_dir" ]; then
        echo "⚠️ 检测到相关目录已存在: $site_expanded_dir"
        echo "是否覆盖现有目录? (yY/n): "
        read -r response
        if [[ "$response" != "y" && "$response" != "Y" ]]; then
            echo "用户选择不覆盖，跳过此解压步骤: $domain_name"
        else
            echo "⚠️用户选择覆盖现有目录: $site_expanded_dir"
            echo "正在删除现有目录并解压新内容 (预计得到目录:$site_expanded_dir) ..."
            rm -rf "$site_expanded_dir"  # 删除现有目录
            
            if ! extract_archive "$site_dir_archive" "$site_domain_home"; then
                echo "❌ 解压失败，跳过部署: $domain_name"
                return 1
            fi
            
            mv  "$site_expanded_dir"/* "$target_dir" -f  # 移动新目录内容到目标目录

        fi
    else
        if ! extract_archive "$site_dir_archive" "$site_domain_home"; then
            echo "❌ 解压失败，跳过部署: $domain_name"
            return 1
        fi
        
        mv  "$site_expanded_dir"/* "$target_dir" -f  # 移动新目录内容到目标目录
    fi

    
    # === 检查并导入对应的 SQL 文件 ===
    local sql_file="$PACK_ROOT/$username/$domain_name.sql"
    if [ -f "$sql_file" ]; then
        import_sql_file "$domain_name" "$username" "$sql_file"
        # === 配置数据库===
        local db_name="${username}_${domain_name}"
        mysql -uroot -h localhost -P3306 -p"$DB_PASSWORD" "$db_name" -e "
    UPDATE wp_options
    SET option_value = 'https://www.${domain_name}'
    WHERE option_name IN ('home', 'siteurl');
    "
    else
        echo "⚠️ 未找到 SQL 文件: $sql_file"
        # 尝试查找其他可能的 SQL 文件名格式
        # local alt_sql_file="$PACK_ROOT/$username/${domain_name}*.sql"
        # if [ -f "$alt_sql_file" ]; then
        #     echo "🔍 找到替代 SQL 文件: $alt_sql_file"
        #     import_sql_file "$domain_name" "$username" "$alt_sql_file"
        # fi
    fi
    # === 站点根目录:创建目标目录并移动内容 ===
    # echo "📂 正在移动网站根目录到目标目录: $target_dir"
    # # 检查目标目录是否存在,如果存在则发出提示,并且移除旧目录,然后在移动新目录
    # if [ -d "$target_dir" ]; then
    #     echo "⚠️ 目标目录已存在: $target_dir"
    #     echo "正在尝试移除旧目录..."
    #     rm -rf "$target_dir" || {
    #         echo "!未完全删除旧目录: $target_dir"
    #     }
    # fi
    # echo "移动新目录内容到目标目录: $target_dir"
    # mv "$extracted_domain_dir"/* "$target_dir" -f
    # 正式移动网站根目录到目标目录

    # 将可能阻碍登录后台wps-hide-login.bak这个插件目录改为wps-hide-login
    local plugins_dir="$target_dir/wp-content/plugins"
    local wps_hide_login_dir="$plugins_dir/wps-hide-login"
    local wps_hide_login_dir_bak="${wps_hide_login_dir}.bak"
    if [ -d "$wps_hide_login_dir_bak" ]; then
        echo "🔄 重命名 wps-hide-login.bak 为 wps-hide-login"
        mv "$target_dir/wps-hide-login.bak" "$target_dir/wps-hide-login"
    else
        echo "ℹ️ 未找到 wps-hide-login.bak 目录，跳过重命名"
    fi

    
    # 检查是否为有效的 WordPress 目录
    if [ -f "$target_dir/wp-config-sample.php" ] || [ -f "$target_dir/wp-config.php" ] || [ -d "$target_dir/wp-content" ]; then
        echo "✅ 检测到有效的 WordPress 目录结构"
    else
        echo "⚠️ 警告：目标目录可能不是有效的 WordPress 安装，未找到典型的 WordPress 文件"
    fi
    
    # === 修改 wp-config.php 文件 ===
    local wp_config_path="$target_dir/wp-config.php"
    if [ -f "$wp_config_path" ]; then
        update_wp_config "$wp_config_path"
    else
        echo "⚠️ 未找到 wp-config.php 文件，跳过 HTTPS 配置"
    fi
    
    # 设置目录权限和所有者
    echo "🔒 设置目录权限和所有者"
    chmod -R 755 "$target_dir"
    chown -R www:www "$target_dir"
    
    # === 写入伪静态规则 ===
    write_rewrite_rules "$domain_name"
    
    echo "✅ 完成站点部署: $domain_name"
    return 0
}

# === 函数：查找并处理SQL备份文件 ===
# 此函数会分析传入的用户名和sql包文件名(针对一个站),构造对应的数据库名,并检查对应的文件是否存在
# 如果存在,则解压sql文件压缩包,如果存在多个
process_sql_file() {
    local username="$1"
    local archive_file="$2"
    
    # 获取域名（去掉.sql.zip或.sql.7z后缀）
    local domain_name="${archive_file%.sql.*}"
    echo "📦 正在处理网站 $domain_name 的SQL备份文件 $archive_file"
    
    local user_dir="$PACK_ROOT/$username"
    
    # 解压SQL备份文件
    if ! extract_archive "$user_dir/$archive_file" "$user_dir"; then
        echo "❌ 解压SQL备份文件失败: $archive_file"
        return 1
    fi
    
    # 查找解压后的SQL文件
    local sql_files=($(find "$user_dir" -name "*.sql" -type f))
    
    if [ ${#sql_files[@]} -eq 0 ]; then
        echo "❌ 在解压后的目录中未找到SQL文件"
        return 1
    fi
    
    # 导入找到的第一个SQL文件
    # echo "🔍 找到SQL文件: ${sql_files[0]}"
    # if import_sql_file "$domain_name" "$username" "${sql_files[0]}"; then
    #     echo "✅ SQL备份成功导入到数据库"
    #     rm -rf "$temp_dir"
    #     return 0
    # else
    #     echo "❌ SQL备份导入失败"
    #     rm -rf "$temp_dir"
    #     return 1
    # fi
}

# === 主程序开始 🎈===

# 检查必要的命令
check_commands

echo "🚀 开始部署 WordPress 站点和数据库..."

# 进入指定目录
cd "$PACK_ROOT" || { echo "❌ 无法进入目录: $PACK_ROOT"; exit 1; }

# 如果指定了用户目录，则仅处理该目录
if [ -n "$USER_DIR" ]; then
    user_dirs=("$USER_DIR")
    echo "🔍 仅处理指定用户目录: $USER_DIR"
else
    # 否则遍历所有子目录
    user_dirs=($(ls -d */ 2>/dev/null))
    if [ ${#user_dirs[@]} -eq 0 ]; then
        echo "❌ 在 $PACK_ROOT 中没有找到任何用户目录"
        exit 1
    fi
    echo "🔍 找到 ${#user_dirs[@]} 个用户目录"
fi

deployed_sites=0
failed_sites=0
sql_backups_processed=0

for user_dir in "${user_dirs[@]}"; do
    # 去掉末尾斜杠，得到用户名缩写
    username="${user_dir%/}"

    echo "📂 正在处理站点人员名所属目录: $username"

    # 进入用户目录
    if ! cd "$PACK_ROOT/$username"; then
        echo "❌ 无法进入用户目录: $PACK_ROOT/$username"
        continue
    fi
    
    # 首先处理SQL备份文件(将所有站点的sql文件都解压,然后逐个导入到对应的数据库)
    # 数据库名字:调用process_sql_file进行处理
    sql_archives=($(ls *.sql.zip *.sql.7z *.sql.tar 2>/dev/null))
    if [ -f "${sql_archives[0]}" ]; then
        echo "🔍 找到SQL备份文件，优先处理"
        
        for sql_archive in "${sql_archives[@]}"; do
            if [ ! -f "$sql_archive" ]; then
                continue
            fi
            
            if process_sql_file "$username" "$sql_archive"; then
                ((sql_backups_processed++))
            else
                ((failed_sites++))
            fi
        done
    else
        echo "ℹ️ 未找到SQL压缩文件,跳过解压步骤"
    fi

    # 然后处理WordPress站点文件（过滤sql压缩文件SQL备份文件）
    site_archives=()
    for archive in *.zip *.7z *.tar ; do
        if [[ -f "$archive" && "$archive" != *.sql.* ]]; then
            site_archives+=("$archive")
        fi
    done
    
    if [ ${#site_archives[@]} -eq 0 ] || [ ! -f "${site_archives[0]}" ]; then
        echo "⚠️ 在目录 $username 中没有找到有效的WordPress站点压缩包。跳过..."
        cd "$PACK_ROOT"
        # continue
    fi
    
    for archive_file in "${site_archives[@]}"; do
        if [ ! -f "$archive_file" ]; then
            continue
        fi
        # 调用部署函数deploy_site进行部署
        if deploy_site "$username" "$archive_file"; then
            ((deployed_sites++))
        else
            ((failed_sites++))
        fi
    done

    # 返回上级目录
    cd "$PACK_ROOT"
done

echo "🎉 部署完成！站点: $deployed_sites, SQL备份: $sql_backups_processed, 失败: $failed_sites"

if [ $failed_sites -gt 0 ]; then
    echo "⚠️ 有 $failed_sites 个操作失败，请检查日志。"
    exit 1
fi

exit 0