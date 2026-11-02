#!/usr/bin/env bash
# 安装/更新/删除反代日志清理的 /etc/cron.d 任务。
# 自动定位仓库内的 clean_reverse_server_logs.sh，并按调用者、日志目录生成任务。
# 用法见 --help。
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
readonly SCRIPT_NAME SCRIPT_DIR
readonly VERSION="20261102.01"

TARGET_FILE="/etc/cron.d/clean-reverse-logs"
RUN_USER="root"
SCHEDULE="10 0 * * *"
LOG_FILE=""
CLEANER=""
BACKUP_DIR=""
ACTION="apply"
DRY_RUN=false
LOG_DIRS=()

DEFAULT_LOG_DIRS=(/www/wwwlogs /var/log/nginx)

usage() {
	cat <<EOF
用法: sudo bash $SCRIPT_NAME [选项]

安装/更新/删除反代日志清理的 /etc/cron.d 任务。

说明:
  自动定位仓库内的 clean_reverse_server_logs.sh，生成 /etc/cron.d 任务。
  默认以 root 每天 00:10 执行，动作日志 /root/clean_log_actions.log。
  --log-dir 可重复，指定后写入 cron 命令的 --dir；不传则用清理脚本的默认目录。
  写入前检查 cron 服务、重复任务、logrotate 与日志目录，只警告不阻断。
  已有目标文件会先备份再替换；--dry-run 只预览，不写文件。

选项:
  -t, --target <路径>        cron 文件，默认 $TARGET_FILE
  -u, --user <用户|self>     任务运行用户，默认 $RUN_USER；self/caller 表示调用者
  -s, --schedule <表达式>    5 段 cron 表达式，默认 "$SCHEDULE"
  -l, --log <路径>           动作日志，默认 <任务用户家目录>/clean_log_actions.log
  -d, --log-dir <目录>       指定日志目录，可重复；指定后不再用默认目录
  -c, --cleaner <路径>       清理脚本，默认自动查找
      --backup-dir <路径>    备份目录，默认 /var/backups/<目标文件名>
      --status               只检查现状，不写文件
      --check                校验目标文件是否与生成内容一致
      --remove               备份后删除目标文件
      --dry-run              只打印将要执行的操作
  -h, --help                 显示本帮助
  -V, --version              显示版本

示例:
  sudo bash $SCRIPT_NAME
  sudo bash $SCRIPT_NAME --user www --log-dir /www/wwwlogs
  sudo bash $SCRIPT_NAME --schedule '0 0 * * *' --dry-run
  sudo bash $SCRIPT_NAME --status
  sudo bash $SCRIPT_NAME --remove

退出码:
  0 成功;1 环境或运行时错误;2 用法错误
EOF
}

die() {
	printf '错误: %s\n' "$*" >&2
	exit 1
}

usage_die() {
	usage >&2
	printf '错误: %s\n' "$*" >&2
	exit 2
}

log() {
	printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

warn() {
	printf '[%s] 警告: %s\n' "$(date '+%F %T')" "$*" >&2
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

absolute_path() {
	local path=$1 dir base resolved_dir tilde='~'
	case "$path" in
	"$tilde") path=${HOME:-} ;;
	"$tilde/"*) path="${HOME:-}/${path#"$tilde/"}" ;;
	esac
	[[ $path == /* ]] || path="$PWD/$path"
	dir=$(dirname -- "$path")
	base=$(basename -- "$path")
	if [[ -d $dir ]]; then
		if resolved_dir=$(cd -- "$dir" 2>/dev/null && pwd -P); then
			dir=$resolved_dir
		fi
	fi
	printf '%s/%s\n' "${dir%/}" "$base"
}

absolute_existing_file() {
	local path=$1 dir resolved_dir tilde='~'
	case "$path" in
	"$tilde") path=${HOME:-} ;;
	"$tilde/"*) path="${HOME:-}/${path#"$tilde/"}" ;;
	esac
	[[ $path == /* ]] || path="$PWD/$path"
	[[ -f $path ]] || return 1
	dir=$(dirname -- "$path")
	if resolved_dir=$(cd -- "$dir" 2>/dev/null && pwd -P); then
		dir=$resolved_dir
	fi
	printf '%s/%s\n' "${dir%/}" "$(basename -- "$path")"
}

find_repo_root() {
	local dir=$1
	while [[ $dir != "/" ]]; do
		if [[ -e $dir/.git ]]; then
			printf '%s\n' "$dir"
			return 0
		fi
		dir=$(dirname -- "$dir")
	done
	return 1
}

default_cleaner() {
	local repo_root candidate
	if repo_root=$(find_repo_root "$SCRIPT_DIR"); then
		candidate="$repo_root/wp/woocommerce/woo_df/sh/clean_reverse_server_logs.sh"
		if [[ -f $candidate ]]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	fi
	for candidate in \
		"$SCRIPT_DIR/../../../clean_reverse_server_logs.sh" \
		"$SCRIPT_DIR/clean_reverse_server_logs.sh" \
		"${HOME:-}/sh/clean_reverse_server_logs.sh"; do
		if [[ -f $candidate ]]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

get_user_home() {
	local user=$1
	if command -v getent >/dev/null 2>&1; then
		getent passwd "$user" | cut -d: -f6
	else
		awk -F: -v u="$user" '$1 == u { print $6; exit }' /etc/passwd
	fi
}

validate_schedule() {
	local schedule=$1 field
	local -a fields=()
	read -r -a fields <<<"$schedule" || true
	((${#fields[@]} == 5)) || die "计划表达式必须是 5 段: $schedule"
	for field in "${fields[@]}"; do
		[[ $field =~ ^[A-Za-z0-9*/,_-]+$ ]] || die "计划表达式含非法字符: $field"
	done
}

validate_cron_safe_path() {
	local value=$1
	[[ $value != *"'"* ]] || die "路径包含单引号，无法写入 cron: $value"
	[[ $value != *$'\n'* ]] || die "路径包含换行，无法写入 cron: $value"
}

shell_quote() {
	printf "'%s'" "$1"
}

can_write_as_run_user() {
	local path=$1
	if [[ $RUN_USER == "root" ]]; then
		[[ -w $path ]]
		return
	fi
	if [[ $(id -u) -ne 0 ]]; then
		return 0
	fi
	if command -v runuser >/dev/null 2>&1; then
		runuser -u "$RUN_USER" -- test -w "$path"
	elif command -v sudo >/dev/null 2>&1; then
		sudo -u "$RUN_USER" test -w "$path"
	else
		return 0
	fi
}

cron_service_state() {
	if command -v systemctl >/dev/null 2>&1; then
		if systemctl is-active --quiet cron 2>/dev/null; then
			printf 'cron(active)'
			return
		fi
		if systemctl is-active --quiet crond 2>/dev/null; then
			printf 'crond(active)'
			return
		fi
	fi
	if command -v pgrep >/dev/null 2>&1; then
		if pgrep -x cron >/dev/null 2>&1; then
			printf 'cron(active)'
			return
		fi
		if pgrep -x crond >/dev/null 2>&1; then
			printf 'crond(active)'
			return
		fi
	fi
	printf '未运行'
}

check_log_dirs() {
	local -a dirs=()
	local explicit=false found=false dir
	if (($# > 0)); then
		dirs=("$@")
		explicit=true
	else
		dirs=("${DEFAULT_LOG_DIRS[@]}")
	fi
	for dir in "${dirs[@]}"; do
		if [[ ! -d $dir ]]; then
			if [[ $explicit == true ]]; then
				warn "日志目录不存在: $dir"
			else
				log "日志目录不存在(将跳过): $dir"
			fi
			continue
		fi
		log "日志目录存在: $dir"
		found=true
		if ! can_write_as_run_user "$dir"; then
			warn "运行用户 $RUN_USER 对 $dir 没有写权限，truncate 会失败"
		fi
	done
	[[ $found == true ]] || warn "未找到任何日志目录；如果 nginx 用了自定义 -l，请用 --log-dir 指定"
}

check_logrotate() {
	local pattern
	local -a patterns=()
	if ((${#LOG_DIRS[@]} > 0)); then
		patterns=("${LOG_DIRS[@]}")
	else
		patterns=("${DEFAULT_LOG_DIRS[@]}")
	fi
	for pattern in "${patterns[@]}"; do
		if grep -Rqs -- "$pattern" /etc/logrotate.d/ 2>/dev/null; then
			warn "检测到 logrotate 配置包含 $pattern；不要同时用本 cron 清同一批日志"
		fi
	done
}

check_duplicates() {
	local needle line file found=false
	needle=$(basename "$CLEANER")
	if command -v crontab >/dev/null 2>&1; then
		while IFS= read -r line; do
			[[ $line == *"$needle"* ]] || continue
			warn "用户 crontab($RUN_USER) 已引用 $needle: $line"
			found=true
		done < <(crontab -l -u "$RUN_USER" 2>/dev/null || true)
	fi
	for file in /etc/crontab /etc/cron.d/*; do
		[[ -f $file ]] || continue
		if [[ $file == "$TARGET_FILE" ]]; then
			continue
		fi
		while IFS= read -r line; do
			[[ $line == *"$needle"* ]] || continue
			warn "$file 已引用 $needle: $line"
			found=true
		done < <(grep -nF -- "$needle" "$file" 2>/dev/null || true)
	done
	if [[ $found == false ]]; then
		log "未发现重复引用"
	fi
}

print_context() {
	local state
	state=$(cron_service_state)
	log "调用者: $INVOKER_DESC"
	log "清理脚本: $CLEANER"
	log "任务用户: $RUN_USER"
	log "计划: $SCHEDULE"
	log "目标文件: $TARGET_FILE"
	log "动作日志: $LOG_FILE"
	log "cron 服务: $state"
	if [[ $state == "未运行" ]]; then
		warn "cron 服务未运行，任务不会被调度"
	fi
}

run_log_dir_checks() {
	if ((${#LOG_DIRS[@]} > 0)); then
		check_log_dirs "${LOG_DIRS[@]}"
	else
		check_log_dirs
	fi
}

render_cron() {
	local cmd dir
	cmd="/bin/bash $(shell_quote "$CLEANER")"
	if ((${#LOG_DIRS[@]} > 0)); then
		for dir in "${LOG_DIRS[@]}"; do
			cmd+=" --dir $(shell_quote "$dir")"
		done
	fi
	cat <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
# managed by $SCRIPT_NAME
# 清理反代 access/error 日志;truncate 不需要 reload nginx
$SCHEDULE $RUN_USER $cmd >> $(shell_quote "$LOG_FILE") 2>&1
EOF
}

normalize_cron() {
	local file=$1
	[[ -s $file ]] || die "生成内容为空"
	grep -qvE '^[[:space:]]*(#|$)' "$file" || die "生成内容没有任务行: $file"
	if [[ $(tail -c 1 "$file" | od -An -tx1 | tr -d ' \n') != 0a ]]; then
		printf '\n' >>"$file"
	fi
}

is_current() {
	local tmp=$1
	[[ -f $TARGET_FILE ]] || return 1
	cmp -s "$tmp" "$TARGET_FILE" || return 1
	[[ $(stat -c '%a %U %G' "$TARGET_FILE") == "644 root root" ]]
}

backup_target() {
	local prefix=$1 dest
	if [[ ! -f $TARGET_FILE ]]; then
		return 0
	fi
	if [[ $DRY_RUN == true ]]; then
		return 0
	fi
	install -d -m 755 "$BACKUP_DIR"
	dest="$BACKUP_DIR/$prefix.$(date +%Y%m%d-%H%M%S).$$"
	cp -p "$TARGET_FILE" "$dest"
	log "已备份: $dest"
}

verify_target() {
	local tmp=$1 expected actual mode
	expected=$(sha256sum "$tmp" | awk '{print $1}')
	actual=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
	[[ $expected == "$actual" ]] || die "写后校验失败: 内容不一致"
	mode=$(stat -c '%a %U %G' "$TARGET_FILE")
	[[ $mode == "644 root root" ]] || die "写后校验失败: 权限为 $mode，期望 644 root root"
}

remove_cron() {
	if [[ ! -f $TARGET_FILE ]]; then
		log "目标文件不存在: $TARGET_FILE"
		return 0
	fi
	if [[ $DRY_RUN == true ]]; then
		log "[dry-run] 将删除: $TARGET_FILE"
		return 0
	fi
	backup_target "$(basename "$TARGET_FILE").removed"
	rm -f "$TARGET_FILE"
	log "已删除: $TARGET_FILE"
}

while (($# > 0)); do
	case "$1" in
	-t | --target)
		(($# >= 2)) || usage_die "参数 $1 缺少取值"
		TARGET_FILE=$2
		shift 2
		;;
	-u | --user)
		(($# >= 2)) || usage_die "参数 $1 缺少取值"
		RUN_USER=$2
		shift 2
		;;
	-s | --schedule)
		(($# >= 2)) || usage_die "参数 $1 缺少取值"
		SCHEDULE=$2
		shift 2
		;;
	-l | --log)
		(($# >= 2)) || usage_die "参数 $1 缺少取值"
		LOG_FILE=$2
		shift 2
		;;
	-d | --log-dir)
		(($# >= 2)) || usage_die "参数 $1 缺少取值"
		LOG_DIRS+=("$2")
		shift 2
		;;
	-c | --cleaner)
		(($# >= 2)) || usage_die "参数 $1 缺少取值"
		CLEANER=$2
		shift 2
		;;
	--backup-dir)
		(($# >= 2)) || usage_die "参数 $1 缺少取值"
		BACKUP_DIR=$2
		shift 2
		;;
	--status)
		ACTION="status"
		shift
		;;
	--check)
		ACTION="check"
		shift
		;;
	--remove | --uninstall)
		ACTION="remove"
		shift
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	-V | --version)
		printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"
		exit 0
		;;
	*)
		usage_die "未知参数: $1"
		;;
	esac
done

for cmd in bash cmp cp cut date dirname basename grep id install mktemp mv od stat tail tr sha256sum awk; do
	need_cmd "$cmd"
done

if [[ $RUN_USER == "self" || $RUN_USER == "caller" ]]; then
	RUN_USER="${SUDO_USER:-$(id -un)}"
fi

[[ $RUN_USER =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || die "任务用户名不合法: $RUN_USER"
id -u "$RUN_USER" >/dev/null 2>&1 || die "任务用户不存在: $RUN_USER"

validate_schedule "$SCHEDULE"

if [[ -z $CLEANER ]]; then
	CLEANER="$(default_cleaner)" || die "未找到 clean_reverse_server_logs.sh，请用 --cleaner 指定"
fi
resolved_cleaner="$(absolute_existing_file "$CLEANER")" || die "清理脚本不存在: $CLEANER"
CLEANER="$resolved_cleaner"
[[ -r $CLEANER ]] || die "清理脚本不可读: $CLEANER"
bash -n "$CLEANER" || die "清理脚本语法检查失败: $CLEANER"

TARGET_FILE="$(absolute_path "$TARGET_FILE")"
target_name="$(basename "$TARGET_FILE")"
[[ $target_name =~ ^[A-Za-z0-9_-]+$ ]] || die "目标文件名 $target_name 含非法字符；/etc/cron.d 中带点号的文件会被忽略"
[[ ! -L $TARGET_FILE ]] || die "目标是符号链接，拒绝覆盖: $TARGET_FILE"
if [[ -e $TARGET_FILE && ! -f $TARGET_FILE ]]; then
	die "目标不是普通文件，拒绝覆盖: $TARGET_FILE"
fi
if [[ $(dirname "$TARGET_FILE") != "/etc/cron.d" ]]; then
	warn "目标文件不在 /etc/cron.d，cron 可能不会自动加载: $TARGET_FILE"
fi

if [[ -z $LOG_FILE ]]; then
	user_home="$(get_user_home "$RUN_USER")"
	[[ -n $user_home ]] || die "无法取得用户 $RUN_USER 的家目录"
	LOG_FILE="$user_home/clean_log_actions.log"
fi
LOG_FILE="$(absolute_path "$LOG_FILE")"
[[ ! -d $LOG_FILE ]] || die "动作日志路径是目录: $LOG_FILE"
log_parent="$(dirname "$LOG_FILE")"
[[ -d $log_parent ]] || die "动作日志目录不存在: $log_parent"
if ! can_write_as_run_user "$log_parent"; then
	warn "运行用户 $RUN_USER 对动作日志目录 $log_parent 没有写权限，cron 输出会丢失"
fi

if [[ -z $BACKUP_DIR ]]; then
	BACKUP_DIR="/var/backups/$target_name"
fi
BACKUP_DIR="$(absolute_path "$BACKUP_DIR")"

if ((${#LOG_DIRS[@]} > 0)); then
	for i in "${!LOG_DIRS[@]}"; do
		LOG_DIRS[i]="$(absolute_path "${LOG_DIRS[i]}")"
	done
fi

validate_cron_safe_path "$CLEANER"
validate_cron_safe_path "$LOG_FILE"
if ((${#LOG_DIRS[@]} > 0)); then
	for log_dir in "${LOG_DIRS[@]}"; do
		validate_cron_safe_path "$log_dir"
	done
fi

INVOKER="$(id -un)"
if [[ -n ${SUDO_USER:-} && ${SUDO_USER:-} != "root" ]]; then
	INVOKER_DESC="sudo 调用者 ${SUDO_USER}(有效用户 root)"
else
	INVOKER_DESC="$INVOKER"
fi

if [[ $RUN_USER != "root" ]]; then
	warn "任务用户不是 root；请确认 $RUN_USER 对日志目录有写权限，否则 truncate 会失败"
fi

if [[ $ACTION == "apply" || $ACTION == "remove" ]]; then
	if [[ $DRY_RUN != true && $(id -u) -ne 0 ]]; then
		die "写入 $TARGET_FILE 需要 root 权限；请使用 sudo，或加 --dry-run 预览"
	fi
fi

case "$ACTION" in
status)
	print_context
	run_log_dir_checks
	check_logrotate
	check_duplicates
	if [[ -f $TARGET_FILE ]]; then
		log "目标权限: $(stat -c '%a %U %G' "$TARGET_FILE")"
		printf '%s\n' '--- 目标内容 ---'
		cat "$TARGET_FILE" 2>/dev/null || warn "无法读取目标文件"
	else
		warn "目标文件不存在: $TARGET_FILE"
	fi
	;;
check)
	tmp="$(mktemp)"
	trap 'rm -f "${tmp:-}" "${tmp_target:-}"' EXIT
	render_cron >"$tmp"
	normalize_cron "$tmp"
	if [[ ! -f $TARGET_FILE ]]; then
		warn "目标文件不存在: $TARGET_FILE"
		exit 1
	fi
	if ! cmp -s "$tmp" "$TARGET_FILE"; then
		warn "目标内容与生成内容不一致: $TARGET_FILE"
		if command -v diff >/dev/null 2>&1; then
			diff -u "$TARGET_FILE" "$tmp" || true
		fi
		exit 1
	fi
	mode="$(stat -c '%a %U %G' "$TARGET_FILE")"
	if [[ $mode != "644 root root" ]]; then
		warn "目标权限不符合要求: $mode(期望 644 root root)"
		exit 1
	fi
	log "校验通过: $TARGET_FILE"
	;;
remove)
	print_context
	remove_cron
	;;
apply)
	print_context
	run_log_dir_checks
	check_logrotate
	check_duplicates

	tmp="$(mktemp)"
	tmp_target="$TARGET_FILE.tmp.$$"
	trap 'rm -f "${tmp:-}" "${tmp_target:-}"' EXIT
	render_cron >"$tmp"
	normalize_cron "$tmp"

	if [[ $DRY_RUN == true ]]; then
		log "[dry-run] 将写入: $TARGET_FILE"
		cat "$tmp"
		exit 0
	fi

	target_dir="$(dirname "$TARGET_FILE")"
	if [[ ! -d $target_dir ]]; then
		install -d -m 755 "$target_dir"
	fi
	if is_current "$tmp"; then
		log "已是最新，跳过: $TARGET_FILE"
		exit 0
	fi
	backup_target "$target_name"
	install -m 0644 -o root -g root "$tmp" "$tmp_target"
	mv -f "$tmp_target" "$TARGET_FILE"
	if command -v restorecon >/dev/null 2>&1; then
		restorecon -F "$TARGET_FILE" >/dev/null 2>&1 || true
	fi
	verify_target "$tmp"
	log "已写入: $TARGET_FILE"
	;;
esac
