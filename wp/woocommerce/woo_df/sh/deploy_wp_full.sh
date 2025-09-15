#!/bin/bash

# === 配置参数 ===
# 依赖说明:主要依赖于外部的伪静态规则文件RewriteRules.LF.conf,以及7z解压工具
# 在powershell中将词文件更新/推送到服务器(可以使用scp命令):
# scp -r C:\repos\scripts\wp\woocommerce\woo_df\sh\deploy_wp_full.sh root@${env:DF_SERVER1}:"/www/wwwroot/deploy_wp_full.sh"
# 默认值
UPLOADER_DIR="/srv/uploads/uploader"
DEFAULT_PACK_ROOT="$UPLOADER_DIR/files"
DEFAULT_DB_USER="root"
DEFAULT_DB_PASSWORD="15a58524d3bd2e49"
DEFAULT_DEPLOYED_DIR="$UPLOADER_DIR/deployed_all"
SERVER_SITE_HOME="/www/wwwroot"

DB_HOST="localhost" # 数据库主机
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
    echo "  --deployed-dir DIR 默认存储已部署的包文件(默认: $DEFAULT_DEPLOYED_DIR)"
    echo "  --help            显示此帮助信息"
    exit 0
}

# 命令行参数解析
while [[ "$#" -gt 0 ]]; do
    case $1 in
    --pack-root)
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
    --help) show_help ;;
    *)
        echo "未知参数: $1"
        exit 1
        ;;
    esac
    shift
done

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

# 提示用户当前使用的 PACK_ROOT
echo "使用 PACK_ROOT: $PACK_ROOT"
echo "检查默认备份文件夹(不存在则创建)"
if [ ! -d "$DEPLOYED_DIR" ]; then
    mkdir -p "$DEPLOYED_DIR"
fi
# === 函数：检查必要的命令是否存在 ===
check_commands() {
    local commands=("mysql" "unzip" "7z" "lz4" "zstd" "tar")
    local missing_commands=()

    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
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

        sed -ri "s/(define\(\s*'DB_HOST',)(.*)\)/\1'${DB_HOST}')/" "$wp_config_path"
        sed -ri "s/(define\(\s*'DB_NAME',)(.*)\)/\1'$db_name')/" "$wp_config_path"
        sed -ri "s/(define\(\s*'DB_USER',)(.*)\)/\1'${DB_USER}')/" "$wp_config_path"
        sed -ri "s/(define\(\s*'DB_PASSWORD',)(.*)\)/\1'${DB_PASSWORD}')/" "$wp_config_path"
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
    if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$db_name" <"$sql_file"; then
        echo "✅ 数据库 $db_name 成功导入。"
        return 0
    else
        echo "❌ 导入失败，请检查 SQL 文件或数据库权限。"
        return 1
    fi
}

# === 函数：设置伪静态规则文件(通过复制文件到指定位置) ===
set_rewrte_rules_file() {
    # 将/www/wwwroot/RewriteRules.LF.conf 赋值到被部署网站的对于伪静态文件存路径:"/www/server/panel/vhost/rewrite/${domain}.conf"
    local domain="$1"
    local rewrite_template="/www/wwwroot/RewriteRules.LF.conf"
    local rewrite_target="/www/server/panel/vhost/rewrite/${domain}.conf"
    # 覆盖式将文件复制到目标位置
    if [ -f "$rewrite_template" ]; then
        # 强制性复制并详情输出，增加 -v 参数提升可读性，并添加错误处理
        echo "🔄 正在复制伪静态规则文件到目标位置: $rewrite_target"
        if cp -v "$rewrite_template" "$rewrite_target"; then
            echo "✅ 伪静态规则文件已成功复制到: $rewrite_target"
            # echo "修改伪静态文件[$rewrite_target]的标志位使其无法被轻易修改或覆盖(比如宝塔添加对应目录下的站点时可以不被覆盖伪静态规则),但是宝塔api创建站点的操作将会执行失败"
            # chattr +i "$rewrite_target"  -V
        else
            echo "❌ 复制伪静态规则文件失败: 源文件=$rewrite_template, 目标=$rewrite_target"
            return 1
        fi
    else
        echo "⚠️ 未找到伪静态规则模板文件: $rewrite_template"
        return 1
    fi

}
# ==获取字符串中主域名.顶级域名的部分
# get_main_domain() {
#     local s="$1"

#     if [[ "$s" == *.*.* ]]; then
#         local a="${s%%.*}"
#         local b="${s#*.}"; b="${b%%.*}"
#         echo "$a.$b"
#     else
#         echo "$s"
#     fi
# }
# === 检查归档文件是否完整===

# === 函数：解压压缩文件(不检查完整性) ===
# extract_archive_without_check() {
#     local archive_file="$1"
#     local target_dir="$2"

#     # 确保目标目录存在
#     mkdir -p "$target_dir"

#     echo "🔍 正在解压文件: $archive_file -> $target_dir/..."

#     case "${archive_file##*.}" in
#         zip)
#             unzip -q "$archive_file" -d "$target_dir"
#             ;;
#         gz|tgz)
#             tar -xzf "$archive_file" -C "$target_dir"
#             ;;
#         bz2|tbz2)
#             tar -xjf "$archive_file" -C "$target_dir"
#             ;;
#         lz4)
#             # 使用 mktemp 创建唯一临时文件名
#             temp_output_file=$(mktemp -u)

#             # 纠正域名提取:target_dir (将domain.com.tar)

#             echo "🔍 正在解压 LZ4 文件: $archive_file"

#             echo "解压 .lz4 到临时文件"
#             if ! lz4 -d "$archive_file" "$temp_output_file"; then
#                 echo "❌ 解压 LZ4 文件失败: $archive_file"
#                 rm -f "$temp_output_file" -v
#                 return 1
#             fi

#             echo  "解包 .tar 文件 $temp_output_file"
#             if ! tar -xf "$temp_output_file" -C "$target_dir"; then
#                 echo "❌ 解包 TAR 文件失败: $temp_output_file"
#                 rm -f "$temp_output_file" -v 
#                 return 1
#             fi

            
#             echo "清理临时文件 $temp_output_file"
#             rm -f "$temp_output_file" -v
#             ;;
#         zst|zstd)
#             # 使用 mktemp 创建唯一临时文件名
#             temp_output_file=$(mktemp -u)


#             echo "🔍 正在解压 zstd 文件: $archive_file"

#             echo "解压 .zst 到临时文件"
#             if ! zstd -d "$archive_file" -o "$temp_output_file"; then
#                 echo "❌ 解压 zstd 文件失败: $archive_file"
#                 rm -f "$temp_output_file" -v
#                 return 1
#             fi

#         echo  "解包 .tar 文件 $temp_output_file"
#             if ! tar -xf "$temp_output_file" -C "$target_dir"; then
#                 echo "❌ 解包 TAR 文件失败: $temp_output_file"
#                 rm -f "$temp_output_file" -v 
#                 return 1
#             fi

#         echo "清理临时文件 $temp_output_file"
#             rm -f "$temp_output_file" -v
#             ;;
#         tar)
#             echo "🔍 正在解包 TAR 文件: $archive_file"
#             if ! tar -xf "$archive_file" -C "$target_dir"; then
#                 echo "❌ 解包 TAR 文件失败: $archive_file"
#                 return 1
#             fi
#             ;;
#         *)
#             7z x "$archive_file" -o"$target_dir"
#             ;;
#     esac
#     # 如果输入的包是zip,则使用unzip解压zip包
#     # if [ "${archive_file##*.}" = "zip" ]; then
#     #     unzip -q "$archive_file" -d "$target_dir"
#     # else
#     #     7z x "$archive_file" -o"$target_dir"
#     # fi

#     # 其他格式使用7z几乎通杀:
#     # 使用7z解压，支持各种格式(对于解压任务,使用多线程解压线程效果似乎没什么)
#     # if ! 7z x -mmt32 -y "$archive_file" -o"$target_dir"; then
#     #     echo "❌ 解压失败: $archive_file"
#     #     return 1
#     # fi
  

#     return 0
# }
# # ====仅检测原生tar格式文件====
is_plain_tar_file() {
    local file_path="$1"
    [[ -f "$file_path" ]] && [[ $(file -b --mime-type "$file_path") == "application/x-tar" ]]
}
# === 函数：解压压缩文件（带完整性检查）===
# 将压缩文件解压到指定位置(目录)
extract_archive() {
    local archive_file="$1"
    local target_dir="$2"

    # 参数校验
    if [ ! -f "$archive_file" ]; then
        echo "❌ 归档文件不存在: $archive_file"
        return 1
    fi

    if [ -z "$target_dir" ]; then
        echo "❌ 目标目录未指定"
        return 1
    fi

    # 确保目标目录存在
    mkdir -p "$target_dir"

    echo "🔍 正在处理归档文件: $archive_file -> $target_dir/"

    local ext="${archive_file##*.}"
    local temp_output_file

    # 完整性检查函数（内联）
    check_integrity() {
        local cmd="$1"
        shift
        echo "🧪 正在验证归档完整性..."
        # if ! "$cmd" --test "$@" >/dev/null 2>&1; then
        if ! "$cmd" --test "$@" ; then
            echo "❌ 归档文件损坏或格式不支持: $archive_file"
            return 1
        fi
        echo "✅ 归档文件完整性验证通过"
    }

    # 根据扩展名处理不同格式
    case "$ext" in
        zip)
            if ! check_integrity unzip "$archive_file"; then
                return 1
            fi
            echo "📦 正在解压 ZIP 文件..."
            if ! unzip -q "$archive_file" -d "$target_dir"; then
                echo "❌ 解压 ZIP 文件失败: $archive_file"
                return 1
            fi
            ;;

        gz|tgz)
            if ! check_integrity tar -tzf "$archive_file"; then
                return 1
            fi
            echo "📦 正在解压 GZ/TGZ 文件..."
            if ! tar -xzf "$archive_file" -C "$target_dir"; then
                echo "❌ 解压 GZ/TGZ 文件失败: $archive_file"
                return 1
            fi
            ;;

        bz2|tbz2)
            if ! check_integrity tar -tjf "$archive_file"; then
                return 1
            fi
            echo "📦 正在解压 BZ2/TBZ2 文件..."
            if ! tar -xjf "$archive_file" -C "$target_dir"; then
                echo "❌ 解压 BZ2/TBZ2 文件失败: $archive_file"
                return 1
            fi
            ;;

        lz4)
            # 先测试是否能解压到 /dev/null
            echo "🧪 正在验证 LZ4 文件完整性..."
            if ! lz4 -t "$archive_file" >/dev/null 2>&1; then
                echo "❌ LZ4 文件损坏或格式错误: $archive_file"
                return 1
            fi
            echo "✅ LZ4 文件完整性验证通过"

            temp_output_file=$(mktemp -u)
            echo "📦 正在解压 LZ4 文件..."
            if ! lz4 -d "$archive_file" "$temp_output_file"; then
                echo "❌ 解压 LZ4 文件失败"
                rm -f "$temp_output_file"
                return 1
            fi

            # 检查解压出的 tar 是否完整
            echo "🧪 正在验证解包后的 TAR 文件完整性..."
            if ! tar -tf "$temp_output_file" >/dev/null 2>&1; then
                echo "❌ 内部 TAR 文件损坏"
                rm -f "$temp_output_file"
                return 1
            fi

            echo "📦 正在解包 TAR 数据..."
            if ! tar -xf "$temp_output_file" -C "$target_dir"; then
                echo "❌ 解包 TAR 失败"
                rm -f "$temp_output_file"
                return 1
            fi

            rm -f "$temp_output_file"
            ;;

        zst|zstd)
        # 这里是特化任务,根据团队规范,默认上传的包实际格式是tar.zst,即便后缀只有.zst而不是.tar.zst,其解压zst层后得到的文件是tar文件(二进制文件)
        # 在这个分支中,首先解压zst层,然后将解压后的内部tar文件再调用tar解压,得到文件(夹)
            echo "🧪 正在验证 ZSTD 文件完整性..."
            if ! zstd -t "$archive_file" >/dev/null 2>&1; then
                echo "❌ ZSTD 文件损坏或格式错误: $archive_file"
                return 1
            fi
            echo "✅ ZSTD 文件完整性验证通过"
            # 解压结果保存成一个临时文件(tar格式的二进制文件)
            temp_output_file=$(mktemp -u)
            echo "📦 正在解压 ZSTD 文件..."
            if ! zstd -T0 -d "$archive_file" -o "$temp_output_file"; then
                echo "❌ 解压 ZSTD 文件失败"
                rm -f "$temp_output_file"
                return 1
            fi

            echo "🧪 正在验证内部文件 (是否为TAR 文件以及tar文件完整性)..."
            
            if is_plain_tar_file "$temp_output_file"; then
                echo "是原生tar文件"
            else
                echo "不是原生tar文件"
            fi

            if ! tar -tf "$temp_output_file" >/dev/null 2>&1; then
                echo "❌ 内部 TAR 文件损坏或者文件不是tar文件"
                rm -f "$temp_output_file"
                return 1
            fi

            echo "📦 正在解包 TAR 数据..."
            if ! tar -xf "$temp_output_file" -C "$target_dir"; then
                echo "❌ 解包 TAR 失败"
                rm -f "$temp_output_file"
                return 1
            fi

            rm -f "$temp_output_file"
            ;;

        tar)
            echo "🧪 正在验证 TAR 文件完整性..."
            if ! tar -tf "$archive_file" >/dev/null 2>&1; then
                echo "❌ TAR 文件损坏或格式错误: $archive_file"
                return 1
            fi
            echo "✅ TAR 文件完整性验证通过"

            echo "📦 正在解包 TAR 文件..."
            if ! tar -xf "$archive_file" -C "$target_dir"; then
                echo "❌ 解包 TAR 文件失败: $archive_file"
                return 1
            fi
            ;;

        *)
            # 使用 7z 处理其他格式（如 rar, 7z, xz, iso 等）
            echo "🧪 正在使用 7z 验证归档完整性..."
            if ! 7z t "$archive_file" >/dev/null 2>&1; then
                echo "❌ 7z 归档验证失败（文件损坏或不支持）: $archive_file"
                return 1
            fi
            echo "✅ 7z 归档完整性验证通过"

            echo "📦 正在使用 7z 解压..."
            if ! 7z x -y "$archive_file" -o"$target_dir" >/dev/null; then
                echo "❌ 7z 解压失败: $archive_file"
                return 1
            fi
            ;;
    esac

    echo "✅ 解压成功: $archive_file -> $target_dir/"
    return 0
}

# === 函数：部署单个站点(解压网站根目录到指定目录,并且找到并导入对应的.sql文件(sql文件在前置步骤中解压完毕)) ===
deploy_site() {
    local username="$1"
    local archive_file="$2"

    # 获取不带扩展名的域名，处理可能包含 .sql 的情况
    # 先去掉 .zip 或 .7z ,lz4等 扩展名
    local domain_name="${archive_file%.*}"

    # 分析sql文件是属于哪一个域名站点(检查是否以 .sql 结尾，如果是则去掉 .sql 后缀,获得sql所属的域名信息)
    if [[ "$domain_name" == *.sql ]]; then
        echo "⚠️ 检测到文件名包含 .sql 后缀，将其从名称字符串中移除获取其对应(所属)的域名"
        domain_name="${domain_name%.sql}"
    fi

    log "📦 正在处理网站: $domain_name ============"

    # === 解压站点压缩包 ===
    # local extracted_domain_dir="$PACK_ROOT/$username/$domain_name"
    local site_dir_archive="$PACK_ROOT/$username/$archive_file"

    local site_domain_home="$SERVER_SITE_HOME/$username/$domain_name" #例如:/www/wwwroot/zsh/domain.com #对于用7z打包domain.com为目录名的7z包,解压后得到domain.com目录 7z x $site_dir_archive -o$site_domain_home 执行结果得到目录$site_domain_home/domain.com,为了便于引用,将其赋值给变量$site_expanded_dir,表示解压后得到的目录
    local site_expanded_dir="$site_domain_home/$domain_name"
    local target_dir="$site_domain_home/wordpress"

    echo "尝试清空目标目录[$target_dir],以便后续干净插入新内容"
    # mkdir -p "$target_dir"
    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir" # 删除网站根目录
    else
        mkdir -p "$target_dir" # 创建网站根目录
    fi
    # 解压网站文件|如果存在同名目录,则默认覆盖🎈
        if [ -d "$site_expanded_dir" ]; then
        echo "⚠️ 检测到相关目录已存在: $site_expanded_dir"

        # echo "是否覆盖现有目录? (yY/n): "
        # read -r response
        # if [[ "$response" != "y" && "$response" != "Y" ]]; then
        #     echo "用户选择不覆盖，跳过此解压步骤: $domain_name"
        # else
        #     echo "⚠️用户选择覆盖现有目录: $site_expanded_dir"
              #覆盖逻辑段存放在此
        # fi
        # 覆盖逻辑段(begin)
        echo "正在删除现有目录[$site_expanded_dir]并解压新内容 (预计得到目录:$site_expanded_dir) ..."
        rm -rf "$site_expanded_dir" # 删除现有目录

        if ! extract_archive "$site_dir_archive" "$site_domain_home"; then
            echo "❌ 解压失败，跳过部署: $domain_name"
            return 1
        fi
        # 覆盖逻辑点(end)
    else
        # 纯净解压(未检测到预先存在或残留的目录)
        if ! extract_archive "$site_dir_archive" "$site_domain_home"; then
            echo "❌ 解压失败，跳过部署: $domain_name"
            return 1
        fi

    fi
    # 如果上述操作没有出错(return 1没有执行),则执行文件归档操作
    echo "<<<归档:顺利解压网站归档文件[$archive_file]>>>"
    deployed_dir="$PACK_ROOT/$username/deployed/"
    mv "$archive_file" "$deployed_dir" -f
    # mv "$archive_file" "$DEPLOYED_DIR" -f
    echo "移动解压后的目录[$site_expanded_dir]内容到目标目录wordpress[$target_dir]🎈"
    mv "$site_expanded_dir"/* "$target_dir" -f # 移动新目录内容到目标目录

    # === 检查并导入对应的 SQL 文件 ===
    local sql_file="$PACK_ROOT/$username/$domain_name.sql"
    if [ -f "$sql_file" ]; then
        echo "🔍 找到 SQL 文件并导入数据库: $sql_file"
        # 将导入环节放到前面去执行,可以并行导入sql文件提高效率
        import_sql_file "$domain_name" "$username" "$sql_file"
        # 删除数据库文件.sql(已导入)
        echo "🗑️ 删除数据库文件: $sql_file"
        rm -f "$sql_file" -v
        

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

    # 站点根目录配置文件和插件相关检车和更改-------------------
    # 将可能阻碍登录后台wps-hide-login.bak这个插件目录改为wps-hide-login
    local plugins_dir="$target_dir/wp-content/plugins"
    local wps_hide_login_dir="$plugins_dir/wps-hide-login"
    local wps_hide_login_dir_bak="${wps_hide_login_dir}.bak"

    if [ -d "$wps_hide_login_dir_bak" ]; then
        echo "🔄 重命名 wps-hide-login.bak 为 wps-hide-login"
        # mv "$target_dir/wps-hide-login.bak" "$target_dir/wps-hide-login"
        mv "$wps_hide_login_dir_bak" "$wps_hide_login_dir"
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
    # write_rewrite_rules "$domain_name"
    set_rewrte_rules_file "$domain_name"
    # 重启nginx以便让伪静态生效
    echo "🔄 重启 nginx 以便让伪静态生效"
    nginx -s reload
    
    echo "✅ 完成站点部署: $domain_name ==============( 检查/访问: https://www.$domain_name )=============="
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
    echo "📦 正在处理网站 $domain_name 的SQL备份文件 $archive_file"

    # 解压SQL备份文件
    local user_dir="$PACK_ROOT/$username"
    sql_archive="$user_dir/$archive_file"
    # 解压sql文件包
    if ! extract_archive "$sql_archive" "$user_dir"; then
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
# 在脚本开头定义
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 ==================开始部署 WordPress 站点和数据库...================="

# 检查必要的命令
check_commands

# 进入指定目录
cd "$PACK_ROOT" || {
    echo "❌ 无法进入目录: $PACK_ROOT"
    exit 1
}

# 如果指定了用户目录，则仅处理该目录
if [ -n "$USER_DIR" ]; then
    # 指定单目录时,将单个目录包装成数组(单个元素),便于后续统一两种情况为数组处理
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

# ==========按照用户名(目录)逐个用户地处理🎈====
for user_dir in "${user_dirs[@]}"; do
    # 去掉末尾斜杠(如果有的话)，得到用户名缩写
    username="${user_dir%/}"
    # 创建用于归档已经使用过的文件的目录(移动到当前user文件的deployed目录中,例如 为用户zsh /srv/uploads/uploader/files/zsh下的deployed目录中,如果不存在,则创建此目录 )

    # 创建全局归档目录
    # deployed_dir="$DEPLOYED_DIR"

    deployed_dir="$PACK_ROOT/$username/deployed/"
    if [ ! -d "$deployed_dir" ]; then
        mkdir -p "$deployed_dir"
    fi

    echo "📂 正在处理站点人员名所属目录: $username"

    # 进入用户目录
    if ! cd "$PACK_ROOT/$username"; then
        echo "❌ 无法进入用户目录: $PACK_ROOT/$username"
        continue
    fi

    # 首先处理SQL备份文件(将所有站点的sql文件都解压,然后逐个导入到对应的数据库)
    # 数据库名字:调用process_sql_file进行处理
    sql_archives=($(ls *.sql.zip *.sql.7z *.sql.tar *.sql.lz4 *.sql.zst 2>/dev/null))
    if [ -f "${sql_archives[0]}" ]; then
        echo "🔍 找到SQL备份文件，优先处理"
        echo  "处理全部待部署网站的数据库文件🎈(使用&和wait并行处理)"
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
                echo "<<<归档:已用过的sql压缩包文件: $sql_archive >>>"
                deployed_dir="$PACK_ROOT/$username/deployed/"
                mv "$sql_archive" "$deployed_dir" -f -v
                # mv "$sql_archive" "$DEPLOYED_DIR" -f -v
            else
                ((failed_sites++))
                echo "❌ SQL备份文件处理失败: $sql_archive"
            fi
        done
    else
        echo "ℹ️ 未找到SQL压缩文件,跳过解压步骤"
    fi

    # 然后处理WordPress站点文件（过滤出非sql压缩备份文件,得到网站根目录包文件）
    site_archives=()
    for archive in *.zip *.7z *.tar *.lz4 *.zst; do
        if [[ -f "$archive" && "$archive" != *.sql.* ]]; then
            site_archives+=("$archive")
        fi
    done

    if [ ${#site_archives[@]} -eq 0 ] || [ ! -f "${site_archives[0]}" ]; then
        echo "⚠️ 在目录 $username 中没有找到有效的WordPress站点压缩包。跳过..."
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
            echo "❌ 站点部署失败: $archive_file"
        fi
    done
    # 更改deployed文件夹权限
    echo "🔒 更改deployed文件夹权限(设置目录权限和所有者)"
    chmod -R 755 "$deployed_dir"
    chown -R uploader:uploader "$deployed_dir"
    
    # 返回上级目录
    cd "$PACK_ROOT" || exit
done

log "=========部署完成！解压站点根目录数量:[$deployed_sites] , 解压SQL备份: $sql_backups_processed, 失败: $failed_sites========================"

if [ $failed_sites -gt 0 ]; then
    echo "⚠️ 有 $failed_sites 个操作失败，请检查日志。"
    exit 1
fi

exit 0
