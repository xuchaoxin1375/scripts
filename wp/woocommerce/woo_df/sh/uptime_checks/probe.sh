#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# 脚本名称: probe.sh
# 功能描述: 对反向代理节点、经节点回源的业务页面和公网入口执行 HTTP 拨测,
#           按连续失败与连续成功判定故障和恢复,写入事件记录并生成邮件通知.
#           仅做观察与通知,不重启服务、不切换线路、不修改代理配置.
# 用法:     ./probe.sh --once [options]
#           ./probe.sh --check-config [options]
#           ./probe.sh --dry-run [options]
# 退出码:   0 本轮执行完成或配置检查通过; 1 配置或运行环境错误; 2 用法错误
# 注意:     本文件换行必须为 LF.
# =============================================================================

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
readonly SCRIPT_DIR
readonly VERSION="20261101.01"

CONFIG_DIR="${UPTIME_CONFIG_DIR:-$SCRIPT_DIR}"
STATE_DIR="${UPTIME_STATE_DIR:-${STATE_DIRECTORY:-/var/lib/uptime-checks}}"
NOTIFY_CMD="${UPTIME_NOTIFY_CMD:-$SCRIPT_DIR/notify-email.sh}"
OBSERVER_LABEL="${UPTIME_OBSERVER_LABEL:-$(uname -n 2>/dev/null || printf 'unknown')}"

FAIL_THRESHOLD="${UPTIME_FAIL_THRESHOLD:-3}"
RECOVER_THRESHOLD="${UPTIME_RECOVER_THRESHOLD:-2}"
REMIND_SECONDS="${UPTIME_REMIND_SECONDS:-3600}"
RETENTION_DAYS="${UPTIME_RETENTION_DAYS:-90}"
EVENT_MAX_LINES="${UPTIME_EVENT_MAX_LINES:-20000}"
NOTIFY_MAX_ATTEMPTS="${UPTIME_NOTIFY_MAX_ATTEMPTS:-20}"

CHECKS_FILE="$CONFIG_DIR/checks.tsv"
MAINTENANCE_FILE="$CONFIG_DIR/maintenance.tsv"
EVENTS_FILE="$STATE_DIR/events.log"
QUEUE_DIR="$STATE_DIR/queue"
FAILED_QUEUE_DIR="$QUEUE_DIR/failed"
LOCK_FILE="$STATE_DIR/lock"

MODE=""
QUIET=false

CHECK_IDS=()
CHECK_KINDS=()
CHECK_GROUPS=()
CHECK_URLS=()
CHECK_ADDRESSES=()
CHECK_HOSTS=()
CHECK_STATUSES=()
CHECK_BODIES=()
CHECK_TIMEOUTS=()
CHECK_CAS=()

MAINT_SCOPES=()
MAINT_STARTS=()
MAINT_ENDS=()

PROBE_OK=false
PROBE_REASON=""
PROBE_CODE=""
PROBE_LATENCY=""

log() {
  [[ $QUIET == true ]] && return 0
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
$SCRIPT_NAME [version:$VERSION] - 反向代理节点与业务页面拨测.

说明:
  读取 $CONFIG_DIR/checks.tsv 中启用的检查项,依次执行 HTTP 拨测.
  连续失败达到 $FAIL_THRESHOLD 轮判定故障,连续成功达到 $RECOVER_THRESHOLD 轮确认恢复.
  故障、恢复与持续故障提醒通过 $NOTIFY_CMD 发送,发送失败进入待发队列并重试.
  维护窗口内的检查照常执行,但不触发告警,窗口结束后重新累计.

模式:
  --once            执行一轮检查;这是 systemd 定时器使用的模式
  --check-config    只校验配置与运行环境,不发起探测
  --dry-run         执行一轮探测并输出结果,不写状态、不发通知

选项:
  --config-dir DIR  配置目录,默认脚本所在目录或 UPTIME_CONFIG_DIR
  --state-dir DIR   状态目录,默认 UPTIME_STATE_DIR 或 STATE_DIRECTORY
  --notify-cmd PATH 通知命令,默认脚本目录下 notify-email.sh
  --quiet           只输出警告与错误,适合 cron 调用
  --help            显示本帮助
  --version         显示版本

配置:
  checks.tsv        检查项,制表符分隔,字段说明见 README
  maintenance.tsv   维护窗口,可选;格式为 作用域<TAB>开始<TAB>结束

环境变量:
  UPTIME_FAIL_THRESHOLD     连续失败判定阈值,默认 $FAIL_THRESHOLD
  UPTIME_RECOVER_THRESHOLD  连续成功恢复阈值,默认 $RECOVER_THRESHOLD
  UPTIME_REMIND_SECONDS     持续故障提醒间隔秒数,默认 $REMIND_SECONDS
  UPTIME_RETENTION_DAYS     事件记录保留天数,默认 $RETENTION_DAYS
  UPTIME_EVENT_MAX_LINES    事件记录最大行数,默认 $EVENT_MAX_LINES
  UPTIME_NOTIFY_MAX_ATTEMPTS 单封通知最大尝试次数,默认 $NOTIFY_MAX_ATTEMPTS
  UPTIME_OBSERVER_LABEL     告警中的观察点名称,默认主机名

退出码:
  0 执行完成或检查通过;1 配置或运行环境错误;2 用法错误
EOF
}

while (($# > 0)); do
  case "$1" in
  --once)
    MODE="once"
    ;;
  --check-config)
    MODE="check"
    ;;
  --dry-run)
    MODE="dry-run"
    ;;
  --config-dir)
    [[ $# -ge 2 ]] || die "--config-dir 缺少参数"
    CONFIG_DIR="$2"
    CHECKS_FILE="$CONFIG_DIR/checks.tsv"
    MAINTENANCE_FILE="$CONFIG_DIR/maintenance.tsv"
    shift
    ;;
  --state-dir)
    [[ $# -ge 2 ]] || die "--state-dir 缺少参数"
    STATE_DIR="$2"
    EVENTS_FILE="$STATE_DIR/events.log"
    QUEUE_DIR="$STATE_DIR/queue"
    FAILED_QUEUE_DIR="$QUEUE_DIR/failed"
    LOCK_FILE="$STATE_DIR/lock"
    shift
    ;;
  --notify-cmd)
    [[ $# -ge 2 ]] || die "--notify-cmd 缺少参数"
    NOTIFY_CMD="$2"
    shift
    ;;
  --quiet)
    QUIET=true
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

if [[ -z $MODE ]]; then
  usage >&2
  exit 2
fi

is_uint() {
  [[ ${1:-} =~ ^[0-9]+$ ]]
}

parse_url() {
  local url="$1"
  local rest hostport host port

  [[ $url =~ ^https?://[^/]+ ]] || return 1
  rest="${url#*://}"
  hostport="${rest%%/*}"

  if [[ $hostport == \[*\]* ]]; then
    return 1
  fi
  if [[ $hostport == *:* ]]; then
    host="${hostport%:*}"
    port="${hostport##*:}"
  else
    host="$hostport"
    if [[ $url == https://* ]]; then
      port=443
    else
      port=80
    fi
  fi

  [[ -n $host && $port =~ ^[0-9]+$ ]] || return 1
  URL_HOST="$host"
  URL_PORT="$port"
}

validate_config() {
  local errors=0
  local line lineno=0 cols
  local id kind group url address host_header expect_status expect_body timeout ca_bundle enabled
  local seen=" "
  local maint_scope maint_start maint_end start_epoch end_epoch

  if [[ ! -r $CHECKS_FILE ]]; then
    warn "无法读取检查配置文件: $CHECKS_FILE"
    return 1
  fi

  while IFS= read -r line || [[ -n $line ]]; do
    lineno=$((lineno + 1))
    [[ -z $line || $line == \#* ]] && continue
    cols="$(printf '%s' "$line" | awk -F'\t' '{print NF}')"
    if [[ $cols -ne 11 ]]; then
      warn "$CHECKS_FILE 第 $lineno 行字段数为 $cols,应为 11"
      errors=$((errors + 1))
      continue
    fi
    IFS=$'\x1f' read -r id kind group url address host_header expect_status expect_body timeout ca_bundle enabled \
      <<<"${line//$'\t'/$'\x1f'}"

    if [[ ! $id =~ ^[A-Za-z0-9._-]+$ ]]; then
      warn "$CHECKS_FILE 第 $lineno 行 id 只允许字母、数字、点、下划线和连字符: $id"
      errors=$((errors + 1))
    elif [[ $seen == *" $id "* ]]; then
      warn "$CHECKS_FILE 第 $lineno 行 id 重复: $id"
      errors=$((errors + 1))
    else
      seen="$seen$id "
    fi

    if [[ ! $group =~ ^[A-Za-z0-9._-]+$ ]]; then
      warn "$CHECKS_FILE 第 $lineno 行 group 只允许字母、数字、点、下划线和连字符: $group"
      errors=$((errors + 1))
    fi

    if [[ -n $address && ! $address =~ ^[A-Za-z0-9._-]+$ ]]; then
      warn "$CHECKS_FILE 第 $lineno 行 address 只支持 IPv4 地址或普通域名: $address"
      errors=$((errors + 1))
    fi

    case "$kind" in
    node | biz)
      if [[ -z $address ]]; then
        warn "$CHECKS_FILE 第 $lineno 行 $kind 检查必须填写 address,用于锚定节点"
        errors=$((errors + 1))
      fi
      ;;
    public)
      if [[ -n $address ]]; then
        warn "$CHECKS_FILE 第 $lineno 行 public 检查不应填写 address;公网入口应走正常解析"
        errors=$((errors + 1))
      fi
      ;;
    *)
      warn "$CHECKS_FILE 第 $lineno 行 kind 只能是 node、biz 或 public: $kind"
      errors=$((errors + 1))
      ;;
    esac

    if ! parse_url "$url"; then
      warn "$CHECKS_FILE 第 $lineno 行 url 不是受支持的 HTTP 地址: $url"
      errors=$((errors + 1))
    fi

    if [[ -n $host_header && ! $host_header =~ ^[A-Za-z0-9._:-]+$ ]]; then
      warn "$CHECKS_FILE 第 $lineno 行 host_header 含非法字符: $host_header"
      errors=$((errors + 1))
    fi

    if [[ ! $expect_status =~ ^[0-9]{3}$ ]]; then
      warn "$CHECKS_FILE 第 $lineno 行 expect_status 应为三位状态码: $expect_status"
      errors=$((errors + 1))
    fi

    if [[ -n $expect_body && $expect_body == *$'\t'* ]]; then
      warn "$CHECKS_FILE 第 $lineno 行 expect_body 不能包含制表符"
      errors=$((errors + 1))
    fi

    if ! is_uint "$timeout" || ((timeout < 1 || timeout > 120)); then
      warn "$CHECKS_FILE 第 $lineno 行 timeout 应为 1 到 120 的整数: $timeout"
      errors=$((errors + 1))
    fi

    if [[ -n $ca_bundle && ! -r $ca_bundle ]]; then
      warn "$CHECKS_FILE 第 $lineno 行 ca_bundle 不可读: $ca_bundle"
      errors=$((errors + 1))
    fi

    if [[ $enabled != 0 && $enabled != 1 ]]; then
      warn "$CHECKS_FILE 第 $lineno 行 enabled 只能是 0 或 1: $enabled"
      errors=$((errors + 1))
    fi
  done <"$CHECKS_FILE"

  if ((lineno == 0)); then
    warn "$CHECKS_FILE 为空"
    errors=$((errors + 1))
  fi

  if [[ -f $MAINTENANCE_FILE ]]; then
    lineno=0
    while IFS= read -r line || [[ -n $line ]]; do
      lineno=$((lineno + 1))
      [[ -z $line || $line == \#* ]] && continue
      cols="$(printf '%s' "$line" | awk -F'\t' '{print NF}')"
      if [[ $cols -ne 3 ]]; then
        warn "$MAINTENANCE_FILE 第 $lineno 行字段数应为 3"
        errors=$((errors + 1))
        continue
      fi
      IFS=$'\t' read -r maint_scope maint_start maint_end <<<"$line"
      if [[ ! $maint_scope =~ ^([A-Za-z0-9._-]+|\*)$ ]]; then
        warn "$MAINTENANCE_FILE 第 $lineno 行作用域非法: $maint_scope"
        errors=$((errors + 1))
      fi
      if ! start_epoch="$(date -d "$maint_start" +%s 2>/dev/null)"; then
        warn "$MAINTENANCE_FILE 第 $lineno 行开始时间无法解析: $maint_start"
        errors=$((errors + 1))
      fi
      if ! end_epoch="$(date -d "$maint_end" +%s 2>/dev/null)"; then
        warn "$MAINTENANCE_FILE 第 $lineno 行结束时间无法解析: $maint_end"
        errors=$((errors + 1))
      fi
      if is_uint "${start_epoch:-}" && is_uint "${end_epoch:-}" && ((start_epoch >= end_epoch)); then
        warn "$MAINTENANCE_FILE 第 $lineno 行结束时间必须晚于开始时间"
        errors=$((errors + 1))
      fi
    done <"$MAINTENANCE_FILE"
  fi

  if ! is_uint "$FAIL_THRESHOLD" || ((FAIL_THRESHOLD < 1)); then
    warn "UPTIME_FAIL_THRESHOLD 应为正整数"
    errors=$((errors + 1))
  fi
  if ! is_uint "$RECOVER_THRESHOLD" || ((RECOVER_THRESHOLD < 1)); then
    warn "UPTIME_RECOVER_THRESHOLD 应为正整数"
    errors=$((errors + 1))
  fi
  if ! is_uint "$REMIND_SECONDS" || ((REMIND_SECONDS < 60)); then
    warn "UPTIME_REMIND_SECONDS 应不小于 60"
    errors=$((errors + 1))
  fi
  if ! is_uint "$RETENTION_DAYS" || ((RETENTION_DAYS < 1)); then
    warn "UPTIME_RETENTION_DAYS 应为正整数"
    errors=$((errors + 1))
  fi
  if ! is_uint "$EVENT_MAX_LINES" || ((EVENT_MAX_LINES < 100)); then
    warn "UPTIME_EVENT_MAX_LINES 应不小于 100"
    errors=$((errors + 1))
  fi
  if ! is_uint "$NOTIFY_MAX_ATTEMPTS" || ((NOTIFY_MAX_ATTEMPTS < 1)); then
    warn "UPTIME_NOTIFY_MAX_ATTEMPTS 应为正整数"
    errors=$((errors + 1))
  fi

  ((errors == 0))
}

load_checks() {
  local line
  local id kind group url address host_header expect_status expect_body timeout ca_bundle enabled

  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    IFS=$'\x1f' read -r id kind group url address host_header expect_status expect_body timeout ca_bundle enabled \
      <<<"${line//$'\t'/$'\x1f'}"
    [[ $enabled == 1 ]] || continue
    CHECK_IDS+=("$id")
    CHECK_KINDS+=("$kind")
    CHECK_GROUPS+=("$group")
    CHECK_URLS+=("$url")
    CHECK_ADDRESSES+=("$address")
    CHECK_HOSTS+=("$host_header")
    CHECK_STATUSES+=("$expect_status")
    CHECK_BODIES+=("$expect_body")
    CHECK_TIMEOUTS+=("$timeout")
    CHECK_CAS+=("$ca_bundle")
  done <"$CHECKS_FILE"
}

load_maintenance() {
  local line scope start end
  [[ -r $MAINTENANCE_FILE ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    IFS=$'\t' read -r scope start end <<<"$line"
    MAINT_SCOPES+=("$scope")
    MAINT_STARTS+=("$(date -d "$start" +%s)")
    MAINT_ENDS+=("$(date -d "$end" +%s)")
  done <"$MAINTENANCE_FILE"
}

is_in_maintenance() {
  local id="$1" group="$2" now="$3"
  local i

  for i in "${!MAINT_SCOPES[@]}"; do
    if [[ ${MAINT_SCOPES[$i]} == "$id" || ${MAINT_SCOPES[$i]} == "$group" || ${MAINT_SCOPES[$i]} == "*" ]]; then
      if ((now >= MAINT_STARTS[i] && now < MAINT_ENDS[i])); then
        return 0
      fi
    fi
  done
  return 1
}

probe_check() {
  local index="$1"
  local tmp_body meta rc http_code

  PROBE_OK=false
  PROBE_REASON=""
  PROBE_CODE=""
  PROBE_LATENCY=""

  if ! parse_url "${CHECK_URLS[$index]}"; then
    PROBE_REASON="url_parse_error"
    return 1
  fi

  tmp_body="$(mktemp "${TMP_WORK}/body.XXXXXX")" || {
    PROBE_REASON="temp_file_error"
    return 1
  }

  local -a args=(
    --disable
    --silent
    --show-error
    --max-time "${CHECK_TIMEOUTS[$index]}"
    --max-filesize 1048576
    --output "$tmp_body"
    --write-out '%{http_code}\t%{time_total}'
    --user-agent "UptimeChecks/$VERSION"
  )

  if [[ -n ${CHECK_ADDRESSES[$index]} ]]; then
    args+=(--resolve "${URL_HOST}:${URL_PORT}:${CHECK_ADDRESSES[$index]}")
  fi
  if [[ -n ${CHECK_HOSTS[$index]} ]]; then
    args+=(--header "Host: ${CHECK_HOSTS[$index]}")
  fi
  if [[ -n ${CHECK_CAS[$index]} ]]; then
    args+=(--cacert "${CHECK_CAS[$index]}")
  fi

  meta="$(curl "${args[@]}" "${CHECK_URLS[$index]}" 2>/dev/null)"
  rc=$?
  if [[ $meta == *$'\t'* ]]; then
    http_code="${meta%%$'\t'*}"
    PROBE_LATENCY="${meta##*$'\t'}"
  else
    http_code=""
    PROBE_LATENCY=""
  fi
  PROBE_CODE="${http_code:-000}"

  if ((rc != 0)); then
    PROBE_REASON="curl_exit_$rc"
    rm -f "$tmp_body"
    return 1
  fi

  if [[ $PROBE_CODE != "${CHECK_STATUSES[$index]}" ]]; then
    PROBE_REASON="unexpected_status_$PROBE_CODE"
    rm -f "$tmp_body"
    return 1
  fi

  if [[ -n ${CHECK_BODIES[$index]} ]]; then
    if ! grep -aFq -- "${CHECK_BODIES[$index]}" "$tmp_body"; then
      PROBE_REASON="body_mismatch"
      rm -f "$tmp_body"
      return 1
    fi
  fi

  rm -f "$tmp_body"
  PROBE_OK=true
  return 0
}

state_path() {
  printf '%s/%s' "$STATE_DIR" "$1"
}

read_state() {
  local file value
  file="$(state_path "$1")"
  if [[ -r $file ]]; then
    IFS= read -r value <"$file" || true
    printf '%s' "${value:-}"
  fi
}

write_state() {
  local name="$1" value="$2" tmp
  tmp="$(state_path "$name.tmp.$$")"
  printf '%s\n' "$value" >"$tmp" && mv -f -- "$tmp" "$(state_path "$name")"
}

append_event() {
  local event="$1" group="$2" detail="${3:-}"
  detail="${detail//$'\t'/ }"
  detail="${detail//$'\n'/ }"
  printf '%s\t%s\t%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$event" "$group" "$detail" >>"$EVENTS_FILE"
}

prune_events() {
  local today cutoff tmp

  today="$(date -u '+%F')"
  [[ "$(read_state '.last_prune')" == "$today" ]] && return 0
  write_state '.last_prune' "$today"

  [[ -f $EVENTS_FILE ]] || return 0
  cutoff="$(date -u -d "-${RETENTION_DAYS} days" '+%F')"
  tmp="${EVENTS_FILE}.tmp.$$"
  awk -F'\t' -v cutoff="$cutoff" '($1 >= cutoff)' "$EVENTS_FILE" >"$tmp" 2>/dev/null || cp "$EVENTS_FILE" "$tmp"
  mv -f -- "$tmp" "$EVENTS_FILE"

  if [[ $(wc -l <"$EVENTS_FILE") -gt $EVENT_MAX_LINES ]]; then
    tmp="${EVENTS_FILE}.tmp.$$"
    tail -n "$EVENT_MAX_LINES" "$EVENTS_FILE" >"$tmp"
    mv -f -- "$tmp" "$EVENTS_FILE"
  fi
}

fmt_duration() {
  local seconds="${1:-0}"
  local days hours minutes
  days=$((seconds / 86400))
  hours=$(((seconds % 86400) / 3600))
  minutes=$(((seconds % 3600) / 60))
  if ((days > 0)); then
    printf '%d 天 %d 小时 %d 分钟' "$days" "$hours" "$minutes"
  elif ((hours > 0)); then
    printf '%d 小时 %d 分钟' "$hours" "$minutes"
  else
    printf '%d 分钟' "$minutes"
  fi
}

failed_check_lines() {
  local group="$1" i output=""
  for i in "${!CHECK_IDS[@]}"; do
    [[ ${CHECK_GROUPS[$i]} == "$group" ]] || continue
    [[ "$(read_state "check.${CHECK_IDS[$i]}.status")" == "fail" ]] || continue
    output+="- ${CHECK_IDS[$i]} (${CHECK_KINDS[$i]}): $(read_state "check.${CHECK_IDS[$i]}.reason"), HTTP $(read_state "check.${CHECK_IDS[$i]}.code"), 耗时 $(read_state "check.${CHECK_IDS[$i]}.latency") 秒"$'\n'
  done
  printf '%s' "$output"
}

group_check_lines() {
  local group="$1" i output=""
  for i in "${!CHECK_IDS[@]}"; do
    [[ ${CHECK_GROUPS[$i]} == "$group" ]] || continue
    output+="- ${CHECK_IDS[$i]} (${CHECK_KINDS[$i]}): HTTP $(read_state "check.${CHECK_IDS[$i]}.code"), 耗时 $(read_state "check.${CHECK_IDS[$i]}.latency") 秒"$'\n'
  done
  printf '%s' "$output"
}

build_message() {
  local event="$1" group="$2" since="$3" now="$4"
  local subject tag duration lines

  case "$event" in
  down)
    tag="故障"
    subject="[拨测][故障] $group"
    ;;
  reminder)
    tag="持续故障"
    subject="[拨测][持续故障] $group"
    ;;
  recovery)
    tag="恢复"
    subject="[拨测][恢复] $group"
    ;;
  *)
    tag="通知"
    subject="[拨测][通知] $group"
    ;;
  esac

  duration=""
  if is_uint "$since" && ((since > 0 && now >= since)); then
    duration="$(fmt_duration $((now - since)))"
  fi

  lines="事件: $tag
分组: $group
时间: $(date '+%Y-%m-%d %H:%M:%S %z')
观察点: $OBSERVER_LABEL"
  if [[ $event == recovery ]]; then
    lines+=$'\n'"持续: ${duration:-未知}"
  else
    lines+=$'\n'"已持续: ${duration:-刚开始}"
  fi
  if [[ $event == recovery ]]; then
    lines+=$'\n\n'"相关检查:"$'\n'
    lines+="$(group_check_lines "$group")"
  else
    lines+=$'\n\n'"失败检查:"$'\n'
    lines+="$(failed_check_lines "$group")"
  fi
  lines+=$'\n'"说明: 以上结果为单一观察点的 HTTP 拨测结果,不能证明所有地区均不可访问。"
  lines+=$'\n'"本邮件由 uptime_checks 自动发送,请勿直接回复。"

  printf '%s\n%s\n' "$subject" "$lines"
}

enqueue_notification() {
  local event="$1" group="$2" since="$3" now="$4"
  local file

  mkdir -p -- "$QUEUE_DIR" || return 1
  file="$QUEUE_DIR/$(date +%s)-$$-$RANDOM.msg"
  build_message "$event" "$group" "$since" "$now" >"$file"
  chmod 600 -- "$file" 2>/dev/null || true
  log "已生成通知: $event / $group"
}

notify_backoff() {
  local attempts="$1" delay=60 i
  for ((i = 1; i < attempts; i++)); do
    delay=$((delay * 2))
    ((delay >= 1800)) && {
      delay=1800
      break
    }
  done
  printf '%s' "$delay"
}

drain_queue() {
  local now="$1" file attempts next delay

  [[ -d $QUEUE_DIR ]] || return 0
  for file in "$QUEUE_DIR"/*.msg; do
    [[ -e $file ]] || continue
    attempts="$(cat "${file}.attempt" 2>/dev/null || printf '0')"
    next="$(cat "${file}.next" 2>/dev/null || printf '0')"
    is_uint "$attempts" || attempts=0
    is_uint "$next" || next=0
    ((now >= next)) || continue

    if "$NOTIFY_CMD" <"$file" 2>/dev/null; then
      append_event "notify_ok" "-" "$(basename "$file")"
      rm -f -- "$file" "${file}.attempt" "${file}.next"
    else
      attempts=$((attempts + 1))
      append_event "notify_fail" "-" "$(basename "$file") attempt=$attempts"
      if ((attempts >= NOTIFY_MAX_ATTEMPTS)); then
        mkdir -p -- "$FAILED_QUEUE_DIR"
        mv -f -- "$file" "$FAILED_QUEUE_DIR/" 2>/dev/null || true
        rm -f -- "${file}.attempt" "${file}.next"
        append_event "notify_dead" "-" "$(basename "$file")"
        warn "通知重试达到上限,已移入失败队列: $(basename "$file")"
      else
        delay="$(notify_backoff "$attempts")"
        printf '%s\n' "$attempts" >"${file}.attempt"
        printf '%s\n' "$((now + delay))" >"${file}.next"
      fi
    fi
  done
}

evaluate_round() {
  local now="$1" i group new_status prev_status last_alert since eligible maint
  local -A group_status=()
  local -A group_has_maint=()
  local -A group_eligible=()
  local -A seen_groups=()

  for i in "${!CHECK_IDS[@]}"; do
    seen_groups["${CHECK_GROUPS[$i]}"]=1
  done

  for i in "${!CHECK_IDS[@]}"; do
    local id="${CHECK_IDS[$i]}" group="${CHECK_GROUPS[$i]}"

    if probe_check "$i"; then
      log "OK   $id (${CHECK_KINDS[$i]}) HTTP $PROBE_CODE ${PROBE_LATENCY}s"
    else
      log "FAIL $id (${CHECK_KINDS[$i]}) $PROBE_REASON"
    fi

    if is_in_maintenance "$id" "$group" "$now"; then
      group_has_maint["$group"]=1
      write_state "check.${id}.fail" 0
      write_state "check.${id}.ok" 0
      write_state "check.${id}.status" "ok"
      if [[ $PROBE_OK == false ]]; then
        if [[ ! -f "$(state_path "maint.${id}.failed")" ]]; then
          append_event "maintenance_fail" "$group" "$id $PROBE_REASON"
          write_state "maint.${id}.failed" 1
        fi
      elif [[ -f "$(state_path "maint.${id}.failed")" ]]; then
        append_event "maintenance_recovered" "$group" "$id"
        rm -f -- "$(state_path "maint.${id}.failed")"
      fi
      continue
    fi

    rm -f -- "$(state_path "maint.${id}.failed")"

    local fail_count ok_count status
    fail_count="$(read_state "check.${id}.fail")"
    ok_count="$(read_state "check.${id}.ok")"
    is_uint "$fail_count" || fail_count=0
    is_uint "$ok_count" || ok_count=0
    status="$(read_state "check.${id}.status")"
    [[ -n $status ]] || status="ok"

    if [[ $PROBE_OK == true ]]; then
      ok_count=$((ok_count + 1))
      fail_count=0
      if ((ok_count >= RECOVER_THRESHOLD)); then
        status="ok"
      fi
    else
      fail_count=$((fail_count + 1))
      ok_count=0
      if ((fail_count >= FAIL_THRESHOLD)); then
        status="fail"
      fi
    fi

    write_state "check.${id}.fail" "$fail_count"
    write_state "check.${id}.ok" "$ok_count"
    write_state "check.${id}.status" "$status"
    write_state "check.${id}.reason" "$PROBE_REASON"
    write_state "check.${id}.code" "${PROBE_CODE:-000}"
    write_state "check.${id}.latency" "${PROBE_LATENCY:-0}"

    group_eligible["$group"]=1
    if [[ $status == fail ]]; then
      group_status["$group"]="down"
    elif [[ -z ${group_status[$group]:-} ]]; then
      group_status["$group"]="ok"
    fi
  done

  for group in "${!seen_groups[@]}"; do
    eligible=${group_eligible[$group]:-0}
    maint=${group_has_maint[$group]:-0}
    prev_status="$(read_state "group.${group}.status")"

    if [[ $eligible == 0 ]]; then
      if [[ $prev_status == down ]]; then
        write_state "group.${group}.status" "ok"
        write_state "group.${group}.since" 0
        append_event "maintenance_suppressed" "$group" "全部检查处于维护窗口"
      fi
      continue
    fi

    new_status="${group_status[$group]:-ok}"

    if [[ -z $prev_status ]]; then
      write_state "group.${group}.status" "$new_status"
      if [[ $new_status == down ]]; then
        write_state "group.${group}.since" "$now"
        write_state "group.${group}.last_alert" "$now"
        append_event "group_down" "$group" "首次运行即判定故障"
        enqueue_notification "down" "$group" "$now" "$now"
      fi
      continue
    fi

    last_alert="$(read_state "group.${group}.last_alert")"
    is_uint "$last_alert" || last_alert=0
    since="$(read_state "group.${group}.since")"
    is_uint "$since" || since=0

    if [[ $new_status == down && $prev_status == ok ]]; then
      write_state "group.${group}.status" "down"
      write_state "group.${group}.since" "$now"
      write_state "group.${group}.last_alert" "$now"
      append_event "group_down" "$group" "$(failed_check_lines "$group" | tr '\n' ' ')"
      enqueue_notification "down" "$group" "$now" "$now"
    elif [[ $new_status == ok && $prev_status == down ]]; then
      write_state "group.${group}.status" "ok"
      write_state "group.${group}.since" 0
      write_state "group.${group}.last_alert" 0
      if [[ $maint == 1 ]]; then
        append_event "maintenance_suppressed" "$group" "恢复发生在维护窗口内"
      else
        append_event "group_up" "$group" "持续时间 $(fmt_duration $((now - since)))"
        enqueue_notification "recovery" "$group" "$since" "$now"
      fi
    elif [[ $new_status == down && $prev_status == down ]]; then
      if ((last_alert == 0 || now - last_alert >= REMIND_SECONDS)); then
        write_state "group.${group}.last_alert" "$now"
        append_event "reminder" "$group" "已持续 $(fmt_duration $((now - since)))"
        enqueue_notification "reminder" "$group" "$since" "$now"
      fi
    fi
  done
}

run_dry() {
  local i
  load_checks
  if ((${#CHECK_IDS[@]} == 0)); then
    warn "没有启用的检查项"
    return 1
  fi
  TMP_WORK="$(mktemp -d "${TMPDIR:-/tmp}/uptime_checks.XXXXXX")"
  for i in "${!CHECK_IDS[@]}"; do
    if probe_check "$i"; then
      printf 'OK   %s\t%s\tHTTP %s\t%s s\n' "${CHECK_IDS[$i]}" "${CHECK_KINDS[$i]}" "$PROBE_CODE" "$PROBE_LATENCY"
    else
      printf 'FAIL %s\t%s\t%s\tHTTP %s\n' "${CHECK_IDS[$i]}" "${CHECK_KINDS[$i]}" "$PROBE_REASON" "${PROBE_CODE:-000}"
    fi
  done
  rm -rf -- "$TMP_WORK"
  TMP_WORK=""
}

run_once() {
  local now

  validate_config || die "配置校验失败,未执行探测"
  if [[ ! -x $NOTIFY_CMD ]]; then
    warn "通知命令不存在或不可执行,告警将停留在队列: $NOTIFY_CMD"
  fi
  load_checks
  load_maintenance

  if ((${#CHECK_IDS[@]} == 0)); then
    warn "没有启用的检查项,未执行探测"
    return 0
  fi

  mkdir -p -- "$STATE_DIR" "$QUEUE_DIR" || die "无法创建状态目录: $STATE_DIR"
  chmod 700 -- "$STATE_DIR" 2>/dev/null || true

  exec 9>"$LOCK_FILE" || die "无法打开锁文件: $LOCK_FILE"
  if ! flock -n 9; then
    warn "上一轮仍在运行,本轮跳过"
    return 0
  fi

  if [[ -z ${NOTIFY_ENV:-} && -r $CONFIG_DIR/notify.env ]]; then
    export NOTIFY_ENV="$CONFIG_DIR/notify.env"
  fi

  now="$(date +%s)"
  TMP_WORK="$(mktemp -d "${STATE_DIR}/tmp.XXXXXX")" || die "无法创建临时目录"
  trap 'rm -rf -- "${TMP_WORK:-}"' EXIT

  prune_events
  drain_queue "$now"
  evaluate_round "$now"
  drain_queue "$(date +%s)"

  rm -rf -- "$TMP_WORK"
  TMP_WORK=""
}

case "$MODE" in
check)
  validate_config || exit 1
  if [[ ! -x $NOTIFY_CMD ]]; then
    warn "通知命令不存在或不可执行: $NOTIFY_CMD"
    exit 1
  fi
  [[ -d $STATE_DIR ]] || warn "状态目录尚不存在,首次运行会自动创建: $STATE_DIR"
  log "配置校验通过: $CHECKS_FILE"
  ;;
dry-run)
  validate_config || die "配置校验失败"
  run_dry
  ;;
once)
  run_once
  ;;
esac
