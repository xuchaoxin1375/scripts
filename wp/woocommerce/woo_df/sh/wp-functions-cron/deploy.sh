#!/usr/bin/env bash
# 批量维护目标机的 /etc/cron.d/wp-functions。
# 设计说明与使用方式见同目录的 方案.md 与 README.md。
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HOSTS_FILE="$SCRIPT_DIR/hosts.txt"
TEMPLATE_FILE=""
DRY_RUN=0
CHECK_ONLY=0
REMOVE=0
ALLOW_EXISTING=0

REMOTE_FILE="/etc/cron.d/wp-functions"
BACKUP_DIR="/var/backups/wp-functions-cron"
CRON_TEMPLATE_CST="$SCRIPT_DIR/wp-functions.cron.cst"
CRON_TEMPLATE_UTC="$SCRIPT_DIR/wp-functions.cron.utc"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)
if [[ -n ${SSH_EXTRA_OPTS:-} ]]; then
	read -r -a _extra_ssh_opts <<<"$SSH_EXTRA_OPTS"
	if ((${#_extra_ssh_opts[@]} > 0)); then
		SSH_OPTS+=("${_extra_ssh_opts[@]}")
	fi
fi

usage() {
	cat <<'EOF'
用法: bash deploy.sh [选项]

在每台目标机上创建或更新 /etc/cron.d/wp-functions，不改动现有 crontab。

选项:
  -f, --hosts <文件>      主机清单，默认 hosts.txt；每行一个 SSH 目标，如 root@192.0.2.10
  -t, --template <文件>   强制指定 cron 模板；默认按目标机系统时区自动选择
  -n, --dry-run           只检测并打印将要执行的操作，不写入目标机
      --check             只校验目标机上的文件内容与权限，不写入
      --remove            删除目标机上的 /etc/cron.d/wp-functions，删除前备份
      --allow-existing    允许 root crontab 或其它 cron.d 文件中已存在引用这两个源文件的条目
  -h, --help              显示本帮助

环境变量:
  SSH_EXTRA_OPTS          追加给 ssh 的参数，例如 "-p 2222 -i ~/.ssh/id_ed25519"

示例:
  bash deploy.sh --dry-run
  bash deploy.sh
  bash deploy.sh --check
  bash deploy.sh -f hosts-prod.txt
  bash deploy.sh --template wp-functions.cron.cst
  bash deploy.sh --remove
EOF
}

die() {
	printf '错误: %s\n' "$*" >&2
	exit 2
}

log() {
	printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

resolve_path() {
	case "$1" in
	/*) printf '%s' "$1" ;;
	*) printf '%s/%s' "$SCRIPT_DIR" "$1" ;;
	esac
}

trim_line() {
	local text=$1
	text=${text%$'\r'}
	text=${text%%#*}
	text=${text#"${text%%[![:space:]]*}"}
	text=${text%"${text##*[![:space:]]}"}
	printf '%s' "$text"
}

ssh_run() {
	# shellcheck disable=SC2029
	ssh "${SSH_OPTS[@]}" "$@"
}

remote_timezone() {
	local host=$1 tz
	tz=$(ssh_run "$host" 'if command -v timedatectl >/dev/null 2>&1; then timedatectl show -p Timezone --value 2>/dev/null || true; fi' 2>/dev/null) || return 1
	if [[ -z $tz ]]; then
		tz=$(ssh_run "$host" 'cat /etc/timezone 2>/dev/null || true' 2>/dev/null) || tz=""
	fi
	if [[ -z $tz ]]; then
		tz=$(ssh_run "$host" 'readlink -f /etc/localtime 2>/dev/null | sed "s#.*/zoneinfo/##"' 2>/dev/null) || tz=""
	fi
	tz=${tz//$'\r'/}
	tz=${tz##*$'\n'}
	[[ -n $tz ]] || return 1
	printf '%s' "$tz"
}

select_template() {
	local tz=$1
	case "$tz" in
	Asia/Shanghai | Asia/Chongqing | Asia/Harbin | PRC)
		printf '%s' "$CRON_TEMPLATE_CST"
		;;
	UTC | Etc/UTC | Etc/GMT | Etc/GMT+0 | Etc/GMT-0 | GMT | UCT | Zulu)
		printf '%s' "$CRON_TEMPLATE_UTC"
		;;
	*)
		return 1
		;;
	esac
}

remote_precheck() {
	local host=$1
	# shellcheck disable=SC2029
	ssh_run "$host" bash -s -- "$ALLOW_EXISTING" "$REMOTE_FILE" <<'REMOTE'
set -euo pipefail

allow_existing=$1
target=$2

[[ $(id -u) -eq 0 ]] || { echo "需要 root 权限" >&2; exit 1; }
[[ -d /etc/cron.d ]] || { echo "/etc/cron.d 不存在" >&2; exit 1; }

for file in /www/sh/wp-functions-update/update_wp_functions.sh /www/functions4.php /www/functions24.php; do
  [[ -f $file ]] || { echo "缺少文件: $file" >&2; exit 1; }
done

for cmd in install mktemp sha256sum stat; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "缺少命令: $cmd" >&2; exit 1; }
done

if command -v systemctl >/dev/null 2>&1; then
  if ! systemctl is-active --quiet cron 2>/dev/null &&
    ! systemctl is-active --quiet crond 2>/dev/null &&
    ! systemctl is-active --quiet cronie 2>/dev/null; then
    echo "cron 服务未运行，请先启动 cron、crond 或 cronie" >&2
    exit 1
  fi
elif ! pgrep -x cron >/dev/null 2>&1 && ! pgrep -x crond >/dev/null 2>&1; then
  echo "cron 进程未运行" >&2
  exit 1
fi

if [[ $allow_existing -eq 0 ]]; then
  if crontab -l >/dev/null 2>&1; then
    matches=$(crontab -l 2>/dev/null | grep -nE 'functions4\.php|functions24\.php' || true)
    if [[ -n $matches ]]; then
      echo "root crontab 中已存在引用 functions4.php 或 functions24.php 的条目:" >&2
      printf '%s\n' "$matches" >&2
      echo "请先备份并删除旧条目: crontab -l > ~/crontab.bak && crontab -e" >&2
      echo "确认后重新执行，或使用 --allow-existing 跳过本检查。" >&2
      exit 2
    fi
  fi

  for file in /etc/crontab /etc/cron.d/*; do
    [[ -f $file ]] || continue
    [[ $file == "$target" ]] && continue
    matches=$(grep -nE 'functions4\.php|functions24\.php' "$file" 2>/dev/null || true)
    if [[ -n $matches ]]; then
      echo "文件 $file 中已存在引用 functions4.php 或 functions24.php 的条目:" >&2
      printf '%s\n' "$matches" >&2
      echo "请先删除旧条目，或使用 --allow-existing 跳过本检查。" >&2
      exit 2
    fi
  done
fi
REMOTE
}

remote_state() {
	local host=$1
	# shellcheck disable=SC2029
	ssh_run "$host" "if [ -f '$REMOTE_FILE' ]; then sha256sum '$REMOTE_FILE'; stat -c '%a %U %G' '$REMOTE_FILE'; else echo MISSING; fi"
}

remote_matches() {
	local host=$1 template=$2 expected_hash state last_line hash mode
	expected_hash=$(sha256sum "$template" | awk '{print $1}')
	if ! state=$(remote_state "$host"); then
		printf '无法读取目标文件状态\n' >&2
		return 1
	fi
	if [[ -z $state ]]; then
		printf '无法读取目标文件状态\n' >&2
		return 1
	fi

	last_line=$(printf '%s\n' "$state" | tail -n 1)
	if [[ $last_line == MISSING ]]; then
		printf '目标文件不存在\n' >&2
		return 1
	fi

	hash=$(printf '%s\n' "$state" | tail -n 2 | head -n 1 | sed 's/ .*//')
	mode=$last_line
	if [[ $hash != "$expected_hash" ]]; then
		printf '文件内容与模板不一致\n' >&2
		return 1
	fi
	if [[ $mode != "644 root root" ]]; then
		printf '权限或属主不符合要求: %s\n' "$mode" >&2
		return 1
	fi
	return 0
}

upload_template() {
	local host=$1 template=$2 remote_tmp=$3
	# shellcheck disable=SC2029
	ssh_run "$host" "cat > '$remote_tmp'" <"$template"
}

create_remote_tmp() {
	local host=$1 tmp
	tmp=$(ssh_run "$host" 'mktemp /tmp/wp-functions-cron.XXXXXX' 2>/dev/null) || return 1
	tmp=${tmp//$'\r'/}
	tmp=${tmp##*$'\n'}
	[[ -n $tmp ]] || return 1
	printf '%s' "$tmp"
}

cleanup_remote_tmp() {
	local host=$1 remote_tmp=$2
	# shellcheck disable=SC2029
	ssh_run "$host" "rm -f '$remote_tmp'" >/dev/null 2>&1 || true
}

install_remote() {
	local host=$1 remote_tmp=$2
	# shellcheck disable=SC2029
	ssh_run "$host" bash -s -- "$remote_tmp" "$REMOTE_FILE" "$BACKUP_DIR" <<'REMOTE'
set -euo pipefail

tmp=$1
target=$2
backup_dir=$3

[[ $(id -u) -eq 0 ]] || { echo "需要 root 权限" >&2; exit 1; }

if [[ -f $target ]]; then
  mkdir -p "$backup_dir"
  cp -p "$target" "$backup_dir/wp-functions.$(date +%Y%m%d-%H%M%S)"
fi

install -m 0644 -o root -g root "$tmp" "$target.tmp.$$"
mv -f "$target.tmp.$$" "$target"
rm -f "$tmp"

if command -v restorecon >/dev/null 2>&1; then
  restorecon -F "$target" >/dev/null 2>&1 || true
fi
REMOTE
}

remove_remote() {
	local host=$1
	# shellcheck disable=SC2029
	ssh_run "$host" bash -s -- "$REMOTE_FILE" "$BACKUP_DIR" <<'REMOTE'
set -euo pipefail

target=$1
backup_dir=$2

[[ $(id -u) -eq 0 ]] || { echo "需要 root 权限" >&2; exit 1; }

if [[ -f $target ]]; then
  mkdir -p "$backup_dir"
  cp -p "$target" "$backup_dir/wp-functions.removed.$(date +%Y%m%d-%H%M%S)"
  rm -f "$target"
fi
REMOTE
}

deploy_host() {
	local host=$1 template=$2 remote_tmp
	if remote_matches "$host" "$template"; then
		log "已是最新，跳过: $host"
		return 0
	fi

	remote_tmp=""
	if ! remote_tmp=$(create_remote_tmp "$host"); then
		log "无法创建远程临时文件: $host"
		return 1
	fi
	if ! upload_template "$host" "$template" "$remote_tmp"; then
		cleanup_remote_tmp "$host" "$remote_tmp"
		log "上传失败: $host"
		return 1
	fi
	if ! install_remote "$host" "$remote_tmp"; then
		cleanup_remote_tmp "$host" "$remote_tmp"
		log "安装失败: $host"
		return 1
	fi
	if ! remote_matches "$host" "$template"; then
		log "安装后校验失败: $host"
		return 1
	fi

	log "部署成功: $host"
	return 0
}

process_host() {
	local host=$1 tz template

	if ((REMOVE)); then
		if ((DRY_RUN)); then
			log "[DRY-RUN] 将删除 $host:$REMOTE_FILE"
			return 0
		fi
		if remove_remote "$host"; then
			log "删除完成: $host:$REMOTE_FILE"
			return 0
		fi
		log "删除失败: $host"
		return 1
	fi

	if [[ -n $TEMPLATE_FILE ]]; then
		tz="forced"
		template=$TEMPLATE_FILE
	else
		if ! tz=$(remote_timezone "$host"); then
			log "无法获取系统时区: $host"
			return 1
		fi
		if ! template=$(select_template "$tz"); then
			log "不支持的时区 ${tz}（$host），请用 --template 指定模板"
			return 1
		fi
	fi

	if ((CHECK_ONLY)); then
		if remote_matches "$host" "$template"; then
			log "检查通过: $host"
			return 0
		fi
		log "检查失败: $host"
		return 1
	fi

	if ! remote_precheck "$host"; then
		log "预检失败: $host"
		return 1
	fi

	if ((DRY_RUN)); then
		if remote_matches "$host" "$template"; then
			log "[DRY-RUN] $host 时区=${tz} 模板=$(basename "$template") 状态=已是最新"
		else
			log "[DRY-RUN] $host 时区=${tz} 模板=$(basename "$template") 状态=需要更新"
		fi
		return 0
	fi

	deploy_host "$host" "$template"
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
	usage
	exit 0
fi

while (($# > 0)); do
	case "$1" in
	-f | --hosts)
		(($# >= 2)) || die "参数 $1 缺少取值"
		HOSTS_FILE=$2
		shift 2
		;;
	-t | --template)
		(($# >= 2)) || die "参数 $1 缺少取值"
		TEMPLATE_FILE=$2
		shift 2
		;;
	-n | --dry-run)
		DRY_RUN=1
		shift
		;;
	--check)
		CHECK_ONLY=1
		shift
		;;
	--remove)
		REMOVE=1
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

if ((CHECK_ONLY && REMOVE)); then
	die "--check 与 --remove 不能同时使用"
fi

HOSTS_FILE=$(resolve_path "$HOSTS_FILE")
[[ -f $HOSTS_FILE ]] || die "主机清单不存在: $HOSTS_FILE（可复制 hosts.example.txt 为 hosts.txt）"

for cmd in ssh sha256sum awk sed tail head; do
	command -v "$cmd" >/dev/null 2>&1 || die "缺少命令: $cmd"
done

if ((!REMOVE)); then
	if [[ -n $TEMPLATE_FILE ]]; then
		TEMPLATE_FILE=$(resolve_path "$TEMPLATE_FILE")
		[[ -f $TEMPLATE_FILE ]] || die "模板不存在: $TEMPLATE_FILE"
	else
		[[ -f $CRON_TEMPLATE_CST ]] || die "缺少模板: $CRON_TEMPLATE_CST"
		[[ -f $CRON_TEMPLATE_UTC ]] || die "缺少模板: $CRON_TEMPLATE_UTC"
	fi
fi

HOSTS=()
while IFS= read -r line || [[ -n $line ]]; do
	line=$(trim_line "$line")
	[[ -n $line ]] && HOSTS+=("$line")
done <"$HOSTS_FILE"

((${#HOSTS[@]} > 0)) || die "主机清单为空: $HOSTS_FILE"

total=0
success=0
failed=0

for host in "${HOSTS[@]}"; do
	total=$((total + 1))
	log "开始处理 $host"
	if process_host "$host"; then
		success=$((success + 1))
	else
		failed=$((failed + 1))
	fi
done

log "汇总: 共 ${total} 台，成功 ${success} 台，失败 ${failed} 台"

if ((failed > 0)); then
	exit 1
fi
exit 0
