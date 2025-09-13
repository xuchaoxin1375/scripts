#!/bin/bash
# 注意事项:
# 0.执行此脚本时建议暂停服务器网站的服务(比如暂停nginx服务,防止备份过程中文件发生变化而导致tar过程出现错误或不一致);
# 建议白天执行备份任务,降低应为服务器暂停而导致的丢单损失
# 1.此脚本主要用于处理历史遗留的备份问题,专门为没有压缩包而只有站点各目录和对应的活跃数据库情况下进行备份
# (备份文件的格式(结构)保持我们惯例的站点压缩包结构,比如domain.com.zst,以及对应网站的domain.com.sql.zst)
# 2.关于数据库文件备份和导出,建议配置免密登录,不仅更安全,代码也更加简单(免密登录mysql配置方案有许多,执行参考资料配置)
# 3.完整性检查:备份完后可以运行一段批量检查文件完整性检查的代码,防止某些文件压缩过程中出错(尤其是被意外终止脚本的情况)
# 4.线程数不要开太高,虽然服务器核心很多,但是tar和zstd算法容易打满磁盘IO,备份速度的主要瓶颈不在cpu而在于磁盘上!
SRC_ROOT="/www/wwwroot"
DEST_ROOT="/srv/uploads/uploader/files"
DRY_RUN=0
FORCE=0
PARALLEL=0
PARALLEL_JOBS=4
USER_FILTER=""
MINDEPTH=2
MAXDEPTH=3
WHITELIST_FILE=""

show_help() {
	echo "用法: $0 [选项]"
	echo "  -s, --src <src_root>     源目录 (默认: /www/wwwroot)"
	echo "  -d, --dest <dest_root>   目标根目录 (默认: /srv/uploads/uploader/files)"
	echo "  -u, --user <username>    仅备份指定用户 (默认: 所有用户)"
	echo "      --whitelist <file>   白名单文件，指定需要处理的用户 (默认: 无)"
	echo "      --mindepth <n>       find 扫描的最小深度 (默认: $MINDEPTH)"
	echo "      --maxdepth <n>       find 扫描的最大深度 (默认: $MAXDEPTH)"
	echo "      --dry-run            预览模式，仅显示将执行的操作"
	echo "      --force              强制覆盖已存在的备份"
	echo "      --parallel           并行处理模式"
	echo "      --jobs <n>           并行任务数 (默认: 4)"
	echo "  -h, --help               显示本帮助信息"
}

# 从路径中提取用户名的函数
extract_username() {
    local path="$1"
    
    # 使用 IFS 按 '/' 分割路径
    IFS='/' read -ra parts <<< "$path"
    
    # 检查是否有至少 4 个部分（因为开头是 /，所以数组第一个元素为空）
    # 例如：/www/wwwroot/xcx/ → ['', 'www', 'wwwroot', 'xcx', '']
    # 我们需要第 4 个元素（索引为 3）作为“第三部分”
    if [[ ${#parts[@]} -lt 4 ]]; then
        echo "警报: 路径中不存在第三部分" >&2
        echo ""
        return 1
    fi
    
    # 提取第三部分（索引为 3）
    third_part="${parts[3]}"
    
    # 检查第三部分是否为空
    if [[ -z "$third_part" ]]; then
        echo "警报: 第三部分为空" >&2
        echo ""
        return 1
    fi
    
    echo "$third_part"
}

# 定义检查用户是否在白名单中的函数
is_user_in_whitelist() {
	local username="$1"
	
	# 如果没有指定白名单文件，则所有用户都在白名单中
	if [[ -z "$WHITELIST_FILE" ]]; then
		return 0
	fi
	
	# 检查用户是否在白名单中
	if grep -q "^${username}$" "$WHITELIST_FILE"; then
		return 0
	else
		return 1
	fi
}

# 备份单个站点的函数
backup_one_site() {
	WP_DIR="$1"
	
	# 根据是否指定了用户过滤器来确定用户名提取方式
	if [[ -n "$USER_FILTER" ]]; then
		USERNAME="$USER_FILTER"
	else
		USERNAME=$(extract_username "$WP_DIR")
	fi
	
	DOMAIN=$(basename "$(dirname "$WP_DIR")")
	
	TAR_NAME="${DOMAIN}"
	TAR_PATH="/tmp/${TAR_NAME}"
	ZST_NAME="${DOMAIN}.zst"
	DEST_DIR="${DEST_ROOT}/${USERNAME}/deployed"
	DEST_PATH="${DEST_DIR}/${ZST_NAME}"

	# 检查压缩包是否已存在
	if [[ -f "$DEST_PATH" && $FORCE -eq 0 ]]; then
		echo "[跳过] 发现已存在压缩包 $DEST_PATH，[user: $USERNAME],跳过站点 $DOMAIN 的备份。"
		return 2  # 返回2表示跳过

	else
		echo "[任务] 将为站点 $DOMAIN 创建备份归档任务,请耐心等待"

	fi

	if [[ $DRY_RUN -eq 1 ]]; then
		if [[ -f "$DEST_PATH" && $FORCE -eq 1 ]]; then
			echo "[预览] 将强制覆盖已存在的压缩包 $DEST_PATH"
		fi
		echo "[预览] 将打包 $WP_DIR 到 $TAR_PATH"
		echo "[预览] 将使用 zstd --rm 压缩 $TAR_PATH 到 $TAR_PATH.zst"
		echo "[预览] 将移动 $TAR_PATH.zst 到 $DEST_PATH"
		echo "[预览] 如目标目录不存在将自动创建 $DEST_DIR"
		echo "[预览] 将尝试导出数据库: ${USERNAME}_${DOMAIN}, ${DOMAIN}, www.${DOMAIN}，并用 zstd 压缩"
		return 0
	else
		echo "正在备份站点 $WP_DIR，用户 $USERNAME，域名 $DOMAIN..."
		mkdir -p "$DEST_DIR"
		tar -cf "$TAR_PATH" -C "$WP_DIR" .
		zstd --rm "$TAR_PATH"
		mv "$TAR_PATH.zst" "$DEST_PATH"
		
		# 设置文件权限和所有者
		chmod 755 "$DEST_PATH"
		chown uploader:uploader "$DEST_PATH"
		echo "站点文件已备份到: $DEST_PATH"

		# 数据库备份，依次尝试三种数据库名
		DB_CANDIDATES=("${USERNAME}_${DOMAIN}" "${DOMAIN}" "www.${DOMAIN}")
		DB_DUMPED=0
		for DBNAME in "${DB_CANDIDATES[@]}"; do
			# 导出sql的备份文件名统一使用"${DOMAIN}.zst"
			SQL_DUMP_PATH="${DEST_DIR}/${DOMAIN}.sql"
			ZST_SQL_DUMP_PATH="${SQL_DUMP_PATH}.zst"
			if mysqlshow "$DBNAME" >/dev/null 2>&1; then
				if mysqldump "$DBNAME" > "$SQL_DUMP_PATH"; then
					# 将sql文件用tar包装一下,文件名保持原来的.sql而不加tar后缀(这看起来有点多余,但是为了和其他配套脚本兼容,这里做一下额外处理)
					## 先临时创建一个.tar文件,然后重命名(去掉.tar)
					echo "正在将 $SQL_DUMP_PATH 打包为tar文件,然后更名回 $SQL_DUMP_PATH"
					sql_tar="${SQL_DUMP_PATH}.tar"
					tar -cvf "$sql_tar" -C "$(dirname "$SQL_DUMP_PATH")" "$(basename "$SQL_DUMP_PATH")"
					rm "$SQL_DUMP_PATH" -v -f
					mv "$sql_tar" "$SQL_DUMP_PATH" -v -f
					echo "检查当前sql归档文件类型:$SQL_DUMP_PATH ($(file -b "$SQL_DUMP_PATH"))"

					echo "将$SQL_DUMP_PATH 压缩为 $ZST_SQL_DUMP_PATH"
					zstd --rm "$SQL_DUMP_PATH" #默认添加后缀.zst
					echo "设置SQL文件权限(755)"
					chmod 755 "$ZST_SQL_DUMP_PATH"
					# chown uploader:uploader "$ZST_SQL_DUMP_PATH"
					# echo "数据库 $DBNAME 已导出并压缩到: $ZST_SQL_DUMP_PATH"
					DB_DUMPED=1
					break
				fi
			fi
		done
		if [[ $DB_DUMPED -eq 0 ]]; then
			echo "[警告] 未找到可用数据库，站点 $DOMAIN (用户 $USERNAME) 未进行数据库备份。"
		fi
		return 0
	fi
}

# 参数解析
while [[ $# -gt 0 ]]; do
	case "$1" in
		-s|--src)
			SRC_ROOT="$2"
			shift 2
			;;
		-d|--dest)
			DEST_ROOT="$2"
			shift 2
			;;
		-u|--user)
			USER_FILTER="$2"
			shift 2
			;;
		--whitelist)
			WHITELIST_FILE="$2"
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
		-h|--help)
			show_help
			exit 0
			;;
		*)
			echo "未知参数: $1"
			show_help
			exit 1
			;;
	esac
done

# 获取所有 wordpress 目录，并打印已匹配到的目录
echo "正在扫描匹配的 wordpress 目录..."

# 确定查找路径和域名提取方式
FIND_PATH="$SRC_ROOT"
if [[ -n "$USER_FILTER" ]]; then
	FIND_PATH="$SRC_ROOT/$USER_FILTER"
fi

# 在 dry-run 模式下显示将要执行的查找命令
if [[ $DRY_RUN -eq 1 ]]; then
	echo "[预览] 将在 $FIND_PATH 下查找深度为 $MINDEPTH-$MAXDEPTH 的 wordpress 目录"
	if [[ -n "$WHITELIST_FILE" ]]; then
		echo "[预览] 使用白名单文件: $WHITELIST_FILE"
	fi
	if [[ $PARALLEL -eq 1 ]]; then
		echo "[预览] 将使用并行模式处理，任务数: $PARALLEL_JOBS"
	fi
fi

# 检查白名单文件是否存在
if [[ -n "$WHITELIST_FILE" && ! -f "$WHITELIST_FILE" ]]; then
	echo "错误: 白名单文件 $WHITELIST_FILE 不存在"
	exit 1
fi

# 扫描并备份所有匹配的站点
SITE_COUNT=0
SITE_EXISTING=0
SITE_TO_BACKUP=0

if [[ $PARALLEL -eq 1 ]]; then
	# 并行处理模式
	if [[ $DRY_RUN -eq 1 ]]; then
		# 并行预览模式
		SITE_LIST=()
		while IFS= read -r WP_DIR; do
			[[ -n "$WP_DIR" ]] || continue
			
			# 获取用户名
			if [[ -n "$USER_FILTER" ]]; then
				USERNAME="$USER_FILTER"
			else
				USERNAME=$(extract_username "$WP_DIR")
			fi
			
			# 如果使用了白名单且用户不在白名单中，则跳过
			if [[ -z "$USER_FILTER" && -n "$WHITELIST_FILE" ]] && ! is_user_in_whitelist "$USERNAME"; then
				echo "[跳过] 用户 $USERNAME 不在白名单中，跳过处理"
				continue
			fi
			
			SITE_LIST+=("$WP_DIR")
			((SITE_COUNT++))
			
			# 获取用户名和域名
			if [[ -n "$USER_FILTER" ]]; then
				USERNAME="$USER_FILTER"
			else
				USERNAME=$(extract_username "$WP_DIR")
			fi
			DOMAIN=$(basename "$(dirname "$WP_DIR")")
			ZST_NAME="${DOMAIN}.zst"
			DEST_DIR="${DEST_ROOT}/${USERNAME}/deployed"
			DEST_PATH="${DEST_DIR}/${ZST_NAME}"
			
			if [[ -f "$DEST_PATH" && $FORCE -eq 0 ]]; then
				echo "[状态] 站点 $DOMAIN 已存在备份"
				((SITE_EXISTING++))
			else
				echo "[状态] 站点 $DOMAIN 需要执行备份"
				((SITE_TO_BACKUP++))
			fi
		done < <(find "$FIND_PATH" -mindepth "$MINDEPTH" -maxdepth "$MAXDEPTH" -type d -name wordpress)
		
		if [[ $SITE_COUNT -eq 0 ]]; then
			if [[ -n "$USER_FILTER" ]]; then
				echo "未找到用户 $USER_FILTER 的 wordpress 站点"
			elif [[ -n "$WHITELIST_FILE" ]]; then
				echo "根据白名单文件 $WHITELIST_FILE 未找到需要处理的 wordpress 站点"
			else
				echo "未找到任何 wordpress 站点"
			fi
		else
			echo "[预览] 查找完成，共匹配到 $SITE_COUNT 个站点"
			echo "[预览] 其中 $SITE_EXISTING 个站点已存在备份，$SITE_TO_BACKUP 个站点需要备份"
			if [[ $FORCE -eq 1 ]]; then
				echo "[预览] 使用 --force 选项将强制覆盖所有已存在的备份"
			fi
			
			# 显示将要并行执行的任务
			for site in "${SITE_LIST[@]}"; do
				echo "[预览] 将处理站点: $site"
			done
		fi
	else
		# 实际并行执行(在parallel模式下,使用--linebuffer参数让输出及时显示到终端而不是必须等待return!)
		export -f backup_one_site
		export USER_FILTER DEST_ROOT FORCE DRY_RUN WHITELIST_FILE MINDEPTH MAXDEPTH
		export -f extract_username
		export is_user_in_whitelist
		
		if [[ -n "$WHITELIST_FILE" && -z "$USER_FILTER" ]]; then
			# 当使用白名单但未指定用户时，需要先过滤目录
			while IFS= read -r WP_DIR; do
				[[ -n "$WP_DIR" ]] || continue
				username=$(extract_username "$WP_DIR")
				if is_user_in_whitelist "$username"; then
					echo "$WP_DIR"
				fi
			done < <(find "$FIND_PATH" -mindepth "$MINDEPTH" -maxdepth "$MAXDEPTH" -type d -name wordpress) | \
				parallel --line-buffer -j "$PARALLEL_JOBS" backup_one_site
		else
			# 原有逻辑
			find "$FIND_PATH" -mindepth "$MINDEPTH" -maxdepth "$MAXDEPTH" -type d -name wordpress | \
				parallel --line-buffer -j "$PARALLEL_JOBS" backup_one_site
		fi
	fi
	
else
	# 原始串行处理模式
	while IFS= read -r WP_DIR; do
		[[ -n "$WP_DIR" ]] || continue
		
		# 如果指定了用户过滤器，则直接使用，否则从路径中提取
		if [[ -n "$USER_FILTER" ]]; then
			USERNAME_SCAN="$USER_FILTER"
		else
			USERNAME_SCAN=$(extract_username "$WP_DIR")
		fi
		
		# 如果使用了白名单且用户不在白名单中，则跳过
		if [[ -z "$USER_FILTER" && -n "$WHITELIST_FILE" ]] && ! is_user_in_whitelist "$USERNAME_SCAN"; then
			echo "[跳过] 用户 $USERNAME_SCAN 不在白名单中，跳过处理 $WP_DIR"
			continue
		fi
		
		echo "[发现] $WP_DIR"
		
		# 根据是否指定了用户过滤器来确定用户名提取方式
		if [[ -n "$USER_FILTER" ]]; then
			USERNAME="$USER_FILTER"
		else
			USERNAME=$(extract_username "$WP_DIR")
		fi
		
		DOMAIN=$(basename "$(dirname "$WP_DIR")")
		ZST_NAME="${DOMAIN}.zst"
		DEST_DIR="${DEST_ROOT}/${USERNAME}/deployed"
		DEST_PATH="${DEST_DIR}/${ZST_NAME}"
		
		((SITE_COUNT++))
		
		if [[ -f "$DEST_PATH" && $FORCE -eq 0 ]]; then
			echo "[状态] 站点 $DOMAIN 已存在备份"
			
			((SITE_EXISTING++))
		else
			echo "[状态] 站点 $DOMAIN 需要执行备份"
			((SITE_TO_BACKUP++))
		fi
		
		backup_one_site "$WP_DIR"
		

	done < <(find "$FIND_PATH" -mindepth "$MINDEPTH" -maxdepth "$MAXDEPTH" -type d -name wordpress)

	# 在 dry-run 模式下显示扫描结果
	if [[ $DRY_RUN -eq 1 ]]; then
		if [[ -n "$WHITELIST_FILE" ]]; then
			echo "[预览] 使用白名单文件: $WHITELIST_FILE"
		fi
		echo "[预览] 查找完成，共匹配到 $SITE_COUNT 个站点"
		echo "[预览] 其中 $SITE_EXISTING 个站点已存在备份，$SITE_TO_BACKUP 个站点需要备份"
		if [[ $FORCE -eq 1 ]]; then
			echo "[预览] 使用 --force 选项将强制覆盖所有已存在的备份"
		fi
	fi

	# 如果没有找到任何站点，给出提示
	if [[ $SITE_COUNT -eq 0 ]]; then
		if [[ -n "$USER_FILTER" ]]; then
			echo "未找到用户 $USER_FILTER 的 wordpress 站点"
		elif [[ -n "$WHITELIST_FILE" ]]; then
			echo "根据白名单文件 $WHITELIST_FILE 未找到需要处理的 wordpress 站点"
		else
			echo "未找到任何 wordpress 站点"
		fi
	else
		echo "总共发现 $SITE_COUNT 个站点，其中 $SITE_EXISTING 个已存在备份，$SITE_TO_BACKUP 个需要备份"
	fi
fi