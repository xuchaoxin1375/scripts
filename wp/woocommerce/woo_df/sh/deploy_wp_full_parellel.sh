#!/bin/bash
echo "deploy_script_version:20260211(parallel)"
# === 配置参数 ===
# 依赖说明:依赖于外部的伪静态规则文件RewriteRules.LF.conf,以及一些实用性程序(7z,unzip等)
# 在windows端可以使用powershell借助scp命令将此文件更新/推送到服务器:
# scp -r C:\repos\scripts\wp\woocommerce\woo_df\sh\deploy_wp_full.sh root@${env:DF_SERVER1}:"/www/wwwroot/deploy_wp_full.sh"
UPLOADER_DIR="/srv/uploads/uploader"
# 默认的网站压缩包存放目录的共同祖先目录(下面有各个用户名的专属目录)
DEFAULT_PACK_ROOT="$UPLOADER_DIR/files"
DEFAULT_DB_USER="root"
DEFAULT_DB_PASSWORD="15a58524d3bd2e49"
DEFAULT_DEPLOYED_DIR="$UPLOADER_DIR/deployed_all"
DEFAULT_PROJECT_HOME="/www/wwwroot"
DEFAULT_JOBS=10
DEFAULT_ZSTD_THREADS=1
PLUGINS_HOME="/www"
FUNCTIONS_PHP="/www/functions.php"
PLUGIN_INSTALL_MODE="symlink" # 插件安装模式: symlink(符号链接), copy(复制)
DB_HOST="localhost"           # 数据库主机

# 跳过解压网站根目录及其相关操作(假设已经解压过根目录包了)
SITE_ROOT_SKIP=false
# 跳过数据库导入(假设已经导入过sql文件了),此选项几乎不使用(完整流程会有步骤修改数据库中的某些字段)除非某次解压部分目录有异常而数据库导入处理是完成的;
# 否则,如果使用此选项跳过数据库导入,则需要注意手动修改
# TODO:在wp-config.php中设定home_url和site_url
SITE_DB_SKIP=false

# wp配置文件编辑
STOP_EDITING_LINE='Add any custom values between this line and the "stop editing" line'
# 非原生包这部分可以跳过插入(已经有相应内容了,可以通过grep检查是否有'FORCE_SSL_ADMIN'字符串存在)
HTTPS_CONFIG_LINE="\$_SERVER['HTTPS'] = 'on'; define('FORCE_SSL_LOGIN', true); define('FORCE_SSL_ADMIN', true);"

# === 函数：显示帮助信息 ===
show_help() {
    cat << EOF
用法: $0 [选项]
对于多硬盘服务器,可能需要设置--pack-root(可选),--project-home:
选项:
  -p,--pack-root DIR        设置压缩包根目录 (默认: $DEFAULT_PACK_ROOT)
  --db-user USER            设置数据库用户名 (默认: $DEFAULT_DB_USER)
  --db-pass PASS            设置数据库密码
  --user-dir DIR            仅处理指定用户目录
  -m,-plugin-install-mode MODE  设置插件安装模式 (默认: $PLUGIN_INSTALL_MODE) (可选值: symlink, copy)
  -R,--site-root-skip       跳过网站解压
  -D,--site-db-skip         跳过数据库导入
  --deployed-dir DIR        默认存储已部署的包文件(默认: $DEFAULT_DEPLOYED_DIR)
  -j,--jobs N               同时并发处理的任务数(默认: $DEFAULT_JOBS)
  --zstd-threads N          每个任务解压zstd时使用的线程数(默认: $DEFAULT_ZSTD_THREADS)
  -r,--project-home DIR     设置站点所属的项目目录PROJECT_HOME (默认: $DEFAULT_PROJECT_HOME)
  --site-home DIR           设置SERVER_SITE_HOME（自定义站点根目录）
  -h,--help                 显示此帮助信息
EOF
    exit 0
}
# 关闭shellcheck路径检查多余报错,尤其是其他平台开发时,使用source命令
# shellcheck source=/dev/null
source /www/sh/shell_utils.sh

######################################
# Description:
#   命令行参数解析
# Globals:
#   $@
# Arguments:
#   $1 - 脚本的所有参数("$@")
#
# Outputs:
# Returns:
#   0 on success, non-zero on error
# Example:
#   parse_args "$@"
######################################
parse_args() {

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p | --pack-root)
                PACK_ROOT="$2"
                shift
                ;;
            --db-user)
                DB_USER="$2"
                shift
                ;;
            --db-pass)
                DB_PASSWORD="$2"
                shift
                ;;
            --user-dir)
                USER_DIR="$2"
                shift
                ;;
            --deployed-dir)
                DEPLOYED_DIR="$2"
                shift
                ;;
            -j | --jobs)
                JOBS="$2"
                shift
                ;;
            --zstd-threads)
                ZSTD_THREADS="$2"
                shift
                ;;
            -m | --plugin-install-mode)
                PLUGIN_INSTALL_MODE="$2"
                shift
                ;;
            -r | --project-home)
                PROJECT_HOME="$2"
                shift
                ;;
            -R | --site-root-skip)
                SITE_ROOT_SKIP=true
                ;;
            -D | --site-db-skip)
                SITE_DB_SKIP=true
                ;;
            -h | --help) show_help ;;
            *)
                echo "未知参数: $1"
                exit 1
                ;;
        esac
        shift
    done
}

# 定义日志函数
log() {
    local message="$1"
    local dt
    dt="$(date '+%Y-%m-%d--%H:%M:%S')"
    message="[$dt] $message"
    echo "$message"
}

# === 函数：检查必要的命令是否存在 ===
check_commands() {
    local commands=("mysql" "zstd" "tar" "parallel") # "unzip" "7z" "lz4" #可选依赖
    local missing_commands=()

    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -gt 0 ]; then
        log "❌ 错误: 以下命令未找到: ${missing_commands[*]}"
        log "请安装缺少的命令后再运行此脚本。"
        exit 1
    fi
}

# === 函数：修改wp-config.php ===
update_wp_config() {
    local wp_config_path="$1"

    if [ ! -f "$wp_config_path" ]; then
        log "❌ 错误：找不到 wp-config.php 文件：$wp_config_path"
        return 1
    fi

    log "正在修改 $wp_config_path ..."

    local STOP_LINE
    STOP_LINE=$(awk -v search="$STOP_EDITING_LINE" '$0 ~ search {print NR}' "$wp_config_path" | head -n 1)
    if [ -n "$STOP_LINE" ]; then
        sed -i "${STOP_LINE}a$HTTPS_CONFIG_LINE" "$wp_config_path"
        sed -ri "s/(define\(\s*'DB_HOST',)(.*)\)/\1'${DB_HOST}')/" "$wp_config_path"
        sed -ri "s/(define\(\s*'DB_NAME',)(.*)\)/\1'$db_name')/" "$wp_config_path"
        sed -ri "s/(define\(\s*'DB_USER',)(.*)\)/\1'${DB_USER}')/" "$wp_config_path"
        sed -ri "s/(define\(\s*'DB_PASSWORD',)(.*)\)/\1'${DB_PASSWORD}')/" "$wp_config_path"
        log "✅ wp-config.php 配置已插入。"
        return 0
    else
        log "⚠️ 未找到 'stop editing' 行，无法插入配置。请手动检查 wp-config.php。"
        return 1
    fi
}

# === 函数：导入 SQL 文件到对应数据库 ===
import_sql_file() {
    local domain="$1"
    local username="$2"
    local sql_file="$3"

    local db_name="${username}_${domain}"

    log "📦 正在处理数据库: $db_name"

    if MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -e "DROP DATABASE IF EXISTS \`${db_name}\`;"; then
        log "🗑️ 旧数据库已删除。"
    else
        log "❌ 删除旧数据库失败，请检查数据库连接和权限。"
        return 1
    fi

    if ! echo "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;" | MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER"; then
        log "❌ 创建数据库失败，请检查数据库连接和权限。"
        return 1
    fi

    log "🚚 正在导入 SQL 文件: $sql_file 到数据库 $db_name"
    if MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" "$db_name" < "$sql_file"; then
        log "✅ 数据库 $db_name 成功导入。"
        return 0
    else
        log "❌ 导入失败，请检查 SQL 文件或数据库权限。"
        return 1
    fi
}

# === 函数：设置伪静态规则文件(通过复制文件到指定位置) ===
set_rewrte_rules_file() {
    local domain="$1"
    local rewrite_template="/www/woo_df/RewriteRules.LF.conf"
    local rewrite_target="/www/server/panel/vhost/rewrite/${domain}.conf"
    if [ -f "$rewrite_template" ]; then
        log "🔄 正在复制伪静态规则文件到目标位置: $rewrite_target"
        if cp -v "$rewrite_template" "$rewrite_target"; then
            log "✅ 伪静态规则文件已成功复制到: $rewrite_target"
        else
            log "❌ 复制伪静态规则文件失败: 源文件=$rewrite_template, 目标=$rewrite_target"
            return 1
        fi
    else
        log "❌ 未找到伪静态规则模板文件: $rewrite_template"
        return 1
    fi

}

is_plain_tar_file() {
    local file_path="$1"
    [[ -f "$file_path" ]] && [[ $(file -b --mime-type "$file_path") == "application/x-tar" ]]
}

extract_archive() {
    local archive_file="$1"
    local site_root="$2"

    if [ ! -f "$archive_file" ]; then
        log "❌ 归档文件不存在: $archive_file"
        return 1
    fi

    if [ -z "$site_root" ]; then
        log "❌ 目标目录未指定"
        return 1
    fi

    mkdir -p "$site_root"

    log "🔍 正在处理归档文件: $archive_file -> $site_root/"

    local ext="${archive_file##*.}"
    local temp_output_file

    check_integrity() {
        local cmd="$1"
        shift
        log "🧪 正在验证归档完整性..."
        if ! "$cmd" --test "$@"; then
            log "❌ 归档文件损坏或格式不支持: $archive_file"
            return 1
        fi
        log "✅ 归档文件完整性验证通过"
    }

    case "$ext" in

        zst | zstd)
            log "🧪 正在验证 ZSTD 文件完整性..."
            if ! zstd -T"$ZSTD_THREADS" -t "$archive_file" > /dev/null 2>&1; then
                log "❌ ZSTD 文件损坏或格式错误: $archive_file"
                return 1
            fi
            log "✅ ZSTD 文件完整性验证通过"
            temp_output_file=$(mktemp -u)
            log "📦 正在解压 ZSTD 文件(得到临时tar文件)..."
            if ! zstd -T"$ZSTD_THREADS" -d "$archive_file" -o "$temp_output_file"; then
                log "❌ 解压 ZSTD 文件失败"
                rm -f "$temp_output_file"
                return 1
            fi

            log "🧪 正在验证内部文件 (是否为TAR 文件以及tar文件完整性)..."
            if is_plain_tar_file "$temp_output_file"; then
                log "是原生tar文件"
            else
                log "不是原生tar文件"
            fi

            if ! tar -tf "$temp_output_file" > /dev/null 2>&1; then
                log "❌ 内部 TAR 文件损坏或者文件不是tar文件"
                rm -f "$temp_output_file"
                return 1
            fi

            log "📦 正在解包 TAR 数据..."
            if ! tar -xf "$temp_output_file" -C "$site_root"; then
                log "❌ 解包 TAR 失败"
                rm -f "$temp_output_file"
                return 1
            fi
            rm -f "$temp_output_file"
            ;;

        tar)
            log "🧪 正在验证 TAR 文件完整性..."
            if ! tar -tf "$archive_file" > /dev/null 2>&1; then
                log "❌ TAR 文件损坏或格式错误: $archive_file"
                return 1
            fi
            log "✅ TAR 文件完整性验证通过"

            log "📦 正在解包 TAR 文件..."
            if ! tar -xf "$archive_file" -C "$site_root"; then
                log "❌ 解包 TAR 文件失败: $archive_file"
                return 1
            fi
            ;;
        zip)
            if ! check_integrity unzip "$archive_file"; then
                return 1
            fi
            log "📦 正在解压 ZIP 文件..."
            if ! unzip -q "$archive_file" -d "$site_root"; then
                log "❌ 解压 ZIP 文件失败: $archive_file"
                return 1
            fi
            ;;

        gz | tgz)
            if ! check_integrity tar -tzf "$archive_file"; then
                return 1
            fi
            log "📦 正在解压 GZ/TGZ 文件..."
            if ! tar -xzf "$archive_file" -C "$site_root"; then
                log "❌ 解压 GZ/TGZ 文件失败: $archive_file"
                return 1
            fi
            ;;

        bz2 | tbz2)
            if ! check_integrity tar -tjf "$archive_file"; then
                return 1
            fi
            log "📦 正在解压 BZ2/TBZ2 文件..."
            if ! tar -xjf "$archive_file" -C "$site_root"; then
                log "❌ 解压 BZ2/TBZ2 文件失败: $archive_file"
                return 1
            fi
            ;;

        lz4)
            log "🧪 正在验证 LZ4 文件完整性..."
            if ! lz4 -t "$archive_file" > /dev/null 2>&1; then
                log "❌ LZ4 文件损坏或格式错误: $archive_file"
                return 1
            fi
            log "✅ LZ4 文件完整性验证通过"

            temp_output_file=$(mktemp -u)
            log "📦 正在解压 LZ4 文件..."
            if ! lz4 -d "$archive_file" "$temp_output_file"; then
                log "❌ 解压 LZ4 文件失败"
                rm -f "$temp_output_file"
                return 1
            fi

            log "🧪 正在验证解包后的 TAR 文件完整性..."
            if ! tar -tf "$temp_output_file" > /dev/null 2>&1; then
                log "❌ 内部 TAR 文件损坏"
                rm -f "$temp_output_file"
                return 1
            fi

            log "📦 正在解包 TAR 数据..."
            if ! tar -xf "$temp_output_file" -C "$site_root"; then
                log "❌ 解包 TAR 失败"
                rm -f "$temp_output_file"
                return 1
            fi

            rm -f "$temp_output_file"
            ;;

        *)
            log "🧪 正在使用 7z 验证归档完整性..."
            if ! 7z t "$archive_file" > /dev/null 2>&1; then
                log "❌ 7z 归档验证失败（文件损坏或不支持）: $archive_file"
                return 1
            fi
            log "✅ 7z 归档完整性验证通过"

            log "📦 正在使用 7z 解压..."
            if ! 7z x -y "$archive_file" -o"$site_root" > /dev/null; then
                log "❌ 7z 解压失败: $archive_file"
                return 1
            fi
            ;;
    esac

    log "✅ 解压成功: $archive_file -> $site_root/"
    return 0
}

install_wp_plugin() {
    local site_plugins_home="$1"
    local source_plugins_home="$2"
    log "🔍 检查插件目录: $site_plugins_home 中的所有文件"
    [[ -d $site_plugins_home ]] || {
        log "❌ 站点插件目录不存在: $site_plugins_home"
        return 1
    }
    for plugin in "$site_plugins_home"/*; do
        if [ -f "$plugin" ] || [ -z "$(ls -A "$plugin")" ]; then
            local plugin_name
            plugin_name=$(basename "$plugin")
            [[ ${plugin_name} = *.php ]] && continue
            log "🔍 检查插件目录源: $plugin_name 是否可用."

            local from_plugin="$source_plugins_home/$plugin_name"
            local to_plugin="$site_plugins_home/$plugin_name"
            if [[ -d $from_plugin ]]; then
                log "✅ 插件存在: $plugin_name,准备安装"
                if [[ $PLUGIN_INSTALL_MODE = "symlink" ]]; then
                    rm -rf "$to_plugin" && ln -sfT "$from_plugin" "$to_plugin" -v
                elif [[ $PLUGIN_INSTALL_MODE = "copy" ]]; then
                    rm -rf "$to_plugin" && cp -r "$from_plugin" "$to_plugin"
                else
                    log "❌ 未知的插件安装模式: $PLUGIN_INSTALL_MODE"
                    return 1
                fi
            else
                log "❌ 插件源目录不存在: $plugin_name"
            fi
        fi
    done
}

install_functions_php() {
    local site_themes_home="$1"
    local functions_php="$2"
    log "检查主题目录..."
    for dir in "$site_themes_home"/*/; do
        log "process theme dir [$dir]"
        if [ -d "$dir" ]; then
            \cp -vf "$functions_php" "$dir"
        fi
    done
}

deploy_site() {
    local username="$1"
    local archive_arg="$2"

    local archive_file
    local site_dir_archive
    if [[ "$archive_arg" == */* ]]; then
        site_dir_archive="$archive_arg"
        archive_file="$(basename -- "$archive_arg")"
    else
        archive_file="$archive_arg"
        site_dir_archive="$PACK_ROOT/$username/$archive_file"
    fi

    local domain_name="${archive_file%.*}"

    if [[ "$domain_name" == *.sql ]]; then
        log "⚠️ 检测到文件名包含 .sql 后缀，将其从名称字符串中移除获取其对应(所属)的域名"
        domain_name="${domain_name%.sql}"
    fi

    log "📦 正在处理网站: $domain_name ============"

    if [ ! -f "$site_dir_archive" ]; then
        log "❌ 归档文件不存在: $site_dir_archive"
        return 1
    fi

    local site_domain_home="$PROJECT_HOME/$username/$domain_name"

    local site_expanded_dir_raw="$site_domain_home/$domain_name"
    local site_expanded_dir_wp="$site_domain_home/wordpress"
    local site_root="$site_domain_home/wordpress"

    local plugins_dir="$site_root/wp-content/plugins"
    local themes_dir="$site_root/wp-content/themes"
    local user_ini="$site_root/.user.ini"

    log "解压之前,尝试清空目标目录[$site_root],以便后续干净插入新内容"
    if [ -d "$site_root" ]; then
        rm1 "$site_root"
    fi
    log "创建网站根目录"
    mkdir -p "$site_root" -v

    if [ -d "$site_expanded_dir_raw" ]; then
        log "⚠️ 检测到相关目录已存在: $site_expanded_dir_raw"
        log "正在强力删除现有目录[$site_expanded_dir_raw]并解压新内容 (预计得到目录:$site_expanded_dir_raw) ..."
        rm1 "$site_expanded_dir_raw"
    fi

    if [[ $SITE_ROOT_SKIP == 'true' ]]; then
        log "跳过站点$archive_file 包的解压"
    elif ! extract_archive "$site_dir_archive" "$site_domain_home"; then
        log "❌ 解压失败，本轮跳过此站部署: $domain_name"
        return 1
    else
        log "✅ 解压成功: $site_dir_archive "
        if [[ -d $site_expanded_dir_raw ]]; then
            log "原生包-> $site_expanded_dir_raw"
            log "移动解压后的目录[$site_expanded_dir_raw]内容到目标目录wordpress[$site_root]🎈"
            mv "$site_expanded_dir_raw"/* "$site_root" -f
        elif [[ -d $site_expanded_dir_wp ]]; then
            log "导出包-> $site_expanded_dir_wp"
            log "根目录已经符合预期,不需要移动根目录"
        fi

        log "检查需要安装的插件..."
        install_wp_plugin "$plugins_dir" "$PLUGINS_HOME"
        install_functions_php "$themes_dir" "$FUNCTIONS_PHP"
        if [[ -f "$user_ini" ]]; then
            log "🔍 检测到 .user.ini 文件,设置open_basedir 放行公共插件目录"
            bash /www/sh/update_user_ini.sh -p "$user_ini" -t "$PLUGINS_HOME"
        else
            log "ℹ️ 未找到 .user.ini 文件，跳过权限设置(等待宝塔创建.user.ini)"
        fi
    fi

    log "<<<归档:顺利解压网站归档文件[$archive_file]>>>"
    deployed_dir="$PACK_ROOT/$username/deployed/"
    if [ -f "$site_dir_archive" ]; then
        mv "$site_dir_archive" "$deployed_dir/$archive_file" -f
    else
        log "⚠️ 压缩包文件不存在，跳过归档移动: $site_dir_archive"
    fi

    local sql_file="$PACK_ROOT/$username/$domain_name.sql"
    if [ -f "$sql_file" ]; then
        log "🔍 找到 SQL 文件并导入数据库: $sql_file"
        if [[ $SITE_DB_SKIP != 'true' ]]; then
            if ! import_sql_file "$domain_name" "$username" "$sql_file"; then
                log "❌ 数据库导入失败，跳过后续数据库更新/清理: $domain_name"
                return 1
            fi
        else
            log "跳过 $sql_file 的导入处理"
            return 0
        fi

        log "🗑️ 删除数据库文件: $sql_file"
        rm -f "$sql_file" -v

        local db_name="${username}_${domain_name}"
        MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -P3306 "$db_name" -e "
    UPDATE wp_options
    SET option_value = 'https://www.${domain_name}'
    WHERE option_name IN ('home', 'siteurl');
    "
    else
        log "⚠️ 未找到 SQL 文件: $sql_file"
    fi

    local wps_hide_login_dir="$plugins_dir/wps-hide-login"
    local wps_hide_login_dir_bak="${wps_hide_login_dir}.bak"

    if [ -d "$wps_hide_login_dir_bak" ]; then
        log "🔄 重命名 wps-hide-login.bak 为 wps-hide-login"
        mv "$wps_hide_login_dir_bak" "$wps_hide_login_dir"
    else
        log "ℹ️ 未找到 wps-hide-login.bak 目录，跳过重命名"
    fi

    if [ -f "$site_root/wp-config-sample.php" ] || [ -f "$site_root/wp-config.php" ] || [ -d "$site_root/wp-content" ]; then
        log "✅ 检测到有效的 WordPress 目录结构"
    else
        log "⚠️ 警告：目标目录可能不是有效的 WordPress 安装，未找到典型的 WordPress 文件"
    fi

    local wp_config_path="$site_root/wp-config.php"
    if [ -f "$wp_config_path" ]; then
        update_wp_config "$wp_config_path"
    else
        log "⚠️ 未找到 wp-config.php 文件，跳过 HTTPS 配置"
    fi

    log "🔒 设置目录权限和所有者..."
    chmod -R 755 "$site_root" &> /dev/null
    chown -R www:www "$site_root" &> /dev/null

    set_rewrte_rules_file "$domain_name"

    log "✅ 完成站点部署: $domain_name ==============( 检查/访问: https://www.$domain_name )=============="
    return 0
}

process_sql_file() {
    local username="$1"
    local archive_file="$2"

    local domain_name="${archive_file%.sql.*}"
    log "📦 正在处理网站 $domain_name 的SQL备份文件 $archive_file"

    local user_dir="$PACK_ROOT/$username"
    sql_archive="$user_dir/$archive_file"
    if ! extract_archive "$sql_archive" "$user_dir"; then
        log "❌ 解压SQL备份文件失败: $archive_file"
        return 1
    fi

    local sql_files
    mapfile -t sql_files < <(find "$user_dir" -name "*.sql" -type f)

    if [ ${#sql_files[@]} -eq 0 ]; then
        log "❌ 在解压后的目录中未找到SQL文件"
        return 1
    fi
}

worker_process_sql() {
    local username="$1"
    local archive_file="$2"

    if ! cd "$PACK_ROOT/$username"; then
        log "❌ 无法进入用户目录: $PACK_ROOT/$username"
        return 1
    fi

    local deployed_dir
    deployed_dir="$PACK_ROOT/$username/deployed/"
    if [ ! -d "$deployed_dir" ]; then
        mkdir -p "$deployed_dir"
    fi

    if [ ! -f "$archive_file" ]; then
        log "❌ SQL压缩包文件不存在(可能已被移动/删除): $PACK_ROOT/$username/$archive_file"
        return 1
    fi

    process_sql_file "$username" "$archive_file"
    local rc=$?
    if [ $rc -eq 0 ]; then
        log "<<<归档:已用过的sql压缩包文件: $archive_file >>>"
        mv "$archive_file" "$deployed_dir" -f -v
    fi
    return $rc
}

worker_deploy_site() {
    local username="$1"
    local archive_file="$2"

    if ! cd "$PACK_ROOT/$username"; then
        log "❌ 无法进入用户目录: $PACK_ROOT/$username"
        return 1
    fi

    deploy_site "$username" "$archive_file"
}

if [[ "$1" == "__process_sql" ]]; then
    shift
    worker_process_sql "$@"
    exit $?
fi

if [[ "$1" == "__deploy_site" ]]; then
    shift
    worker_deploy_site "$@"
    exit $?
fi

parse_args "$@"

# ========语法(默认值设置)======
# 使用默认值或用户提供的值🎈
PACK_ROOT=${PACK_ROOT:-$DEFAULT_PACK_ROOT}
DB_USER=${DB_USER:-$DEFAULT_DB_USER}
DB_PASSWORD=${DB_PASSWORD:-$DEFAULT_DB_PASSWORD}
DEPLOYED_DIR=${DEPLOYED_DIR:-$DEFAULT_DEPLOYED_DIR}
PROJECT_HOME=${PROJECT_HOME:-$DEFAULT_PROJECT_HOME}
JOBS=${JOBS:-$DEFAULT_JOBS}
ZSTD_THREADS=${ZSTD_THREADS:-$DEFAULT_ZSTD_THREADS}

export PACK_ROOT DB_USER DB_PASSWORD DEPLOYED_DIR PROJECT_HOME JOBS

if ! [[ "$ZSTD_THREADS" =~ ^[0-9]+$ ]] || [ "$ZSTD_THREADS" -lt 1 ]; then
    log "❌ 无效的 --zstd-threads: $ZSTD_THREADS (必须是 >= 1 的整数)"
    exit 1
fi

export ZSTD_THREADS

# 提示用户当前使用的 PACK_ROOT
log "使用 PACK_ROOT: $PACK_ROOT"
log "检查默认备份文件夹(不存在则创建)"
if [ ! -d "$DEPLOYED_DIR" ]; then
    mkdir -p "$DEPLOYED_DIR"
fi

log "🚀 ==================开始部署 WordPress 站点和数据库...================="

check_commands

cd "$PACK_ROOT" || {
    log "❌ 无法进入目录: $PACK_ROOT"
    exit 1
}

if [ -n "$USER_DIR" ]; then
    user_dirs=("$USER_DIR")
    log "🔍 仅处理指定用户目录: $USER_DIR"
else
    shopt -s nullglob
    user_dirs=(*/)
    shopt -u nullglob
    if [ ${#user_dirs[@]} -eq 0 ]; then
        log "❌ 在 $PACK_ROOT 中没有找到任何用户目录"
        exit 1
    fi
    log "🔍 找到 ${#user_dirs[@]} 个用户目录"
fi

deployed_sites=0
failed_sites=0
sql_backups_processed=0

for user_dir in "${user_dirs[@]}"; do
    username="${user_dir%/}"

    deployed_dir="$PACK_ROOT/$username/deployed/"
    if [ ! -d "$deployed_dir" ]; then
        mkdir -p "$deployed_dir"
    fi

    log "📂 正在处理站点人员名所属目录: $username"

    if ! cd "$PACK_ROOT/$username"; then
        log "❌ 无法进入用户目录: $PACK_ROOT/$username"
        continue
    fi

    shopt -s nullglob
    sql_archives=(*.sql.zip *.sql.7z *.sql.tar *.sql.lz4 *.sql.zst)
    shopt -u nullglob
    if [ -f "${sql_archives[0]}" ]; then
        log "🔍 找到SQL备份文件，优先处理"
        joblog_sql="/tmp/deploy_wp_${username}_sql_$(date +%Y%m%d_%H%M%S).joblog"

        sql_list_file=$(mktemp)
        sql_total=${#sql_archives[@]}
        for ((i = 0; i < sql_total; i++)); do
            printf '%s\t%s\n' "$((i + 1))/$sql_total" "${sql_archives[$i]}" >> "$sql_list_file"
        done

        parallel --jobs "$JOBS" --line-buffer --colsep $'\t' --tagstring "[job {%}/$JOBS][progress {1}][SQL ${username}]" --joblog "$joblog_sql" \
            bash "$0" __process_sql "$username" '{2}' :::: "$sql_list_file"
        rc=$?

        rm -f "$sql_list_file"

        sql_fail=$(awk 'NR>1 && $7!=0 {c++} END{print c+0}' "$joblog_sql")
        sql_ok=$(awk 'NR>1 && $7==0 {c++} END{print c+0}' "$joblog_sql")

        ((sql_backups_processed+=sql_ok))
        ((failed_sites+=sql_fail))

        if [ $rc -ne 0 ]; then
            log "❌ SQL备份文件处理存在失败，请查看: $joblog_sql"
        fi
    else
        log "ℹ️ 未找到SQL压缩文件,跳过解压步骤"
    fi

    site_archives=()
    for archive in *.zip *.7z *.tar *.lz4 *.zst; do
        if [[ -f "$archive" && "$archive" != *.sql.* ]]; then
            site_archives+=("$archive")
        fi
    done

    if [ ${#site_archives[@]} -eq 0 ] || [ ! -f "${site_archives[0]}" ]; then
        log "⚠️ 在目录 $username 中没有找到有效的WordPress站点压缩包。跳过..."
        cd "$PACK_ROOT" || exit
    fi

    joblog_site="/tmp/deploy_wp_${username}_site_$(date +%Y%m%d_%H%M%S).joblog"

    site_list_file=$(mktemp)
    site_total=${#site_archives[@]}
    for ((i = 0; i < site_total; i++)); do
        archive_name="${site_archives[$i]}"
        domain_name="${archive_name%.*}"
        if [[ "$domain_name" == *.sql ]]; then
            domain_name="${domain_name%.sql}"
        fi
        if [[ "$domain_name" == *.tar ]]; then
            domain_name="${domain_name%.tar}"
        fi
        printf '%s\t%s\t%s\n' "$((i + 1))/$site_total" "$domain_name" "$PACK_ROOT/$username/$archive_name" >> "$site_list_file"
    done

    parallel --jobs "$JOBS" --line-buffer --colsep $'\t' --tagstring "[job {%}/$JOBS][progress {1}][SITE {2}]" --joblog "$joblog_site" \
        bash "$0" __deploy_site "$username" '{3}' :::: "$site_list_file"
    rc=$?

    rm -f "$site_list_file"

    site_fail=$(awk 'NR>1 && $7!=0 {c++} END{print c+0}' "$joblog_site")
    site_ok=$(awk 'NR>1 && $7==0 {c++} END{print c+0}' "$joblog_site")

    ((deployed_sites+=site_ok))
    ((failed_sites+=site_fail))

    if [ $rc -ne 0 ]; then
        log "❌ 站点部署存在失败，请查看: $joblog_site"
    fi

    log "🔒 更改deployed文件夹权限(设置目录权限和所有者)"
    chmod -R 755 "$deployed_dir"
    chown -R uploader:uploader "$deployed_dir"

    cd "$PACK_ROOT" || exit

done

log "🚀 ==================重载Nginx 配置...================="
nginx -s reload

log "=========部署完成！解压站点根目录数量:[$deployed_sites] , 解压SQL备份: $sql_backups_processed, 失败: $failed_sites========================"

if [ $failed_sites -gt 0 ]; then
    log "⚠️ 有 $failed_sites 个操作失败，请检查日志。"
    exit 1
fi

exit 0
