#!/bin/bash
echo "deploy_script_version:20260210"
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
                ;; # 指定用户目录,则将工作范围缩小到该目录下
            --deployed-dir)
                DEPLOYED_DIR="$2"
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
            -R | --site-root-only)
                SITE_ROOT_SKIP="$2"
                shift
                ;;
            -D | --site-db-only)
                SITE_DB_SKIP="$2"
                shift
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
parse_args "$@"
# 定义日志文件路径
# LOG_FILE="/srv/uploads/uploader/files/deploy_wp_$($USER_DIR)_$(date +%Y%m%d_%H%M%S).log"
# LOG_DIR=$(dirname "$LOG_FILE") #获取日志文件字符串的目录,然后创建这个目录(如果不存在的话)
# mkdir -p "$LOG_DIR"
# 重定向标准输出和标准错误到日志文件
# exec > >(tee -a "$LOG_FILE") 2>&1

# ========语法(默认值设置)======
# 如果变量未定义或为空，可以设置默认值：
# 使用 ${}扩展语法, ${} 是 参数扩展（Parameter Expansion） 的语法，用于对变量进行操作，包括获取值、字符串处理、默认值设置等
# 语法	             说明
# ${var-default}	如果 var 未定义，使用 default
# ${var:-default}	如果 var 未定义 或为空，使用 default

# 使用默认值或用户提供的值🎈
PACK_ROOT=${PACK_ROOT:-$DEFAULT_PACK_ROOT}
DB_USER=${DB_USER:-$DEFAULT_DB_USER}
DB_PASSWORD=${DB_PASSWORD:-$DEFAULT_DB_PASSWORD}
DEPLOYED_DIR=${DEPLOYED_DIR:-$DEFAULT_DEPLOYED_DIR}
PROJECT_HOME=${PROJECT_HOME:-$DEFAULT_PROJECT_HOME}

# 定义日志函数
log() {
    local message="$1"
    local dt
    dt="$(date '+%Y-%m-%d--%H:%M:%S')"
    message="[$dt] $message"
    echo "$message"
}
# 提示用户当前使用的 PACK_ROOT
log "使用 PACK_ROOT: $PACK_ROOT"
log "检查默认备份文件夹(不存在则创建)"
if [ ! -d "$DEPLOYED_DIR" ]; then
    mkdir -p "$DEPLOYED_DIR"
fi
# === 函数：检查必要的命令是否存在 ===
check_commands() {
    local commands=("mysql" "zstd" "tar") # "unzip" "7z" "lz4" #可选依赖
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

    # 检查配置是否已存在
    # if grep -q "FORCE_SSL_ADMIN" "$wp_config_path"; then
    #     log "ℹ️ HTTPS 配置已存在，跳过修改。"
    #     return 0
    # fi

    # 使用 awk 查找包含 "stop editing" 的那一行号(第一次出现)

    local STOP_LINE
    STOP_LINE=$(awk -v search="$STOP_EDITING_LINE" '$0 ~ search {print NR}' "$wp_config_path" | head -n 1)
    if [ -n "$STOP_LINE" ]; then
        # 插入用于启用https的代码片段
        sed -i "${STOP_LINE}a$HTTPS_CONFIG_LINE" "$wp_config_path"
        # 编辑数据库链接信息
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

    # 构造数据库名：保留域名中的点 "."
    local db_name="${username}_${domain}"

    log "📦 正在处理数据库: $db_name"

    # 导入前现检查是否有对应数据库存在,如果有先移除旧数据库!
    if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" -e "DROP DATABASE IF EXISTS \`${db_name}\`;"; then
        log "🗑️ 旧数据库已删除。"
    else
        log "❌ 删除旧数据库失败，请检查数据库连接和权限。"
        return 1
    fi
    # 创建数据库(空数据库)
    if ! echo "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;" | mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD"; then
        log "❌ 创建数据库失败，请检查数据库连接和权限。"
        return 1
    fi

    # 导入 SQL 文件
    log "🚚 正在导入 SQL 文件: $sql_file 到数据库 $db_name"
    if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$db_name" < "$sql_file"; then
        log "✅ 数据库 $db_name 成功导入。"
        return 0
    else
        log "❌ 导入失败，请检查 SQL 文件或数据库权限。"
        return 1
    fi
}

# === 函数：设置伪静态规则文件(通过复制文件到指定位置) ===
set_rewrte_rules_file() {
    # 将/www/wwwroot/RewriteRules.LF.conf 赋值到被部署网站的对于伪静态文件存路径:"/www/server/panel/vhost/rewrite/${domain}.conf"
    local domain="$1"
    local rewrite_template="/www/woo_df/RewriteRules.LF.conf"
    local rewrite_target="/www/server/panel/vhost/rewrite/${domain}.conf"
    # 覆盖式将文件复制到目标位置
    if [ -f "$rewrite_template" ]; then
        # 强制性复制并详情输出，增加 -v 参数提升可读性，并添加错误处理
        log "🔄 正在复制伪静态规则文件到目标位置: $rewrite_target"
        if cp -v "$rewrite_template" "$rewrite_target"; then
            log "✅ 伪静态规则文件已成功复制到: $rewrite_target"
            # log "修改伪静态文件[$rewrite_target]的标志位使其无法被轻易修改或覆盖(比如宝塔添加对应目录下的站点时可以不被覆盖伪静态规则),但是宝塔api创建站点的操作将会执行失败"
            # chattr +i "$rewrite_target"  -V
        else
            log "❌ 复制伪静态规则文件失败: 源文件=$rewrite_template, 目标=$rewrite_target"
            return 1
        fi
    else
        log "❌ 未找到伪静态规则模板文件: $rewrite_template"
        return 1
    fi

}

# # ====仅检测原生tar格式文件====
is_plain_tar_file() {
    local file_path="$1"
    [[ -f "$file_path" ]] && [[ $(file -b --mime-type "$file_path") == "application/x-tar" ]]
}
######################################
# === 函数：解压压缩文件（带完整性检查）===
# Description:
# 将压缩文件解压到指定位置(目录),解压网站根目录和数据库sql文件的zst文件
# 具体的格式转换为:将tar格式压缩成的zst包进行zstd解压和tar抽取
# 注意,如果解压的文件是从原文件直接zstd压缩,而没有预先tar处理再压缩的zst包,则解压可能会现出乎意料的错误.
# 此函数无法直接控制解压结束后得到的文件或目录名,只能控制到其父目录!
# 因此,如果要进一步操作,尤其是精确操作的话,需要你对压缩包的目录结构有了解
# Globals:
#   None
# Arguments:
#   $1 - 压缩包文件路径
#   $2 - 将文件解压到指定目录下
#
# Outputs:
# Returns:
#   0 on success, non-zero on error
# Example:
#
######################################
extract_archive() {
    local archive_file="$1"
    local site_root="$2"

    # 参数校验
    if [ ! -f "$archive_file" ]; then
        log "❌ 归档文件不存在: $archive_file"
        return 1
    fi

    if [ -z "$site_root" ]; then
        log "❌ 目标目录未指定"
        return 1
    fi

    # 确保目标目录存在,否则创建此目录
    mkdir -p "$site_root"

    log "🔍 正在处理归档文件: $archive_file -> $site_root/"

    local ext="${archive_file##*.}"
    # tar文件临时名字
    local temp_output_file

    # 完整性检查函数（内联）
    check_integrity() {
        local cmd="$1"
        shift
        log "🧪 正在验证归档完整性..."
        # if ! "$cmd" --test "$@" >/dev/null 2>&1; then
        if ! "$cmd" --test "$@"; then
            log "❌ 归档文件损坏或格式不支持: $archive_file"
            return 1
        fi
        log "✅ 归档文件完整性验证通过"
    }

    # 根据扩展名处理不同格式
    case "$ext" in

        zst | zstd)
            # 这里是特化任务,根据团队规范,默认上传的包实际格式是tar.zst,即便后缀只有.zst而不是.tar.zst,其解压zst层后得到的文件是tar文件(二进制文件)
            # 在这个分支中,首先解压zst层,然后将解压后的内部tar文件再调用tar解压,得到文件(夹)
            log "🧪 正在验证 ZSTD 文件完整性..."
            if ! zstd -t "$archive_file" > /dev/null 2>&1; then
                log "❌ ZSTD 文件损坏或格式错误: $archive_file"
                return 1
            fi
            log "✅ ZSTD 文件完整性验证通过"
            # 解压结果保存成一个临时文件(tar格式的二进制文件)
            temp_output_file=$(mktemp -u)
            log "📦 正在解压 ZSTD 文件(得到临时tar文件)..."
            if ! zstd -T0 -d "$archive_file" -o "$temp_output_file"; then
                log "❌ 解压 ZSTD 文件失败"
                rm -f "$temp_output_file"
                return 1
            fi

            log "🧪 正在验证内部文件 (是否为TAR 文件以及tar文件完整性)..."
            # tar文件的测试,检查和解压
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
            # tar包临时文件已经抽取完毕,移除
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
            # 先测试是否能解压到 /dev/null
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

            # 检查解压出的 tar 是否完整
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

        \
            *)
            # 使用 7z 处理其他格式（如 rar, 7z, xz, iso 等）
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
# 安装插件
# 检查网站插件目录中的文件及其文件名(视为插件名,文件是插件需要安装的标记)
# 函数将在指定目录中检查插件是否存在,如果存在指定插件,则安装该插件(默认安装模式为符号链接)
# Args:
#   $1: 站点插件目录,供检索待安装插件标记文件
#   $2: 插件源目录所在目录,供检索指定插件是否存在(可用)
install_wp_plugin() {
    local site_plugins_home="$1"
    local source_plugins_home="$2"
    log "🔍 检查插件目录: $site_plugins_home 中的所有文件"
    [[ -d $site_plugins_home ]] || {
        log "❌ 站点插件目录不存在: $site_plugins_home"
        return 1
    }
    for plugin in "$site_plugins_home"/*; do
        # 将插件标记文件或空目录视为插件要安装(覆盖)
        if [ -f "$plugin" ] || [ -z "$(ls -A "$plugin")" ]; then
            local plugin_name
            plugin_name=$(basename "$plugin")
            [[ ${plugin_name} = *.php ]] && continue #跳过.php文件
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
# 安装functions.php文件
# Args:
#   $1:网站的主题目录
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
######################################
# Description:
#   部署单个站点
#   解压网站根目录的归档压缩包到指定目录
#   根据给定的压缩包路径计算配套的sql文件归档压缩包路径
#       首先解析网站域名,再构造sql文件名,拼接出完整sql文件路径
#       再导入对应的.sql文件(sql文件在前置步骤中解压完毕)
#   收尾:更改必要的目录权限和配置文件
# 关于解压根目录压缩包,需要兼容两种路径规范(十分相近,根目录仅差一层wordpress目录级别)
# 可以分为原生包和导出包,前者是建站人员初次打包的,根目录名是网站域名.后者是从服务器导出的,会多一层根目录名wordpress.
# 因此在解压完毕后(zst->tar->site_dir),需要将site_dir做分支判断处理
#
# Globals:
#   None
# Arguments:
#   $1 - username 部署到那个人员名(用户名)目录下
#   $2 - archive_file 被部署的网站归档文件(站点根目录压缩包)
#
# Outputs:
# Returns:
#   0 on success, non-zero on error
# Example:
#
######################################
deploy_site() {
    local username="$1"
    local archive_file="$2"

    # 获取不带扩展名的域名，处理可能包含 .sql 的情况
    # 先去掉 .zip 或 .7z ,lz4等 扩展名
    local domain_name="${archive_file%.*}"

    # 分析sql文件是属于哪一个域名站点(检查是否以 .sql 结尾，如果是则去掉 .sql 后缀,获得sql所属的域名信息)
    if [[ "$domain_name" == *.sql ]]; then
        log "⚠️ 检测到文件名包含 .sql 后缀，将其从名称字符串中移除获取其对应(所属)的域名"
        domain_name="${domain_name%.sql}"
    fi

    log "📦 正在处理网站: $domain_name ============"

    # === 解压站点压缩包 ===
    # local extracted_domain_dir="$PACK_ROOT/$username/$domain_name"
    local site_dir_archive="$PACK_ROOT/$username/$archive_file" #压缩包路径

    # 网站根目录所在目录, 例如:/www/wwwroot/zsh/domain.com
    local site_domain_home="$PROJECT_HOME/$username/$domain_name"
    #对于用7z打包domain.com为目录名的7z包,解压后得到domain.com目录 7z x $site_dir_archive -o$site_domain_home 执行结果得到目录$site_domain_home/domain.com,为了便于引用,将其赋值给变量$site_expanded_dir_raw,表示解压后得到的目录

    # 网站压缩包要解压结果所在的目录(默认情况,根据需要可以进一步移动处理)
    local site_expanded_dir_raw="$site_domain_home/$domain_name"
    # # 网站压缩包要解压结果所在的目录(从服务器导出备份包还原的情况,和site_root恰好相同)
    local site_expanded_dir_wp="$site_domain_home/wordpress"
    # 网站最终的根目录
    local site_root="$site_domain_home/wordpress"

    # 根目录下的其他目录

    # 网站插件目录
    local plugins_dir="$site_root/wp-content/plugins"
    # 网站主题总目录
    local themes_dir="$site_root/wp-content/themes"
    # 网站根目录下的路径限制配置文件(防跨站open_basedir...)
    local user_ini="$site_root/.user.ini"

    log "解压之前,尝试清空目标目录[$site_root],以便后续干净插入新内容"
    # mkdir -p "$site_root"
    if [ -d "$site_root" ]; then
        rm1 "$site_root" # 删除网站根目录
    fi
    log "创建网站根目录"
    mkdir -p "$site_root" -v
    # 解压网站文件|如果存在同名目录,则默认覆盖🎈
    # 原生包情况下(另一种是导出包)
    if [ -d "$site_expanded_dir_raw" ]; then
        log "⚠️ 检测到相关目录已存在: $site_expanded_dir_raw"

        # log "是否覆盖现有目录? (yY/n): "
        # read -r response
        # if [[ "$response" != "y" && "$response" != "Y" ]]; then
        #     log "用户选择不覆盖，跳过此解压步骤: $domain_name"
        # else
        #     log "⚠️用户选择覆盖现有目录: $site_expanded_dir_raw"
        #覆盖逻辑段存放在此
        # fi
        # 覆盖逻辑段(begin)
        log "正在强力删除现有目录[$site_expanded_dir_raw]并解压新内容 (预计得到目录:$site_expanded_dir_raw) ..."
        # rm -rf "$site_expanded_dir_raw" # 删除现有目录
        rm1 "$site_expanded_dir_raw" # 删除现有目录
    fi

    # 纯净解压(预先存在或残留的目录此时已经清理完毕.)
    if [[ $SITE_ROOT_SKIP == 'true' ]]; then
        log "跳过站点$archive_file 包的解压"
        # 判断解压是否成功
    elif ! extract_archive "$site_dir_archive" "$site_domain_home"; then
        log "❌ 解压失败，本轮跳过此站部署: $domain_name"
        return 1
    else
        log "✅ 解压成功: $site_dir_archive "
        # 判断包到类型(情况)
        if [[ -d $site_expanded_dir_raw ]]; then
            log "原生包-> $site_expanded_dir_raw"
            log "移动解压后的目录[$site_expanded_dir_raw]内容到目标目录wordpress[$site_root]🎈"
            if [[ -d $site_root ]]; then
                log "目标目录[$site_root]已存在,直接移动解压内容到该目录"
            fi
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
    # 如果上述操作没有出错(return 1没有执行),则执行文件归档操作
    log "<<<归档:顺利解压网站归档文件[$archive_file]>>>"
    deployed_dir="$PACK_ROOT/$username/deployed/"
    mv "$archive_file" "$deployed_dir" -f
    # mv "$archive_file" "$DEPLOYED_DIR" -f

    # === 检查并导入对应的 SQL 文件 ===
    local sql_file="$PACK_ROOT/$username/$domain_name.sql"
    if [ -f "$sql_file" ]; then
        log "🔍 找到 SQL 文件并导入数据库: $sql_file"
        # 将导入环节放到前面去执行,可以并行导入sql文件提高效率
        if [[ $SITE_DB_SKIP != 'true' ]]; then
            import_sql_file "$domain_name" "$username" "$sql_file"
        else
            log "跳过 $sql_file 的导入处理"
            # 返回
            return 0
        fi
        # 删除数据库文件.sql(已导入)
        log "🗑️ 删除数据库文件: $sql_file"
        rm -f "$sql_file" -v

        # === 配置数据库===
        local db_name="${username}_${domain_name}"
        mysql -h "$DB_HOST" -u "$DB_USER" -P3306 -p"$DB_PASSWORD" "$db_name" -e "
    UPDATE wp_options
    SET option_value = 'https://www.${domain_name}'
    WHERE option_name IN ('home', 'siteurl');
    "
    else
        log "⚠️ 未找到 SQL 文件: $sql_file"
        # 尝试查找其他可能的 SQL 文件名格式
        # local alt_sql_file="$PACK_ROOT/$username/${domain_name}*.sql"
        # if [ -f "$alt_sql_file" ]; then
        #     log "🔍 找到替代 SQL 文件: $alt_sql_file"
        #     import_sql_file "$domain_name" "$username" "$alt_sql_file"
        # fi
    fi

    # 站点根目录配置文件和插件相关检车和更改-------------------
    # 将可能阻碍登录后台wps-hide-login.bak这个插件目录改为wps-hide-login

    local wps_hide_login_dir="$plugins_dir/wps-hide-login"
    local wps_hide_login_dir_bak="${wps_hide_login_dir}.bak"

    if [ -d "$wps_hide_login_dir_bak" ]; then
        log "🔄 重命名 wps-hide-login.bak 为 wps-hide-login"
        # mv "$site_root/wps-hide-login.bak" "$site_root/wps-hide-login"
        mv "$wps_hide_login_dir_bak" "$wps_hide_login_dir"
    else
        log "ℹ️ 未找到 wps-hide-login.bak 目录，跳过重命名"
    fi

    # 检查是否为有效的 WordPress 目录
    if [ -f "$site_root/wp-config-sample.php" ] || [ -f "$site_root/wp-config.php" ] || [ -d "$site_root/wp-content" ]; then
        log "✅ 检测到有效的 WordPress 目录结构"
    else
        log "⚠️ 警告：目标目录可能不是有效的 WordPress 安装，未找到典型的 WordPress 文件"
    fi

    # === 修改 wp-config.php 文件 ===
    local wp_config_path="$site_root/wp-config.php"
    if [ -f "$wp_config_path" ]; then
        update_wp_config "$wp_config_path"
    else
        log "⚠️ 未找到 wp-config.php 文件，跳过 HTTPS 配置"
    fi

    # 设置目录权限和所有者
    log "🔒 设置目录权限和所有者..."
    chmod -R 755 "$site_root" &> /dev/null
    chown -R www:www "$site_root" &> /dev/null

    # === 写入伪静态规则 ===
    # write_rewrite_rules "$domain_name"
    set_rewrte_rules_file "$domain_name"
    log "🔄 等待重载 nginx 配置,以便让伪静态生效"
    # 部署批次结束后再统一重启,减少重载次数提高效率
    # nginx -s reload

    log "✅ 完成站点部署: $domain_name ==============( 检查/访问: https://www.$domain_name )=============="
    return 0
}

# === 函数：查找并处理SQL备份文件🎈 ===
# 此函数会分析传入的用户名和sql包文件名(针对一个站),构造对应的数据库名,并检查对应的文件是否存在
# 如果存在,则解压sql文件压缩包,如果不存在,则报错
process_sql_file() {
    local username="$1"
    local archive_file="$2"

    # 获取域名（去掉.sql.zip或.sql.7z后缀）
    local domain_name="${archive_file%.sql.*}"
    log "📦 正在处理网站 $domain_name 的SQL备份文件 $archive_file"

    # 解压SQL备份文件
    local user_dir="$PACK_ROOT/$username"
    sql_archive="$user_dir/$archive_file"
    # 解压sql文件包
    if ! extract_archive "$sql_archive" "$user_dir"; then
        log "❌ 解压SQL备份文件失败: $archive_file"
        return 1
    fi

    # 查找解压后的SQL文件
    local sql_files=($(find "$user_dir" -name "*.sql" -type f))

    if [ ${#sql_files[@]} -eq 0 ]; then
        log "❌ 在解压后的目录中未找到SQL文件"
        return 1
    fi

    # 导入找到的第一个SQL文件
    # log "🔍 找到SQL文件: ${sql_files[0]}"
    # if import_sql_file "$domain_name" "$username" "${sql_files[0]}"; then
    #     log "✅ SQL备份成功导入到数据库"
    #     rm -rf "$temp_dir"
    #     return 0
    # else
    #     log "❌ SQL备份导入失败"
    #     rm -rf "$temp_dir"
    #     return 1
    # fi
}

# ================================================ 主程序开始 🎈=============================================

log "🚀 ==================开始部署 WordPress 站点和数据库...================="

# 检查必要的命令
check_commands

# 进入指定目录
cd "$PACK_ROOT" || {
    log "❌ 无法进入目录: $PACK_ROOT"
    exit 1
}

# 如果指定了用户目录，则仅处理该目录,否则遍历所有子目录
if [ -n "$USER_DIR" ]; then
    # 指定单目录时,将单个目录包装成数组(单个元素),便于后续统一两种情况为数组处理
    user_dirs=("$USER_DIR")
    log "🔍 仅处理指定用户目录: $USER_DIR"
else
    # 否则遍历所有子目录
    user_dirs=($(ls -d */ 2> /dev/null))
    if [ ${#user_dirs[@]} -eq 0 ]; then
        log "❌ 在 $PACK_ROOT 中没有找到任何用户目录"
        exit 1
    fi
    log "🔍 找到 ${#user_dirs[@]} 个用户目录"
fi
# 统计处理的站点数
deployed_sites=0
failed_sites=0
sql_backups_processed=0

# ==========按照用户名(目录)逐个用户地处理🎈====
for user_dir in "${user_dirs[@]}"; do
    # 去掉末尾斜杠(如果有的话)，得到用户名缩写
    username="${user_dir%/}"
    # 创建用于归档已经使用过的文件的目录(移动到当前user文件的deployed目录中,例如 为用户zsh /srv/uploads/uploader/files/zsh下的deployed目录中,如果不存在,则创建此目录 )

    # 创建全局归档目录
    # deployed_dir="$DEPLOYED_DIR"
    # 为当前用户创建归档目录(deployed)
    deployed_dir="$PACK_ROOT/$username/deployed/"
    if [ ! -d "$deployed_dir" ]; then
        mkdir -p "$deployed_dir"
    fi

    log "📂 正在处理站点人员名所属目录: $username"

    # 进入用户目录
    if ! cd "$PACK_ROOT/$username"; then
        log "❌ 无法进入用户目录: $PACK_ROOT/$username"
        continue
    fi

    # 首先处理SQL备份文件(将所有站点的sql文件都解压,然后逐个导入到对应的数据库)
    # 数据库名字:调用process_sql_file进行处理
    sql_archives=($(ls *.sql.zip *.sql.7z *.sql.tar *.sql.lz4 *.sql.zst 2> /dev/null))
    if [ -f "${sql_archives[0]}" ]; then
        log "🔍 找到SQL备份文件，优先处理"
        log "处理全部待部署网站的数据库文件🎈(使用&和wait并行处理)"
        # 并行处理SQL备份文件
        pids=()
        sql_archive_names=()
        for sql_archive in "${sql_archives[@]}"; do
            if [ ! -f "$sql_archive" ]; then
                continue
            fi
            process_sql_file "$username" "$sql_archive" &

            pids+=("$!")
            sql_archive_names+=("$sql_archive")
        done
        # 等待所有后台任务完成，并统计成功/失败
        for i in "${!pids[@]}"; do
            pid="${pids[$i]}"
            sql_archive="${sql_archive_names[$i]}"
            if wait "$pid"; then
                ((sql_backups_processed++))
                # 归档已用过的sql压缩包文件
                log "<<<归档:已用过的sql压缩包文件: $sql_archive >>>"
                deployed_dir="$PACK_ROOT/$username/deployed/"
                mv "$sql_archive" "$deployed_dir" -f -v
                # mv "$sql_archive" "$DEPLOYED_DIR" -f -v
            else
                ((failed_sites++))
                log "❌ SQL备份文件处理失败: $sql_archive"
            fi
        done
    else
        log "ℹ️ 未找到SQL压缩文件,跳过解压步骤"
    fi

    # 然后处理WordPress站点文件（过滤出非sql压缩备份文件,得到网站根目录包文件）
    site_archives=()
    for archive in *.zip *.7z *.tar *.lz4 *.zst; do
        if [[ -f "$archive" && "$archive" != *.sql.* ]]; then
            site_archives+=("$archive")
        fi
    done

    if [ ${#site_archives[@]} -eq 0 ] || [ ! -f "${site_archives[0]}" ]; then
        log "⚠️ 在目录 $username 中没有找到有效的WordPress站点压缩包。跳过..."
        cd "$PACK_ROOT" || exit
        # continue
    fi

    # 并行处理站点部署
    deploy_pids=()
    deploy_archive_names=()
    for archive_file in "${site_archives[@]}"; do
        if [ ! -f "$archive_file" ]; then
            continue
        fi
        # 后台执行部署任务
        deploy_site "$username" "$archive_file" &
        deploy_pids+=("$!")
        deploy_archive_names+=("$archive_file")
    done
    # 等待所有后台部署任务完成，并统计成功/失败
    for i in "${!deploy_pids[@]}"; do
        pid="${deploy_pids[$i]}"
        archive_file="${deploy_archive_names[$i]}"
        if wait "$pid"; then
            ((deployed_sites++))
            # 可在此处添加归档逻辑（如需）

        else
            ((failed_sites++))
            log "❌ 站点部署失败: $archive_file"
        fi
    done
    # 更改deployed文件夹权限
    log "🔒 更改deployed文件夹权限(设置目录权限和所有者)"
    chmod -R 755 "$deployed_dir"
    chown -R uploader:uploader "$deployed_dir"

    # 返回上级目录
    cd "$PACK_ROOT" || exit
done
# 部署批次结束后再统一重启,减少重载次数提高效率
log "🚀 ==================重载Nginx 配置...================="
nginx -s reload

log "=========部署完成！解压站点根目录数量:[$deployed_sites] , 解压SQL备份: $sql_backups_processed, 失败: $failed_sites========================"

if [ $failed_sites -gt 0 ]; then
    log "⚠️ 有 $failed_sites 个操作失败，请检查日志。"
    exit 1
fi

exit 0
