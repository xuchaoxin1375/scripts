#!/bin/bash
# 网站部署脚本,可以批量并行部署多个站点,可以指定并发数量.
# 对于对硬盘用户,请事先决定将网站部署到哪个盘(目录)中,通过-r指定要解压到的目录
# 如果你发现某个盘已经快满了，请及时更换默认的解压目录到另一个磁盘上(尤其是定时任务中的解压配置脚本参数)
# (如果条件允许,将多个磁盘合并为一个逻辑磁盘会便于使用,省去切换磁盘的麻烦)
# 尽管脚本可以检测可用磁盘并计算磁盘使用情况然后自动切换,但默认的自动切换策略不一定是用户想要的行为
# 特别是宝塔批量建站创建的网站路径需要和实际解压路径对应
# 或许我们可以用符号链接在相关磁盘目录下创建对应的符号解决,
# 但是符号连接毕竟和普通目录有差异,可能有权限问题需要额外配置.)
#
# 解压部署以外的功能:
#
# 执行正式的解压部署前检查数据库连通性,否则停止脚本
# 统计运行时间,统计失败任务数量
# 部署指定路径下的站点(单个站点),支持指定站点压缩包名称(域名),脚本自动搜索满足该名称的站点包进行部署
# TODO:
# 1. 对于多个磁盘的服务器,检测磁盘使用情况自动处理解压位置(为每个盘事先设定一个项目目录)
# 2. 并发部署中的日志打印在终端容易错乱,改进此问题.
#
# Examples
#   /deploy.sh --user-dir zlj -P /srv/uploads/uploader/files/zlj/domain1.com.zst  -M single
#   /deploy.sh -u xcx  -M single  -n domain1.com --dry-run
#   /deploy.sh -M single  -n domain1.com --yes
#   /deploy.sh -M single  -n domain1.com
#   /deploy.sh -M single  --user-dir zsh -S .../domain1.com.zst -N domain2.com
#   /deploy.sh -M single   --user-dir uuu  -n d1.com --pack-format zip --dry-run
#   /deploy.sh  --user-dir xcx  --ssp '' -K  --dry-run #适合服务器迁移参数组合!

VERSION=20260308
shopt -s extglob globstar
shopt -s nullglob
# === 配置参数 ===
# 依赖说明:依赖于外部的伪静态规则文件RewriteRules.LF.conf,以及一些实用性程序(7z,unzip等)
# 并发方案:
# 基础方案是后台运行并等待执行结果(&+wait组合);
# 主要在process_sql_file和deploy_site这两个耗时函数的执行丢进后台
JOBS=5 # 默认并发数,根据服务器性能和实际情况调整
STRICT_MODE="false"
UPLOADER_DIR="/srv/uploads/uploader"
UPLOADER="uploader" # 默认uploader,成员通过(sftp等)上传到指定目录所用的专用用户名
PLUGINS_HOME="/www"
PROJECT_HOME="/www/wwwroot"
SITE_DIR_PACK=""
FUNCTIONS_PHP="/www/functions.php"
# ARCHIVE_FORMATS=(zip 7z tar lz4 zst)
# ARCHIVE_FORMATS_STR=$(IFS=,; echo "${ARCHIVE_FORMATS[*]}") #可以配合eval使用
# 默认的网站压缩包存放目录的共同祖先目录(下面有各个人员名的专属目录)
PACK_ROOT="$UPLOADER_DIR/files"
DB_HOST="localhost" # 数据库主机
DB_USER="root"
DB_PASSWORD="15a58524d3bd2e49"
DB_PORT="3306"
DEPLOY_MODE="auto" # 部署模式(批量解压或手动指定压缩包解压特定网站)
DEPLOYED_DIR="$UPLOADER_DIR/deployed_all"
PLUGIN_INSTALL_MODE="symlink"    # 插件安装模式: symlink(符号链接), copy(复制)
USER_DIRS=()                     #需要部署的用户目录
SITE_ROOT_NAME="wordpress"       # 站点根目录是否要包一层wordpress目录
SKIP_SCAN_PATTERN="*/deployed/*" # 对于部署指定包的模式下,功能find扫描参考跳过部分目录
# 跳过解压网站根目录及其相关操作(假设已经解压过根目录包了),如果不想跳过则设为空串""即可.
SITE_ROOT_SKIP=false
# 跳过数据库导入(假设已经导入过sql文件了),此选项几乎不使用(完整流程会有步骤修改数据库中的某些字段)除非某次解压部分目录有异常而数据库导入处理是完成的;
# 否则,如果使用此选项跳过数据库导入,则需要注意手动修改
# TODO:在wp-config.php中设定home_url和site_url
SITE_DB_SKIP=false
DRY_RUN=false
ASSUME_ANSWER=""

# wp配置文件编辑标记
STOP_EDITING_LINE='Add any custom values between this line and the "stop editing" line'
# 非原生包这部分可以跳过插入(已经有相应内容了,可以通过grep检查是否有'FORCE_SSL_ADMIN'字符串存在)
HTTPS_CONFIG_LINE="\$_SERVER['HTTPS'] = 'on'; define('FORCE_SSL_LOGIN', true); define('FORCE_SSL_ADMIN', true);"

# 关闭shellcheck路径检查多余报错,尤其是其他平台开发时,使用source命令
# shellcheck source=/dev/null
SH=/www/sh                            # linux 软连接短路径风格
SH1=/scripts/wp/woocommerce/woo_df/sh # linux风格
SH2="/c/repos""${SH1}"                # git bash风格
# 计算并确定可用的SH目录
[[ -d $SH1 ]] && SH="$SH1"
[[ -d $SH2 ]] && SH="$SH2"
shell_utils=$SH/shell_utils.sh
echo "deploy_script_version: $VERSION"
echo "verbose:正在加载shell工具函数库...[$shell_utils]"
# shellcheck disable=SC1090
source "$shell_utils"

# === 函数：显示帮助信息 ===
show_help() {
    cat <<- EOF
        用法：$0 [选项]

        描述:
          WordPress 站点批量部署脚本，支持并发部署、数据库导入、插件安装等功能。
          对于多硬盘服务器，可能需要设置 --pack-root 和 --project-home 参数。

        部署模式:
          -M, --deploy-mode MODE     部署模式：single(单站) 或 auto(批量扫描) (默认:$DEPLOY_MODE)

        路径配置:
          -p, --pack-root DIR        设置压缩包根目录 (默认:$PACK_ROOT)
          -r, --project-home DIR     设置站点项目目录 (默认:$PROJECT_HOME)
          --deployed-dir DIR         设置已部署包归档目录 (默认:$DEPLOYED_DIR)
          --site-sql-pack FILE       单站模式：设置数据库 SQL 压缩包路径
          -S, --site-dir-pack-standard FILE  单站模式：设置网站目录压缩包（标准路径）
          -P, --site-dir-pack FILE   单站模式：设置网站目录压缩包路径

        数据库配置:
          --db-user USER             设置数据库用户名 (默认:$DB_USER)
          --db-pass PASS             设置数据库密码
          --db-host HOST             设置数据库主机 (默认:$DB_HOST)
          --db-port PORT             设置数据库端口 (默认:$DB_PORT)

        站点配置:
          -u, -U, --user-dir DIR     指定用户目录（可多次使用以处理多个用户）
          -n, --domain-name NAME     设置网站域名
          -N, --update-domain-name NAME  更新已上传包网站的域名
          -W, --site-root-name NAME  设置站点根目录名称 (默认:$SITE_ROOT_NAME)
          --uploader USER            设置 uploader 用户名 (默认:$UPLOADER)

        插件配置:
          -m, --plugin-install-mode MODE  插件安装模式：symlink(符号链接) 或 copy(复制) (默认:$PLUGIN_INSTALL_MODE)

        跳过选项:
          -R, --site-root-skip       跳过网站根目录解压
          -D, --site-db-skip         跳过数据库导入
          --ssp, --skip-scan-pattern PATTERN  扫描站点包时跳过指定目录模式 (默认:$SKIP_SCAN_PATTERN)

        压缩配置:
          --pack-format FORMAT       扫描站点包时限定压缩格式（如：zst,zip,tar 等）
          -K, --keep-pack, --no-move-pack  部署后保留压缩包（不移动归档到 deployed 目录）

        并发与执行:
          -j, --jobs NUM             设置并发数 (默认:$JOBS)
          --dry-run                  干运行模式（仅模拟，不实际执行）
          --yes, --force             自动确认所有交互提示
          --no                       自动拒绝所有交互提示
          -E, --strict-mode          严格模式（启用 set -euo pipefail）

        其他:
          -h, --help                 显示此帮助信息
          -V, --version              显示脚本版本

        示例:
          # 批量部署（自动扫描）
          $0 --user-dir zlj --deploy-mode auto

          # 单站部署（指定压缩包）
          $0 -M single -P /srv/uploads/uploader/files/zlj/domain1.com.zst

          # 单站部署（指定域名自动搜索）
          $0 -M single -u xcx -n domain1.com --dry-run

          # 服务器迁移（保留压缩包）
          $0 --user-dir xcx --ssp '' -K --dry-run

          # 仅处理数据库或仅处理网站根目录
          $0 -M single -n domain1.com --site-db-skip    # 仅解压网站
          $0 -M single -n domain1.com --site-root-skip  # 仅导入数据库

        版本：$VERSION
EOF
    exit 0
}

######################################
# Description:
#   命令行参数解析
# Globals:
#   None
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
            --db-host)
                DB_HOST="$2"
                shift
                ;;
            --db-port)
                DB_PORT="$2"
                shift
                ;;
            -u | -U | --user-dir)
                # 指定用户目录,则将工作范围缩小到该目录下
                # USER_DIR="$2"
                # shift
                # ;;

                # 添加用户目录,可以使用多个此选项以添加多个用户目录
                USER_DIRS+=("$2")

                [[ ${#USER_DIRS} -gt 0 ]] && USER_DIR="${USER_DIRS[0]}"
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
            -m | --plugin-install-mode)
                PLUGIN_INSTALL_MODE="$2"
                shift
                ;;
            -r | --project-home)
                PROJECT_HOME="$2"
                shift
                ;;
            -M | --deploy-mode)
                DEPLOY_MODE="$2"
                shift
                ;;
            -S | --site-dir-pack-standard)
                SITE_DIR_PACK_STD="$2"
                shift
                ;;
            -P | --site-dir-pack)
                SITE_DIR_PACK="$2"
                shift
                ;;
            -n | --domain-name)
                DOMAIN_NAME="$2"
                shift
                ;;
            -N | --update-domain-name)
                # 当某个已上传包网站的域名需要更改时,使用此参数
                # 配合单包部署选项来使用.
                UPDATE_DOMAIN_NAME="$2"
                shift
                ;;
            -W | --site-root-name)
                # 站点根目录是否要包一层目录名(通常是wordpress)
                SITE_ROOT_NAME="$2"
                shift
                ;;
            --uploader)
                UPLOADER="$2"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            # --force)
            #     FORCE=true
            #     ;;
            --yes | --force)
                ASSUME_ANSWER="y"
                shift
                ;;
            --no)
                ASSUME_ANSWER="n"
                shift
                ;;
            --ssp | --skip-scan-pattern)
                # 扫描站点包时跳过某些目录(例如指定deployed)
                SKIP_SCAN_PATTERN="$2"
                shift
                ;;
            --pack-format)
                # 自动扫描站点包时,要求文件后缀匹配指定格式,默认为空,不要求特定的压缩格式
                PACK_FORMAT="$2"
                shift
                ;;
            -K | --keep-pack | --no-move-pack)
                # 部署解压网站包后不做移动归档操作
                KEEP_PACK=true
                ;;
            -R | --site-root-only)
                # 仅处理网站根目录(而不处理数据库)
                SITE_ROOT_SKIP="true"
                ;;
            -D | --site-db-only)
                # 仅处理数据库的部署(而不处理站点根目录)
                SITE_DB_SKIP="true"
                ;;
            -E | --strict-mode)
                # 严格模式,使用set -euo pipefail
                STRICT_MODE="true"
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
[[ $STRICT_MODE == "true" ]] && set -euo pipefail
# 定义日志文件路径
# LOG_FILE="/srv/uploads/uploader/files/deploy_wp_$($USER_DIR)_$(date +%Y%m%d_%H%M%S).log"
# LOG_DIR=$(dirname "$LOG_FILE") #获取日志文件字符串的目录,然后创建这个目录(如果不存在的话)
# mkdir -p "$LOG_DIR"
# 重定向标准输出和标准错误到日志文件
# exec > >(tee -a "$LOG_FILE") 2>&1

# 定义日志函数
log() {
    local message="$*"
    local dt
    dt="$(date '+%Y-%m-%d--%H:%M:%S')"
    message="[$dt] $message"
    echo "$message"
}
export -f log
# 提示用户当前使用的 PACK_ROOT
log "使用 PACK_ROOT: $PACK_ROOT"
log "检查默认备份文件夹(不存在则创建)"
if [ ! -d "$DEPLOYED_DIR" ]; then
    mkdir -p "$DEPLOYED_DIR"
fi

export -f confirm
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
        log "Error❌ 错误: 以下命令未找到: ${missing_commands[*]}"
        log "请安装缺少的命令后再运行此脚本。"
        exit 1
    fi
}
export -f check_commands
# === 函数：修改wp-config.php ===
update_wp_config() {
    local wp_config_path="$1"

    if [ ! -f "$wp_config_path" ]; then
        log "Error❌ 错误：找不到 wp-config.php 文件：$wp_config_path"
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
export -f update_wp_config
######################################
# === 函数：导入 SQL 文件到对应数据库 ===
# Description:
#
# Globals:
#   DB_HOST
#   DB_USER
#   DB_PASSWORD
#   DB_PORT
# Arguments:
#   $1 db_name 将要创建的完整数据库的名字(名结构通常为数据库所属人员名"前缀_网站域名")
#   $2 sql_file 被导入的 SQL 文件路径(文件名字通常和domain相关,但不是必须的)
#
# Outputs:
#   None
# Returns:
#   0 on success, non-zero on error
# Example:
#  import_sql_file "$domain_name" "$user_name" "$sql_file"
######################################
import_sql_file() {
    local db_name="$1"
    local sql_file="$2"

    log "📦 正在处理数据库: $db_name"

    # 导入前现检查是否有对应数据库存在,如果有先移除旧数据库!
    if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" -P "$DB_PORT" -e "DROP DATABASE IF EXISTS \`${db_name}\`;"; then
        log "🗑️ 旧数据库已删除。"
    else
        log "Error❌ 删除旧数据库失败，请检查数据库连接和权限。"
        return 1
    fi
    # 创建数据库(空数据库)
    if ! echo "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;" | mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" -P "$DB_PORT"; then
        log "Error❌ 创建数据库失败，请检查数据库连接和权限。"
        return 1
    fi

    # 导入 SQL 文件
    log "🚚 正在导入 SQL 文件: $sql_file 到数据库 $db_name"
    if mysql -h "$DB_HOST" -u "$DB_USER" -P "$DB_PORT" -p"$DB_PASSWORD" "$db_name" < "$sql_file"; then
        log "✅ 数据库 $db_name 成功导入。"
        return 0
    else
        log "Error❌ 导入失败，请检查 SQL 文件或数据库权限。"
        return 1
    fi
}
export -f import_sql_file

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
            log "Error❌ 复制伪静态规则文件失败: 源文件=$rewrite_template, 目标=$rewrite_target"
            return 1
        fi
    else
        log "Error❌ 未找到伪静态规则模板文件: $rewrite_template"
        return 1
    fi

}
export -f set_rewrte_rules_file

# ====检测文件是否为原生tar格式文件====
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
        log "Error❌ 压缩文件不存在: $archive_file"
        return 1
    fi

    if [ -z "$site_root" ]; then
        log "Error❌ 目标目录未指定"
        return 1
    fi

    # 确保目标目录存在,否则创建此目录
    mkdir -p "$site_root"

    log "🔍 正在处理压缩文件: $archive_file -> $site_root/"

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
            log "Error❌ 压缩文件损坏或格式不支持: $archive_file"
            return 1
        fi
        log "✅ 压缩文件完整性验证通过"
    }

    # 根据扩展名处理不同格式
    case "$ext" in

        zst | zstd)
            # 这里是特化任务,根据团队规范,默认上传的包实际格式是tar.zst,即便后缀只有.zst而不是.tar.zst,其解压zst层后得到的文件是tar文件(二进制文件)
            # 在这个分支中,首先解压zst层,然后将解压后的内部tar文件再调用tar解压,得到文件(夹)
            log "🧪 正在验证 ZSTD 文件完整性..."
            if ! zstd -t "$archive_file" > /dev/null 2>&1; then
                log "Error❌ ZSTD 文件损坏或格式错误: $archive_file"
                return 1
            fi
            log "✅ ZSTD 文件完整性验证通过"
            # 解压结果保存成一个临时文件(tar格式的二进制文件)
            temp_output_file=$(mktemp -u)
            log "📦 正在解压 ZSTD 文件(得到临时tar文件)..."
            if ! zstd -T0 -d "$archive_file" -o "$temp_output_file"; then
                log "Error❌ 解压 ZSTD 文件失败"
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
                log "Error❌ 内部 TAR 文件损坏或者文件不是tar文件"
                rm -f "$temp_output_file"
                return 1
            fi

            log "📦 正在解包 TAR 数据..."
            if ! tar -xf "$temp_output_file" -C "$site_root"; then
                log "Error❌ 解包 TAR 失败"
                rm -f "$temp_output_file"
                return 1
            fi
            # tar包临时文件已经抽取完毕,移除
            rm -f "$temp_output_file"
            ;;

        tar)
            log "🧪 正在验证 TAR 文件完整性..."
            if ! tar -tf "$archive_file" > /dev/null 2>&1; then
                log "Error❌ TAR 文件损坏或格式错误: $archive_file"
                return 1
            fi
            log "✅ TAR 文件完整性验证通过"

            log "📦 正在解包 TAR 文件..."
            if ! tar -xf "$archive_file" -C "$site_root"; then
                log "Error❌ 解包 TAR 文件失败: $archive_file"
                return 1
            fi
            ;;
        zip)
            if ! check_integrity unzip "$archive_file"; then
                return 1
            fi
            log "📦 正在解压 ZIP 文件..."
            if ! unzip -q "$archive_file" -d "$site_root"; then
                log "Error❌ 解压 ZIP 文件失败: $archive_file"
                return 1
            fi
            ;;

        gz | tgz)
            if ! check_integrity tar -tzf "$archive_file"; then
                return 1
            fi
            log "📦 正在解压 GZ/TGZ 文件..."
            if ! tar -xzf "$archive_file" -C "$site_root"; then
                log "Error❌ 解压 GZ/TGZ 文件失败: $archive_file"
                return 1
            fi
            ;;

        bz2 | tbz2)
            if ! check_integrity tar -tjf "$archive_file"; then
                return 1
            fi
            log "📦 正在解压 BZ2/TBZ2 文件..."
            if ! tar -xjf "$archive_file" -C "$site_root"; then
                log "Error❌ 解压 BZ2/TBZ2 文件失败: $archive_file"
                return 1
            fi
            ;;

        lz4)
            # 先测试是否能解压到 /dev/null
            log "🧪 正在验证 LZ4 文件完整性..."
            if ! lz4 -t "$archive_file" > /dev/null 2>&1; then
                log "Error❌ LZ4 文件损坏或格式错误: $archive_file"
                return 1
            fi
            log "✅ LZ4 文件完整性验证通过"

            temp_output_file=$(mktemp -u)
            log "📦 正在解压 LZ4 文件..."
            if ! lz4 -d "$archive_file" "$temp_output_file"; then
                log "Error❌ 解压 LZ4 文件失败"
                rm -f "$temp_output_file"
                return 1
            fi

            # 检查解压出的 tar 是否完整
            log "🧪 正在验证解包后的 TAR 文件完整性..."
            if ! tar -tf "$temp_output_file" > /dev/null 2>&1; then
                log "Error❌ 内部 TAR 文件损坏"
                rm -f "$temp_output_file"
                return 1
            fi

            log "📦 正在解包 TAR 数据..."
            if ! tar -xf "$temp_output_file" -C "$site_root"; then
                log "Error❌ 解包 TAR 失败"
                rm -f "$temp_output_file"
                return 1
            fi

            rm -f "$temp_output_file"
            ;;

        *)
            # 使用 7z 处理其他格式（如 rar, 7z, xz, iso 等）
            log "🧪 正在使用 7z 验证归档完整性..."
            if ! 7z t "$archive_file" > /dev/null 2>&1; then
                log "Error❌ 7z 归档验证失败（文件损坏或不支持）: $archive_file"
                return 1
            fi
            log "✅ 7z 归档完整性验证通过"

            log "📦 正在使用 7z 解压..."
            if ! 7z x -y "$archive_file" -o"$site_root" > /dev/null; then
                log "Error❌ 7z 解压失败: $archive_file"
                return 1
            fi
            ;;
    esac

    log "✅ 解压成功: $archive_file -> $site_root/"
    return 0
}
export -f extract_archive
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
        log "Error❌ 站点插件目录不存在: $site_plugins_home"
        return 1
    }
    for plugin in "$site_plugins_home"/*; do
        # 将插件标记文件或空目录视为插件要安装(覆盖)
        if [ -f "$plugin" ] || is_empty_dir "$plugin"; then
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
                    log "Error❌ 未知的插件安装模式: $PLUGIN_INSTALL_MODE"
                    return 1
                fi
            else
                log "Warning 插件源目录不存在: $plugin_name"
            fi
        fi
    done
}
export -f install_wp_plugin
# 安装functions.php文件
# Args:
#   $1:网站的主题目录
install_functions_php() {
    local site_themes_home="$1"
    local functions_php="$2"
    log "检查主题目录,functions.php路径并安装插件..."
    if [[ -f $functions_php ]]; then

        for dir in "$site_themes_home"/*/; do
            log "process theme dir [$dir]"
            if [ -d "$dir" ]; then
                \cp -vf "$functions_php" "$dir"
            fi
        done
    else
        log "ERROR:function.php文件[$functions_php] 不存在"
    fi
}
export -f install_functions_php
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
#   PACK_ROOT 标准的用户网站包存放目录
#   PROJECT_HOME 网站项目根目录(特别是不同磁盘上的网站项目要注意)
# Arguments:
#   $1 - user_name 部署到指定人员名目录下
#   $2 - domain_name 被部署的网站压缩文件(站点根目录压缩包)
#   $3 - site_dir_archive 站点根目录包
#   $4 - site_sql_archive 站点sql包
#
# Outputs:
# Returns:
#   0 on success, non-zero on error
# Example:
#
######################################
deploy_site() {

    local user_name="$1"
    local domain_name="$2"
    local site_dir_archive="$3"
    local site_sql_archive="$4"

    local deployed_dir="$PACK_ROOT/$user_name/deployed/"
    local sql_file="$PACK_ROOT/$user_name/$domain_name.sql"
    # 计算可能需要更正的最终的网站域名和数据库名(如果需要网站更名,不要直接覆盖domain_name,而是另起一个新名,因为后续原名要被多词使用!)
    local final_domain_name="${UPDATE_DOMAIN_NAME:-${domain_name}}"
    local db_name="${user_name}_${final_domain_name}"

    log "📦 正在处理网站: $domain_name ============"

    # 检查关于domain_name网站的压缩包组
    # local extracted_domain_dir="$PACK_ROOT/$user_name/$domain_name"
    # local site_archives="$PACK_ROOT/$user_name/$domain_name.*"

    if ! [[ -f "$site_sql_archive" ]]; then
        log "Warning⚠️ 站点[$domain_name]的sql包文件[$site_sql_archive]不可用,确保包上传完毕并可用,等待下一轮再尝试"
        return 1
    fi
    if ! [[ -f "$site_dir_archive" ]]; then
        log "Warning⚠️ 站点[$domain_name]根目录压缩包[$site_dir_archive]不可用,确保包上传完毕并可用,等待下一轮再尝试"
        return 1
    fi
    # 测试模式下跳过实际解压和导入等操作
    if [[ $DRY_RUN == "true" ]]; then
        log "[DRY_RUN] End for $domain_name "
        return 0
    fi
    # START-SQL-IMPORT 检查并导入对应的 SQL 文件 ===
    log "检查是否已经有.sql文件(解压过的)"
    if [[ -f $sql_file ]]; then
        log "已找到原sql文件[$sql_file],可能之前解压过"
    else
        log "开始解压站点[$domain_name]的sql文件"
        # 解压数据库压缩包,归档已解压文件,并可选地统计解压情况
        if process_sql_file "$user_name" "$site_sql_archive"; then
            # ((sql_backups_processed++))
            log "✅ 站点[$domain_name]的sql文件解压成功"
        else
            # ((failed_sites++))
            log "Error❌ SQL备份文件处理失败: $site_sql_archive"
            log "跳过此站点的处理"
            return 1
        fi
    fi
    # 导入已经解压的数据库(import sql)
    if [ -f "$sql_file" ]; then
        log "🔍 找到 SQL 文件并导入数据库: $sql_file"
        # 将导入环节放到前面去执行,可以并行导入sql文件提高效率
        if [[ $SITE_DB_SKIP != 'true' ]]; then
            # if [[ -n $UPDATE_DOMAIN_NAME ]]; then
            #     db_domain_name=$UPDATE_DOMAIN_NAME
            # else
            #     db_domain_name=$domain_name
            # fi

            import_sql_file "$db_name" "$sql_file"
        else
            log "跳过 $sql_file 的导入处理"
            # 返回
            return 1
        fi
        # 删除数据库文件.sql(已导入)
        log "🗑️ 删除数据库文件: $sql_file"
        rm -f "$sql_file" -v

        # === 配置数据库===

        mysql -h "$DB_HOST" -u "$DB_USER" -P "$DB_PORT" -p"$DB_PASSWORD" "$db_name" -e "
    UPDATE wp_options
    SET option_value = 'https://www.${final_domain_name}'
    WHERE option_name IN ('home', 'siteurl');
    "
    else
        log "Error❌ 未找到 SQL 文件: $sql_file"
        return 1
    fi
    # END-SQL-IMPORT

    # START-DIR-EXPAND
    log "开始处理网站[$final_domain_name]根目录..."

    # 网站根目录所在目录, 例如:/www/wwwroot/zsh/domain.com
    local site_domain_home="$PROJECT_HOME/$user_name/$final_domain_name"
    # local final_site_domain_home="$PROJECT_HOME/$user_name/$final_domain_name"
    #对于用7z打包domain.com为目录名的7z包,解压后得到domain.com目录 7z x $site_dir_archive -o$site_domain_home 执行结果得到目录$site_domain_home/domain.com,为了便于引用,将其赋值给变量$site_expanded_dir_raw,表示解压后得到的目录
    # 定义网站最终的根目录
    local site_root="$site_domain_home"
    #例如:/www/wwwroot/zsh/domain.com/
    if [[ -n $SITE_ROOT_NAME ]]; then
        site_root="$site_domain_home/$SITE_ROOT_NAME"
        # 例如:/www/wwwroot/zsh/domain.com/wordpress
    fi

    # 根据事先设计的目录压缩结构,配套的网站压缩包将会解压得到的目录有两种可能(事先规划):
    # 人员初次导出的原生包:(默认情况,根据需要可以进一步移动处理)
    local site_expanded_dir_raw="$site_domain_home/$domain_name"
    # 例如: /www/wwwroot/zsh/(final)domain.com/domain.com

    # 从服务器导出备份包:通常是形如: PROJECT_HOME/user_name/domain_name/SITE_ROOT_NAME
    # 例如:/www/wwwroot/zsh/domain.com/wordpress
    local site_expanded_dir_wp="$site_root" # 通常final和导出包没有关系,因为导出时域名一般是确定可用的,不需要更新.

    # 根目录下的其他目录(解压后要进行到额外处理)会用到的目录

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

        log "正在强力删除现有目录[$site_expanded_dir_raw]并解压新内容 (预计得到目录:$site_expanded_dir_raw) ..."
        # rm -rf "$site_expanded_dir_raw" # 删除现有目录
        rm1 "$site_expanded_dir_raw" # 删除现有目录
    fi

    # 纯净解压(预先存在或残留的目录此时已经清理完毕.)
    if [[ $SITE_ROOT_SKIP == 'true' ]]; then
        log "跳过站点$site_dir_archive 包的解压"
        # 进入此分支后,就不会进入下面的解压分支,不要这里return 0;
    elif ! extract_archive "$site_dir_archive" "$site_domain_home"; then
        log "Error❌ 解压失败，本轮跳过此站部署: $domain_name"
        return 1
    else
        log "✅ 解压成功: $site_dir_archive "
        # 判断包的类型:原生包还是导出包
        if [[ -d $site_expanded_dir_raw ]]; then
            log "原生包-> $site_expanded_dir_raw"
            log "移动解压后的目录[$site_expanded_dir_raw]内容到目标目录wordpress[$site_root]🎈"
            if [[ -d $site_root ]]; then
                log "目标目录[$site_root]已存在,直接移动解压内容到该目录"
            fi
            mv "$site_expanded_dir_raw"/* "$site_root" -f
        elif [[ -d $site_expanded_dir_wp ]]; then
            if is_empty_dir "$site_expanded_dir_wp"; then
                log "Error:站点根目录[$site_expanded_dir_wp]为空,未将文件正确移动到目标目录,跳过处理,请检查此站点"
                return 1
            else
                log "导出包-> $site_expanded_dir_wp"
                log "根目录已经符合预期,不需要移动根目录"
            fi
        fi

        log "检查需要安装的插件..."
        install_wp_plugin "$plugins_dir" "$PLUGINS_HOME"
        install_functions_php "$themes_dir" "$FUNCTIONS_PHP" || exit 1
        if [[ -f "$user_ini" ]]; then
            log "🔍 检测到 .user.ini 文件,设置open_basedir 放行公共插件目录"
            bash /www/sh/update_user_ini.sh -p "$user_ini" -t "$PLUGINS_HOME"
        else
            log "ℹ️ 未找到 .user.ini 文件，跳过权限设置(等待宝塔创建.user.ini)"
        fi
    fi

    # 站点根目录配置文件和插件相关处理和更改-------------------
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

    log "===修改element 容器背景广告图链接"
    sed -i "s/http:\/\/$domain_name/https:\/\/www.$final_domain_name/g" "$site_root"/wp-content/uploads/elementor/css/post-10.css
    # END-DIR-EXPAND

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

    # ===如果上述操作没有出错(return 1没有执行),则按需执行文件归档操作
    if [[ $KEEP_PACK == "true" ]]; then
        log "站点包不归档到${deployed_dir}中,留在原地."
    else
        log "<<<归档:已用过的sql压缩包文件: $site_sql_archive >>>"
        mv "$site_sql_archive" "$deployed_dir" -f -v
        # mv "$site_sql_archive" "$DEPLOYED_DIR" -f -v
        log "<<<归档:顺利解压网站压缩文件[$site_dir_archive]>>>"
        mv "$site_dir_archive" "$deployed_dir" -fv
        # mv "$archive_file" "$DEPLOYED_DIR" -f
    fi

    log "✅ 完成站点部署: $domain_name ( 检查/访问: https://www.$final_domain_name )=============="
    return 0
}

# === 函数：查找并处理SQL备份文件🎈 ===
# 此函数会分析传入的人员名和sql包文件名(针对一个站),构造对应的数据库名,并检查对应的文件是否存在
# 如果存在,则解压sql文件压缩包,如果不存在,则报错
# Arguments:
#   $1: 用户名
#   $2: SQL备份文件名
process_sql_file() {
    local user_name="$1"
    local archive_file="$2"

    # 获取域名（去掉.sql.zip或.sql.7z后缀）
    local domain_name="${archive_file%.sql*}"
    log "📦 正在处理网站 $domain_name 的SQL备份文件 $archive_file"

    # 解压SQL备份文件
    local user_dir="$PACK_ROOT/$user_name"
    # sql_archive="$user_dir/$archive_file"
    sql_archive="$archive_file"
    # 解压sql文件包
    if ! extract_archive "$sql_archive" "$user_dir"; then
        log "Error❌ 解压SQL备份文件失败: $archive_file"
        return 1
    fi

    # 查找解压后的SQL文件
    local sql_files
    mapfile -t -d '' sql_files < <(find "$user_dir" -name "*.sql" -type f -print0)

    if [ ${#sql_files[@]} -eq 0 ]; then
        log "Error❌ 在解压后的目录中未找到SQL文件"
        return 1
    fi
}
export -f process_sql_file

main() {

    log "🚀 ====开始部署 WordPress 站点和数据库..."

    # 检查必要的命令
    check_commands

    # 进入指定的网站备份包存放目录(切换工作目录便于处理)
    cd "$PACK_ROOT" || {
        log "Error❌ 无法进入目录: $PACK_ROOT"
        exit 1
    }
    log "📦 当前工作目录: $PACK_ROOT"

    # 统计处理的站点数
    # deployed_sites=0
    # failed_sites=0
    # sql_backups_processed=0

    # ==========按照待处理人员名(目录)数组,逐个用户地处理🎈====
    # 使用两个并行数组保存结果(分被记录压缩包所属的人员目录和网站名)
    local -a user_dir_names=()
    local -a site_names=()
    local -a user_dirs

    # if [[ $DEPLOY_MODE == "single" ]]; then
    if [[ $DEPLOY_MODE != "auto" ]]; then
        log "处理指定的站点[$SITE_DIR_PACK_STD]"
        local user_dir
        local site_name
        # 在需要用户确认解析结果的时候将need_check设置为1
        local need_check=0
        if [[ -n $SITE_DIR_PACK_STD ]]; then
            local candidate_path=./"$USER_DIR/$SITE_DIR_PACK_STD"
            if [[ -f $candidate_path ]]; then
                SITE_DIR_PACK_STD="${candidate_path/\/.\//\/}"
            fi
            if ! [[ -f $SITE_DIR_PACK_STD ]]; then
                log "Error:检查是否使用绝对路径,或确保路径存在[$(pwd)]"
                return 1
            fi
            log "找到待处理站点(尝试按标准方式解析所属人员和域名): $SITE_DIR_PACK_STD"
            # user_dir+=($SITE_DIR_PACK)
        elif [ -f "$SITE_DIR_PACK" ]; then
            echo "指定站点压缩包路径不规范的路径,优先尝试读取相关选项参数"
            [[ -n "$DOMAIN_NAME" ]] && site_name="$DOMAIN_NAME"
            [[ -n "$USER_DIR" ]] && user_dir="$USER_DIR"
        elif [[ -n "$DOMAIN_NAME" ]]; then
            # 仅提供网站包的名字(域名),而不提供包的路径的情况下尝试扫描确定路径
            site_name="$DOMAIN_NAME"
            # 搜索PACK_ROOT(及其子目录)下的站点名为site_name的压缩包
            local site_packs=()
            # 安全且兼容性强的find扫描文件保存到数组中的方法
            while IFS= read -r -d '' file; do
                site_packs+=("$file")
            done < <(find "$PACK_ROOT/$USER_DIR" -path "$SKIP_SCAN_PATTERN" -prune -o -type f -iname "*${site_name}*" -print0)

            # 检查候选包路径数组长度
            local pack_num=${#site_packs[@]}
            if [[ $pack_num -eq 0 ]]; then
                log "未找到任何文件,请检查文件名是否正确"
                exit 1
            elif [[ $pack_num -gt 1 ]]; then
                declare -p site_packs
                log "共找到 $pack_num 个相关文件,使用第一个文件作为代表(用于提取domain_name),如果不合适,请在命令行(-P或-S)参数中提供路径!"

            fi
            SITE_DIR_PACK_STD="${site_packs[0]}"
            declare -p SITE_DIR_PACK_STD
            echo ""
            declare -p site_packs

            need_check=1

        else
            log "请指定待处理站点的路径或名字(域名)"
            exit 1
        fi
        # 下面的分支下,是脚本推测站点的所属人员和网站名,建议请求用户输入确认(输入y/n)
        local archive_path="${SITE_DIR_PACK_STD:-$SITE_DIR_PACK}"
        if [[ -z "$user_dir" ]]; then
            # SITE_DIR_PACK_STD="/srv/uploads/uploaders/files/john/domain1.com.sql.zst"
            local pack_dir
            pack_dir="$(dirname "$archive_path")" # .../files/john
            # 提取站点所属人员名(目录名),移除路径前缀
            user_dir="${pack_dir##*/}" # john
            need_check=1
        fi
        if [[ -z "$site_name" ]]; then
            # 提取站点名(域名)
            site_name="$(basename "$archive_path")"
            site_name="${site_name%.*}"
            site_name="${site_name%.sql}" # domain1.com
            need_check=1
        fi
        if [[ $need_check -eq 1 ]]; then
            if [[ -n "$user_dir" && -n "$site_name" ]]; then
                echo "tips: [$user_dir] [$site_name]"
                if confirm "❓ 是否继续处理该站点文件?" "y" "$ASSUME_ANSWER"; then
                    echo "继续处理[$site_name]..."
                else
                    echo "跳过处理[$site_name]..."
                    return 1
                fi
                # read -rp "❓ 是否继续处理该站点文件? (y/n, 默认y): " confirm
                # # 将输入转换为小写（可选，Bash 4+ 支持 ${confirm,,}）
                # local confirm=${confirm:-y} # 如果直接回车，默认为 y

                # case "${confirm,,}" in
                #     # 兼容yes,y 大小写都兼容
                #     yes | y)
                #         echo "🚀 正在继续执行..."
                #         # 在这里放置你的逻辑
                #         ;;
                #     no | n)
                #         echo "🛑 操作已取消。"
                #         exit 1
                #         ;;
                #     *)
                #         echo "Error❌ 输入无效，脚本退出。"
                #         exit 1
                #         ;;
                # esac
            else
                echo "自动提取站点所属人员和网站名失败,请提供站点所属人员名(目录名)"
            fi
        fi

        user_dir_names+=("$user_dir")
        site_names+=("$site_name")
    else
        local user_dirs
        # START-DP(确定要部署网站的人员)
        # 如果指定了用户目录，则仅处理该目录,否则遍历所有子目录
        # if [ -n "$USER_DIR" ]; then
        #    user_dirs=("$USER_DIR")
        # 指定单目录时,将单个目录包装成数组(单个元素),便于后续统一两种情况为数组处理
        if [[ "${#USER_DIRS}" -gt 0 ]]; then
            user_dirs=("${USER_DIRS[@]}")
            log "🔍 仅处理指定用户目录: ${USER_DIRS[*]}"
        else
            log " 将自动扫描目录"
            user_dirs=(*/) #直接使用通配匹配指定目录下的目录名
        fi
        # 否则遍历当前工作目录的所有子目录(计算用户目录名)

        # END-DP
        if [ ${#user_dirs[@]} -eq 0 ]; then
            log "Error❌ 在 $PACK_ROOT 中没有找到任何用户目录"
            exit 1
        fi
        log "🔍 找到 ${#user_dirs[@]} 个用户目录"
        for user_dir in "${user_dirs[@]}"; do

            # 去掉末尾斜杠(如果有的话)，得到人员名缩写
            user_name="${user_dir%/}"
            # 创建用于归档已经使用过的文件的目录(移动到当前user文件的deployed目录中,例如 为用户zsh /srv/uploads/uploader/files/zsh下的deployed目录中,如果不存在,则创建此目录 )
            log "📂 正在处理站点人员名所属目录: $user_name"

            # 进入用户目录
            if ! cd "$PACK_ROOT/$user_name"; then
                log "Error❌ 无法进入用户目录: $PACK_ROOT/$user_name"
                continue
            fi

            # ===编写网站部署逻辑,并发可控===
            # 首先处理SQL备份文件(将所有站点的sql文件都解压,然后逐个导入到对应的数据库)
            # 数据库名字:调用process_sql_file进行处理
            # 收集网站压缩包目录下的压缩包文件列表,基于此过滤并计算出待部署到网站名及对应的压缩包组(可以仅收集sql压缩包,特点鲜明,和网站备份文件强相关)

            # local sql_archives=()
            # sql_archives=(*.sql{zip,7z,tar,lz4,zst})
            # ARCHIVE_FORMATS=(zip 7z tar lz4 zst)
            # for format in "${ARCHIVE_FORMATS[@]}"; do
            #     sql_archives+=(*.sql."$format")
            #     # echo '*.sql.'"$format"
            # done
            # declare -p sql_archives
            # shopt -s extglob
            # local sql_files=( @(*.sql|*.sql.*) )  # 或 files=( *.sql?(.?*) )

            # for site_sql_archive in "${sql_archives[@]}"; do
            # 获取域名（去掉.sql.zip或.sql.7z后缀）
            #     domain_name="${site_sql_archive%.sql.*}"
            #     user_dir_names+=("$user_name")
            #     site_names+=("$domain_name")
            # done

            # 简单单层通配扫描:
            # local sql_files=(*.sql*) # 这足够区分domain.xxx.sql开头的文件了
            # 如果有搜索深度的需要,可以考虑用find
            local sql_files=()
            while IFS= read -r -d '' sql_file; do
                sql_files+=("$sql_file")
            done < <(find . -path "$SKIP_SCAN_PATTERN" -prune -o -type f -iname "*sql*" -printf "%f\0")
            # debug
            declare -p sql_files
            # return 0
            local -A unique_map=() # 初始化为空

            for f in "${sql_files[@]}"; do
                # 提取前缀：删除从 ".sql" 开始到结尾的所有内容
                # 例如：backup.sql.gz -> backup
                #      data.sql      -> data
                local prefix="${f%%.sql*}"

                # 如果该前缀还没存入 map，则存入（保留第一个遇到的完整文件名）
                if [[ -z "${unique_map[$prefix]}" ]]; then
                    unique_map[$prefix]="$f"
                fi
            done

            # 将去重后的结果重新写回普通数组(取key名字即可)
            local domain_names=("${!unique_map[@]}") # 网站名(域名)数组

            # 验证结果
            printf '%s\n' "${domain_names[@]}"

            # 分层处理(少嵌套逻辑,让代码容易阅读和调试)

            # 初步计算待处理的网站名(域名),没找到要给网站包(以sql包为代表即可),就成组加入两个任务数组中

            for domain_name in "${domain_names[@]}"; do
                site_names+=("$domain_name")
                user_dir_names+=("$user_name")
            done
            declare -p site_names

            # 返回上级目录,准备下一个人员目录的处理
            cd "$PACK_ROOT" || exit
        done
    fi

    # START-C:核心调度部分(按合适的方式部署任务(网站域名)列表中的网站文件组)
    # for domain_name in "${site_names[@]}"; do
    for i in "${!site_names[@]}"; do
        local domain_name="${site_names[$i]}"
        local user_name="${user_dir_names[$i]}"
        # 计算合法后缀的网站压缩包相关文件(通常只有2个包),为了支持多种后缀(压缩格式),所以代码会比固定压缩格式的情况要多一些.
        # 计算当前站点($domain_name)的候选(可能)合法格式的压缩包
        local candidate_sql_archives=()
        local candidate_site_archives=()

        # START-C-P(计算最终的包文件路径)
        candidate_sql_archives+=("$PACK_ROOT/$user_name"/**/"$domain_name".sql*"$PACK_FORMAT")
        # mapfile -d '' -t candidate_site_archives <  <(find "$PACK_ROOT/$user_name" -maxdepth 1 -type f ! -name "*.sql*" -and -name "*$domain_name*" -printf "%p\0")
        # for pack in "$PACK_ROOT/$user_name"/**/!(*.sql*); do
        for pack in "$PACK_ROOT/$user_name"/**/"$domain_name"*; do
            # echo "$pack"
            # if [[ $pack == */"$domain_name"*"$PACK_FORMAT" ]]; then
            if [[ $pack != *.sql* && $pack == *"$PACK_FORMAT" ]]; then
                candidate_site_archives+=("$pack")
                break
            fi
        done
        # for format in "${ARCHIVE_FORMATS[@]}"; do
        #     local candidate_pack="$PACK_ROOT/$user_name/$domain_name.$format"
        #     if [[ -f $candidate_pack ]]; then
        #         candidate_site_archives+=("$candidate_pack")
        #         break
        #     fi
        # done
        declare -p candidate_sql_archives candidate_site_archives
        # 计算网站根目录包路径
        for site_archive in "${candidate_site_archives[@]}"; do
            if [ -f "$site_archive" ]; then
                log "📦 检测到网站根目录压缩包: $site_archive"
                site_dir_archive="$site_archive"
                break
            fi
        done
        # 计算网站sql包路径
        for sql_archive in "${candidate_sql_archives[@]}"; do
            # log "debug:test sql file:[[$sql_archive]]"
            if [ -f "$sql_archive" ]; then
                log "🗄️ 检测到数据库文件: $sql_archive"
                site_sql_archive=$sql_archive

                # 注意break的位置!
                break
            fi
        done
        # END-C-P

        # 串行部署(或者把JOBS改成1)
        # deploy_site "$user_name" "$domain_name" ...

        # START-C-W(并发方案)
        # & + wait -n 循环并发部署
        # 利用循环检测任务数，控制并发数!
        job_cnt=$(jobs -rp | wc -l)
        while (("$job_cnt" >= JOBS)); do
            # 等待一个任务完成(简洁起见,这里不添加失败数统计)
            log "后台任务数:$job_cnt"
            log "等待一个任务完成..."
            wait -n
            job_cnt=$(jobs -rp | wc -l)
        done
        # debug:
        log "['verbose:' '$user_name', '$domain_name', '$site_dir_archive', '$site_sql_archive']"
        # continue
        ! [[ -f "$site_dir_archive" && -f "$site_sql_archive" ]] && {
            log "[$domain_name]缺少必要的站点包文件(若指定了包格式,请检查是否指定格式的包不存在,或取消包格式指定)"
            return 1
        }
        deploy_site "$user_name" "$domain_name" "$site_dir_archive" "$site_sql_archive" &
        # END-C-W
    done
    log "等待剩余后台任务结束"
    wait
    log "所有后台任务结束"
    # END-C:结束所有后台任务

    # 收尾(集中处理权限)
    local deployed_dir_used_users=()
    if [[ ${#USER_DIRS} -gt 0 ]]; then
        deployed_dir_used_users=("${USER_DIRS[@]}")
    else
        deployed_dir_used_users=("$PACK_ROOT"/*/)
    fi
    declare -p deployed_dir_used_users
    for user_dir in "${deployed_dir_used_users[@]}"; do
        # 创建全局归档目录
        # deployed_dir="$DEPLOYED_DIR"
        # 为当前用户创建归档目录(deployed)
        user_dir="${user_dir%/}"

        deployed_dir="$PACK_ROOT/$user_dir/deployed/"
        if [ ! -d "$deployed_dir" ]; then
            mkdir -p "$deployed_dir"
        fi
        # 更改计算得到的deployed文件夹权限
        log "🔒 更改${user_dir}的${deployed_dir}文件夹权限(设置目录权限和所有者)"
        chmod -R 755 "$deployed_dir"
        chown -R "$UPLOADER:$UPLOADER" "$deployed_dir"
    done
    # 部署批次结束后再统一重启,减少重载次数提高效率
    log "🚀 ==================重载Nginx 配置...================="
    [[ $DRY_RUN == "false" ]] && nginx -s reload

    log "部署结束！"
    # 解压站点根目录数量:[$deployed_sites] , 解压SQL备份: $sql_backups_processed, 失败: $failed_sites========================"

    # if [ "$failed_sites" -gt 0 ]; then
    #     log "⚠️ 有 $failed_sites 个操作失败，请检查日志。"
    #     exit 1
    # fi

    # exit 0
    return 0
}
# 检查数据库连通性(如果无法连接,直接停止脚本.)
check_mysql -H "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -v || exit 1

start_time=$(date +%s)
main
end_time=$(date +%s)

seconds=$((end_time - start_time))
minutes=$((seconds / 60))
log "总耗时: ${seconds} 秒,合${minutes}分钟"
