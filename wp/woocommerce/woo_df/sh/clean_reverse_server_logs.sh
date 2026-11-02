#!/usr/bin/env bash
# 清空反代日志内容：默认扫描 /www/wwwlogs 与 /var/log/nginx，
# 只处理文件名含 access.log / error.log 的文件；truncate 不删除 inode，nginx 无需 reload。
# 用法见 --help。
set -uo pipefail

DEFAULT_DIRS=(
	/www/wwwlogs
	/var/log/nginx
)
LOG_DIRS=()
DRY_RUN=false

usage() {
	cat <<'EOF'
用法: bash clean_reverse_server_logs.sh [选项]

清空反代 access/error 日志内容。使用 truncate，不删除 inode，nginx 不需要 reload。

选项:
  -d, --dir <目录>   只扫描指定目录，可重复；不传时扫描 /www/wwwlogs 与 /var/log/nginx
      --dry-run      只列出将清空的文件，不执行 truncate
  -h, --help         显示本帮助

示例:
  bash clean_reverse_server_logs.sh
  bash clean_reverse_server_logs.sh --dry-run
  bash clean_reverse_server_logs.sh --dir /www/wwwlogs --dir /var/log/nginx
EOF
}

die() {
	printf '错误: %s\n' "$*" >&2
	exit 2
}

while (($# > 0)); do
	case "$1" in
	-d | --dir)
		(($# >= 2)) || die "参数 $1 缺少取值"
		[[ $2 == /* ]] || die "日志目录必须是绝对路径: $2"
		LOG_DIRS+=("$2")
		shift 2
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "未知参数: $1（可用 --help 查看用法）"
		;;
	esac
done

if ((${#LOG_DIRS[@]} == 0)); then
	LOG_DIRS=("${DEFAULT_DIRS[@]}")
fi

printf '[%s] Run the cleaner routine.\n' "$(date +%F-%T)"

rc=0
for logdir in "${LOG_DIRS[@]}"; do
	if [[ ! -d $logdir ]]; then
		printf '[%s] Skip missing directory: %s\n' "$(date +%F-%T)" "$logdir"
		continue
	fi

	while IFS= read -r -d '' file; do
		if [[ $DRY_RUN == true ]]; then
			printf '[%s] [dry-run] Would truncate: %s\n' "$(date +%F-%T)" "$file"
			continue
		fi
		printf '[%s] Truncating: %s\n' "$(date +%F-%T)" "$file"
		truncate -s 0 "$file" || {
			printf '错误: 清空失败: %s\n' "$file" >&2
			rc=1
		}
	done < <(find "$logdir" -type f \( -name '*access.log*' -o -name '*error.log*' \) -print0)
done

df -h || true
exit "$rc"
