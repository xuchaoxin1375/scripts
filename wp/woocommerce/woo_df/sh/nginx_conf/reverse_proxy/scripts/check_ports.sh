#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 脚本名称: check_ports.sh
# 功能描述: 检查反向代理服务器常用端口的本地监听状态与防火墙放行状态,定位阻断点.
#           可选修复模式尝试放行端口.兼容主流 Linux 发行版,自动检测防火墙后端.
# 用法:     ./check_ports.sh [options] [port ...]
# 示例:     ./check_ports.sh --ports 80,443
#           ./check_ports.sh --fix --ports 80,443
#           source ./check_ports.sh; is_port_listening 80 tcp
# 退出码:   0 全部通过; 1 发现阻断或状态未知; 2 用法错误
# 被引用的稳定接口: is_port_listening, is_firewall_open, ensure_firewall_port,
#           detect_firewall_backend, check_single_port (详见 usage).
# 注意:     本文件换行必须为 LF.在 Windows 上编辑后请确认未转为 CRLF,
#           否则在 Linux 上执行将报告 $'\r': command not found.
# =============================================================================

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
readonly SCRIPT_NAME
readonly VERSION="20260926.02"
readonly DEFAULT_PORTS="80,443"
readonly DEFAULT_PROTO="tcp"
readonly DEFAULT_ZONE="public"

PROTO="$DEFAULT_PROTO"
PORTS=()
PORTS_ARG=""
BACKEND="auto"
ZONE="$DEFAULT_ZONE"
FIX_MODE=false
DRY_RUN=false
QUIET=false
JSON_OUTPUT=false
DETECTED_BACKEND="none"
TOTAL_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
JSON_ENTRIES=()
TMP_WORK=""
SYSTEM_HOSTNAME=""
SYSTEM_OS=""
SYSTEM_KERNEL=""
SYSTEM_ARCH=""

log() {
  local msg
  msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  if [[ $QUIET == true || $JSON_OUTPUT == true ]]; then
    printf '[%s] INFO:  %s\n' "$ts" "$msg" >&2
  else
    printf '[%s] INFO:  %s\n' "$ts" "$msg"
  fi
}

warn() {
  local msg
  msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] WARN:  %s\n' "$ts" "$msg" >&2
}

die() {
  local msg
  msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] ERROR: %s\n' "$ts" "$msg" >&2
  exit 1
}

cleanup() {
  if [[ -n ${TMP_WORK:-} && -d $TMP_WORK ]]; then
    rm -rf "$TMP_WORK"
  fi
}

collect_system_info() {
  SYSTEM_HOSTNAME="$(uname -n 2>/dev/null || printf 'unknown')"
  SYSTEM_KERNEL="$(uname -sr 2>/dev/null || printf 'unknown')"
  SYSTEM_ARCH="$(uname -m 2>/dev/null || printf 'unknown')"
  SYSTEM_OS=""
  if [[ -r /etc/os-release ]]; then
    SYSTEM_OS="$(sed -n 's/^PRETTY_NAME="\(.*\)"$/\1/p' /etc/os-release)"
  fi
  if [[ -z $SYSTEM_OS && -f /etc/arch-release ]]; then
    SYSTEM_OS="Arch Linux"
  fi
  if [[ -z $SYSTEM_OS ]]; then
    SYSTEM_OS="$(uname -s 2>/dev/null || printf 'unknown')"
  fi
  SYSTEM_OS="${SYSTEM_OS//\"/}"
  SYSTEM_HOSTNAME="${SYSTEM_HOSTNAME:-unknown}"
  SYSTEM_OS="${SYSTEM_OS:-unknown}"
  SYSTEM_KERNEL="${SYSTEM_KERNEL:-unknown}"
  SYSTEM_ARCH="${SYSTEM_ARCH:-unknown}"
}

print_system_info() {
  log "系统信息: 主机=${SYSTEM_HOSTNAME} | 系统=${SYSTEM_OS}"
  log "系统信息: 内核=${SYSTEM_KERNEL} | 架构=${SYSTEM_ARCH} | 防火墙后端=${DETECTED_BACKEND}"
}

usage() {
  cat <<EOF
$SCRIPT_NAME [version:$VERSION] - 反向代理服务器端口与防火墙检查.

说明:
  检查指定端口的本地监听状态与防火墙放行状态,定位阻断点.
  默认检查 $DEFAULT_PORTS (协议 $DEFAULT_PROTO).
  若服务器仅承担 HTTP 入口(例如 Cloudflare Flexible 模式),请使用 --ports 80.
  检查前先输出系统基本信息(主机/系统/内核/架构/防火墙后端):
  --quiet 时省略;--json 时日志走 stderr,并以 system 字段嵌入 JSON 结果.

用法:
  $SCRIPT_NAME [options] [port ...]

选项:
  -p, --ports <list>        端口列表,逗号或空格分隔,例如 "80,443".也可使用位置参数直接给出.
  --proto <tcp|udp>         检测协议,默认 $DEFAULT_PROTO.环境变量 CHECK_PROTO 可设置默认值.
  --backend <name>          防火墙后端:auto(默认,自动检测) | firewalld | ufw | iptables | nft.
  --zone <zone>             firewalld zone,默认 $DEFAULT_ZONE.
  --fix                     防火墙未放行时尝试放行(需 root 权限;状态未知时不处理).
  --no-fix                  仅检查,不修复(默认).
  --dry-run                 仅预览修复命令,不实际执行.可与 --fix 联用.
  -q, --quiet               精简输出,仅打印一行汇总,调用方以退出码判断.
  --json                    以 JSON 输出结果到 stdout,含 system 字段(日志改走 stderr,便于管道解析).
  -h, --help                显示本帮助并退出.
  --version                 显示版本号并退出.

位置参数:
  port ...                  一个或多个端口,可为 "80" 或 "80,443" 形式.与 --ports 合并去重.

环境变量:
  CHECK_PORTS               未传参时的默认端口列表.命令行参数优先.
  CHECK_PROTO               未传参时的默认协议.命令行参数优先.

退出码:
  0   全部端口监听正常且防火墙已放行.
  1   存在未监听,防火墙未放行或状态未知的端口.
  2   用法错误(参数非法,端口非法).

示例:
  $SCRIPT_NAME --ports 80,443
  $SCRIPT_NAME 80 443 --backend ufw
  $SCRIPT_NAME --fix --ports 80,443
  $SCRIPT_NAME --fix --dry-run --ports 80,443
  $SCRIPT_NAME --quiet --ports 80; echo \$?
  $SCRIPT_NAME --json --ports 80,443

被其他脚本调用:
  引用后仅加载函数,不执行检查.以下为稳定接口:
    is_port_listening <port> [proto]  返回 0 已监听 / 1 未监听 / 2 未知
    is_firewall_open <port> [proto]   返回 0 已放行 / 1 未放行 / 2 未知
    ensure_firewall_port <port> [proto] 需 FIX_MODE=true;尝试放行并返回结果
    detect_firewall_backend [auto|name] 输出后端名称,并设置 DETECTED_BACKEND
  source ./check_ports.sh
  FIX_MODE=true
  ensure_firewall_port 80 tcp || echo "放行失败" >&2

注意:
  本文件换行必须为 LF.在 Windows 上编辑后请确认未转为 CRLF,否则在 Linux 上无法执行.
EOF
}

usage_error() {
  local msg
  msg="$1"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] ERROR: %s\n' "$ts" "$msg" >&2
  usage >&2
  exit 2
}

check_dependencies() {
  local deps
  deps=("awk" "grep" "sed" "date")
  local dep
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      die "缺少依赖: ${dep},请先安装"
    fi
  done
  if ! command -v ss >/dev/null 2>&1 &&
    ! command -v netstat >/dev/null 2>&1 &&
    ! command -v lsof >/dev/null 2>&1; then
    warn "未检测到 ss, netstat 或 lsof,监听检查将降级为 bash 内建探测,建议安装 iproute2."
  fi
}

is_valid_port() {
  local candidate
  candidate="$1"
  if [[ ! $candidate =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if ((10#$candidate < 1 || 10#$candidate > 65535)); then
    return 1
  fi
  return 0
}

add_ports_from_string() {
  local raw
  raw="$1"
  local normalized
  normalized="${raw//,/ }"
  local parts
  parts=()
  read -r -a parts <<<"$normalized" || true
  if ((${#parts[@]} == 0)); then
    return 0
  fi
  local p
  for p in "${parts[@]}"; do
    [[ -n $p ]] || continue
    PORTS+=("$p")
  done
}

finalize_ports() {
  local uniq
  uniq=" "
  local uniq_list
  uniq_list=()
  local p
  if ((${#PORTS[@]} > 0)); then
    for p in "${PORTS[@]}"; do
      if ! is_valid_port "$p"; then
        usage_error "端口非法: [${p}],应为 1-65535 的整数"
      fi
      p="$((10#$p))"
      if [[ $uniq != *" ${p} "* ]]; then
        uniq_list+=("$p")
        uniq+=" ${p} "
      fi
    done
  fi
  PORTS=()
  if ((${#uniq_list[@]} > 0)); then
    local q
    for q in "${uniq_list[@]}"; do
      PORTS+=("$q")
    done
  fi
  if ((${#PORTS[@]} == 0)); then
    usage_error "未指定任何有效端口"
  fi
}

validate_proto() {
  case "$PROTO" in
    tcp | udp) return 0 ;;
    *) usage_error "--proto 非法: [${PROTO}],可选 tcp|udp" ;;
  esac
}

validate_backend() {
  case "$BACKEND" in
    auto | firewalld | ufw | iptables | nft) return 0 ;;
    *) usage_error "--backend 非法: [${BACKEND}],可选 auto|firewalld|ufw|iptables|nft" ;;
  esac
}

validate_zone() {
  if [[ ! $ZONE =~ ^[A-Za-z0-9_.-]+$ ]]; then
    usage_error "--zone 非法: [${ZONE}]"
  fi
}

detect_firewall_backend() {
  local requested
  requested="${1:-auto}"
  if [[ $requested != "auto" ]]; then
    DETECTED_BACKEND="$requested"
    printf '%s\n' "$DETECTED_BACKEND"
    return 0
  fi
  if command -v firewall-cmd >/dev/null 2>&1 &&
    firewall-cmd --state >/dev/null 2>&1; then
    DETECTED_BACKEND="firewalld"
  elif command -v ufw >/dev/null 2>&1 &&
    ufw status 2>/dev/null | grep -qE 'Status:[[:space:]]*active'; then
    DETECTED_BACKEND="ufw"
  elif command -v nft >/dev/null 2>&1 &&
    nft list ruleset >/dev/null 2>&1; then
    DETECTED_BACKEND="nft"
  elif command -v iptables >/dev/null 2>&1; then
    DETECTED_BACKEND="iptables"
  else
    DETECTED_BACKEND="none"
  fi
  printf '%s\n' "$DETECTED_BACKEND"
}

is_port_listening() {
  local port
  port="$1"
  local proto
  proto="${2:-$DEFAULT_PROTO}"
  if ! is_valid_port "$port"; then
    return 2
  fi
  if [[ $proto != "tcp" && $proto != "udp" ]]; then
    return 2
  fi
  if command -v ss >/dev/null 2>&1; then
    local ss_opt
    ss_opt="-ltn"
    if [[ $proto == "udp" ]]; then
      ss_opt="-lun"
    fi
    local ss_out
    ss_out="$(ss "$ss_opt" 2>/dev/null || true)"
    if printf '%s\n' "$ss_out" | grep -qE "[:.]${port}([[:space:]]|$)"; then
      return 0
    fi
    return 1
  fi
  if command -v netstat >/dev/null 2>&1; then
    local ns_opt
    ns_opt="-ltn"
    if [[ $proto == "udp" ]]; then
      ns_opt="-lun"
    fi
    local ns_out
    ns_out="$(netstat "$ns_opt" 2>/dev/null || true)"
    if printf '%s\n' "$ns_out" | grep -qE "[:.]${port}([[:space:]]|$)"; then
      return 0
    fi
    return 1
  fi
  if command -v lsof >/dev/null 2>&1; then
    if [[ $proto == "udp" ]]; then
      if lsof -nP -i"udp:${port}" >/dev/null 2>&1; then
        return 0
      fi
    else
      if lsof -nP -i"tcp:${port}" -sTCP:LISTEN >/dev/null 2>&1; then
        return 0
      fi
    fi
    return 1
  fi
  if [[ $proto == "tcp" ]]; then
    if (exec 3<>"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi
  return 2
}

fw_check_firewalld() {
  local port
  port="$1"
  local proto
  proto="$2"
  if ! command -v firewall-cmd >/dev/null 2>&1; then
    return 2
  fi
  if ! firewall-cmd --state >/dev/null 2>&1; then
    return 2
  fi
  if firewall-cmd --zone="$ZONE" --query-port="${port}/${proto}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

fw_check_ufw() {
  local port
  port="$1"
  local proto
  proto="$2"
  local st
  if ! st="$(ufw status 2>/dev/null)"; then
    return 2
  fi
  if ! printf '%s\n' "$st" | grep -qE 'Status:[[:space:]]*active'; then
    return 2
  fi
  if printf '%s\n' "$st" | grep -qE "^${port}/${proto}[[:space:]]+ALLOW"; then
    return 0
  fi
  if printf '%s\n' "$st" | grep -qE "^${port}[[:space:]]+ALLOW"; then
    return 0
  fi
  return 1
}

fw_check_iptables() {
  local port
  port="$1"
  local proto
  proto="$2"
  if ! command -v iptables >/dev/null 2>&1; then
    return 2
  fi
  if iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1; then
    return 0
  fi
  local rules
  if ! rules="$(iptables -S 2>/dev/null)"; then
    return 2
  fi
  if printf '%s\n' "$rules" | grep -qE -- "-p[[:space:]]+${proto}.*--dport[[:space:]]+${port}.*-j[[:space:]]+ACCEPT"; then
    return 0
  fi
  local policy
  policy="$(printf '%s\n' "$rules" | awk '/^-P INPUT/ {print $3}')"
  if [[ $policy == "ACCEPT" ]]; then
    if printf '%s\n' "$rules" | grep -qE -- "--dport[[:space:]]+${port}.*-j[[:space:]]+(DROP|REJECT)"; then
      return 1
    fi
    return 0
  fi
  return 1
}

fw_check_nft() {
  local port
  port="$1"
  local proto
  proto="$2"
  if ! command -v nft >/dev/null 2>&1; then
    return 2
  fi
  local rs
  if ! rs="$(nft list ruleset 2>/dev/null)"; then
    return 2
  fi
  if printf '%s\n' "$rs" | grep -qE "${proto}[[:space:]]+dport[[:space:]]+${port}[[:space:]]+.*accept"; then
    return 0
  fi
  if printf '%s\n' "$rs" | grep -qE -- "${proto}[[:space:]]+dport[[:space:]]+${port}[[:space:]]+.*(drop|reject)"; then
    return 1
  fi
  # 未配置任何 input 钩子(例如 Arch 系出厂未启用 nftables 过滤)时,视为无阻断.
  if ! printf '%s\n' "$rs" | grep -qE 'hook[[:space:]]+input'; then
    return 0
  fi
  # 无端口级拒绝时,按 input 链策略判定:accept 视为放行,drop/reject 视为未放行.
  local policy
  policy="$(printf '%s\n' "$rs" |
    awk '/hook[ \t]+input/ {for (i=1; i<=NF; i++) if ($i=="policy") {gsub(/;/,"",$(i+1)); print $(i+1); exit}}')"
  if [[ $policy == "accept" ]]; then
    return 0
  fi
  return 1
}

is_firewall_open() {
  local port
  port="$1"
  local proto
  proto="${2:-$DEFAULT_PROTO}"
  if ! is_valid_port "$port"; then
    return 2
  fi
  local backend
  backend="$DETECTED_BACKEND"
  case "$backend" in
    firewalld) fw_check_firewalld "$port" "$proto" ;;
    ufw) fw_check_ufw "$port" "$proto" ;;
    iptables) fw_check_iptables "$port" "$proto" ;;
    nft) fw_check_nft "$port" "$proto" ;;
    *) return 2 ;;
  esac
}

fw_open_firewalld() {
  local port
  port="$1"
  local proto
  proto="$2"
  if [[ $DRY_RUN == true ]]; then
    log "DRY-RUN: firewall-cmd --permanent --zone=${ZONE} --add-port=${port}/${proto} && firewall-cmd --reload"
    return 1
  fi
  if [[ $EUID -ne 0 ]]; then
    warn "放行 ${port}/${proto} 需要 root 权限,请使用 sudo 执行."
    return 1
  fi
  if firewall-cmd --permanent --zone="$ZONE" --add-port="${port}/${proto}" >&2 &&
    firewall-cmd --reload >&2; then
    return 0
  fi
  return 1
}

fw_open_ufw() {
  local port
  port="$1"
  local proto
  proto="$2"
  if [[ $DRY_RUN == true ]]; then
    log "DRY-RUN: ufw allow ${port}/${proto}"
    return 1
  fi
  if [[ $EUID -ne 0 ]]; then
    warn "放行 ${port}/${proto} 需要 root 权限,请使用 sudo 执行."
    return 1
  fi
  if ufw allow "${port}/${proto}" >&2; then
    return 0
  fi
  return 1
}

fw_open_iptables() {
  local port
  port="$1"
  local proto
  proto="$2"
  if [[ $DRY_RUN == true ]]; then
    log "DRY-RUN: iptables -I INPUT -p ${proto} --dport ${port} -j ACCEPT"
    return 1
  fi
  if [[ $EUID -ne 0 ]]; then
    warn "放行 ${port}/${proto} 需要 root 权限,请使用 sudo 执行."
    return 1
  fi
  if iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT >&2; then
    if command -v ip6tables >/dev/null 2>&1; then
      ip6tables -I INPUT -p "$proto" --dport "$port" -j ACCEPT >&2 || true
    fi
    warn "iptables 规则仅对当前运行时生效,持久化请按发行版执行保存(Debian 系: netfilter-persistent save;RHEL 系: service iptables save)."
    return 0
  fi
  return 1
}

fw_open_nft() {
  local port
  port="$1"
  local proto
  proto="$2"
  if [[ $DRY_RUN == true ]]; then
    log "DRY-RUN: nft add rule inet filter input ${proto} dport ${port} accept"
    return 1
  fi
  if [[ $EUID -ne 0 ]]; then
    warn "放行 ${port}/${proto} 需要 root 权限,请使用 sudo 执行."
    return 1
  fi
  # Arch 等发行版默认可能没有 nftables 规则集,先补齐表与 input 链再加规则.
  if ! nft list table inet filter >/dev/null 2>&1; then
    if ! nft add table inet filter >&2; then
      warn "nft 创建表 inet filter 失败,请执行 nft list ruleset 确认后人工放行."
      return 1
    fi
  fi
  if ! nft list chain inet filter input >/dev/null 2>&1; then
    if ! nft 'add chain inet filter input { type filter hook input priority 0 ; policy accept ; }' >&2; then
      warn "nft 创建链 inet filter input 失败,请执行 nft list ruleset 确认后人工放行."
      return 1
    fi
  fi
  if nft add rule inet filter input "$proto" dport "$port" accept >&2; then
    warn "nft 规则仅对当前运行时生效,持久化请执行 nft list ruleset > /etc/nftables.conf 并确认服务开机加载."
    return 0
  fi
  warn "nft 放行失败,当前表或链可能不是 inet filter input,请用 nft list ruleset 确认后手工放行."
  return 1
}

open_firewall_port() {
  local port
  port="$1"
  local proto
  proto="${2:-$DEFAULT_PROTO}"
  case "$DETECTED_BACKEND" in
    firewalld) fw_open_firewalld "$port" "$proto" ;;
    ufw) fw_open_ufw "$port" "$proto" ;;
    iptables) fw_open_iptables "$port" "$proto" ;;
    nft) fw_open_nft "$port" "$proto" ;;
    *)
      warn "未检测到受支持的防火墙后端,无法自动放行 ${port}/${proto}."
      return 1
      ;;
  esac
}

ensure_firewall_port() {
  local port
  port="$1"
  local proto
  proto="${2:-$DEFAULT_PROTO}"
  local rc=0
  is_firewall_open "$port" "$proto" || rc=$?
  if [[ $rc -eq 0 ]]; then
    return 0
  fi
  if [[ $rc -ne 1 ]]; then
    warn "端口 ${port}/${proto}:防火墙状态未知(后端=${DETECTED_BACKEND}),无法自动修复,请人工确认."
    return 1
  fi
  if [[ $FIX_MODE != true ]]; then
    return 1
  fi
  open_firewall_port "$port" "$proto"
}

check_single_port() {
  local port
  port="$1"
  local proto
  proto="${2:-$DEFAULT_PROTO}"
  if ! is_valid_port "$port"; then
    warn "端口非法,跳过: [${port}]"
    return 1
  fi
  local listen_st
  listen_st="unknown"
  if is_port_listening "$port" "$proto"; then
    listen_st="yes"
  else
    local listen_rc=$?
    if [[ $listen_rc -eq 1 ]]; then
      listen_st="no"
    else
      listen_st="unknown"
    fi
  fi
  local fw_st
  fw_st="unknown"
  if is_firewall_open "$port" "$proto"; then
    fw_st="open"
  else
    local fw_rc=$?
    if [[ $fw_rc -eq 1 ]]; then
      fw_st="closed"
    else
      fw_st="unknown"
    fi
  fi
  local fixed_bool
  fixed_bool=false
  if [[ $fw_st == "closed" && $FIX_MODE == true ]]; then
    if ensure_firewall_port "$port" "$proto"; then
      if is_firewall_open "$port" "$proto"; then
        fw_st="open"
        fixed_bool=true
        if [[ $QUIET == false ]]; then
          log "端口 ${port}/${proto}:防火墙已放行(修复成功)."
        fi
      else
        if [[ $QUIET == false ]]; then
          warn "端口 ${port}/${proto}:已执行放行,但复查仍未开放,请人工确认."
        fi
      fi
    else
      if [[ $QUIET == false ]]; then
        warn "端口 ${port}/${proto}:防火墙放行未完成(仅预览或执行失败),请人工处理."
      fi
    fi
  fi
  local fw_zh
  fw_zh="状态未知"
  if [[ $fw_st == "open" ]]; then
    fw_zh="已放行"
  elif [[ $fw_st == "closed" ]]; then
    fw_zh="未放行"
  fi
  local listen_zh
  listen_zh="状态未知"
  if [[ $listen_st == "yes" ]]; then
    listen_zh="监听正常"
  elif [[ $listen_st == "no" ]]; then
    listen_zh="未监听"
  fi
  local detail
  detail=""
  local pass
  pass=true
  if [[ $listen_st != "yes" ]]; then
    pass=false
    detail="本地${listen_zh}"
  fi
  if [[ $fw_st != "open" ]]; then
    pass=false
    if [[ -n $detail ]]; then
      detail="${detail};防火墙${fw_zh}(后端=${DETECTED_BACKEND})"
    else
      detail="防火墙${fw_zh}(后端=${DETECTED_BACKEND})"
    fi
  fi
  if [[ -z $detail ]]; then
    detail="监听正常,防火墙已放行"
  fi
  local entry
  entry="{\"port\": ${port}, \"proto\": \"${proto}\", \"listening\": \"${listen_st}\", \"firewall\": \"${fw_st}\", \"fixed\": ${fixed_bool}, \"detail\": \"${detail}\"}"
  JSON_ENTRIES+=("$entry")
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  if [[ $pass == true ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    if [[ $QUIET == false ]]; then
      log "通过: 端口 ${port}/${proto}:监听正常,防火墙已放行."
    fi
    return 0
  fi
  FAIL_COUNT=$((FAIL_COUNT + 1))
  if [[ $QUIET == false ]]; then
    warn "未通过: 端口 ${port}/${proto}:${detail}."
  fi
  return 1
}

print_summary() {
  local rc
  rc="$1"
  if [[ $QUIET == true ]]; then
    if [[ $rc -eq 0 ]]; then
      printf 'PASS: %s/%s\n' "$PASS_COUNT" "$TOTAL_COUNT"
    else
      printf 'FAIL: 通过 %s,未通过 %s,共 %s\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL_COUNT"
    fi
    return 0
  fi
  if [[ $rc -eq 0 ]]; then
    log "检查通过: ${PASS_COUNT}/${TOTAL_COUNT} 个端口(协议 ${PROTO},后端 ${DETECTED_BACKEND})."
  else
    warn "检查未通过: 通过 ${PASS_COUNT},未通过 ${FAIL_COUNT},共 ${TOTAL_COUNT}(协议 ${PROTO},后端 ${DETECTED_BACKEND})."
    warn "排查路径:监听请核对 nginx listen 与服务状态;防火墙请用对应后端命令复查;修复可加 --fix(需 root) 或 --dry-run 预览."
  fi
}

print_json() {
  local rc
  rc="$1"
  local body
  body=""
  local e
  if ((${#JSON_ENTRIES[@]} > 0)); then
    for e in "${JSON_ENTRIES[@]}"; do
      if [[ -n $body ]]; then
        body="${body},${e}"
      else
        body="${e}"
      fi
    done
  fi
  printf '{"script":"%s","version":"%s","system":{"hostname":"%s","os":"%s","kernel":"%s","arch":"%s"},"proto":"%s","backend":"%s","total":%s,"pass":%s,"fail":%s,"exit_code":%s,"results":[%s]}\n' \
    "$SCRIPT_NAME" "$VERSION" \
    "$SYSTEM_HOSTNAME" "$SYSTEM_OS" "$SYSTEM_KERNEL" "$SYSTEM_ARCH" \
    "$PROTO" "$DETECTED_BACKEND" \
    "$TOTAL_COUNT" "$PASS_COUNT" "$FAIL_COUNT" "$rc" "$body"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --version)
        printf '%s\n' "$VERSION"
        exit 0
        ;;
      -p | --ports)
        [[ $# -ge 2 ]] || usage_error "$1 需要端口列表参数"
        PORTS_ARG="$2"
        shift
        ;;
      --ports=*)
        PORTS_ARG="${1#*=}"
        ;;
      --proto)
        [[ $# -ge 2 ]] || usage_error "$1 需要协议参数"
        PROTO="$2"
        shift
        ;;
      --proto=*)
        PROTO="${1#*=}"
        ;;
      --backend)
        [[ $# -ge 2 ]] || usage_error "$1 需要后端参数"
        BACKEND="$2"
        shift
        ;;
      --backend=*)
        BACKEND="${1#*=}"
        ;;
      --zone)
        [[ $# -ge 2 ]] || usage_error "$1 需要 zone 参数"
        ZONE="$2"
        shift
        ;;
      --zone=*)
        ZONE="${1#*=}"
        ;;
      --fix)
        FIX_MODE=true
        ;;
      --no-fix)
        FIX_MODE=false
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      -q | --quiet)
        QUIET=true
        ;;
      --json)
        JSON_OUTPUT=true
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          add_ports_from_string "$1"
          shift
        done
        break
        ;;
      -*)
        usage_error "未知参数: $1"
        ;;
      *)
        add_ports_from_string "$1"
        ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  trap cleanup EXIT
  local ports_src
  ports_src=""
  if [[ -n $PORTS_ARG ]]; then
    ports_src="$PORTS_ARG"
  elif ((${#PORTS[@]} == 0)); then
    if [[ -n ${CHECK_PORTS:-} ]]; then
      ports_src="$CHECK_PORTS"
    else
      ports_src="$DEFAULT_PORTS"
    fi
  fi
  if [[ -n $ports_src ]]; then
    add_ports_from_string "$ports_src"
  fi
  if [[ -n ${CHECK_PROTO:-} && $PROTO == "$DEFAULT_PROTO" ]]; then
    PROTO="$CHECK_PROTO"
  fi
  validate_proto
  validate_backend
  validate_zone
  finalize_ports
  check_dependencies
  detect_firewall_backend "$BACKEND" >/dev/null
  collect_system_info
  if [[ $QUIET == false ]]; then
    print_system_info
  fi
  if [[ $FIX_MODE == true && $DRY_RUN == false && $EUID -ne 0 ]]; then
    die "修复模式需要 root 权限.请使用 sudo 执行,或改用 --fix --dry-run 预览."
  fi
  if [[ $QUIET == false && $JSON_OUTPUT == false ]]; then
    log "开始检查: 端口=${PORTS[*]} 协议=${PROTO} 防火墙后端=${DETECTED_BACKEND} 修复模式=${FIX_MODE}"
  fi
  local port
  local rc
  rc=0
  for port in "${PORTS[@]}"; do
    if ! check_single_port "$port" "$PROTO"; then
      rc=1
    fi
  done
  if [[ $JSON_OUTPUT == true ]]; then
    print_json "$rc"
  else
    print_summary "$rc"
  fi
  exit "$rc"
}

__CHECK_PORTS_SOURCED=false
if (return 0 2>/dev/null); then
  __CHECK_PORTS_SOURCED=true
fi
if [[ $__CHECK_PORTS_SOURCED == false ]]; then
  main "$@"
fi
