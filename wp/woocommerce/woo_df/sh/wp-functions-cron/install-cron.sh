#!/usr/bin/env bash
# 在目标服务器本地安装 /etc/cron.d/wp-functions。
# 典型用法：Windows 侧先 scp 上传 cron 文件，再通过 ssh 调用本脚本；
# 也可让本脚本直接读取随仓库部署的模板文件。
set -euo pipefail

SOURCE_FILE="/tmp/wp-functions.cron"
TARGET_FILE="/etc/cron.d/wp-functions"
BACKUP_DIR="/var/backups/wp-functions-cron"
ACTION="apply"
ALLOW_EXISTING=0

usage() {
	cat <<'EOF'
用法: bash install-cron.sh [选项]

在目标服务器本地把一份 cron 文件安装到 /etc/cron.d/wp-functions。
脚本负责去 BOM、去 CR、补齐尾换行、备份、原子替换和写后校验。

选项:
  -f, --file <路径>      待安装的 cron 文件，默认 /tmp/wp-functions.cron
  -t, --target <路径>    目标文件，默认 /etc/cron.d/wp-functions
      --check            只校验目标文件是否与 --file 一致
      --remove           备份后删除目标文件
      --allow-existing   跳过重复条目检查
  -h, --help             显示本帮助

示例:
  bash install-cron.sh -f /tmp/wp-functions.cron
  bash install-cron.sh --check -f /tmp/wp-functions.cron
  bash install-cron.sh --remove
EOF
}

die() {
	printf '错误: %s\n' "$*" >&2
	exit 2
}

log() {
	printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

warn() {
	printf '[%s] 警告: %s\n' "$(date '+%F %T')" "$*" >&2
}

require_root() {
	[[ $(id -u) -eq 0 ]] || die "需要 root 权限，请以 root 登录或使用 sudo 运行"
}

# 只允许字母、数字、下划线和连字符：Debian 系的 run-parts 会跳过含点号的文件
check_target_name() {
	local name
	name=$(basename "$TARGET_FILE")
	[[ $name =~ ^[A-Za-z0-9_-]+$ ]] || die "目标文件名 $name 含非法字符；/etc/cron.d 中带点号的文件会被 run-parts 跳过"
}

normalize_file() {
	local src=$1 dst=$2 magic
	[[ -f $src ]] || die "文件不存在: $src"
	[[ -s $src ]] || die "文件为空: $src"

	magic=$(head -c 3 "$src" | od -An -tx1 | tr -d ' \n')
	if [[ $magic == efbbbf ]]; then
		tail -c +4 "$src" | tr -d '\r' >"$dst"
	else
		tr -d '\r' <"$src" >"$dst"
	fi

	[[ -s $dst ]] || die "去除 BOM 与 CR 后内容为空: $src"
	if [[ $(tail -c 1 "$dst" | od -An -tx1 | tr -d ' \n') != 0a ]]; then
		printf '\n' >>"$dst"
	fi
}

check_content() {
	local file=$1
	grep -qvE '^[[:space:]]*(#|$)' "$file" || die "没有找到可执行的任务行: $file"
}

# 从待安装文件中提取 .php 与 .sh 的基名，检查其它 cron 配置里是否已有同名任务
duplicate_check() {
	local file=$1 patterns found=0 matches entry
	patterns=$(mktemp)
	# shellcheck disable=SC2016
	grep -vE '^[[:space:]]*(#|$)' "$file" |
		grep -oE '[^[:space:]]+\.(php|sh)' |
		while IFS= read -r entry; do basename "$entry"; done |
		sort -u >"$patterns" || true

	if [[ ! -s $patterns ]]; then
		rm -f "$patterns"
		return 0
	fi

	if command -v crontab >/dev/null 2>&1 && crontab -l >/dev/null 2>&1; then
		matches=$(crontab -l 2>/dev/null | grep -Fn -f "$patterns" || true)
		if [[ -n $matches ]]; then
			printf 'root crontab 中已存在引用下列文件的条目:\n%s\n' "$matches" >&2
			found=1
		fi
	fi

	for entry in /etc/crontab /etc/cron.d/*; do
		[[ -f $entry ]] || continue
		[[ $entry == "$TARGET_FILE" ]] && continue
		case $(basename "$entry") in .*) continue ;; esac
		matches=$(grep -Fn -f "$patterns" "$entry" 2>/dev/null || true)
		if [[ -n $matches ]]; then
			printf '文件 %s 中已存在引用下列文件的条目:\n%s\n' "$entry" "$matches" >&2
			found=1
		fi
	done

	rm -f "$patterns"

	if ((found == 0)); then
		return 0
	fi
	if ((ALLOW_EXISTING == 1)); then
		warn "存在重复条目，已按 --allow-existing 继续"
		return 0
	fi
	die "请先备份并删除上述旧条目，或使用 --allow-existing 跳过本检查"
}

backup_current() {
	local prefix=$1
	[[ -f $TARGET_FILE ]] || return 0
	mkdir -p "$BACKUP_DIR"
	cp -p "$TARGET_FILE" "$BACKUP_DIR/$prefix.$(date +%Y%m%d-%H%M%S)"
}

apply_file() {
	local file=$1
	backup_current "wp-functions"
	install -m 0644 -o root -g root "$file" "$TARGET_FILE.tmp.$$"
	mv -f "$TARGET_FILE.tmp.$$" "$TARGET_FILE"
	if command -v restorecon >/dev/null 2>&1; then
		restorecon -F "$TARGET_FILE" >/dev/null 2>&1 || true
	fi
}

verify_file() {
	local file=$1 expected actual mode
	expected=$(sha256sum "$file" | awk '{print $1}')
	actual=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
	mode=$(stat -c '%a %U %G' "$TARGET_FILE")
	[[ $expected == "$actual" ]] || die "写后校验失败：目标文件内容与源文件不一致"
	[[ $mode == "644 root root" ]] || die "写后校验失败：权限为 $mode，期望 644 root root"
}

# 内容与权限都已符合要求时不重复写入，避免备份目录堆积
is_current() {
	local file=$1 expected actual mode
	[[ -f $TARGET_FILE ]] || return 1
	expected=$(sha256sum "$file" | awk '{print $1}')
	actual=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
	[[ $expected == "$actual" ]] || return 1
	mode=$(stat -c '%a %U %G' "$TARGET_FILE")
	[[ $mode == "644 root root" ]]
}

check_file() {
	local file=$1 expected actual mode
	[[ -f $TARGET_FILE ]] || die "目标文件不存在: $TARGET_FILE"
	expected=$(sha256sum "$file" | awk '{print $1}')
	actual=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
	mode=$(stat -c '%a %U %G' "$TARGET_FILE")
	[[ $expected == "$actual" ]] || die "内容不一致: $TARGET_FILE"
	[[ $mode == "644 root root" ]] || die "权限或属主不符合要求: $mode"
	log "校验通过: $TARGET_FILE 权限 $mode"
}

remove_file() {
	[[ -f $TARGET_FILE ]] || {
		log "目标文件不存在: $TARGET_FILE"
		return 0
	}
	backup_current "wp-functions.removed"
	rm -f "$TARGET_FILE"
	log "已删除: $TARGET_FILE"
}

cron_service_check() {
	if command -v systemctl >/dev/null 2>&1; then
		systemctl is-active --quiet cron 2>/dev/null ||
			systemctl is-active --quiet crond 2>/dev/null ||
			warn "cron 服务未运行，任务不会被调度"
	elif ! pgrep -x cron >/dev/null 2>&1 && ! pgrep -x crond >/dev/null 2>&1; then
		warn "cron 进程未运行，任务不会被调度"
	fi
}

while (($# > 0)); do
	case "$1" in
	-f | --file)
		(($# >= 2)) || die "参数 $1 缺少取值"
		SOURCE_FILE=$2
		shift 2
		;;
	-t | --target)
		(($# >= 2)) || die "参数 $1 缺少取值"
		TARGET_FILE=$2
		shift 2
		;;
	--check)
		ACTION="check"
		shift
		;;
	--remove)
		ACTION="remove"
		shift
		;;
	--allow-existing)
		ALLOW_EXISTING=1
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

if [[ $ACTION == "check" && $ALLOW_EXISTING == 1 ]]; then
	die "--check 与 --allow-existing 不能同时使用"
fi

check_target_name

if [[ $ACTION == "remove" ]]; then
	require_root
	remove_file
	exit 0
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
normalize_file "$SOURCE_FILE" "$tmp"
check_content "$tmp"

if [[ $ACTION == "check" ]]; then
	check_file "$tmp"
	exit 0
fi

require_root
if is_current "$tmp"; then
	log "已是最新，跳过: $TARGET_FILE"
	exit 0
fi
duplicate_check "$tmp"
apply_file "$tmp"
verify_file "$tmp"

cron_service_check
log "安装完成: $TARGET_FILE"
