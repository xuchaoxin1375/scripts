#!/usr/bin/env bash
# 批量维护目标机上的一份受管 cron 文件，默认 /etc/cron.d/update-cron。
# 不改动现有 crontab，也不修改系统时区。
# 设计说明与使用方式见同目录的 方案.md 与 README.md。
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HOSTS_FILE="$SCRIPT_DIR/hosts.txt"
TEMPLATE_FILE=""
DRY_RUN=0
CHECK_ONLY=0
REMOVE=0
ALLOW_EXISTING=0
REQUIRED_FILES=()

REMOTE_FILE="/etc/cron.d/update-cron"
BACKUP_DIR=""
CRON_TEMPLATE_CST="$SCRIPT_DIR/cron.cst"
CRON_TEMPLATE_UTC="$SCRIPT_DIR/cron.utc"

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

在每台目标机上创建或更新一份受管 cron 文件，默认 /etc/cron.d/update-cron，不改动现有 crontab。

选项:
  -f, --hosts <文件>      主机清单，默认 hosts.txt；每行一个 SSH 目标，如 root@192.0.2.10
  -t, --template <文件>   强制指定 cron 模板；默认按目标机系统时区选择脚本目录的 cron.cst 或 cron.utc
      --target <路径>     受管文件路径，默认 /etc/cron.d/update-cron；文件名不能含点号
      --backup-dir <路径> 备份目录，默认 /var/backups/<受管文件名>
      --require <路径>    下发前要求目标机存在的文件，可重复用于预检依赖
  -n, --dry-run           只检测并打印将要执行的操作，不写入目标机
      --check             只校验目标机上的文件内容与权限，不写入
      --remove            删除目标机上的受管文件，删除前备份
      --allow-existing    允许 root crontab 或其它 cron 配置中已存在相同任务
  -h, --help              显示本帮助

环境变量:
  SSH_EXTRA_OPTS          追加给 ssh 的参数，例如 "-p 2222 -i ~/.ssh/id_ed25519"

示例:
  bash deploy.sh --template ~/wpfc/update-cron.cron --dry-run
  bash deploy.sh --template ~/wpfc/update-cron.cron
  bash deploy.sh --template ~/wpfc/update-cron.cron --check
  bash deploy.sh -f hosts-prod.txt --target /etc/cron.d/my-tasks
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

# 从模板中提取被引用脚本的基名，用于判断其它 cron 配置里是否已有相同任务
template_patterns() {
	local file=$1
	grep -vE '^[[:space:]]*(#|$)' "$file" |
		grep -oE '[^[:space:]]+\.(php|sh)' |
		while IFS= read -r entry; do basename "$entry"; done |
		sort -u
}

encode_list() {
	base64 | tr -d '\n'
}

remote_precheck() {
	local host=$1 template=$2 patterns_b64 requires_b64
	patterns_b64=$(template_patterns "$template" | encode_list)
	requires_b64=""
	if ((${#REQUIRED_FILES[@]} > 0)); then
		requires_b64=$(printf '%s\n' "${REQUIRED_FILES[@]}" | encode_list)
	fi
	# ssh 会把多个参数拼成一行再交给远端 shell 解析，空参数会直接消失；
	# 用 '-' 作为空列表的占位符，远端再还原
	patterns_b64=${patterns_b64:--}
	requires_b64=${requires_b64:--}
	# shellcheck disable=SC2029
	ssh_run "$host" bash -s -- "$ALLOW_EXISTING" "$REMOTE_FILE" "$patterns_b64" "$requires_b64" <<'REMOTE'
set -euo pipefail

allow_existing=$1
target=$2
patterns_b64=$3
requires_b64=$4
[[ $patterns_b64 == '-' ]] && patterns_b64=''
[[ $requires_b64 == '-' ]] && requires_b64=''
target_dir=$(dirname "$target")

[[ $(id -u) -eq 0 ]] || { echo "需要 root 权限" >&2; exit 1; }
[[ -d $target_dir ]] || { echo "目标目录不存在: $target_dir" >&2; exit 1; }

for cmd in install mktemp sha256sum stat base64; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "缺少命令: $cmd" >&2; exit 1; }
done

if [[ -n $requires_b64 ]]; then
  require_list=$(mktemp)
  printf '%s' "$requires_b64" | base64 -d >"$require_list"
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    [[ -f $file ]] || { rm -f "$require_list"; echo "缺少文件: $file" >&2; exit 1; }
  done <"$require_list"
  rm -f "$require_list"
fi

cron_ok=0
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet cron 2>/dev/null ||
    systemctl is-active --quiet crond 2>/dev/null ||
    systemctl is-active --quiet cronie 2>/dev/null; then
    cron_ok=1
  fi
fi
# 容器与 WSL 里 systemctl 可能存在但不是 PID 1，补一次进程判断，避免误报未运行
if [[ $cron_ok -eq 0 ]] && (pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1 || pgrep -x cronie >/dev/null 2>&1); then
  cron_ok=1
fi
if [[ $cron_ok -eq 0 ]]; then
  echo "cron 服务未运行，请先启动 cron、crond 或 cronie" >&2
  exit 1
fi

if [[ $allow_existing -eq 0 && -n $patterns_b64 ]]; then
  patterns=$(mktemp)
  printf '%s' "$patterns_b64" | base64 -d >"$patterns"

  if crontab -l >/dev/null 2>&1; then
    matches=$(crontab -l 2>/dev/null | grep -nF -f "$patterns" || true)
    if [[ -n $matches ]]; then
      echo "root crontab 中已存在引用下列脚本的条目:" >&2
      printf '%s\n' "$matches" >&2
      echo "请先备份并删除旧条目: crontab -l > ~/crontab.bak && crontab -e" >&2
      echo "确认后重新执行，或使用 --allow-existing 跳过本检查。" >&2
      rm -f "$patterns"
      exit 2
    fi
  fi

  for file in /etc/crontab /etc/cron.d/*; do
    [[ -f $file ]] || continue
    [[ $file == "$target" ]] && continue
    case $(basename "$file") in .*) continue ;; esac
    matches=$(grep -nF -f "$patterns" "$file" 2>/dev/null || true)
    if [[ -n $matches ]]; then
      echo "文件 $file 中已存在引用下列脚本的条目:" >&2
      printf '%s\n' "$matches" >&2
      echo "请先删除旧条目，或使用 --allow-existing 跳过本检查。" >&2
      rm -f "$patterns"
      exit 2
    fi
  done

  rm -f "$patterns"
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
	tmp=$(ssh_run "$host" 'mktemp /tmp/update-cron.XXXXXX' 2>/dev/null) || return 1
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
name=$(basename "$target")

[[ $(id -u) -eq 0 ]] || { echo "需要 root 权限" >&2; exit 1; }

if [[ -f $target ]]; then
  mkdir -p "$backup_dir"
  cp -p "$target" "$backup_dir/$name.$(date +%Y%m%d-%H%M%S)"
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
name=$(basename "$target")

[[ $(id -u) -eq 0 ]] || { echo "需要 root 权限" >&2; exit 1; }

if [[ -f $target ]]; then
  mkdir -p "$backup_dir"
  cp -p "$target" "$backup_dir/$name.removed.$(date +%Y%m%d-%H%M%S)"
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

	if ! remote_precheck "$host" "$template"; then
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
	--target)
		(($# >= 2)) || die "参数 $1 缺少取值"
		REMOTE_FILE=$2
		shift 2
		;;
	--backup-dir)
		(($# >= 2)) || die "参数 $1 缺少取值"
		BACKUP_DIR=$2
		shift 2
		;;
	--require)
		(($# >= 2)) || die "参数 $1 缺少取值"
		REQUIRED_FILES+=("$2")
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

[[ $REMOTE_FILE == /* ]] || die "受管文件必须是绝对路径: $REMOTE_FILE"
remote_name=$(basename "$REMOTE_FILE")
[[ $remote_name =~ ^[A-Za-z0-9_-]+$ ]] || die "受管文件名 $remote_name 含非法字符；/etc/cron.d 中带点号的文件会被 run-parts 跳过"
if [[ -z $BACKUP_DIR ]]; then
	BACKUP_DIR="/var/backups/$remote_name"
fi
[[ $BACKUP_DIR == /* ]] || die "备份目录必须是绝对路径: $BACKUP_DIR"

HOSTS_FILE=$(resolve_path "$HOSTS_FILE")
[[ -f $HOSTS_FILE ]] || die "主机清单不存在: $HOSTS_FILE（可复制 hosts.example.txt 为 hosts.txt）"

for cmd in ssh sha256sum awk sed tail head base64; do
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
