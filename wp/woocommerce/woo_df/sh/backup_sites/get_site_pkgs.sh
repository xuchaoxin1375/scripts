#!/bin/bash
# 脚本功能和设计
# 脚本支持多个选项,满足备份指定网站(可通过网站白名单文件来指定备份哪些网站),也可以指定工作目录及其下面的需要参与备份的目录名(可能是网站所属人员的名字代号或拼写)来备份某个人员的站点
# 无论是哪种方式,基本思路是指定的任务通过计算直接或间接(比如find扫描指定目录下的所有网站)得到需要执行打包备份的网站根目录路径列表,然后遍历这些路径调用一个网站打包函数完整站点备份;并且可选的,允许同时对多个网站进行备份.
# 如果本机磁盘空间紧张,可以使用 -I 考虑即时传输备份方案(打包后立刻传输到备份服务器并删除本机包,但暂时要求配置ssh免密);
# 并且注意,使用即时传输的情况下,如果中断后重新运行,将会因为备份目录中缺少相应的包而再次出发备份,需要额外的机制来来辅助判断上一轮是否备份过:(多种方案,简单期间,这里使用标记文件方案)
## 日志方案:(日志中包含字段:网站名(域名),备份模式(db/dir/full),上一次备份日期时间,是否成功备份),日志使用csv的方式记录,但是注意并发需要锁机制(例如flock),否则写操作可能会导致文件错乱,影响阅读和解析.
## 标记文件方案:比较简单,并发操作创建文件不用担心错乱问题.
#
#
# ===========
# 注意事项:
# export 让并发子进程能够访问相关变量🎈
#
# 0.执行此脚本时建议暂停服务器网站的服务(比如暂停nginx服务,防止备份过程中文件发生变化而导致tar过程出现错误或不一致);
# 建议白天执行备份任务,降低应为服务器暂停而导致的丢单损失
# 1.此脚本主要用于处理历史遗留的备份问题,专门为没有压缩包而只有站点各目录和对应的活跃数据库情况下进行备份
# (备份文件的格式(结构)保持我们惯例的站点压缩包结构,比如domain.com.zst,以及对应网站的domain.com.sql.zst)
# 2.关于数据库文件备份和导出,建议配置免密登录,不仅更安全,代码也更加简单(免密登录mysql配置方案有许多,自行查阅资料配置)
# 3.完整性检查:备份完后可以运行一段批量检查文件完整性检查的代码,防止某些文件压缩过程中出错(尤其是被意外终止脚本的情况)
# 4.线程数不要开太高,虽然服务器核心很多,但是tar和zstd算法容易打满磁盘IO,备份速度的主要瓶颈不在cpu而在于磁盘上!
VERSION=20260528.1208

SRC_ROOT="/www/wwwroot"
DEST_ROOT="/srv/uploads/uploader/files" # 备份文件存储目录
SITE_ROOT=""                            # 单个站点备份
# OWNER="uploader"
DRY_RUN=0
FORCE=0
PARALLEL_JOBS=4 #不要过多

# 并发子进程内部需要访问的变量
LOG_FILE="" # 备份进度日志文件路径(可选,建议加锁机制)
USER=""     # 仅备份指定人员的站点.
MINDEPTH=2
MAXDEPTH=3
VALID_USERS=""
WHITELIST_SITE=""
export STATUS_TAG_DIR="$DEST_ROOT/status_tags" # 即时备份模式在,备份并传输一个包后,就创建对应的名字的空文件.
export MODE="full"                             # db,dir,full.分被表示:仅备份数据库,仅备份文件,还是两者都备份(默认)
export IMMEDIATELY=false                       # 网站文件导出后立即传输到备份服务器并删除本机包
export HOSTNAME
HOSTNAME=$(hostname)
# mysql链接参数
declare -a MYSQL_ARGS
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
MYSQL_USER="root"
MYSQL_PASS=""

# 传输相关参数(需要导出)
REMOTE_USER="root"
REMOTE_HOST=""
REMOTE_PORT="22"
REMOTE_ADMINER_NAME=""
# 远程服务器上的存储路径(基础路径,请务必自行指定跟具体的目录防止混乱.)
# 参考路径结构: /www/wwwroot/$adminer/$HOSTNAME/$userx/deployed/
REMOTE_PATH_BASE="/www/wwwroot/$REMOTE_ADMINER_NAME/$HOSTNAME"

export USER DEST_ROOT FORCE DRY_RUN VALID_USERS MINDEPTH MAXDEPTH
export REMOTE_HOST REMOTE_USER REMOTE_PORT REMOTE_ADMINER_NAME REMOTE_PATH_BASE
export MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PASS

# export 让并发子进程能够访问相关变量🎈
# export MODE IMMEDIATELY REMOTE_HOST REMOTE_USER REMOTE_PORT REMOTE_PATH

show_help() {
    cat << EOF

站点批量备份脚本.

version: $VERSION
用法：$0 [选项] 
-s, --src <src_root>     项目目录:网站根目录所在总目录 (默认：$SRC_ROOT)
-d, --dest <dest_root>   备份存储基础目录 (默认：$DEST_ROOT)
-m, --mode <mode>        备份模式，dir表示仅备份文件，db表示仅备份数据库，full表示同时备份文件和数据库 (默认：full)
-u, --user <username>    仅备份指定人员的站点(人员专属目录名，通常是人名拼音缩写),从而仅备份指定用户的网站目录下的站点

-U, --valid-users <file>    白名单文件,指定需要处理的人员目录名列表
-W, --whitelist-site <file>   白名单文件，指定需要处理的网站 (域名) 列表
-L, --mindepth <n>       find 扫描的最小深度 (默认：$MINDEPTH)
-M, --maxdepth <n>       find 扫描的最大深度 (默认：$MAXDEPTH)

--site,--domain <site_name or domain> 备份指定的单个网站(指定域名(网站名),而不是网站根目录)

-I, --immediately        网站文件导出后立即传输到备份服务器并删除本机包(本机磁盘紧张的情况下使用)
    --remote-user <user> 远程服务器SSH登录用户名 (默认：$REMOTE_USER)
    --remote-host <host> 远程服务器SSH登录主机地址 (必填)
    --remote-port <port> 远程服务器SSH登录端口 (默认：$REMOTE_PORT)
    --remote-path <path> 远程服务器上的存储路径基础目录 (默认：$REMOTE_PATH_BASE)

-D, --dry-run            预览模式，仅显示将执行的操作
    --force              强制覆盖已存在的备份
-j, --jobs <n>           并行任务数 (默认：$PARALLEL_JOBS)
-h, --help               显示本帮助信息
--tag-dir                即时备份模式在,备份并传输一个包后,就创建对应的名字的空文件,
                         实现简单的进度恢复,此参数指定标记文件保存目录.
--log                    备份进度日志文件路径 (默认：$LOG_FILE),如果需要忽略备份历史,请删除此文件.

    --mysql-host <host>  MySQL 主机地址
    --mysql-port <port>  MySQL 端口
    --mysql-user <user>  MySQL 用户名
    --mysql-pass <pass>  MySQL 密码

examples:
	# 指定MySQL主机和端口
	./backup_sites_from_source_dir.sh --mysql-host 192.168.1.100 --mysql-port 3306

	# 指定MySQL用户名和密码
	./backup_sites_from_source_dir.sh --mysql-user myuser --mysql-pass mypassword
	bash ./backup_sites_from_source_dir.sh  --jobs 2 --valid-users  valid_users.ini -u xcx --mysql-user myusername --mysql-pass password123
	# 组合使用所有参数
	./backup_sites_from_source_dir.sh -d /srv/uploads/uploader/files --mysql-host localhost --mysql-port 3306 --mysql-user root --mysql-pass password123

	# 备份单个站点(指定网站名字,自动搜索网站根路径)
	bash ./backup_sites_from_source_dir.sh --site goodpayway.shop  --jobs 1

    # 扫描白名单用户的所有网站,并备份数据库(不备份目录文件),最大扫描深度限制为2
    bash get_site_pkgs.sh -U valid_users.ini -m db -j 4  -M 2 -D # 预览操作.
    # 直接指定网站白名单(域名列表)
    bash get_site_pkgs.sh  -m db -j 4 -M 2 -D -W w.txt # W选项和U选项不要同时使用.

EOF
}

# 参数解析
parse_args() {

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s | --src)
                SRC_ROOT="$2"
                shift 2
                ;;
            -d | --dest)
                DEST_ROOT="$2"
                shift 2
                ;;
            -u | --user)
                USER="$2"
                shift 2
                ;;
            -U | --valid-users)
                VALID_USERS="$2"
                shift 2
                ;;
            -m | --mode)
                MODE="$2"
                shift 2
                ;;
            --domain | --site)
                SITE_ROOT="$2"
                shift 2
                ;;
            -W | --whitelist-site)
                WHITELIST_SITE="$2"
                shift 2
                ;;
            -L | --mindepth)
                MINDEPTH="$2"
                shift 2
                ;;
            -M | --maxdepth)
                MAXDEPTH="$2"
                shift 2
                ;;
            -I | --immediately)
                IMMEDIATELY=true
                shift
                ;;

            -D | --dry-run)
                DRY_RUN=1
                shift
                ;;

            -j | --jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -h | --help)
                show_help
                shift
                exit 0
                ;;
            --remote-user)
                REMOTE_USER="$2"
                shift 2
                ;;
            --remote-host)
                REMOTE_HOST="$2"
                shift 2
                ;;
            --remote-port)
                REMOTE_PORT="$2"
                shift 2
                ;;
            --remote-path)
                REMOTE_PATH_BASE="$2"
                shift 2
                ;;
            --mysql-host)
                MYSQL_HOST="$2"
                shift 2
                ;;
            --mysql-port)
                MYSQL_PORT="$2"
                shift 2
                ;;
            --mysql-user)
                MYSQL_USER="$2"
                shift 2
                ;;
            --mysql-pass)
                MYSQL_PASS="$2"
                shift 2
                ;;
            --force)
                FORCE=1
                shift
                ;;
            --tag-dir)
                STATUS_TAG_DIR="$2"
                shift 2
                ;;
            --log)
                LOG_FILE="$2"
                shift 2
                ;;
            *)
                echo "未知参数: $1"
                show_help
                shift
                exit 1
                ;;
        esac
    done
}
parse_args "$@"
mkdir -pv "$STATUS_TAG_DIR" # 确保标记文件目录存在

# 移除字符串边缘空白字符
trim() {
    local var="$*"
    # 移除开头空格
    var="${var#"${var%%[![:space:]]*}"}"
    # 移除结尾空格
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}
# 测试SSH连接是否成功的函数
ssh_test() {
    local host="$1"
    local user="${2:-root}"
    local port="${3:-22}"

    ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -p "$port" \
        "${user}@${host}" exit

    local status=$?

    if [ $status -eq 0 ]; then
        echo "✅ SSH connection success: ${user}@${host}:${port}"
    else
        echo "❌ SSH connection failed: ${user}@${host}:${port}"
    fi

    return $status
}

#Function: isCommandInstalled()
#
#Brief: Checks if a command or a package is installed, by trying to run it
#
#Argument 1($1): command to test if it's installed
#Usage example :
#  if ! isCommandInstalled  ls ; then echo "You can install it with \"sudo dnf install tree\""; fi
isCommandInstalled() {
    if [ $# -ne 1 ]; then
        echo "Invalid number of parameters provided "
    fi
    if ! command -v "$1" &> /dev/null; then
        echo "$1 is not installed"
        return 1
    fi
}

# 定义日志函数
log() {
    local message="$1"
    local dt
    dt="$(date '+%Y-%m-%d--%H:%M:%S')"
    message="[$dt] $message"
    echo "$message"
}
######################################
# 从路径中提取用户名的函数
#
# Arguments:
#   $1 - 路径
# Returns:
#   0 on success, non-zero on error
######################################
extract_username() {
    local path="$1"

    # 使用 IFS 按 '/' 分割路径
    IFS='/' read -ra parts <<< "$path"

    # 检查是否有至少 4 个部分（因为开头是 /，所以数组第一个元素为空）
    # 例如：/www/wwwroot/xcx/ → ['', 'www', 'wwwroot', 'xcx', '']
    # 我们需要第 4 个元素（索引为 3）作为“第三部分”
    if [[ ${#parts[@]} -lt 4 ]]; then
        log "警报: 路径${path} 中不存在第三部分" >&2
        echo ""
        return 1
    fi

    # 提取第三部分（索引为 3）
    third_part="${parts[3]}"

    # 检查第三部分是否为空
    if [[ -z "$third_part" ]]; then
        log "警报: 第三部分为空" >&2
        echo ""
        return 1
    fi

    echo "$third_part"
}

# 定义检查用户是否在白名单中的函数
is_user_in_whitelist() {
    local username="$1"

    # 如果没有指定白名单文件，则所有用户都在白名单中
    if [[ -z "$VALID_USERS" ]]; then
        return 0
    fi

    # 检查用户是否在白名单中
    if grep -q "^${username}$" "$VALID_USERS"; then
        return 0
    else
        return 1
    fi
}

######################################
# Description:
# 检查MySQL连接是否可用
# Globals:
#   MYSQL_ARGS - mysql连接参数
# Arguments:
#
# Outputs:
# Returns:
#   0 on success, non-zero on error
# Example:
#
######################################
check_mysql_connection() {
    log "正在检查MySQL连接..."
    isCommandInstalled mysql || exit 1
    # 构建mysql连接参数(使用数组比较合适)

    [[ -n "$MYSQL_HOST" ]] && MYSQL_ARGS+=("-h" "$MYSQL_HOST")
    [[ -n "$MYSQL_PORT" ]] && MYSQL_ARGS+=("-P" "$MYSQL_PORT")
    [[ -n "$MYSQL_USER" ]] && MYSQL_ARGS+=("-u" "$MYSQL_USER")
    # 密码的拼接比较特殊,需要与选项合并到一起
    [[ -n "$MYSQL_PASS" ]] && MYSQL_ARGS+=("-p$MYSQL_PASS")

    echo "mysql 最终的链接参数: ${MYSQL_ARGS[*]}"
    # 在dry-run模式下，仅显示将要执行的检查命令
    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ -n "${MYSQL_ARGS[*]}" ]]; then
            log "[预览] 将测试MySQL连接: mysqlshow $MYSQL_ARGS"
        else
            log "[预览] 将测试MySQL连接: mysqlshow (使用系统默认配置)"
        fi
        return 0
    fi

    # 实际测试MySQL连接
    log "正在检查MySQL连接..."
    # mysqlshow 命令用于检查MySQL连接,但是系统不一定自带,建议使用mysql命令直接测试.
    # 如果MYSQL_ARGS是字符串直接拼接的,并且使用了引号包裹变量,将会导致mysqlshow 接受的参数只有一个而不会正确解析,去掉引号虽然可以解析,但是存在空格分割错误的风险
    # mysqlshow "$MYSQL_ARGS"

    # 使用数组的方式传递参数比较好.
    # declare -p MYSQL_ARGS
    # mysqlshow "${MYSQL_ARGS[@]}"

    # if mysqlshow "$MYSQL_ARGS" >/dev/null 2>&1; then
    if mysql "${MYSQL_ARGS[@]}" -e "SELECT 1" &> /dev/null; then
        log "MySQL连接成功"
        return 0
    else
        log "错误: 无法连接到MySQL服务器，请检查连接参数和服务器状态"
        return 1
    fi
}
# 检查白名单文件是否存在
check_listfile() {
    listfile="$1"
    if [[ -n "$listfile" && ! -f "$listfile" ]]; then
        log "错误: 列表文件(白名单) $listfile 不存在"
        exit 1
    fi
}

######################################
# Description:
# 	备份单个站点的函数
# 函数会分析传入的站点根目录路径,按照约定的规则提取网站域名,构造合适的网站压缩包路径(包名和域名相关)
# 例如计算得出的域名为domain.com,那么会压缩得到domain.com.zst以及domain.com.sql.zst
# 注意,为了解压时流程的一致性等因素,这里的包在压缩成.zst文件之前都会先压缩成.tar文件,即便是当文件的.sql
# 不仅如此,作为过渡包到tar文件名中不会保留.tar,但是不要因为没有.tar就忽略了这个中间格式,在解压时不要漏掉用tar解压.
# tar包在zstd打包结束后,会自动移除,以节约空间.
# Globals:
# 	USER
# 	DEST_ROOT
# Arguments:
# 	$1:WP_DIR: 站点根目录
#
# Outputs:
#   Writes output description to stdout
# Returns:
#   0 on success, non-zero on error
# Example:
#
######################################
backup_one_site() {
    WP_DIR="$1"
    USERNAME=""
    # 根据是否指定了用户过滤器来确定用户名提取方式
    if [[ -n "$USER" ]]; then
        USERNAME="$USER"
    else
        USERNAME=$(extract_username "$WP_DIR")
    fi

    # 计算当前网站的域名.
    # 计算并构造压缩包要保存的完整路径.
    _get_pack_names() {
        DOMAIN=$(basename "$(dirname "$WP_DIR")")

        DEST_DIR="${DEST_ROOT}/${USERNAME}/deployed"
        ZST_NAME="${DOMAIN}.zst"

        DEST_DIR_PATH="${DEST_DIR}/${ZST_NAME}"
        DEST_DB_PATH="${DEST_DIR}/${DOMAIN}.sql.zst"
    }
    _get_pack_names

    TAR_NAME="${DOMAIN}"
    TAR_PATH="/tmp/${TAR_NAME}"
    # 判断指定站点的(db或dir)包已经备份过了
    judger() {
        local pkg_path="$1"
        local pkg_name
        pkg_name="$(basename "$pkg_path")"
        local tag_file="$STATUS_TAG_DIR/${pkg_name}"
        log "正在检查备份包 $pkg_path 是否已存在，或标记文件 $tag_file 是否存在..."

        # if [[ -f $STATUS_TAG_DIR/"$pkg_name" ]]; then
        #     log "[跳过[$MODE]] 发现标记文件 $STATUS_TAG_DIR/$pkg_name,之前已成功备份过 $pkg_name,将跳过站点 $DOMAIN 的备份。"
        #     return 2 # 返回2表示跳过
        # fi
        if [[ -f "$pkg_path" ]] || [[ -f "$tag_file" ]]; then
            if [[ $FORCE -eq 0 ]]; then
                log "[跳过[$MODE]] 发现已存在压缩包 $pkg_path,[user: $USERNAME],跳过站点 $DOMAIN 的备份。"
                return 2 # 返回2表示跳过
            else
                log " 将强制覆盖已存在的压缩包 $pkg_path"
            fi
        else
            log "[任务[$MODE]] 将为站点 $DOMAIN 创建备份归档任务,请耐心等待"

        fi

        return 0 #表示需要执行备份
    }
    # 检查压缩包是否已存在(如果存在且不强制覆盖,则跳过此站)
    if [[ $MODE == dir ]]; then
        judger "$DEST_DIR_PATH"
        [[ $? -eq 2 ]] && return 2
    elif [[ $MODE == db ]]; then
        judger "$DEST_DB_PATH"
        [[ $? -eq 2 ]] && return 2
    elif [[ $MODE == full ]]; then
        judger "$DEST_DIR_PATH"
        [[ $? -eq 2 ]] && return 2
        judger "$DEST_DB_PATH"
        [[ $? -eq 2 ]] && return 2
    fi

    mkdir -p "$DEST_DIR" -v # 确保存储包的目录存在
    # 远程备份用到的字段
    authority="$REMOTE_USER"@"$REMOTE_HOST"
    remote_full_path="$authority":"$REMOTE_PATH_BASE/$USERNAME/deployed" # /www/wwwroot/xcx/serverx/username/deployed
    # 传输指定文件到远程服务器并删除本地文件,并记录到日志的函数(使用rsync)
    rsync_pack() {
        pkg="$1"
        pkg_name="$(basename "$pkg")"
        log "使用 rsync 将 $pkg 传输到远程服务器 ${authority}:${remote_full_path} 并删除本地文件"
        # -q (quiet) 抑制了所有文件的条目输出不会向上滚动刷屏
        if rsync -aq --size-only --remove-source-files "$pkg" "$remote_full_path"; then
            # rc=failed
            log "✅ rsync 传输 $pkg 到远程服务器成功,已删除本地文件 $pkg"
            # 创建标记文件(如果启用了标记文件机制)
            tag_file="$STATUS_TAG_DIR/${pkg_name}"
            if touch "$tag_file"; then
                log "已创建标记文件 $tag_file 来标识备份和传输完成"
            fi
        else
            # rc=success
            log "错误: rsync 传输 $pkg 到远程服务器失败!"

        fi
        # 记录情况到进度日志(使用前要初始化表头,并且每行注意字段对齐.)
        # echo "${DOMAIN},$MODE,$(date '+%Y-%m-%d %H:%M:%S'),$rc" >> "$LOG_FILE"

    }

    log "正在备份站点 $WP_DIR，用户 $USERNAME，域名 $DOMAIN; [$MODE]..."
    if [[ $MODE == dir || $MODE == full ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "将打包 $WP_DIR 到 $TAR_PATH"
            log "将使用 zstd --rm 压缩 $TAR_PATH 到 $TAR_PATH.zst"
            log "将移动 $TAR_PATH.zst 到 $DEST_DIR_PATH"
            log "如目标目录不存在将自动创建 $DEST_DIR"
            return 0
        fi
        log "📦 正在打包 WordPress 文件,排除缓存和日志:打包 $WP_DIR 到 $TAR_PATH..."
        # tar -cf "$TAR_PATH" -C "$WP_DIR" .
        # tar -cf "$TAR_PATH" -C "$WP_DIR/.." wordpress #完整备份
        # 跳过不重要的内容的轻量备份(这里打包的文件夹指定为wordpress,
        # 其他用户如果使用此套代码要注意原本的目录结构,可能需要自行调整tar打包的命令行)
        tar --exclude='wp-content/cache' \
            --exclude='wp-content/uploads/cache' \
            --exclude='wp-content/uploads/wpo' \
            --exclude='wp-content/uploads/wp-rocket' \
            --exclude='wp-content/uploads/backupbuddy_temp' \
            --exclude='wp-content/uploads/*-cache' \
            --exclude='wp-content/updraft' \
            --exclude='wp-content/ai1wm-backups' \
            --exclude='wp-content/backups' \
            --exclude='wp-content/tmp' \
            --exclude='wp-content/upgrade' \
            --exclude='wp-content/*.log' \
            --exclude='wp-content/*.sql' \
            --exclude='wp-content/*.zip' \
            --exclude='wp-content/*.tar.gz' \
            --exclude='wp-content/debug.log' \
            -cf "$TAR_PATH" -C "$WP_DIR"/.. wordpress

        # 调用zstd命令,使用--rm来删除被压缩成zst包之前的文件tar文件;注意,使用-v疑似会降低速度
        log "使用 zstd --rm 压缩 $TAR_PATH 到 $TAR_PATH.zst"
        zstd -T0 --rm "$TAR_PATH" -f -v
        mv "$TAR_PATH.zst" "$DEST_DIR_PATH"

        # 设置文件权限和所有者
        chmod 755 "$DEST_DIR_PATH"
        # 可选,设置的话可以让普通用户看到/管理包目录的文件包
        # chown "$OWNER":"$OWNER" "$DEST_DIR_PATH"
        log "站点文件已备份到: $DEST_DIR_PATH"
        if [[ $IMMEDIATELY == true ]]; then

            rsync_pack "$DEST_DIR_PATH"
        fi
        # START-DB:数据库备份，依次尝试三种数据库名
    elif [[ $MODE == db || $MODE == full ]]; then
        log "将尝试导出数据库: ${USERNAME}_${DOMAIN}, ${DOMAIN}, www.${DOMAIN}，并用 zstd 压缩"
        if [[ $DRY_RUN -eq 1 ]]; then
            return 0
        fi
        DB_CANDIDATES=("${USERNAME}_${DOMAIN}" "${DOMAIN}" "www.${DOMAIN}" "${DOMAIN%.*}")
        DB_DUMPED=0
        for DBNAME in "${DB_CANDIDATES[@]}"; do
            # 导出sql的备份文件名统一使用"${DOMAIN}.zst"
            SQL_DUMP_PATH="${DEST_DIR}/${DOMAIN}.sql"
            ZST_SQL_DUMP_PATH="${SQL_DUMP_PATH}.zst"

            # 构建mysql连接参数

            # if mysqlshow "${MYSQL_ARGS[@]}" "$DBNAME" >/dev/null 2>&1; then
            if mysql "${MYSQL_ARGS[@]}" -e "USE \`$DBNAME\`;" > /dev/null 2>&1; then
                if mysqldump "${MYSQL_ARGS[@]}" "$DBNAME" > "$SQL_DUMP_PATH"; then
                    # 将sql文件用tar包装一下,文件名保持原来的.sql而不加tar后缀(这看起来有点多余,但是为了和其他配套脚本兼容,这里做一下额外处理)
                    ## 先临时创建一个.tar文件,然后重命名(去掉.tar)
                    log "正在将 $SQL_DUMP_PATH 打包为tar文件,然后更名回 $SQL_DUMP_PATH"
                    sql_tar="${SQL_DUMP_PATH}.tar"
                    tar -cvf "$sql_tar" -C "$(dirname "$SQL_DUMP_PATH")" "$(basename "$SQL_DUMP_PATH")"
                    rm "$SQL_DUMP_PATH" -v -f
                    mv "$sql_tar" "$SQL_DUMP_PATH" -v -f
                    log "检查当前sql归档文件类型:$SQL_DUMP_PATH ($(file -b "$SQL_DUMP_PATH"))"

                    log "将$SQL_DUMP_PATH 压缩为 $ZST_SQL_DUMP_PATH"
                    zstd -T0 --rm "$SQL_DUMP_PATH" -f #默认添加后缀.zst
                    log "设置SQL文件权限(755)"
                    chmod 755 "$ZST_SQL_DUMP_PATH"
                    # chown uploader:uploader "$ZST_SQL_DUMP_PATH"
                    # log "数据库 $DBNAME 已导出并压缩到: $ZST_SQL_DUMP_PATH"
                    DB_DUMPED=1
                    break
                fi
            fi
        done
        # 提示本站数据库备份情况:
        if [[ $DB_DUMPED -eq 0 ]]; then
            log "[警告] 未找到可用数据库，站点 $DOMAIN (用户 $USERNAME) 未进行数据库备份。"
        fi
        if [[ $IMMEDIATELY == true ]]; then

            rsync_pack "$ZST_SQL_DUMP_PATH"
            # log "[即时传输]使用 rsync 将 $ZST_SQL_DUMP_PATH 传输到远程服务器 ${authority}:$REMOTE_PATH_BASE，并删除本地文件"

            # rsync -aq --info=progress2 --size-only --remove-source-files "$ZST_SQL_DUMP_PATH" "$remote_full_path"
        fi
    fi
    # END-DB
    return 0

}
# 环境检查
if [[ $IMMEDIATELY == true ]]; then
    log "正在测试SSH连接到远程服务器 $REMOTE_HOST..."
    if ! ssh_test "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PORT"; then
        log "错误: 无法连接到远程服务器 $REMOTE_HOST，请检查SSH连接参数和服务器状态"
        exit 1
    fi
    # rsync 联通性测试

fi
# 获取所有 wordpress 目录，并打印已匹配到的目录

# 在 dry-run 模式下显示将要执行的查找命令
# if [[ $DRY_RUN -eq 1 ]]; then
# fi
valid_users=()

if [[ -n "$WHITELIST_SITE" ]]; then
    log "使用域名白名单文件: $WHITELIST_SITE"
fi

log "脚本版本: $VERSION"
log "备份模式: $MODE"
log "即时传输: $IMMEDIATELY"
log "将使用并行任务数: $PARALLEL_JOBS"
check_listfile "$VALID_USERS"
check_listfile "$WHITELIST_SITE"
log "正在扫描匹配的 wordpress 目录..."

# 确定查找路径和域名提取方式,打印提示信息,并计算FIND_BASE
FIND_BASE="$SRC_ROOT" # FIND_BASE 默认值(例如/www/wwwroot/),将作为find命令的起始路径

if [[ -n "$WHITELIST_SITE" ]]; then
    log "仅扫描文件[$WHITELIST_SITE]中指定站点..."
fi

# 在开始备份前检查MySQL连接
if ! check_mysql_connection; then
    exit 1
fi

# 扫描并备份所有匹配的站点(数量)
SITE_COUNT=0
SITE_EXISTING=0
SITE_TO_BACKUP=0
# 计算是否仅备份指定网站(将命令行指定的单个网站(根目录作为代表)保存到临时白名单文件中)
## 将处理逻辑统一到白名单指定的方式一样处理
if [[ $SITE_ROOT ]]; then
    log "指定备份站点:SITE_ROOT=$SITE_ROOT"

    WHITELIST_SITE_TMP=$(mktemp ~/whitelist_site.XXXXXX)
    WHITELIST_SITE=$WHITELIST_SITE_TMP
    log "WHITELIST_SITE=$WHITELIST_SITE"
    # 单个网站写入此文件中
    echo "$SITE_ROOT" > "$WHITELIST_SITE"
fi

# 并行处理模式
# 初始化一个空数组,记录网站目录
declare -a site_dirs
# 创建一个文件用于观察中间处理结果的文件(便于调试)
site_dirs_listfile="/www/site_dirs_list.txt"
# 清空原文件防止旧数据干扰
echo -n "" > "$site_dirs_listfile"

# 计算待备份网站根目录(初步计算,尚未计算列表中已有备份包的过滤处理.)
# log "将使用用户名白名单文件搜索指定网站根目录: $VALID_USERS"

# 计算site_dirs
# 单用户情况也可以考虑统一到用户白名单模式.
if [[ -n "$USER" ]]; then

    VALID_USERS_TEMP=$(mktemp ~/valid_user.XXXXXX)
    # VALID_USERS_TEMP 记得用完清理掉
    VALID_USERS="$VALID_USERS_TEMP"
    echo "$USER" > "$VALID_USERS"
fi

if [[ -n "$VALID_USERS" ]]; then
    log "使用人员名白名单文件: $VALID_USERS"

    # mapfile 安全地读取白名单文件到数组中,每行一个元素,并且会自动去掉行末的换行符,
    # CRLF的文件配合tr预处理也可以正确读取.
    # mapfile -t valid_users < "$VALID_USERS"
    mapfile -t valid_users < <(tr -d '\r' < "$VALID_USERS")
    log "有效用户列表:${valid_users[*]}"
    # fi
    for user in "${valid_users[@]}"; do
        FIND_BASE="$SRC_ROOT/$user" # 例如/www/wwwroot/xcx/
        log "扫描指定人员目录级别[$FIND_BASE]..."

        log "将在 $FIND_BASE 下查找深度为 $MINDEPTH-$MAXDEPTH 的 wordpress 目录"
        # /www/wwwroot/xcx/domain.com/wordpress
        # site_dirs=$(find "$FIND_BASE" -mindepth "$MINDEPTH" -maxdepth "$MAXDEPTH" -type d -name wordpress)

        # 使用 mapfile 安全读取
        # 方案1:
        # -d '' 指定以 NULL 字符作为行分隔符
        # < <(...) 使用进程替换将 find 的输出喂给 mapfile
        find "$FIND_BASE" -mindepth "$MINDEPTH" -maxdepth "$MAXDEPTH" -type d -name wordpress >> "$site_dirs_listfile"
        log "debug:$(wc -l $site_dirs_listfile) lines on [$site_dirs_listfile]"
        # nl $site_dirs_listfile
        mapfile -t site_dirs_user < "$site_dirs_listfile"
        # 将site_dirs_user中的路径添加到site_dirs数组中
        site_dirs+=("${site_dirs_user[@]}")

        # 方案2: 直接使用mapfile 的-O "${#site_dirs[@]}" 使得追加到数组末尾，而不是覆盖数组
        # mapfile -d $'\0' -t -O "${#site_dirs[@]}" site_dirs < <(find "$FIND_BASE" -mindepth "$MINDEPTH" -maxdepth "$MAXDEPTH" -type d -name wordpress)
    done
    # debug:检查site_dirs数组的内容
    # declare -p site_dirs

elif [[ -n "$WHITELIST_SITE" ]]; then
    log "将对指定的网站做备份: $WHITELIST_SITE" #域名列表
    mapfile -t sites < "$WHITELIST_SITE"

    # 遍历处理所有网站域名,计算网站的路径.
    for site in "${sites[@]}"; do
        # 跳过第一个非空白字符是#或;的行(视为注释)
        if [[ $site =~ ^[[:space:]]*(#|;).* ]]; then
            log "Jump line [$site]"
            continue
        fi
        # 移除行边缘空格
        # site=$(echo "$site" | xargs)
        site=$(trim "$site")
        log "site:$site"

        # 利用通配符计算路径,添加到site_dirs.
        shopt -s nullglob
        dir=$(echo "$SRC_ROOT"/*/"$site"/wordpress)
        # 检查路径是否存在,如果存在则添加到site_dirs数组中,并写入到文件中;如果不存在则记录日志警告.(这个可以通过shopt -s nullglob简化.)
        if [[ -d "$dir" ]]; then
            # [[ -d "$dir" ]] && site_dirs+=("$dir")
            # find $base_dir -maxdepth 2 -type d -name $site
            site_dirs+=("$dir")
            # 写入到文件中使用printf并以\0 分隔路径字符串比echo要安全(但是用户直接打开文件没有一行一个路径) printf "%s\0"
            # 使用mapfile 的 -d '' 选项可以轻松读取 \0 分隔的元素,while read -r -d ''也支持
            # 而在已知路径不会包含\n的情况下,可以用\n
            printf "%s\n" "$dir" >> $site_dirs_listfile
        else
            log "[警告] 站点 $site [$dir] 不存在"
        fi
    done
else
    log "不使用任何白名单"
fi
# 保存到临时文件做调试用途.
log "已匹配到的站点列表:"
nl "$site_dirs_listfile"

# 统计最终将要处理的站点数(计算要跳过的站点)
declare -a site_need_backup_dirs
# 有两种方案遍历需要判断或处理的网站.
## 直接遍历site_dirs数组
## 使用while read 和输入重定向 < 读取路径文件$site_dirs_list_file文件中的行.

# 以方案2为例:
while IFS= read -r WP_DIR || [[ -n "$WP_DIR" ]]; do
    # while中的[[ -n "$WP_DIR" ]]是为了防止windows系统创建的文件CRLF导致最后一行丢失.
    # 循环体内的[[ -n "$WP_DIR" ]]是为了跳过空行
    [[ -n "$WP_DIR" ]] || continue

    # 计算用户名,如果命令行参数中没有指定user目录范围,则从扫描到的路径中提取用户名.
    if [[ -n "$USER" ]]; then
        USERNAME="$USER"
    else
        USERNAME=$(extract_username "$WP_DIR")
    fi

    # 如果使用了用户白名单且用户不在白名单中，则跳过该用户目录的处理
    if [[ -z "$USER" && -n "$VALID_USERS" ]] && ! is_user_in_whitelist "$USERNAME"; then
        log "[跳过] 用户 $USERNAME 不在白名单中，跳过处理"
        continue
    fi

    site_need_backup_dirs+=("$WP_DIR")
    ((SITE_COUNT++))
    # log "debug: $SITE_COUNT ; $WP_DIR"
    # 计算待备份网站中是否存曾经备份过,即检查备份包路径是否已存在.(如果有,则按需跳过此站点备份)
    _get_pack_names() {
        DOMAIN=$(basename "$(dirname "$WP_DIR")")

        DEST_DIR="${DEST_ROOT}/${USERNAME}/deployed"
        ZST_NAME="${DOMAIN}.zst"

        DEST_DIR_PATH="${DEST_DIR}/${ZST_NAME}"
        DEST_DB_PATH="${DEST_DIR}/${DOMAIN}.sql.zst"
    }
    _get_pack_names
    judger_cnt() {
        pkg_path="$1"
        pkg_name="$(basename "$pkg_path")"
        if [[ -f "$pkg_path" ]] || [[ -f $STATUS_TAG_DIR/"$pkg_name" ]]; then
            if [[ $FORCE -eq 0 ]]; then
                log "[跳过[$MODE]] 发现已存在压缩包 $pkg_path,[user: $USERNAME],跳过站点 $DOMAIN 的备份。"
                return 2 # 返回2表示跳过
            else
                log " 将强制覆盖已存在的压缩包 $pkg_path"
            fi
        else
            log "[任务[$MODE]] 将为站点 $DOMAIN 创建备份归档任务,请耐心等待"

        fi
        return 0 #表示需要执行备份
    }
    # 报告有哪些站点已经备份以及需要执行备份
    if [[ $MODE == dir ]]; then
        judger_cnt "$DEST_DIR_PATH"
        if [[ $? -eq 2 ]]; then ((SITE_EXISTING++)); else ((SITE_TO_BACKUP++)); fi
    elif [[ $MODE == db ]]; then
        judger_cnt "$DEST_DB_PATH"
        if [[ $? -eq 2 ]]; then ((SITE_EXISTING++)); else ((SITE_TO_BACKUP++)); fi
    elif [[ $MODE == full ]]; then

        judger_cnt "$DEST_DIR_PATH"
        rc1=$?
        judger_cnt "$DEST_DB_PATH"
        rc2=$?

        # dir,db全部跳过时才算整站跳过
        if [[ $rc1 -eq 2 && $rc2 -eq 2 ]]; then ((SITE_EXISTING++)); else ((SITE_TO_BACKUP++)); fi
    fi

    # 仅根据dir包是否存在来判断
    # if [[ -f "$DEST_DIR_PATH" && $FORCE -eq 0 ]]; then
    #     log "[状态[$MODE]] 站点 $DOMAIN 已存在备份"
    #     ((SITE_EXISTING++))
    # else
    #     log "[状态[$MODE]] 站点 $DOMAIN 需要执行备份"
    #     ((SITE_TO_BACKUP++))
    # fi
done < "$site_dirs_listfile"

# 扫描结果报告(包括找不到要处理站点的报告)
if [[ $SITE_COUNT -eq 0 ]]; then
    if [[ -n "$USER" ]]; then
        log "未找到用户 $USER 的 wordpress 站点"
    elif [[ -n "$VALID_USERS" ]]; then
        log "根据用户目录白名单文件 $VALID_USERS 未找到需要处理的 wordpress 站点"
    elif [[ -n "$WHITELIST_SITE" ]]; then
        log "根据站点白名单文件 $WHITELIST_SITE 未找到需要处理的 wordpress 站点"
    else
        log "未找到任何满足指定条件的 wordpress 站点"
    fi
else

    # 显示将要并行执行的任务
    for site in "${site_need_backup_dirs[@]}"; do
        log "将处理站点: $site" #todo:将网站根目录优化为域名显示
    done
    # declare -p site_need_backup_dirs

    # 最后的总结
    log "查找完成，共匹配到 $SITE_COUNT 个站点"
    log "其中 $SITE_EXISTING 个站点已存在备份(或--force条件下被保留)，$SITE_TO_BACKUP 个站点需要备份(或--force条件覆盖)"
    if [[ $FORCE -eq 1 ]]; then
        log "使用 --force 选项将强制覆盖所有已存在的备份"
    fi
fi

# 实际并行执行(在parallel模式下,使用--linebuffer参数让输出及时显示到终端而不是必须等待return!)
if [[ $DRY_RUN -eq 0 ]]; then
    # 导出函数,供子进程访问(普通变量可以在前面声明的时候导出)
    export -f backup_one_site
    export -f extract_username
    export -f log
    export -f is_user_in_whitelist

    if [[ -n "$VALID_USERS" && -z "$USER" ]]; then
        # 当指定了合法用户目录但未指定扫描哪个用户时，需要先过滤目录
        while IFS= read -r WP_DIR || [[ -n "$WP_DIR" ]]; do
            [[ -n "$WP_DIR" ]] || continue
            username=$(extract_username "$WP_DIR")
            if is_user_in_whitelist "$username"; then
                # 使用echo or printf 将路径传递出去
                echo "$WP_DIR"
            fi
        done < "$site_dirs_listfile" |
            parallel --line-buffer -j "$PARALLEL_JOBS" backup_one_site
    else
        # 原有逻辑
        # cat $site_dirs_listfile | parallel --line-buffer -j "$PARALLEL_JOBS" backup_one_site
        # 使用 --null 可以指定\0作为路径列表文件的分割符
        parallel --line-buffer -j "$PARALLEL_JOBS" -a "$site_dirs_listfile" backup_one_site

    fi
fi

# 清理临时文件
[[ -f WHITELIST_SITE_TMP ]] && rm -rfv "$WHITELIST_SITE_TMP"
[[ -f VALID_USERS_TEMP ]] && rm -rfv "$VALID_USERS_TEMP"
