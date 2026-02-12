#!/bin/bash
# 脚本功能和设计
# 脚本支持多个选项,满足备份指定网站(可通过网站白名单文件来指定备份哪些网站),也可以指定工作目录及其下面的需要参与备份的目录名(可能是网站所属人员的名字代号或拼写)来备份某个人员的站点
# 无论是哪种方式,基本思路是指定的任务通过计算直接或间接(比如find扫描指定目录下的所有网站)得到需要执行打包备份的网站根目录路径列表,然后遍历这些路径调用一个网站打包函数完整站点备份;并且可选的,允许同时对多个网站进行备份.
# 注意事项:
# 0.执行此脚本时建议暂停服务器网站的服务(比如暂停nginx服务,防止备份过程中文件发生变化而导致tar过程出现错误或不一致);
# 建议白天执行备份任务,降低应为服务器暂停而导致的丢单损失
# 1.此脚本主要用于处理历史遗留的备份问题,专门为没有压缩包而只有站点各目录和对应的活跃数据库情况下进行备份
# (备份文件的格式(结构)保持我们惯例的站点压缩包结构,比如domain.com.zst,以及对应网站的domain.com.sql.zst)
# 2.关于数据库文件备份和导出,建议配置免密登录,不仅更安全,代码也更加简单(免密登录mysql配置方案有许多,自行查阅资料配置)
# 3.完整性检查:备份完后可以运行一段批量检查文件完整性检查的代码,防止某些文件压缩过程中出错(尤其是被意外终止脚本的情况)
# 4.线程数不要开太高,虽然服务器核心很多,但是tar和zstd算法容易打满磁盘IO,备份速度的主要瓶颈不在cpu而在于磁盘上!

# # 指定MySQL主机和端口
# ./backup_sites_from_source_dir.sh --mysql-host 192.168.1.100 --mysql-port 3306

# # 指定MySQL用户名和密码
# ./backup_sites_from_source_dir.sh --mysql-user myuser --mysql-pass mypassword
# bash ./backup_sites_from_source_dir.sh --parallel --jobs 2 --valid-users  valid_users.ini -u xcx --mysql-user myusername --mysql-pass password123
# # 组合使用所有参数
# ./backup_sites_from_source_dir.sh -d /srv/uploads/uploader/files --mysql-host localhost --mysql-port 3306 --mysql-user root --mysql-pass password123

SRC_ROOT="/www/wwwroot"
DEST_ROOT="/srv/uploads/uploader/files"
DRY_RUN=0
FORCE=0
PARALLEL=0
PARALLEL_JOBS=4
USER=""
MINDEPTH=2
MAXDEPTH=3
VALID_USERS=""
WHITELIST_SITE=""
declare -a MYSQL_ARGS
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
MYSQL_USER="root"
MYSQL_PASS=""

show_help() {
	log "用法: $0 [选项]"
	log "  -s, --src <src_root>     网站根目录所在总目录 (默认: $SRC_ROOT)"
	log "  -d, --dest <dest_root>   目标根目录 (默认: $DEST_ROOT)"
	log "  -u, --user <username>    根据站点所属人员来指定网站范围(人员专属目录名,通常是人名拼音缩写),从而仅备份指定用户的网站目录下的站点 (默认: 所有用户)"
	log "      --valid-users  <file>   白名单文件，指定需要处理的用户目录名列表 (默认: 无)"
	log "      --whitelist-site <file>   白名单文件，指定需要处理的网站(域名)列表 (默认: 无)"
	log "      --mysql-host <host>  MySQL主机地址"
	log "      --mysql-port <port>  MySQL端口"
	log "      --mysql-user <user>  MySQL用户名"
	log "      --mysql-pass <pass>  MySQL密码"
	log "      --mindepth <n>       find 扫描的最小深度 (默认: $MINDEPTH)"
	log "      --maxdepth <n>       find 扫描的最大深度 (默认: $MAXDEPTH)"
	log "      --dry-run            预览模式，仅显示将执行的操作"
	log "      --force              强制覆盖已存在的备份"
	log "      --parallel           并行处理模式"
	log "      --jobs <n>           并行任务数 (默认: 4)"
	log "  -h, --help               显示本帮助信息"
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
	if ! command -v "$1" &>/dev/null; then
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
	IFS='/' read -ra parts <<<"$path"

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
	if mysql "${MYSQL_ARGS[@]}" -e "SELECT 1" &>/dev/null; then
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
	DOMAIN=$(basename "$(dirname "$WP_DIR")")

	TAR_NAME="${DOMAIN}"
	TAR_PATH="/tmp/${TAR_NAME}"
	# 计算并构造压缩包要保存的完整路径.
	ZST_NAME="${DOMAIN}.zst"
	DEST_DIR="${DEST_ROOT}/${USERNAME}/deployed"
	DEST_PATH="${DEST_DIR}/${ZST_NAME}"

	# 检查压缩包是否已存在(如果存在且不强制覆盖,则跳过此站)
	if [[ -f "$DEST_PATH" && $FORCE -eq 0 ]]; then
		log "[跳过] 发现已存在压缩包 $DEST_PATH，[user: $USERNAME],跳过站点 $DOMAIN 的备份。"
		return 2 # 返回2表示跳过

	else
		log "[任务] 将为站点 $DOMAIN 创建备份归档任务,请耐心等待"

	fi

	if [[ $DRY_RUN -eq 1 ]]; then
		if [[ -f "$DEST_PATH" && $FORCE -eq 1 ]]; then
			log "[预览] 将强制覆盖已存在的压缩包 $DEST_PATH"
		fi
		log "[预览] 将打包 $WP_DIR 到 $TAR_PATH"
		log "[预览] 将使用 zstd --rm 压缩 $TAR_PATH 到 $TAR_PATH.zst"
		log "[预览] 将移动 $TAR_PATH.zst 到 $DEST_PATH"
		log "[预览] 如目标目录不存在将自动创建 $DEST_DIR"
		log "[预览] 将尝试导出数据库: ${USERNAME}_${DOMAIN}, ${DOMAIN}, www.${DOMAIN}，并用 zstd 压缩"
		return 0
	else
		log "正在备份站点 $WP_DIR，用户 $USERNAME，域名 $DOMAIN..."
		log "📦 正在打包 WordPress 文件（排除缓存和日志）..."
		mkdir -p "$DEST_DIR"
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
		zstd -T0 --rm "$TAR_PATH" -f -v
		mv "$TAR_PATH.zst" "$DEST_PATH"

		# 设置文件权限和所有者
		chmod 755 "$DEST_PATH"
		chown uploader:uploader "$DEST_PATH"
		log "站点文件已备份到: $DEST_PATH"

		# 数据库备份，依次尝试三种数据库名
		DB_CANDIDATES=("${USERNAME}_${DOMAIN}" "${DOMAIN}" "www.${DOMAIN}")
		DB_DUMPED=0
		for DBNAME in "${DB_CANDIDATES[@]}"; do
			# 导出sql的备份文件名统一使用"${DOMAIN}.zst"
			SQL_DUMP_PATH="${DEST_DIR}/${DOMAIN}.sql"
			ZST_SQL_DUMP_PATH="${SQL_DUMP_PATH}.zst"

			# 构建mysql连接参数

			# if mysqlshow "${MYSQL_ARGS[@]}" "$DBNAME" >/dev/null 2>&1; then
			if mysql "${MYSQL_ARGS[@]}" -e "USE \`$DBNAME\`;" >/dev/null 2>&1; then
				if mysqldump "${MYSQL_ARGS[@]}" "$DBNAME" >"$SQL_DUMP_PATH"; then
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
		if [[ $DB_DUMPED -eq 0 ]]; then
			log "[警告] 未找到可用数据库，站点 $DOMAIN (用户 $USERNAME) 未进行数据库备份。"
		fi
		return 0
	fi
}

# 参数解析
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
	--valid-users)
		VALID_USERS="$2"
		shift 2
		;;
	--whitelist-site)
		WHITELIST_SITE="$2"
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
	--mindepth)
		MINDEPTH="$2"
		shift 2
		;;
	--maxdepth)
		MAXDEPTH="$2"
		shift 2
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	--force)
		FORCE=1
		shift
		;;
	--parallel)
		PARALLEL=1
		shift
		;;
	--jobs)
		PARALLEL_JOBS="$2"
		shift 2
		;;
	-h | --help)
		show_help
		exit 0
		;;
	*)
		log "未知参数: $1"
		show_help
		exit 1
		;;
	esac
done

# 获取所有 wordpress 目录，并打印已匹配到的目录
log "正在扫描匹配的 wordpress 目录..."

# 确定查找路径和域名提取方式
FIND_PATH="$SRC_ROOT" # FIND_PATH 默认值
if [[ -n "$WHITELIST_SITE" ]]; then
	log "仅扫描指定域名路径"
elif [[ -n "$USER" ]]; then
	FIND_PATH="$SRC_ROOT/$USER"
	log "将在 $FIND_PATH 下查找深度为 $MINDEPTH-$MAXDEPTH 的 wordpress 目录"
fi

# 在 dry-run 模式下显示将要执行的查找命令
if [[ $DRY_RUN -eq 1 ]]; then
	if [[ -n "$VALID_USERS" ]]; then
		log "[预览] 使用用户名白名单文件: $VALID_USERS"
	fi
	if [[ -n "$VALID_USERS" ]]; then
		log "[预览] 使用域名白名单文件: $WHITELIST_SITE"
	fi
	if [[ $PARALLEL -eq 1 ]]; then
		log "[预览] 将使用并行模式处理，任务数: $PARALLEL_JOBS"
	fi
fi

check_listfile "$VALID_USERS"
check_listfile "$WHITELIST_SITE"

# if [[ -n "$VALID_USERS" && ! -f "$VALID_USERS" ]]; then
# 	log "错误: 白名单文件 $VALID_USERS 不存在"
# 	exit 1
# fi

# 在开始备份前检查MySQL连接
if ! check_mysql_connection; then
	exit 1
fi

# 扫描并备份所有匹配的站点
SITE_COUNT=0
SITE_EXISTING=0
SITE_TO_BACKUP=0

if [[ $PARALLEL -eq 1 ]]; then
	# 并行处理模式
	# 初始化一个空数组
	declare -a site_dirs
	site_dirs_listfile="/www/site_dirs_list.txt"
	# 清空原文件防止旧数据干扰
	echo -n "" >"$site_dirs_listfile"

	# 计算待备份网站根目录(初步计算,尚未计算列表中曾经备份而已有备份包到过滤处理.)
	if [[ -n "$VALID_USERS" ]]; then
		log "将使用用户名白名单文件搜索指定网站根目录: $VALID_USERS"
		# site_dirs=$(find "$FIND_PATH" -mindepth "$MINDEPTH" -maxdepth "$MAXDEPTH" -type d -name wordpress)

		# 使用 mapfile 安全读取
		# -d '' 指定以 NULL 字符作为行分隔符
		# < <(...) 使用进程替换将 find 的输出喂给 mapfile
		find "$FIND_PATH" -mindepth "$MINDEPTH" -maxdepth "$MAXDEPTH" -type d -name wordpress >"$site_dirs_listfile"

		mapfile -d '' site_dirs <"$site_dirs_listfile"

	elif [[ -n "$WHITELIST_SITE" ]]; then
		log "将使用域名白名单文件搜索指定网站根目录: $WHITELIST_SITE"
		mapfile -t sites <"$WHITELIST_SITE"
		for site in "${sites[@]}"; do
			# 跳过第一个非空白字符是#或;的行(视为注释)
			if [[ $site =~ ^[[:space:]]*(#|;).* ]]; then
				log "Jump line [$site]"
				continue
			fi
			# 移除行边缘空格
			# site=$(echo "$site" | xargs)
			site=$(trim "$site")
			dir=$(echo "$SRC_ROOT"/*/"$site"/wordpress)
			if [[ -d "$dir" ]]; then
				# [[ -d "$dir" ]] && site_dirs+=("$dir")
				# find $base_dir -maxdepth 2 -type d -name $site
				site_dirs+=("$dir")
				# 写入到文件中使用printf并以\0 分隔路径字符串比echo要安全(但是用户直接打开文件没有一行一个路径) printf "%s\0"
				# 使用mapfile 的 -d '' 选项可以轻松读取 \0 分隔的元素,while read -r -d ''也支持
				# 而在已知路径不会包含\n的情况下,可以用\n
				printf "%s\n" "$dir" >>$site_dirs_listfile
			else
				log "[警告] 站点 $site 不存在"
			fi
		done
	else
		log "不使用任何白名单"
	fi
	# 保存到临时文件做调试用途.
	log "已匹配到的站点列表:"
	nl "$site_dirs_listfile"

	# 统计最终将要处理的站点数(计算过滤要跳过的站点)
	declare -a site_need_backup_dirs
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
		DOMAIN=$(basename "$(dirname "$WP_DIR")")
		ZST_NAME="${DOMAIN}.zst"
		DEST_DIR="${DEST_ROOT}/${USERNAME}/deployed"
		DEST_PATH="${DEST_DIR}/${ZST_NAME}"

		# 报告有哪些站点已经备份以及需要执行备份
		if [[ -f "$DEST_PATH" && $FORCE -eq 0 ]]; then
			log "[状态] 站点 $DOMAIN 已存在备份"
			((SITE_EXISTING++))
		else
			log "[状态] 站点 $DOMAIN 需要执行备份"
			((SITE_TO_BACKUP++))
		fi
	done <"$site_dirs_listfile"

	# 扫描结果报告(包括找不到要处理站点的报告)
	if [[ $SITE_COUNT -eq 0 ]]; then
		if [[ -n "$USER" ]]; then
			log "未找到用户 $USER 的 wordpress 站点"
		elif [[ -n "$VALID_USERS" ]]; then
			log "根据用户目录白名单文件 $VALID_USERS 未找到需要处理的 wordpress 站点"
		elif [[ -n "$WHITELIST_SITE" ]]; then
			log "根据站点白名单文件 $WHITELIST_SITE 未找到需要处理的 wordpress 站点"
		else
			log "未找到任何 wordpress 站点"
		fi
	else
		log "查找完成，共匹配到 $SITE_COUNT 个站点"
		log "其中 $SITE_EXISTING 个站点已存在备份，$SITE_TO_BACKUP 个站点需要备份"
		if [[ $FORCE -eq 1 ]]; then
			log "使用 --force 选项将强制覆盖所有已存在的备份"
		fi

		# 显示将要并行执行的任务
		for site in "${site_need_backup_dirs[@]}"; do
			log "将处理站点: $site"
		done
		# declare -p site_need_backup_dirs
	fi

	# 实际并行执行(在parallel模式下,使用--linebuffer参数让输出及时显示到终端而不是必须等待return!)
	if [[ $DRY_RUN -eq 0 ]]; then
		export -f backup_one_site
		export -f extract_username
		export -f log
		export -f is_user_in_whitelist
		export USER DEST_ROOT FORCE DRY_RUN VALID_USERS MINDEPTH MAXDEPTH
		export MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PASS

		if [[ -n "$VALID_USERS" && -z "$USER" ]]; then
			# 当指定了合法用户目录但未指定扫描哪个用户时，需要先过滤目录
			while IFS= read -r WP_DIR || [[ -n "$WP_DIR" ]]; do
				[[ -n "$WP_DIR" ]] || continue
				username=$(extract_username "$WP_DIR")
				if is_user_in_whitelist "$username"; then
					# 使用echo or printf 将路径传递出去
					echo "$WP_DIR"
				fi
			done <"$site_dirs_listfile" |
				parallel --line-buffer -j "$PARALLEL_JOBS" backup_one_site
		else
			# 原有逻辑
			# cat $site_dirs_listfile | parallel --line-buffer -j "$PARALLEL_JOBS" backup_one_site
			# 使用 --null 可以指定\0作为路径列表文件的分割符
			parallel --line-buffer -j "$PARALLEL_JOBS" -a "$site_dirs_listfile" backup_one_site

		fi
	fi

else
	log "串行处理模式(deprecated.)"
	# # 原始串行处理模式
	# while IFS= read -r WP_DIR; do
	# 	[[ -n "$WP_DIR" ]] || continue

	# 	# 如果指定了用户过滤器，则直接使用，否则从路径中提取
	# 	if [[ -n "$USER" ]]; then
	# 		USERNAME_SCAN="$USER"
	# 	else
	# 		USERNAME_SCAN=$(extract_username "$WP_DIR")
	# 	fi

	# 	# 如果使用了白名单且用户不在白名单中，则跳过
	# 	if [[ -z "$USER" && -n "$VALID_USERS" ]] && ! is_user_in_whitelist "$USERNAME_SCAN"; then
	# 		log "[跳过] 用户 $USERNAME_SCAN 不在白名单中，跳过处理 $WP_DIR"
	# 		continue
	# 	fi

	# 	log "[发现] $WP_DIR"

	# 	# 根据是否指定了用户过滤器来确定用户名提取方式
	# 	if [[ -n "$USER" ]]; then
	# 		USERNAME="$USER"
	# 	else
	# 		USERNAME=$(extract_username "$WP_DIR")
	# 	fi

	# 	DOMAIN=$(basename "$(dirname "$WP_DIR")")
	# 	ZST_NAME="${DOMAIN}.zst"
	# 	DEST_DIR="${DEST_ROOT}/${USERNAME}/deployed"
	# 	DEST_PATH="${DEST_DIR}/${ZST_NAME}"

	# 	((SITE_COUNT++))

	# 	if [[ -f "$DEST_PATH" && $FORCE -eq 0 ]]; then
	# 		log "[状态] 站点 $DOMAIN 已存在备份"

	# 		((SITE_EXISTING++))
	# 	else
	# 		log "[状态] 站点 $DOMAIN 需要执行备份"
	# 		((SITE_TO_BACKUP++))

	# 	fi

	# 	backup_one_site "$WP_DIR"

	# done < $site_dirs_listfile

	# # 在 dry-run 模式下显示扫描结果
	# if [[ $DRY_RUN -eq 1 ]]; then
	# 	if [[ -n "$VALID_USERS" ]]; then
	# 		log "[预览] 使用白名单文件: $VALID_USERS"
	# 	fi
	# 	log "[预览] 查找完成，共匹配到 $SITE_COUNT 个站点"
	# 	log "[预览] 其中 $SITE_EXISTING 个站点已存在备份，$SITE_TO_BACKUP 个站点需要备份"
	# 	if [[ $FORCE -eq 1 ]]; then
	# 		log "[预览] 使用 --force 选项将强制覆盖所有已存在的备份"
	# 	fi
	# fi

	# # 如果没有找到任何站点，给出提示
	# if [[ $SITE_COUNT -eq 0 ]]; then
	# 	if [[ -n "$USER" ]]; then
	# 		log "未找到用户 $USER 的 wordpress 站点"
	# 	elif [[ -n "$VALID_USERS" ]]; then
	# 		log "根据白名单文件 $VALID_USERS 未找到需要处理的 wordpress 站点"
	# 	else
	# 		log "未找到任何 wordpress 站点"
	# 	fi
	# else
	# 	log "总共发现 $SITE_COUNT 个站点，其中 $SITE_EXISTING 个已存在备份，$SITE_TO_BACKUP 个需要备份"
	# fi
fi
