#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# vps-inspect.sh - 低依赖 Linux VPS/服务器信息与轻量性能检查脚本
#
# 设计原则：
#   1. 默认只读，不访问公网，不修改内核参数。
#   2. 优先读取 /proc、/sys 与 /etc；有常见工具时增强显示，无工具时自动降级。
#   3. 信息按重要性排序，并通过 --level 0..3 控制详细程度。
#   4. 基准测试必须显式启用；结果仅适合快速横向参考，不替代 fio、sysbench 等专业测试。
#
# 兼容目标：Bash 4.0+，常见 GNU/Linux 发行版与多数容器环境。

set -o nounset
set -o pipefail

readonly SCRIPT_NAME=${0##*/}
readonly SCRIPT_VERSION="1.1.0"

LEVEL=1
COLOR_MODE="auto"
PLAIN=0
SHOW_HEADER=1
REDACT=0
OUTPUT_FILE=""
ONLY_SECTIONS=""
SKIP_SECTIONS=""
BENCHMARKS=""
DISK_BENCH_PATH="/tmp"
DISK_BENCH_MIB=256
BENCH_TEMP_FILE=""
SECTION_INDEX=0
BAR_WIDTH=20

# 运行时样式变量，由 init_style 初始化。
C_RESET=""
C_BOLD=""
C_DIM=""
C_BLUE=""
C_CYAN=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_MAGENTA=""
GLYPH_BAR="-"
GLYPH_OK="[OK]"
GLYPH_WARN="[!]"
GLYPH_INFO="[i]"
GLYPH_FILL="#"
GLYPH_EMPTY="-"
GLYPH_SUB="-"

cleanup_temp_file() {
    if [[ -n ${BENCH_TEMP_FILE:-} ]]; then
        rm -f -- "$BENCH_TEMP_FILE"
        BENCH_TEMP_FILE=""
SECTION_INDEX=0
BAR_WIDTH=20
    fi
}

usage() {
    cat <<'USAGE'
用法：
  vps-inspect.sh [选项]

详细程度：
  -l, --level LEVEL       信息级别：
                            0/essential  仅关键状态
                            1/normal     常用配置（默认）
                            2/detail     增加限制、文件系统与网络细节
                            3/full       展开原始表格与诊断信息

筛选与输出：
      --only LIST         只显示指定章节，逗号分隔
      --skip LIST         跳过指定章节，逗号分隔
                          章节：summary,system,virt,cpu,memory,storage,
                                network,kernel,benchmark
      --no-color          禁用 ANSI 颜色
      --color             强制启用 ANSI 颜色
      --plain             纯 ASCII 输出，同时禁用颜色
      --no-header         不显示标题横幅
      --redact            隐去主机名、IP、MAC 等标识信息
  -o, --output FILE       将结果写入文件；终端仍显示错误信息

可选轻量基准：
  -b, --benchmark LIST    运行 cpu、disk 或 all，逗号分隔
      --disk-path DIR     磁盘测试目录，默认 /tmp
      --disk-size MIB     磁盘写入测试大小，默认 256 MiB

其他：
  -h, --help              显示帮助
  -V, --version           显示版本

示例：
  ./vps-inspect.sh
  ./vps-inspect.sh --level 2 --no-color
  ./vps-inspect.sh --only summary,cpu,memory,storage
  ./vps-inspect.sh --level full --skip network --redact
  ./vps-inspect.sh --benchmark cpu,disk --disk-path /var/tmp --disk-size 512

说明：
  * 默认采用紧凑输出，不执行任何基准测试。
  * 磁盘测试会创建临时文件并在结束时删除；请确保目标目录空间充足。
  * 脚本不会主动获取公网 IP，也不会向第三方服务发送请求。
USAGE
}

version() {
    printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
}

fatal() {
    printf '错误：%s\n' "$*" >&2
    exit 2
}

warn_stderr() {
    printf '警告：%s\n' "$*" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

trim() {
    local value=${1-}
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "$value"
}

lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_level() {
    case $(lower "$1") in
        0|essential|min|minimal|basic) printf '0' ;;
        1|normal|default|standard)     printf '1' ;;
        2|detail|detailed)             printf '2' ;;
        3|full|verbose|all)            printf '3' ;;
        *) return 1 ;;
    esac
}

is_uint() {
    [[ $1 =~ ^[0-9]+$ ]]
}

normalize_csv() {
    local input=${1-}
    input=${input// /}
    input=$(lower "$input")
    input=${input#,}
    input=${input%,}
    printf '%s' "$input"
}

csv_has() {
    local csv=",${1},"
    local item=$2
    [[ $csv == *",${item},"* ]]
}

valid_section() {
    case $1 in
        summary|system|virt|cpu|memory|storage|network|kernel|benchmark) return 0 ;;
        *) return 1 ;;
    esac
}

validate_section_list() {
    local list=$1
    local item
    [[ -z $list ]] && return 0
    local -a items=()
    IFS=',' read -r -a items <<< "$list"
    for item in "${items[@]}"; do
        valid_section "$item" || fatal "未知章节：$item"
    done
}

normalize_benchmarks() {
    local list
    list=$(normalize_csv "$1")
    [[ $list == "all" ]] && list="cpu,disk"
    local item
    local -a bench_items=()
    IFS=',' read -r -a bench_items <<< "$list"
    for item in "${bench_items[@]}"; do
        case $item in
            cpu|disk) ;;
            "") fatal "--benchmark 不能为空" ;;
            *) fatal "未知基准项目：$item（可用：cpu,disk,all）" ;;
        esac
    done
    printf '%s' "$list"
}

parse_args() {
    while (($# > 0)); do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -V|--version)
                version
                exit 0
                ;;
            -l|--level)
                (($# >= 2)) || fatal "$1 需要参数"
                LEVEL=$(normalize_level "$2") || fatal "无效级别：$2"
                shift 2
                ;;
            --level=*)
                LEVEL=$(normalize_level "${1#*=}") || fatal "无效级别：${1#*=}"
                shift
                ;;
            --only)
                (($# >= 2)) || fatal "$1 需要参数"
                ONLY_SECTIONS=$(normalize_csv "$2")
                shift 2
                ;;
            --only=*)
                ONLY_SECTIONS=$(normalize_csv "${1#*=}")
                shift
                ;;
            --skip)
                (($# >= 2)) || fatal "$1 需要参数"
                SKIP_SECTIONS=$(normalize_csv "$2")
                shift 2
                ;;
            --skip=*)
                SKIP_SECTIONS=$(normalize_csv "${1#*=}")
                shift
                ;;
            --no-color)
                COLOR_MODE="never"
                shift
                ;;
            --color)
                COLOR_MODE="always"
                shift
                ;;
            --plain)
                PLAIN=1
                COLOR_MODE="never"
                shift
                ;;
            --no-header)
                SHOW_HEADER=0
                shift
                ;;
            --redact)
                REDACT=1
                shift
                ;;
            -o|--output)
                (($# >= 2)) || fatal "$1 需要参数"
                OUTPUT_FILE=$2
                shift 2
                ;;
            --output=*)
                OUTPUT_FILE=${1#*=}
                shift
                ;;
            -b|--benchmark)
                (($# >= 2)) || fatal "$1 需要参数"
                BENCHMARKS=$(normalize_benchmarks "$2")
                shift 2
                ;;
            --benchmark=*)
                BENCHMARKS=$(normalize_benchmarks "${1#*=}")
                shift
                ;;
            --disk-path)
                (($# >= 2)) || fatal "$1 需要参数"
                DISK_BENCH_PATH=$2
                shift 2
                ;;
            --disk-path=*)
                DISK_BENCH_PATH=${1#*=}
                shift
                ;;
            --disk-size)
                (($# >= 2)) || fatal "$1 需要参数"
                DISK_BENCH_MIB=$2
                shift 2
                ;;
            --disk-size=*)
                DISK_BENCH_MIB=${1#*=}
                shift
                ;;
            --)
                shift
                (($# == 0)) || fatal "不接受位置参数：$*"
                ;;
            -*)
                fatal "未知选项：$1（使用 --help 查看帮助）"
                ;;
            *)
                fatal "不接受位置参数：$1"
                ;;
        esac
    done

    validate_section_list "$ONLY_SECTIONS"
    validate_section_list "$SKIP_SECTIONS"
    is_uint "$DISK_BENCH_MIB" || fatal "--disk-size 必须是正整数"
    ((DISK_BENCH_MIB >= 16)) || fatal "--disk-size 至少为 16 MiB"
    ((DISK_BENCH_MIB <= 16384)) || fatal "--disk-size 不应超过 16384 MiB"
}

section_enabled() {
    local section=$1
    local min_level=0

    if [[ -n $ONLY_SECTIONS ]] && ! csv_has "$ONLY_SECTIONS" "$section"; then
        return 1
    fi
    if [[ -n $SKIP_SECTIONS ]] && csv_has "$SKIP_SECTIONS" "$section"; then
        return 1
    fi
    if [[ $section == benchmark && -z $BENCHMARKS ]]; then
        return 1
    fi

    # --only 表示显式请求：此时不受默认级别门槛限制。
    if [[ -z $ONLY_SECTIONS ]]; then
        case $section in
            summary) min_level=0 ;;
            system|virt|cpu|memory|storage|network) min_level=1 ;;
            kernel) min_level=2 ;;
            benchmark) min_level=0 ;;
        esac
        ((LEVEL >= min_level)) || return 1
    fi
    return 0
}


init_style() {
    local use_color=0
    case $COLOR_MODE in
        always) use_color=1 ;;
        never)  use_color=0 ;;
        auto)
            if [[ -t 1 && ${TERM-} != "dumb" && -z ${NO_COLOR-} ]]; then
                use_color=1
            fi
            ;;
    esac

    if ((use_color)); then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_BLUE=$'\033[34m'
        C_CYAN=$'\033[36m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_RED=$'\033[31m'
        C_MAGENTA=$'\033[35m'
    fi

    if ((PLAIN == 0)) && [[ ${LC_ALL-${LC_CTYPE-${LANG-}}} == *UTF-8* || ${LC_ALL-${LC_CTYPE-${LANG-}}} == *utf8* ]]; then
        GLYPH_BAR="─"
        GLYPH_OK="✓"
        GLYPH_WARN="⚠"
        GLYPH_INFO="•"
        GLYPH_FILL="█"
        GLYPH_EMPTY="░"
        GLYPH_SUB="└─"
    fi
}


repeat_char() {
    local char=$1
    local count=$2
    local out=""
    while ((count > 0)); do
        out+=$char
        ((count--))
    done
    printf '%s' "$out"
}


level_name() {
    case $LEVEL in
        0) printf 'essential' ;;
        1) printf 'normal' ;;
        2) printf 'detail' ;;
        3) printf 'full' ;;
    esac
}

display_width() {
    # 终端宽度的轻量近似：ASCII 计 1，非 ASCII 计 2。
    # 在 UTF-8 locale 下可让常见中英文标签基本对齐，无需依赖 column/wcwidth。
    local text=$1 char
    local width=0 i
    for ((i = 0; i < ${#text}; i++)); do
        char=${text:i:1}
        if [[ $char == [\ -~] ]]; then
            ((width += 1))
        else
            ((width += 2))
        fi
    done
    printf '%s' "$width"
}

subsection() {
    printf '  %s%s %s%s\n' "$C_DIM" "$GLYPH_SUB" "$1" "$C_RESET"
}

metric_bar() {
    local label=$1 percentage=${2:-0} detail=$3 warn_at=$4 bad_at=$5
    local normalized filled empty color width pad
    normalized=$(awk -v p="$percentage" 'BEGIN {
        if (p < 0) p=0;
        if (p > 100) p=100;
        printf "%.1f", p
    }')
    filled=$(awk -v p="$normalized" -v n="$BAR_WIDTH" 'BEGIN {printf "%d", (p*n/100)+0.5}')
    ((filled > BAR_WIDTH)) && filled=$BAR_WIDTH
    empty=$((BAR_WIDTH - filled))

    color=$C_GREEN
    if awk -v p="$percentage" -v b="$bad_at" 'BEGIN {exit !(p >= b)}'; then
        color=$C_RED
    elif awk -v p="$percentage" -v w="$warn_at" 'BEGIN {exit !(p >= w)}'; then
        color=$C_YELLOW
    fi

    width=$(display_width "$label")
    pad=$((12 - width))
    ((pad < 1)) && pad=1
    printf '  %s%s%s%s[%s%s%s%s%s] %s%6s%%%s  %s\n' \
        "$C_CYAN" "$label" "$C_RESET" "$(repeat_char ' ' "$pad")" \
        "$color" "$(repeat_char "$GLYPH_FILL" "$filled")" "$C_DIM" \
        "$(repeat_char "$GLYPH_EMPTY" "$empty")" "$C_RESET" \
        "$color" "$percentage" "$C_RESET" "$detail"
}

effective_memory_raw() {
    # 输出：used_bytes total_bytes source，其中 source 为 system 或 cgroup。
    local total_kib available_kib host_total host_used cg_current cg_limit
    total_kib=$(proc_mem_kib MemTotal)
    available_kib=$(proc_mem_kib MemAvailable)
    [[ -z $available_kib ]] && available_kib=$(proc_mem_kib MemFree)
    host_total=$(( ${total_kib:-0} * 1024 ))
    host_used=$(( (${total_kib:-0} - ${available_kib:-0}) * 1024 ))
    ((host_used < 0)) && host_used=0

    cg_current=$(cgroup_memory_current_number 2>/dev/null || true)
    cg_limit=$(cgroup_memory_limit_number 2>/dev/null || true)
    if [[ -n $cg_current && -n $cg_limit ]] \
        && awk -v l="$cg_limit" -v h="$host_total" 'BEGIN {exit !(h > 0 && l < h)}'; then
        printf '%s %s cgroup\n' "$cg_current" "$cg_limit"
    else
        printf '%s %s system\n' "$host_used" "$host_total"
    fi
}

print_header() {
    ((SHOW_HEADER)) || return 0
    local host generated mode
    host=$(hostname_value)
    generated=$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || printf '未知时间')
    mode=$(level_name)

    if ((PLAIN)); then
        printf '+----------+  %sLinux 服务器配置概览%s  %sv%s%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$SCRIPT_VERSION" "$C_RESET"
        printf '|  o  o    |  主机  %s\n' "$host"
        printf '+----------+  级别  %s · 生成于 %s\n' "$mode" "$generated"
        printf '|  o  o    |  只读采集 · 默认离线 · 基准按需\n'
        printf '+----------+\n'
    else
        printf '%s╭──────────╮%s  %s%sLinux 服务器配置概览%s  %sv%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_DIM" "$SCRIPT_VERSION" "$C_RESET"
        printf '%s│  ●  ●    │%s  %s主机%s  %s\n' "$C_BLUE" "$C_RESET" "$C_DIM" "$C_RESET" "$host"
        printf '%s├──────────┤%s  %s级别%s  %s · 生成于 %s\n' "$C_BLUE" "$C_RESET" "$C_DIM" "$C_RESET" "$mode" "$generated"
        printf '%s│  ●  ●    │%s  %s只读采集 · 默认离线 · 基准按需%s\n' "$C_BLUE" "$C_RESET" "$C_DIM" "$C_RESET"
        printf '%s╰──────────╯%s\n' "$C_BLUE" "$C_RESET"
    fi
}


section() {
    local title=$1
    ((SECTION_INDEX += 1))
    printf '\n%s%s[%d. %s]%s\n' "$C_BOLD" "$C_CYAN" "$SECTION_INDEX" "$title" "$C_RESET"
}


kv() {
    local key=$1
    local value=${2:-"不可用"}
    local width pad
    width=$(display_width "$key")
    pad=$((16 - width))
    ((pad < 1)) && pad=1
    printf '  %s%s%s%s%s%s%s\n' \
        "$C_CYAN" "$key" "$C_RESET" "$(repeat_char ' ' "$pad")" \
        "$C_GREEN" "$value" "$C_RESET"
}


status_line() {
    local level=$1
    local message=$2
    case $level in
        ok)   printf '  %s%s%s %s\n' "$C_GREEN" "$GLYPH_OK" "$C_RESET" "$message" ;;
        warn) printf '  %s%s%s %s\n' "$C_YELLOW" "$GLYPH_WARN" "$C_RESET" "$message" ;;
        bad)  printf '  %s%s%s %s\n' "$C_RED" "$GLYPH_WARN" "$C_RESET" "$message" ;;
        *)    printf '  %s%s%s %s%s%s\n' "$C_BLUE" "$GLYPH_INFO" "$C_RESET" "$C_DIM" "$message" "$C_RESET" ;;
    esac
}


indent_command() {
    # 将命令输出缩进；保留命令的退出码。
    local output rc
    output=$("$@" 2>/dev/null)
    rc=$?
    if [[ -n $output ]]; then
        while IFS= read -r line; do
            printf '  %s\n' "$line"
        done <<< "$output"
    fi
    return "$rc"
}

redact_value() {
    local kind=$1
    local value=$2
    if ((REDACT == 0)); then
        printf '%s' "$value"
        return
    fi
    case $kind in
        hostname) printf '<已隐藏主机名>' ;;
        ip)       printf '<已隐藏 IP>' ;;
        mac)      printf '<已隐藏 MAC>' ;;
        id)       printf '<已隐藏标识>' ;;
        *)        printf '<已隐藏>' ;;
    esac
}

read_first_line() {
    local file=$1
    [[ -r $file ]] || return 1
    IFS= read -r _line < "$file" || true
    printf '%s' "${_line-}"
}

read_os_release_value() {
    local wanted=$1
    local key value
    [[ -r /etc/os-release ]] || return 1
    while IFS='=' read -r key value; do
        [[ $key == "$wanted" ]] || continue
        value=${value%$'\r'}
        if [[ $value == \"*\" && $value == *\" ]]; then
            value=${value:1:${#value}-2}
            value=${value//\\\"/\"}
            value=${value//\\n/$'\n'}
            value=${value//\\\\/\\}
        elif [[ $value == \'*\' && $value == *\' ]]; then
            value=${value:1:${#value}-2}
        fi
        printf '%s' "$value"
        return 0
    done < /etc/os-release
    return 1
}

human_bytes() {
    local bytes=${1:-0}
    awk -v b="$bytes" 'BEGIN {
        split("B KiB MiB GiB TiB PiB", u, " ");
        i=1;
        while (b >= 1024 && i < 6) { b /= 1024; i++ }
        if (i == 1) printf "%.0f %s", b, u[i];
        else printf "%.2f %s", b, u[i];
    }'
}

human_kib() {
    local kib=${1:-0}
    human_bytes "$((kib * 1024))"
}

human_duration() {
    local total=${1:-0}
    local days hours mins secs
    days=$((total / 86400))
    hours=$(((total % 86400) / 3600))
    mins=$(((total % 3600) / 60))
    secs=$((total % 60))
    if ((days > 0)); then
        printf '%d天 %02d:%02d:%02d' "$days" "$hours" "$mins" "$secs"
    else
        printf '%02d:%02d:%02d' "$hours" "$mins" "$secs"
    fi
}

percent() {
    local numerator=${1:-0}
    local denominator=${2:-0}
    awk -v n="$numerator" -v d="$denominator" 'BEGIN {
        if (d <= 0) print "0.0"; else printf "%.1f", n * 100 / d
    }'
}

proc_mem_kib() {
    local key=$1
    awk -v k="$key" '$1 == k ":" {print $2; exit}' /proc/meminfo 2>/dev/null
}

logical_cpu_count() {
    local count=""
    if command_exists getconf; then
        count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
    fi
    if ! is_uint "${count:-}"; then
        count=$(awk '/^processor[[:space:]]*:/ {n++} END {print n+0}' /proc/cpuinfo 2>/dev/null)
    fi
    if ! is_uint "${count:-}" || ((count < 1)); then
        count=1
    fi
    printf '%s' "$count"
}

cpu_model() {
    local model=""
    if command_exists lscpu; then
        model=$(LC_ALL=C lscpu 2>/dev/null | awk -F: '$1 == "Model name" {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
    fi
    if [[ -z $model && -r /proc/cpuinfo ]]; then
        model=$(awk -F: '/^model name[[:space:]]*:|^Hardware[[:space:]]*:|^Processor[[:space:]]*:/ {
            sub(/^[[:space:]]+/, "", $2); print $2; exit
        }' /proc/cpuinfo)
    fi
    printf '%s' "${model:-未知}"
}

cpu_vendor() {
    awk -F: '/^vendor_id[[:space:]]*:|^CPU implementer[[:space:]]*:/ {
        sub(/^[[:space:]]+/, "", $2); print $2; exit
    }' /proc/cpuinfo 2>/dev/null
}

cpu_topology() {
    local sockets="" cores="" threads=""
    threads=$(logical_cpu_count)
    if command_exists lscpu; then
        sockets=$(LC_ALL=C lscpu 2>/dev/null | awk -F: '$1 == "Socket(s)" {gsub(/[[:space:]]/, "", $2); print $2; exit}')
        cores=$(LC_ALL=C lscpu 2>/dev/null | awk -F: '$1 == "Core(s) per socket" {gsub(/[[:space:]]/, "", $2); print $2; exit}')
        if is_uint "${sockets:-}" && is_uint "${cores:-}"; then
            cores=$((sockets * cores))
        else
            cores=""
        fi
    fi
    if [[ -z $cores ]] && command_exists sort && [[ -d /sys/devices/system/cpu ]]; then
        local path local_dir core package
        cores=$(for path in /sys/devices/system/cpu/cpu[0-9]*/topology/core_id; do
            [[ -r $path ]] || continue
            local_dir=${path%/core_id}
            core=$(cat "$path" 2>/dev/null || true)
            package=$(cat "$local_dir/physical_package_id" 2>/dev/null || printf '0')
            printf '%s:%s\n' "$package" "$core"
        done | sort -u | awk 'NF {n++} END {print n+0}')
    fi
    if ! is_uint "${cores:-}" || ((cores < 1)); then
        cores=$threads
    fi
    printf '%s 核 / %s 线程' "$cores" "$threads"
}

cpu_max_frequency() {
    local khz="" mhz=""
    for file in \
        /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq \
        /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq; do
        if [[ -r $file ]]; then
            khz=$(read_first_line "$file")
            break
        fi
    done
    if is_uint "${khz:-}" && ((khz > 0)); then
        awk -v k="$khz" 'BEGIN {printf "%.2f GHz", k / 1000000}'
        return
    fi
    mhz=$(awk -F: '/^cpu MHz[[:space:]]*:/ {sum += $2; n++} END {if (n) printf "%.2f GHz", sum / n / 1000}' /proc/cpuinfo 2>/dev/null)
    printf '%s' "${mhz:-不可用}"
}

cpu_cache_summary() {
    local result="" level size type
    for dir in /sys/devices/system/cpu/cpu0/cache/index*; do
        [[ -d $dir && -r $dir/level && -r $dir/size ]] || continue
        level=$(read_first_line "$dir/level")
        size=$(read_first_line "$dir/size")
        type=$(read_first_line "$dir/type")
        [[ -n $result ]] && result+=", "
        result+="L${level} ${type} ${size}"
    done
    printf '%s' "${result:-不可用}"
}

cpu_steal_percent() {
    local _cpu user nice system idle iowait irq softirq steal guest guest_nice total
    [[ -r /proc/stat ]] || return 1
    read -r _cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    user=${user:-0}; nice=${nice:-0}; system=${system:-0}; idle=${idle:-0}
    iowait=${iowait:-0}; irq=${irq:-0}; softirq=${softirq:-0}; steal=${steal:-0}
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    percent "$steal" "$total"
}

load_averages() {
    awk '{print $1 " / " $2 " / " $3}' /proc/loadavg 2>/dev/null
}

detect_virtualization() {
    local value="" dmi="" cgroup=""

    if grep -qi microsoft /proc/sys/kernel/osrelease /proc/version 2>/dev/null; then
        printf 'WSL'
        return
    fi

    if command_exists systemd-detect-virt; then
        value=$(systemd-detect-virt 2>/dev/null || true)
        if [[ -n $value && $value != "none" ]]; then
            printf '%s' "$value"
            return
        fi
    fi

    cgroup=$(cat /proc/1/cgroup 2>/dev/null || true)
    case $(lower "$cgroup") in
        *docker*)     printf 'Docker'; return ;;
        *kubepods*)   printf 'Kubernetes'; return ;;
        *containerd*) printf 'containerd'; return ;;
        *lxc*)        printf 'LXC'; return ;;
        *podman*)     printf 'Podman'; return ;;
    esac
    [[ -f /.dockerenv ]] && { printf 'Docker'; return; }
    [[ -f /run/.containerenv ]] && { printf '容器'; return; }

    for file in /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/board_vendor; do
        [[ -r $file ]] && dmi+=" $(cat "$file" 2>/dev/null)"
    done
    dmi=$(lower "$dmi")
    case $dmi in
        *kvm*|*qemu*)                 printf 'KVM/QEMU'; return ;;
        *vmware*)                     printf 'VMware'; return ;;
        *virtualbox*)                 printf 'VirtualBox'; return ;;
        *xen*)                        printf 'Xen'; return ;;
        *microsoft*virtual*|*hyper-v*) printf 'Hyper-V'; return ;;
        *amazon*ec2*)                 printf 'Amazon EC2'; return ;;
        *google*)                     printf 'Google Compute Engine'; return ;;
        *openstack*)                  printf 'OpenStack'; return ;;
    esac

    if grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
        printf '虚拟机（类型未知）'
    elif [[ -d /sys/hypervisor ]]; then
        printf 'Hypervisor'
    else
        printf '物理机或未识别'
    fi
}

cgroup_version() {
    if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
        printf 'v2'
    elif awk '$0 ~ / - cgroup / {found=1} END {exit !found}' /proc/self/mountinfo 2>/dev/null; then
        printf 'v1'
    else
        printf '不可用'
    fi
}

cgroup_v2_mountpoint() {
    awk '
        {
            for (i=1; i<=NF; i++) {
                if ($i == "-" && $(i+1) == "cgroup2") {print $5; exit}
            }
        }
    ' /proc/self/mountinfo 2>/dev/null
}

cgroup_v1_mountpoint() {
    local controller=$1
    awk -v wanted="$controller" '
        {
            sep=0
            for (i=1; i<=NF; i++) {
                if ($i == "-") {sep=i; break}
            }
            if (!sep || $(sep+1) != "cgroup") next
            n=split($(sep+3), opts, ",")
            for (j=1; j<=n; j++) {
                if (opts[j] == wanted) {print $5; exit}
            }
        }
    ' /proc/self/mountinfo 2>/dev/null
}

cgroup_relative_path() {
    local controller=$1
    if [[ $(cgroup_version) == "v2" ]]; then
        awk -F: '$1 == "0" {print $3; exit}' /proc/self/cgroup 2>/dev/null
    else
        awk -F: -v wanted="$controller" '
            {
                n=split($2, controllers, ",")
                for (i=1; i<=n; i++) {
                    if (controllers[i] == wanted) {print $3; exit}
                }
            }
        ' /proc/self/cgroup 2>/dev/null
    fi
}

cgroup_file() {
    local controller=$1
    local filename=$2
    local version mountpoint relative path
    version=$(cgroup_version)
    case $version in
        v2) mountpoint=$(cgroup_v2_mountpoint) ;;
        v1) mountpoint=$(cgroup_v1_mountpoint "$controller") ;;
        *) return 1 ;;
    esac
    relative=$(cgroup_relative_path "$controller")
    [[ -n $mountpoint ]] || return 1
    [[ -n $relative ]] || relative="/"
    path="${mountpoint%/}${relative%/}/$filename"
    if [[ -r $path ]]; then
        printf '%s' "$path"
        return 0
    fi
    # 某些 cgroup namespace 只暴露当前组为挂载根，退回挂载点根目录。
    path="${mountpoint%/}/$filename"
    [[ -r $path ]] || return 1
    printf '%s' "$path"
}

cgroup_cpu_raw() {
    local max_file quota_file period_file quota period
    if [[ $(cgroup_version) == "v2" ]]; then
        max_file=$(cgroup_file cpu cpu.max 2>/dev/null || true)
        [[ -n $max_file ]] || return 1
        read -r quota period < "$max_file"
    else
        quota_file=$(cgroup_file cpu cpu.cfs_quota_us 2>/dev/null || true)
        period_file=$(cgroup_file cpu cpu.cfs_period_us 2>/dev/null || true)
        [[ -n $quota_file && -n $period_file ]] || return 1
        quota=$(read_first_line "$quota_file")
        period=$(read_first_line "$period_file")
    fi
    printf '%s %s\n' "$quota" "$period"
}

cgroup_cpu_quota() {
    local quota period
    read -r quota period < <(cgroup_cpu_raw 2>/dev/null) || {
        printf '不可用'
        return
    }
    [[ $quota == "max" || $quota == "-1" ]] && {
        printf '无限制'
        return
    }
    if is_uint "${quota:-}" && is_uint "${period:-}" && ((period > 0)); then
        awk -v q="$quota" -v p="$period" 'BEGIN {printf "%.2f CPU", q / p}'
    else
        printf '不可用'
    fi
}

cgroup_cpu_quota_number() {
    local quota period
    read -r quota period < <(cgroup_cpu_raw 2>/dev/null) || return 1
    [[ $quota == "max" || $quota == "-1" ]] && return 1
    is_uint "${quota:-}" && is_uint "${period:-}" && ((period > 0)) || return 1
    awk -v q="$quota" -v p="$period" 'BEGIN {printf "%.2f", q / p}'
}

effective_cpu_capacity() {
    local logical quota
    logical=$(logical_cpu_count)
    quota=$(cgroup_cpu_quota_number 2>/dev/null || true)
    if [[ -n $quota ]] && awk -v q="$quota" -v l="$logical" 'BEGIN {exit !(q < l)}'; then
        printf '%s' "$quota"
    else
        printf '%s' "$logical"
    fi
}

cgroup_memory_raw() {
    local current_file limit_file current limit
    if [[ $(cgroup_version) == "v2" ]]; then
        current_file=$(cgroup_file memory memory.current 2>/dev/null || true)
        limit_file=$(cgroup_file memory memory.max 2>/dev/null || true)
    else
        current_file=$(cgroup_file memory memory.usage_in_bytes 2>/dev/null || true)
        limit_file=$(cgroup_file memory memory.limit_in_bytes 2>/dev/null || true)
    fi
    [[ -n $current_file && -n $limit_file ]] || return 1
    current=$(read_first_line "$current_file")
    limit=$(read_first_line "$limit_file")
    printf '%s %s\n' "$current" "$limit"
}

cgroup_memory_current_number() {
    local current limit
    read -r current limit < <(cgroup_memory_raw 2>/dev/null) || return 1
    is_uint "${current:-}" || return 1
    printf '%s' "$current"
    : "$limit"
}

cgroup_memory_limit_number() {
    local current limit
    read -r current limit < <(cgroup_memory_raw 2>/dev/null) || return 1
    [[ $limit == "max" ]] && return 1
    is_uint "${limit:-}" || return 1
    # cgroup v1 用接近 int64 上限的数值表示“不限制”。
    awk -v l="$limit" 'BEGIN {exit !(l < 9e18)}' || return 1
    printf '%s' "$limit"
    : "$current"
}

cgroup_memory_values() {
    local current limit
    read -r current limit < <(cgroup_memory_raw 2>/dev/null) || {
        printf '不可用'
        return
    }
    if [[ $limit == "max" ]] || ! awk -v l="$limit" 'BEGIN {exit !(l < 9e18)}'; then
        printf '%s / 无限制' "$(human_bytes "$current")"
    elif is_uint "$current" && is_uint "$limit"; then
        printf '%s / %s（%s%%）' \
            "$(human_bytes "$current")" "$(human_bytes "$limit")" "$(percent "$current" "$limit")"
    else
        printf '不可用'
    fi
}

cgroup_pids_limit() {
    local file value=""
    file=$(cgroup_file pids pids.max 2>/dev/null || true)
    [[ -n $file ]] && value=$(read_first_line "$file")
    printf '%s' "${value:-不可用}"
}

hostname_value() {
    local value=""
    if command_exists hostname; then
        value=$(hostname 2>/dev/null || true)
    fi
    [[ -z $value ]] && value=$(read_first_line /proc/sys/kernel/hostname 2>/dev/null || true)
    redact_value hostname "${value:-未知}"
}

primary_ip() {
    local value=""
    if command_exists ip; then
        value=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')
    fi
    if [[ -z $value ]] && command_exists hostname; then
        value=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    redact_value ip "${value:-不可用}"
}

root_filesystem_summary() {
    if command_exists df; then
        df -hP / 2>/dev/null | awk 'NR==2 {printf "%s / %s（%s 已用）", $3, $2, $5}'
    else
        printf '不可用'
    fi
}

boot_mode() {
    [[ -d /sys/firmware/efi ]] && printf 'UEFI' || printf 'Legacy/未知'
}

init_system() {
    local init=""
    if command_exists ps; then
        init=$(ps -p 1 -o comm= 2>/dev/null | awk '{$1=$1; print}')
    fi
    [[ -z $init ]] && init=$(read_first_line /proc/1/comm 2>/dev/null || true)
    printf '%s' "${init:-未知}"
}

summary_section() {
    section_enabled summary || return 0
    section "关键状态"

    local cpus load1 load_pct mem_used mem_total mem_source mem_pct
    local root_pct root_detail steal warning_count=0
    cpus=$(effective_cpu_capacity)
    load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    load_pct=$(awk -v l="${load1:-0}" -v c="$cpus" 'BEGIN {if (c>0) printf "%.1f", l*100/c; else print "0.0"}')
    read -r mem_used mem_total mem_source < <(effective_memory_raw)
    mem_pct=$(percent "$mem_used" "$mem_total")
    root_pct=$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
    root_detail=$(root_filesystem_summary)
    steal=$(cpu_steal_percent 2>/dev/null || printf '0.0')

    metric_bar "CPU 负载" "$load_pct" "${load1:-?} / ${cpus} CPU" 80 100
    metric_bar "内存使用" "$mem_pct" "$(human_bytes "$mem_used") / $(human_bytes "$mem_total") · ${mem_source}" 80 90
    metric_bar "根分区" "${root_pct:-0}" "$root_detail" 80 90
    metric_bar "CPU Steal" "$steal" "${steal}% · 自启动累计" 3 10

    if awk -v p="$load_pct" 'BEGIN {exit !(p >= 100)}'; then
        status_line warn "当前 1 分钟负载已达到有效 CPU 容量"
        ((warning_count += 1))
    fi
    if awk -v p="$mem_pct" 'BEGIN {exit !(p >= 90)}'; then
        status_line bad "有效内存使用率较高"
        ((warning_count += 1))
    elif awk -v p="$mem_pct" 'BEGIN {exit !(p >= 80)}'; then
        status_line warn "有效内存使用偏高"
        ((warning_count += 1))
    fi
    if is_uint "${root_pct:-}" && ((root_pct >= 90)); then
        status_line bad "根分区空间紧张"
        ((warning_count += 1))
    elif is_uint "${root_pct:-}" && ((root_pct >= 80)); then
        status_line warn "根分区使用率偏高"
        ((warning_count += 1))
    fi
    if awk -v p="$steal" 'BEGIN {exit !(p >= 10)}'; then
        status_line bad "CPU steal 较高，宿主机争用可能明显"
        ((warning_count += 1))
    elif awk -v p="$steal" 'BEGIN {exit !(p >= 3)}'; then
        status_line warn "CPU steal 偏高，建议分时段复测"
        ((warning_count += 1))
    fi
    ((warning_count == 0)) && status_line ok "当前快照未发现明显资源压力"
}


system_section() {
    section_enabled system || return 0
    section "系统与内核"
    local os uptime_seconds timezone now
    os=$(read_os_release_value PRETTY_NAME 2>/dev/null || true)
    [[ -z $os ]] && os=$(uname -s 2>/dev/null || printf 'Linux')
    uptime_seconds=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null)

    ((SHOW_HEADER == 0)) && kv "主机名" "$(hostname_value)"
    kv "操作系统" "$os"
    kv "内核版本" "$(uname -r 2>/dev/null || printf '不可用')"
    kv "系统架构" "$(uname -m 2>/dev/null || printf '不可用')"
    kv "运行时间" "$(human_duration "${uptime_seconds:-0}")"

    if ((LEVEL >= 2)); then
        timezone=$(cat /etc/timezone 2>/dev/null || date +%Z 2>/dev/null || true)
        now=$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || true)
        kv "当前时间" "${now:-不可用}"
        kv "时区" "${timezone:-不可用}"
        kv "启动模式" "$(boot_mode)"
        kv "PID 1" "$(init_system)"
        kv "系统语言" "${LANG-未设置}"
    fi

    if ((LEVEL >= 3)); then
        if ((REDACT)); then
            kv "内核命令行" "<已隐藏>"
        else
            kv "内核命令行" "$(read_first_line /proc/cmdline 2>/dev/null || printf '不可用')"
        fi
        kv "机器 ID" "$(redact_value id "$(read_first_line /etc/machine-id 2>/dev/null || printf '不可用')")"
        kv "内核编译信息" "$(cat /proc/version 2>/dev/null || printf '不可用')"
        kv "当前时钟源" "$(read_first_line /sys/devices/system/clocksource/clocksource0/current_clocksource 2>/dev/null || printf '不可用')"
        kv "可用时钟源" "$(read_first_line /sys/devices/system/clocksource/clocksource0/available_clocksource 2>/dev/null || printf '不可用')"
    fi
}


virt_section() {
    section_enabled virt || return 0
    section "虚拟化与资源配额"
    local logical quota cg_current cg_limit host_total limited=0
    logical=$(logical_cpu_count)
    quota=$(cgroup_cpu_quota_number 2>/dev/null || true)
    cg_current=$(cgroup_memory_current_number 2>/dev/null || true)
    cg_limit=$(cgroup_memory_limit_number 2>/dev/null || true)
    host_total=$(( $(proc_mem_kib MemTotal 2>/dev/null || printf '0') * 1024 ))

    kv "运行环境" "$(detect_virtualization)"
    if [[ -n $quota ]] && awk -v q="$quota" -v l="$logical" 'BEGIN {exit !(q < l)}'; then
        kv "CPU 配额" "${quota} CPU（系统可见 ${logical} 线程）"
        limited=1
    fi
    if [[ -n $cg_current && -n $cg_limit ]] \
        && awk -v l="$cg_limit" -v h="$host_total" 'BEGIN {exit !(h > 0 && l < h)}'; then
        kv "内存配额" "$(human_bytes "$cg_current") / $(human_bytes "$cg_limit")（$(percent "$cg_current" "$cg_limit")%）"
        limited=1
    fi
    ((limited == 0)) && status_line info "未检测到低于系统可见资源的 cgroup CPU/内存上限"

    if ((LEVEL >= 2)); then
        kv "cgroup 版本" "$(cgroup_version)"
        kv "进程数上限" "$(cgroup_pids_limit)"
        local product vendor board
        product=$(read_first_line /sys/class/dmi/id/product_name 2>/dev/null || true)
        vendor=$(read_first_line /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
        board=$(read_first_line /sys/class/dmi/id/board_name 2>/dev/null || true)
        [[ -n $vendor ]] && kv "系统厂商" "$vendor"
        [[ -n $product ]] && kv "产品型号" "$product"
        [[ -n $board ]] && kv "主板型号" "$board"
    fi

    if ((LEVEL >= 3)); then
        local uuid serial
        uuid=$(read_first_line /sys/class/dmi/id/product_uuid 2>/dev/null || true)
        serial=$(read_first_line /sys/class/dmi/id/product_serial 2>/dev/null || true)
        [[ -n $uuid ]] && kv "产品 UUID" "$(redact_value id "$uuid")"
        [[ -n $serial ]] && kv "产品序列号" "$(redact_value id "$serial")"
        if [[ -r /proc/1/cgroup ]]; then
            subsection "/proc/1/cgroup"
            indent_command sed -n '1,20p' /proc/1/cgroup || true
        fi
    fi
}


cpu_section() {
    section_enabled cpu || return 0
    section "处理器"
    local steal flags logical quota
    steal=$(cpu_steal_percent 2>/dev/null || printf '不可用')
    logical=$(logical_cpu_count)
    quota=$(cgroup_cpu_quota_number 2>/dev/null || true)

    kv "CPU 型号" "$(cpu_model)"
    kv "核心拓扑" "$(cpu_topology)"
    if ! section_enabled virt && [[ -n $quota ]] \
        && awk -v q="$quota" -v l="$logical" 'BEGIN {exit !(q < l)}'; then
        kv "有效算力" "${quota} CPU（受 cgroup 限制）"
    fi
    kv "当前频率" "$(cpu_max_frequency)"
    if ! section_enabled summary; then
        kv "负载 1/5/15m" "$(load_averages)"
        kv "CPU Steal" "${steal}%（自启动累计）"
    fi

    if ((LEVEL >= 2)); then
        kv "CPU 厂商" "$(cpu_vendor)"
        kv "缓存概览" "$(cpu_cache_summary)"
        if [[ -r /sys/devices/system/cpu/smt/active ]]; then
            kv "SMT" "$([[ $(read_first_line /sys/devices/system/cpu/smt/active) == 1 ]] && printf '启用' || printf '禁用')"
        fi
        if [[ -r /proc/loadavg ]]; then
            kv "可运行/进程" "$(awk '{print $4}' /proc/loadavg)"
        fi
        flags=$(awk -F: '/^flags[[:space:]]*:|^Features[[:space:]]*:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
        local capabilities="" feature
        for feature in vmx svm aes avx avx2 avx512f sha_ni; do
            if [[ " $flags " == *" $feature "* ]]; then
                [[ -n $capabilities ]] && capabilities+=", "
                capabilities+=$feature
            fi
        done
        kv "关键指令集" "${capabilities:-未检测到/不可用}"
        if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
            kv "频率调节器" "$(read_first_line /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
        fi
    fi

    if ((LEVEL >= 3)); then
        flags=$(awk -F: '/^flags[[:space:]]*:|^Features[[:space:]]*:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
        kv "完整 CPU flags" "${flags:-不可用}"
        if command_exists lscpu; then
            subsection "lscpu 完整输出"
            indent_command lscpu || true
        fi
    fi
}


memory_section() {
    section_enabled memory || return 0
    section "内存与 Swap"
    local used total source available swap_total swap_free swap_used
    local host_total_kib host_available_kib host_used_kib extra_output line
    read -r used total source < <(effective_memory_raw)
    available=$((total - used))
    ((available < 0)) && available=0
    swap_total=$(proc_mem_kib SwapTotal)
    swap_free=$(proc_mem_kib SwapFree)
    swap_used=$(( ${swap_total:-0} - ${swap_free:-0} ))

    if ! section_enabled summary; then
        kv "有效内存" "$(human_bytes "$used") / $(human_bytes "$total")（$(percent "$used" "$total")%）"
    fi
    kv "可用内存" "$(human_bytes "$available")"
    kv "Swap" "$(human_kib "$swap_used") / $(human_kib "${swap_total:-0}")（$(percent "$swap_used" "${swap_total:-0}")%）"

    if ((LEVEL >= 2)); then
        if [[ $source == cgroup ]]; then
            host_total_kib=$(proc_mem_kib MemTotal)
            host_available_kib=$(proc_mem_kib MemAvailable)
            [[ -z $host_available_kib ]] && host_available_kib=$(proc_mem_kib MemFree)
            host_used_kib=$(( ${host_total_kib:-0} - ${host_available_kib:-0} ))
            kv "系统可见内存" "$(human_kib "$host_used_kib") / $(human_kib "${host_total_kib:-0}")（不代表实例上限）"
        fi
        kv "页缓存" "$(human_kib "$(proc_mem_kib Cached)")"
        kv "缓冲区" "$(human_kib "$(proc_mem_kib Buffers)")"
        kv "共享内存" "$(human_kib "$(proc_mem_kib Shmem)")"
        kv "脏页" "$(human_kib "$(proc_mem_kib Dirty)")"
        kv "HugePages" "$(proc_mem_kib HugePages_Free) / $(proc_mem_kib HugePages_Total) 空闲/总数"
        kv "HugePage 大小" "$(human_kib "$(proc_mem_kib Hugepagesize)")"
        kv "内存提交" "$(human_kib "$(proc_mem_kib Committed_AS)") / $(human_kib "$(proc_mem_kib CommitLimit)")"
    fi

    if ((LEVEL >= 3)); then
        if command_exists swapon; then
            extra_output=$(swapon --show --bytes 2>/dev/null || true)
            if [[ -n $extra_output ]]; then
                subsection "Swap 设备"
                while IFS= read -r line; do printf '  %s\n' "$line"; done <<< "$extra_output"
            fi
        fi
        if command_exists zramctl; then
            extra_output=$(zramctl 2>/dev/null || true)
            if [[ -n $extra_output ]]; then
                subsection "zram"
                while IFS= read -r line; do printf '  %s\n' "$line"; done <<< "$extra_output"
            fi
        fi
    fi
}


storage_section() {
    section_enabled storage || return 0
    section "存储"
    if ! section_enabled summary; then
        kv "根分区" "$(root_filesystem_summary)"
    fi
    if command_exists findmnt; then
        kv "根挂载" "$(findmnt -n -o SOURCE,FSTYPE / 2>/dev/null || printf '不可用')"
    fi

    if ((LEVEL >= 1)) && command_exists lsblk; then
        local devices
        devices=$(lsblk -dn -e 1,7 -o NAME,SIZE,ROTA,TYPE,MODEL 2>/dev/null \
            | awk '$4 == "disk" {model=$5; for(i=6;i<=NF;i++) model=model " " $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", model); printf "%s  %s  %s  %s\n", $1, $2, ($3==0?"非旋转":"旋转标志=1"), (model==""?"-":model)}')
        if [[ -n $devices ]]; then
            subsection "块设备（名称 / 容量 / 类型 / 型号）"
            while IFS= read -r line; do printf '  %s\n' "$line"; done <<< "$devices"
        fi
    fi

    if ((LEVEL >= 2)); then
        if command_exists df; then
            subsection "主要文件系统"
            if LC_ALL=C df --help 2>&1 | grep -q -- '-T'; then
                df -hPT 2>/dev/null | awk '
                    NR==1 {print "  " $0; next}
                    $2 ~ /^(tmpfs|devtmpfs|proc|sysfs|cgroup|cgroup2|mqueue|debugfs|tracefs|securityfs)$/ {next}
                    $7 ~ /^\/(proc|sys|dev)(\/|$)/ {next}
                    {print "  " $0}
                '
            else
                indent_command df -hP || true
            fi
            subsection "Inode 使用"
            indent_command df -hiP -x tmpfs -x devtmpfs || true
        fi
        local path dev scheduler rotational
        for path in /sys/block/*; do
            [[ -d $path ]] || continue
            dev=${path##*/}
            [[ $dev == loop* || $dev == ram* ]] && continue
            scheduler=$(read_first_line "$path/queue/scheduler" 2>/dev/null || printf '不可用')
            rotational=$(read_first_line "$path/queue/rotational" 2>/dev/null || printf '?')
            kv "$dev I/O" "$scheduler · rotational=${rotational}"
        done
    fi

    if ((LEVEL >= 3)); then
        if command_exists lsblk; then
            subsection "lsblk 完整输出"
            if LC_ALL=C lsblk --help 2>&1 | grep -q 'MOUNTPOINTS'; then
                indent_command lsblk -e 1,7 -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,ROTA,MODEL || true
            else
                indent_command lsblk -e 1,7 -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,ROTA,MODEL || true
            fi
        fi
        if command_exists findmnt; then
            if ((REDACT)); then
                status_line info "--redact 已启用，完整挂载源未展开"
            else
                subsection "全部挂载（排除常见伪文件系统）"
                findmnt -r -n -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null \
                    | awk '$3 !~ /^(sysfs|proc|tmpfs|devtmpfs|devpts|cgroup|cgroup2|mqueue|debugfs|tracefs|securityfs|pstore|configfs)$/ {print "  " $0}'
            fi
        fi
    fi
}


network_section() {
    section_enabled network || return 0
    section "网络"
    kv "主要 IPv4" "$(primary_ip)"

    if command_exists ip; then
        local route gateway iface
        route=$(ip -4 route show default 2>/dev/null | head -n 1)
        gateway=$(awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}' <<< "$route")
        iface=$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<< "$route")
        if ((REDACT)); then
            [[ -n $gateway ]] && gateway='<已隐藏网关>'
        fi
        kv "默认出口" "${iface:-不可用}${gateway:+ · gateway ${gateway}}"
    fi

    local dns
    dns=$(awk '/^nameserver[[:space:]]+/ {if (n++) printf ", "; printf "%s", $2} END {if (n) print ""}' /etc/resolv.conf 2>/dev/null)
    if ((REDACT)) && [[ -n $dns ]]; then dns='<已隐藏 DNS>'; fi
    kv "DNS" "${dns:-不可用}"

    if ((LEVEL >= 2)); then
        if command_exists ip; then
            subsection "活动接口与地址"
            if ((REDACT)); then
                ip -brief address show up 2>/dev/null | awk '{print "  " $1, $2, "<地址已隐藏>"}'
            else
                indent_command ip -brief address show up || true
            fi
        fi
        local path iface_name rx tx mac operstate mtu
        for path in /sys/class/net/*; do
            [[ -d $path ]] || continue
            iface_name=${path##*/}
            operstate=$(read_first_line "$path/operstate" 2>/dev/null || printf '?')
            mtu=$(read_first_line "$path/mtu" 2>/dev/null || printf '?')
            mac=$(read_first_line "$path/address" 2>/dev/null || printf '?')
            rx=$(read_first_line "$path/statistics/rx_bytes" 2>/dev/null || printf '0')
            tx=$(read_first_line "$path/statistics/tx_bytes" 2>/dev/null || printf '0')
            kv "$iface_name" "$operstate · MTU $mtu · MAC $(redact_value mac "$mac") · RX $(human_bytes "$rx") · TX $(human_bytes "$tx")"
        done
        kv "TCP 拥塞控制" "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || printf '不可用')"
        kv "可用拥塞算法" "$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || printf '不可用')"
    fi

    if ((LEVEL >= 3)); then
        if command_exists ip; then
            subsection "路由表"
            if ((REDACT)); then
                status_line info "--redact 已启用，路由表未展开"
            else
                indent_command ip route show table all || true
            fi
        fi
        if command_exists ss; then
            subsection "套接字摘要"
            indent_command ss -s || true
        fi
    fi
}


kernel_section() {
    section_enabled kernel || return 0
    section "内核与运行限制"
    kv "进程 FD 上限" "$(ulimit -n 2>/dev/null || printf '不可用')"
    kv "用户进程上限" "$(ulimit -u 2>/dev/null || printf '不可用')"
    kv "vm.swappiness" "$(cat /proc/sys/vm/swappiness 2>/dev/null || printf '不可用')"
    kv "内存过量分配" "$(cat /proc/sys/vm/overcommit_memory 2>/dev/null || printf '不可用')"
    kv "系统 FD 当前/上限" "$(awk '{print $1 " / " $3}' /proc/sys/fs/file-nr 2>/dev/null || printf '不可用')"
    kv "PID 最大值" "$(cat /proc/sys/kernel/pid_max 2>/dev/null || printf '不可用')"
    kv "THP" "$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || printf '不可用')"

    if ((LEVEL >= 3)); then
        kv "dirty_ratio" "$(cat /proc/sys/vm/dirty_ratio 2>/dev/null || printf '不可用')"
        kv "dirty_background" "$(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null || printf '不可用')"
        kv "somaxconn" "$(cat /proc/sys/net/core/somaxconn 2>/dev/null || printf '不可用')"
        kv "TCP SYN backlog" "$(cat /proc/sys/net/ipv4/tcp_max_syn_backlog 2>/dev/null || printf '不可用')"
        kv "端口范围" "$(cat /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null || printf '不可用')"
        kv "已加载模块数" "$(awk 'END {print NR+0}' /proc/modules 2>/dev/null)"
        kv "进程总数" "$(find /proc -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null | wc -l | awk '{$1=$1;print}')"
        if command_exists ps; then
            subsection "高 CPU 进程（前 8）"
            indent_command ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 9 || true
            subsection "高内存进程（前 8）"
            indent_command ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -n 9 || true
        fi
    fi
}


monotonic_seconds() {
    if [[ -r /proc/uptime ]]; then
        awk '{print $1}' /proc/uptime
    else
        date +%s
    fi
}

elapsed_seconds() {
    local start=$1
    local end=$2
    awk -v s="$start" -v e="$end" 'BEGIN {d=e-s; if (d<=0) d=0.001; printf "%.3f", d}'
}

benchmark_cpu() {
    status_line info "CPU：对 256 MiB 零数据计算 SHA-256；结果同时受内存与实现影响"
    if ! command_exists dd || ! command_exists sha256sum; then
        status_line warn "缺少 dd 或 sha256sum，跳过 CPU 基准"
        return
    fi
    local mib=256 start end elapsed rate
    start=$(monotonic_seconds)
    if ! dd if=/dev/zero bs=1M count="$mib" status=none 2>/dev/null | sha256sum >/dev/null; then
        status_line warn "CPU 基准执行失败"
        return
    fi
    end=$(monotonic_seconds)
    elapsed=$(elapsed_seconds "$start" "$end")
    rate=$(awk -v m="$mib" -v t="$elapsed" 'BEGIN {printf "%.1f", m/t}')
    kv "SHA-256 吞吐" "${rate} MiB/s（${elapsed}s）"
}

available_bytes_for_path() {
    local path=$1
    df -Pk "$path" 2>/dev/null | awk 'NR==2 {print $4 * 1024}'
}

filesystem_type_for_path() {
    local path=$1
    if command_exists findmnt; then
        findmnt -n -o FSTYPE -T "$path" 2>/dev/null
    elif command_exists df && LC_ALL=C df --help 2>&1 | grep -q -- '-T'; then
        df -PT "$path" 2>/dev/null | awk 'NR==2 {print $2}'
    fi
}

benchmark_disk() {
    status_line info "磁盘：顺序写入并 fdatasync，再顺序读取；读取可能命中页缓存"
    if ! command_exists dd || ! command_exists mktemp || ! command_exists df; then
        status_line warn "缺少 dd、mktemp 或 df，跳过磁盘基准"
        return
    fi
    if [[ ! -d $DISK_BENCH_PATH || ! -w $DISK_BENCH_PATH ]]; then
        status_line warn "目录不可写：$DISK_BENCH_PATH"
        return
    fi

    local required available fs_type start end elapsed write_rate read_rate
    required=$((DISK_BENCH_MIB * 1024 * 1024))
    available=$(available_bytes_for_path "$DISK_BENCH_PATH")
    if is_uint "${available:-}" && ((available < required * 2)); then
        status_line warn "可用空间不足：需要至少约 $(human_bytes "$((required * 2))")"
        return
    fi

    fs_type=$(filesystem_type_for_path "$DISK_BENCH_PATH")
    kv "测试目录/文件系统" "$DISK_BENCH_PATH / ${fs_type:-未知}"
    case ${fs_type:-} in
        tmpfs|ramfs|overlay)
            status_line warn "当前文件系统为 ${fs_type}，结果可能主要反映内存或叠加层性能"
            ;;
    esac

    BENCH_TEMP_FILE=$(mktemp "$DISK_BENCH_PATH/.vps-inspect.XXXXXX") || {
        status_line warn "无法创建临时文件"
        return
    }

    start=$(monotonic_seconds)
    if ! dd if=/dev/zero of="$BENCH_TEMP_FILE" bs=1M count="$DISK_BENCH_MIB" conv=fdatasync status=none 2>/dev/null; then
        status_line warn "磁盘写入测试失败"
        cleanup_temp_file
        return
    fi
    end=$(monotonic_seconds)
    elapsed=$(elapsed_seconds "$start" "$end")
    write_rate=$(awk -v m="$DISK_BENCH_MIB" -v t="$elapsed" 'BEGIN {printf "%.1f", m/t}')
    kv "顺序写入" "${write_rate} MiB/s（${elapsed}s，fdatasync）"

    start=$(monotonic_seconds)
    if dd if="$BENCH_TEMP_FILE" of=/dev/null bs=1M status=none 2>/dev/null; then
        end=$(monotonic_seconds)
        elapsed=$(elapsed_seconds "$start" "$end")
        read_rate=$(awk -v m="$DISK_BENCH_MIB" -v t="$elapsed" 'BEGIN {printf "%.1f", m/t}')
        kv "顺序读取" "${read_rate} MiB/s（${elapsed}s，可能有缓存）"
    else
        status_line warn "磁盘读取测试失败"
    fi

    cleanup_temp_file
}

benchmark_section() {
    section_enabled benchmark || return 0
    section "可选轻量基准"
    status_line warn "快速指示值会受共享负载、缓存、限频与突发额度影响"
    csv_has "$BENCHMARKS" cpu && benchmark_cpu
    csv_has "$BENCHMARKS" disk && benchmark_disk
}


print_footer() {
    if ((LEVEL >= 2)) || [[ -n $BENCHMARKS ]]; then
        printf '\n%s%s 单次快照不代表长期质量；共享 VPS 建议分时段复测负载、steal、I/O 与网络抖动。%s\n' \
            "$C_DIM" "$GLYPH_INFO" "$C_RESET"
    fi
}


main_report() {
    SECTION_INDEX=0
    print_header
    summary_section
    system_section
    virt_section
    cpu_section
    memory_section
    storage_section
    network_section
    kernel_section
    benchmark_section
    print_footer
}

main() {
    if ((BASH_VERSINFO[0] < 4)); then
        fatal "需要 Bash 4.0 或更高版本"
    fi
    parse_args "$@"
    trap cleanup_temp_file EXIT
    trap 'cleanup_temp_file; exit 130' HUP INT TERM

    if [[ -n $OUTPUT_FILE ]]; then
        # 文件输出默认无颜色，除非用户显式指定 --color。
        [[ $COLOR_MODE == "auto" ]] && COLOR_MODE="never"
        init_style
        if ! main_report > "$OUTPUT_FILE"; then
            fatal "写入输出文件失败：$OUTPUT_FILE"
        fi
        printf '报告已写入：%s\n' "$OUTPUT_FILE"
    else
        init_style
        main_report
    fi
}

main "$@"
