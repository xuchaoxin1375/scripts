#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 脚本名称: install.sh
# 功能描述: 安装 uptime_checks 脚本、配置样例、运行目录与 /etc/cron.d 定时任务.
#           默认使用 cron,不安装 systemd 定时器;已有配置默认保留,不覆盖.
# 用法:     sudo ./install.sh [options]
# 退出码:   0 安装完成; 1 环境或参数错误; 2 用法错误
# 注意:     本文件换行必须为 LF.
# =============================================================================

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
readonly SCRIPT_DIR
readonly VERSION="20261101.01"

PREFIX="/opt/uptime_checks"
CONFIG_DIR="/etc/uptime-checks"
STATE_DIR="/var/lib/uptime-checks"
RUN_USER="uptime"
CRON_FILE="/etc/cron.d/uptime_checks_cron"
LOGROTATE_FILE="/etc/logrotate.d/uptime-checks"
LOG_FILE_OPT=""
INSTALL_CRON=true
INSTALL_LOGROTATE=true
FORCE=false
DRY_RUN=false

log() {
  printf '[%s] INFO:  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
  printf '[%s] WARN:  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
$SCRIPT_NAME [version:$VERSION] - uptime_checks 一键安装.

说明:
  安装拨测脚本、配置样例、运行目录与 /etc/cron.d 任务.
  默认每分钟以 $RUN_USER 用户执行一轮,正常输出写入运行日志.
  已有 checks.tsv、notify.env 与 maintenance.tsv 默认保留;脚本文件会更新.
  systemd 单元随仓库提供,但默认不安装;需要时按 README 手动启用.

用法:
  sudo $SCRIPT_NAME [options]

选项:
  --prefix DIR       安装目录,默认 $PREFIX
  --config-dir DIR   配置目录,默认 $CONFIG_DIR
  --state-dir DIR    状态与日志目录,默认 $STATE_DIR
  --user USER        运行用户,不存在时创建,默认 $RUN_USER
  --cron-file PATH   cron 文件,默认 $CRON_FILE
  --log PATH         运行日志,默认 <state-dir>/cron.log
  --no-cron          只安装文件与配置,不写 cron 文件
  --no-logrotate     不安装 logrotate 配置
  --force            允许覆盖已有配置与 cron 文件;notify.env 会被覆盖,慎用
  --dry-run          只打印将要执行的操作,不修改系统
  --help             显示本帮助
  --version          显示版本

退出码:
  0 安装完成;1 环境或参数错误;2 用法错误
EOF
}

while (($# > 0)); do
  case "$1" in
  --prefix)
    [[ $# -ge 2 ]] || die "--prefix 缺少参数"
    PREFIX="$2"
    shift
    ;;
  --config-dir)
    [[ $# -ge 2 ]] || die "--config-dir 缺少参数"
    CONFIG_DIR="$2"
    shift
    ;;
  --state-dir)
    [[ $# -ge 2 ]] || die "--state-dir 缺少参数"
    STATE_DIR="$2"
    shift
    ;;
  --user)
    [[ $# -ge 2 ]] || die "--user 缺少参数"
    RUN_USER="$2"
    shift
    ;;
  --cron-file)
    [[ $# -ge 2 ]] || die "--cron-file 缺少参数"
    CRON_FILE="$2"
    shift
    ;;
  --log)
    [[ $# -ge 2 ]] || die "--log 缺少参数"
    LOG_FILE_OPT="$2"
    shift
    ;;
  --no-cron)
    INSTALL_CRON=false
    ;;
  --no-logrotate)
    INSTALL_LOGROTATE=false
    ;;
  --force)
    FORCE=true
    ;;
  --dry-run)
    DRY_RUN=true
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  --version)
    printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"
    exit 0
    ;;
  *)
    usage >&2
    die "未知参数: $1"
    ;;
  esac
  shift
done

PREFIX="${PREFIX%/}"
CONFIG_DIR="${CONFIG_DIR%/}"
STATE_DIR="${STATE_DIR%/}"
LOG_FILE="${LOG_FILE_OPT:-$STATE_DIR/cron.log}"

validate_path() {
  local name="$1" value="$2"
  [[ $value =~ ^/[A-Za-z0-9._/-]+$ ]] || die "$name 必须是绝对路径,且只包含字母、数字、点、下划线、斜杠和连字符: $value"
}

validate_path "prefix" "$PREFIX"
validate_path "config-dir" "$CONFIG_DIR"
validate_path "state-dir" "$STATE_DIR"
validate_path "cron-file" "$CRON_FILE"
validate_path "log" "$LOG_FILE"
validate_path "logrotate-file" "$LOGROTATE_FILE"
[[ $RUN_USER =~ ^[a-z_][a-z0-9_-]*$ ]] || die "user 名称不合法: $RUN_USER"

run() {
  if [[ $DRY_RUN == true ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

if [[ $DRY_RUN == false && $(id -u) -ne 0 ]]; then
  die "请使用 root 执行,或先加 --dry-run 查看操作"
fi

need_cmd install
need_cmd sed
need_cmd awk
need_cmd grep
need_cmd mktemp
need_cmd date
need_cmd id
need_cmd curl
need_cmd flock
need_cmd tail
need_cmd wc
need_cmd base64
need_cmd stat
need_cmd dirname
need_cmd chmod
need_cmd chown

if [[ $INSTALL_CRON == true && ! -d /etc/cron.d ]]; then
  run install -d -m 755 /etc/cron.d
fi
if [[ $INSTALL_LOGROTATE == true && ! -d /etc/logrotate.d ]]; then
  run install -d -m 755 /etc/logrotate.d
fi

if id -u "$RUN_USER" >/dev/null 2>&1; then
  log "运行用户已存在: $RUN_USER"
else
  need_cmd useradd
  run useradd --system --home "$STATE_DIR" --shell /usr/sbin/nologin "$RUN_USER"
fi

RUN_GROUP="$(id -gn "$RUN_USER" 2>/dev/null || printf '%s' "$RUN_USER")"

run install -d -m 755 "$PREFIX"
run install -d -m 755 "$CONFIG_DIR"
run install -d -m 700 -o "$RUN_USER" -g "$RUN_GROUP" "$STATE_DIR"

run install -m 755 -o root -g root "$SCRIPT_DIR/probe.sh" "$PREFIX/probe.sh"
run install -m 755 -o root -g root "$SCRIPT_DIR/notify-email.sh" "$PREFIX/notify-email.sh"
run install -m 644 -o root -g root "$SCRIPT_DIR/README.md" "$PREFIX/README.md"

copy_example() {
  local src="$1" dest="$2" mode="$3" owner="$4" group="$5"
  if [[ -e $dest && $FORCE != true ]]; then
    warn "已存在,保留原文件: $dest"
    return 0
  fi
  run install -m "$mode" -o "$owner" -g "$group" "$src" "$dest"
}

copy_example "$SCRIPT_DIR/checks.tsv.example" "$CONFIG_DIR/checks.tsv" 644 root root
copy_example "$SCRIPT_DIR/maintenance.tsv.example" "$CONFIG_DIR/maintenance.tsv" 644 root root
copy_example "$SCRIPT_DIR/notify.env.example" "$CONFIG_DIR/notify.env" 600 "$RUN_USER" "$RUN_GROUP"

render_template() {
  local src="$1"
  sed \
    -e "s|@PREFIX@|$PREFIX|g" \
    -e "s|@CONFIG_DIR@|$CONFIG_DIR|g" \
    -e "s|@STATE_DIR@|$STATE_DIR|g" \
    -e "s|@RUN_USER@|$RUN_USER|g" \
    -e "s|@LOG@|$LOG_FILE|g" \
    "$src"
}

install_template() {
  local src="$1" dest="$2" mode="$3"
  local tmp
  if [[ -e $dest && $FORCE != true ]]; then
    warn "已存在,保留原文件: $dest"
    return 0
  fi
  tmp="$(mktemp)"
  render_template "$src" >"$tmp"
  run install -m "$mode" -o root -g root "$tmp" "$dest"
  rm -f -- "$tmp"
}

if [[ $INSTALL_CRON == true ]]; then
  cron_dir="$(dirname "$CRON_FILE")"
  [[ -d $cron_dir ]] || run install -d -m 755 "$cron_dir"
  install_template "$SCRIPT_DIR/cron/uptime_checks_cron" "$CRON_FILE" 644
fi

if [[ $INSTALL_LOGROTATE == true ]]; then
  logrotate_dir="$(dirname "$LOGROTATE_FILE")"
  [[ -d $logrotate_dir ]] || run install -d -m 755 "$logrotate_dir"
  install_template "$SCRIPT_DIR/logrotate/uptime-checks" "$LOGROTATE_FILE" 644
fi

log_dir="$(dirname "$LOG_FILE")"
[[ -d $log_dir ]] || run install -d -m 755 "$log_dir"

if [[ -e $LOG_FILE ]]; then
  run chown "$RUN_USER:$RUN_GROUP" "$LOG_FILE"
  run chmod 640 "$LOG_FILE"
else
  run install -m 640 -o "$RUN_USER" -g "$RUN_GROUP" /dev/null "$LOG_FILE"
fi

if [[ $DRY_RUN == false ]]; then
  log "安装完成"
  cat <<EOF

下一步:
- 编辑 $CONFIG_DIR/checks.tsv,替换示例目标;确认后把最后一列 enabled 改为 1.
- 编辑 $CONFIG_DIR/notify.env,填写真实 SMTP 信息.
- 测试邮件: sudo -u $RUN_USER $PREFIX/notify-email.sh --env $CONFIG_DIR/notify.env --test
- 校验配置: sudo -u $RUN_USER $PREFIX/probe.sh --config-dir $CONFIG_DIR --state-dir $STATE_DIR --check-config
- 试跑一次: sudo -u $RUN_USER $PREFIX/probe.sh --config-dir $CONFIG_DIR --state-dir $STATE_DIR --dry-run

cron:
- 定时任务已写入 $CRON_FILE,默认每分钟执行.
- 确认 cron 服务正在运行: systemctl status cron 或 systemctl status crond.
- 运行日志: $LOG_FILE
- 使用 systemd 时,不要同时启用 systemd 定时器;两者只能选一种.

注意:
- 示例 checks.tsv 默认 enabled=0,不会探测示例地址.
- 配置未完成前 cron 也会执行,但不会产生有效告警;完成后自动生效.
EOF
fi
