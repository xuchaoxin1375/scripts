#!/usr/bin/env bash
#
# qps.sh —— 实时 QPS 监控（nginx main_format_lite 聚合日志，按域名 / URI 维度）
#
# 用法：qps.sh [选项] [日志文件]
#   -f, --file <文件>    日志文件，默认 /www/wwwlogs/spider.log（位置参数等价）
#   -t, --top <N>        每帧显示前 N 名，默认 15（1-200）；0 或 all 表示不截断
#   -x, --expand         启动即展开全部名称（等价于 -t 0）
#   -m, --mode <模式>    统计维度：domain（按域名，默认）/ uri（按域名+路径）
#   -a, --all            从文件头回放再跟踪（默认只从文件尾新增开始）
#   -g, --grep <正则>    只统计 key 匹配该正则的请求
#   -G, --skip <正则>    排除 key 匹配该正则的请求
#   -h, --help           显示本帮助
# 说明：
#   - 基于 tail -F 按文件名跟踪，日志轮转（改名重建）不中断监控。
#   - 秒级分桶优先取日志内 time_local 时间戳，回放旧日志统计也准确。
#   - 每帧含单秒 QPS、与上一秒的增量 Δ（绿=升/红=降）、状态码分布；
#     TOTAL 行按 2xx/3xx/4xx/5xx/其他 各列分别求和，另显示全程累计。
#   - 退出时会打印总请求 / 平均 QPS / 单秒峰值，以及各状态码类的累计合计。
#   - 显示随当前终端窗口自适应：数据行数随窗口高度、KEY 列宽随窗口宽度（优先保证名称完整），
#     改窗口后约 1 秒内重排；窗口过窄时依次隐去 OTHER、DELTA、状态码列，仅留 KEY + QPS
#     （名称过长则截断），再窄则只显示 TOTAL 总值行。
#   - 交互快捷键（stdin 为终端时）：q 退出、h/? 显隐帮助（面板显示在画面最上方）、a 展开/收起全部名称；
#     按键与改窗口无需等待新日志，即刻重绘（空闲时也一样）。
#   - 名称被 Top 上限（-t/--top）截断时按 a 展开查看全部；展开后仍受窗口高度限制，
#     装不下的部分在表格中提示“窗口高度不足，可放大窗口”。
#   - 字段解析对应 nginx log_format main_format_lite（见 nginx_conf/com_log_format.conf）。
# 依赖：bash、tail、awk（需支持 strftime/systime，如 gawk/mawk；建议安装 gawk）。

set -u

usage() {
    cat <<'EOF'
用法：qps.sh [选项] [日志文件]

选项：
  -f, --file <文件>    日志文件，默认 /www/wwwlogs/spider.log（位置参数等价）
  -t, --top <N>        每帧显示前 N 名，默认 15（1-200）；0 或 all 表示不截断
  -x, --expand         启动即展开全部名称（等价于 -t 0）
  -m, --mode <模式>    统计维度：domain（按域名，默认）/ uri（按域名+路径）
  -a, --all            从文件头回放再跟踪（默认只从文件尾新增开始）
  -g, --grep <正则>    只统计 key 匹配该正则的请求
  -G, --skip <正则>    排除 key 匹配该正则的请求
  -h, --help           显示本帮助

交互快捷键（stdin 为终端时可用，按键即刻生效，无需等待新日志）：
  q / Q                退出监控并打印摘要（等同 Ctrl+C）
  h / H / ?            显示或隐藏帮助（快捷键与列含义说明，显示在画面最上方）
  a / A                展开 / 收起被 Top 上限截断的名称（默认未设上限时无需展开）
  Ctrl+C               退出监控并打印摘要

显示：
  随当前终端窗口自适应——数据行数默认铺满窗口高度、KEY 列宽随窗口宽度，改窗口后约 1 秒内按新尺寸
  重排；KEY 列优先保证名称完整显示，窗口过窄时依次隐去 OTHER、DELTA、状态码列，仅留 KEY + QPS
  （名称过长则截断）；再窄则只显示 TOTAL 总值行。标题也按可用宽度自动精简。

  Top 上限（-t N）只截断行数，不改变统计口径：被上限截断时按 a 可展开全部名称，但展开后仍受窗口
  高度限制——装不下的部分在表格中提示“窗口高度不足，可放大窗口”。

示例：
  qps.sh                                    # 监控默认聚合日志
  qps.sh -f /www/wwwlogs/all.log            # 监控全部访问日志
  qps.sh -g 'example\.com'                  # 只关注某域名
  qps.sh -m uri -t 20                       # 按域名+路径统计，看最热路径
  qps.sh -x                                 # 不截断，列出全部名称
  qps.sh -a -f spider.log                   # 回放全文件后继续跟踪
EOF
}

# ---------------- 参数解析 ----------------
LOG_FILE="/www/wwwlogs/spider.log"
TOP=15
TOP_EXPLICIT=0
EXPAND=0
MODE="domain"
REPLAY=0
RE_ONLY=""
RE_SKIP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f | --file)
            [[ $# -ge 2 ]] || {
                echo "错误：$1 缺少参数" >&2
                usage >&2
                exit 2
            }
            LOG_FILE="$2"
            shift 2
            ;;
        -t | --top)
            [[ $# -ge 2 && $2 != -* ]] || {
                echo "错误：$1 缺少参数" >&2
                usage >&2
                exit 2
            }
            TOP="$2"
            TOP_EXPLICIT=1
            shift 2
            ;;
        -x | --expand)
            EXPAND=1
            shift
            ;;
        -m | --mode)
            [[ $# -ge 2 && $2 != -* ]] || {
                echo "错误：$1 缺少参数" >&2
                usage >&2
                exit 2
            }
            MODE="$2"
            shift 2
            ;;
        -a | --all)
            REPLAY=1
            shift
            ;;
        -g | --grep)
            [[ $# -ge 2 ]] || {
                echo "错误：$1 缺少参数" >&2
                usage >&2
                exit 2
            }
            RE_ONLY="$2"
            shift 2
            ;;
        -G | --skip)
            [[ $# -ge 2 ]] || {
                echo "错误：$1 缺少参数" >&2
                usage >&2
                exit 2
            }
            RE_SKIP="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "错误：未知参数：$1" >&2
            usage >&2
            exit 2
            ;;
        *) break ;;
    esac
done
# 位置参数作为日志文件（与旧行为兼容）
if [[ $# -gt 0 ]]; then
    LOG_FILE="$1"
    shift
fi
[[ $# -gt 0 ]] && {
    echo "错误：多余参数：$*" >&2
    usage >&2
    exit 2
}

# ---------------- 校验 ----------------
[[ -f $LOG_FILE ]] || {
    echo "错误：日志文件不存在：$LOG_FILE" >&2
    exit 2
}
[[ -r $LOG_FILE ]] || {
    echo "错误：日志文件不可读：$LOG_FILE" >&2
    exit 2
}
# -t 支持数字（1-200）或 0 / all（不截断，等价于 --expand）
case $TOP in
    all | ALL | all-rows | unlimited | 0)
        EXPAND=1
        TOP=15
        TOP_EXPLICIT=0
        ;;
    *[!0-9]* | "")
        echo "错误：-t 取值须为 1-200 的整数，或 0/all 表示不截断：$TOP" >&2
        exit 2
        ;;
    *) ((TOP >= 1 && TOP <= 200)) || {
        echo "错误：-t 取值须为 1-200 的整数，或 0/all 表示不截断：$TOP" >&2
        exit 2
    } ;;
esac
case $MODE in
    domain | uri) ;;
    *)
        echo "错误：-m 仅支持 domain 或 uri：$MODE" >&2
        exit 2
        ;;
esac
[[ -s $LOG_FILE ]] || echo "提示：文件当前为空，等待新增内容…" >&2

# 优先使用 gawk（macOS 自带的 BWK awk 不支持 strftime/systime）
AWK=$(command -v gawk 2>/dev/null || true)
AWK="${AWK:-awk}"
if ! printf '' | "$AWK" 'BEGIN { strftime("%H:%M:%S"); systime() }' >/dev/null 2>&1; then
    echo "错误：当前 awk（$AWK）不支持 strftime/systime，请安装 gawk 后重试。" >&2
    exit 2
fi

# 正则预检（非法正则会令 awk 运行时报错，提前拦截）
_regex_check() {
    printf x | "$AWK" -v re="$1" 'BEGIN { x = "x"; x ~ re }' >/dev/null 2>&1
}
for _r in "$RE_ONLY" "$RE_SKIP"; do
    if [[ -n $_r ]] && ! _regex_check "$_r"; then
        echo "错误：非法正则：$_r" >&2
        exit 2
    fi
done

# 日志文件长期无写入时给出提示（tail 空等会像“卡死”）
if _mt=$(stat -c %Y "$LOG_FILE" 2>/dev/null || stat -f %m "$LOG_FILE" 2>/dev/null); then
    _age=$(($(date +%s) - _mt))
    ((_age > 300)) && echo "提示：日志最后写入于 ${_age} 秒前，可能暂无流量或另有轮转。" >&2
fi

# ---------------- 终端尺寸 ----------------
# 输出 "行 列"；仅在可访问终端时取真实窗口，否则回退环境变量或 24x80，并做合理性兜底
term_size() {
    local sz="" r="" c=""
    if [[ -t 0 ]]; then sz=$(stty size 2>/dev/null) || sz=""; fi
    if [[ ! $sz =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
        # stdin 非终端时尝试控制终端；整组重定向以吞掉 bash 打开 /dev/tty 失败的提示
        sz=$({ stty size </dev/tty; } 2>/dev/null) || sz=""
    fi
    if [[ $sz =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
        r=${BASH_REMATCH[1]}
        c=${BASH_REMATCH[2]}
    fi
    ((${r:-0} >= 5)) || r=${LINES:-24}
    ((${c:-0} >= 20)) || c=${COLUMNS:-80}
    ((r >= 5)) || r=24 # 部分 pty 尺寸为 0x0，逐级兜底
    ((c >= 20)) || c=80
    printf '%s %s\n' "$r" "$c"
}

# ---------------- 退出摘要 ----------------
# awk 收到中断信号不会执行 END，故每秒冲刷时把累计指标写入状态文件；
# 正常退出时先让 tail 停下，awk 读到 EOF 会执行 END，把最后一秒也补进状态文件，
# 退出摘要再由 shell 读取该文件打印。
QPS_DIR=$(mktemp -d "${TMPDIR:-/tmp}/qps.XXXXXX" 2>/dev/null || printf '/tmp/qps.%s' "$$")
QPS_STATE="$QPS_DIR/stat"
QPS_FIFO="$QPS_DIR/in"
QPS_CTRL=""
QPS_SIZE="$QPS_DIR/size"
QPS_SENTINEL="#qps:redraw" # 注入 FIFO 的哨兵行：唤醒 awk 立即按当前状态重绘
TAIL_PID=""
AWK_PID=""
if ! mkfifo "$QPS_FIFO" 2>/dev/null; then
    echo "错误：无法创建 FIFO：$QPS_FIFO" >&2
    exit 2
fi
trap 'rm -rf "$QPS_DIR"' EXIT

TERM_SIZE=$(term_size)
printf '%s\n' "$TERM_SIZE" >"$QPS_SIZE"
IFS=' ' read -r TROWS TCOLS <<<"$TERM_SIZE"

# 输出是否连接终端：决定是否启用“按窗口高度决定数据行数”的自适应
TTYOUT=0
[[ -t 1 ]] && TTYOUT=1

finish() {
    local rc=${1:-130}
    # 供 Ctrl+C 场景：中断可能发生在 `IFS= read` 执行期间，此时 IFS 被临时置空，
    # 恢复默认值才能让后面的参数正常分词。
    local IFS=$' \t\n'
    trap '' INT TERM HUP
    [[ -t 0 ]] && stty sane 2>/dev/null
    # 先释放 FIFO 写端（哨兵注入用）：awk 需在所有写端关闭后才能读到 EOF
    exec 9>&- 2>/dev/null || true
    # 再停 tail：awk 随即读到 EOF，执行 END 写出最终累计值（含最后一秒）
    if [[ -n $TAIL_PID ]]; then
        kill -TERM "$TAIL_PID" 2>/dev/null
        local i=0
        while [[ -n $AWK_PID ]] && kill -0 "$AWK_PID" 2>/dev/null && ((i < 50)); do
            sleep 0.02
            ((i++))
        done
    fi
    [[ -n $AWK_PID ]] && kill -TERM "$AWK_PID" 2>/dev/null
    wait 2>/dev/null
    printf '\n监控已结束\n'
    # 摘要按“当前”窗口宽度决定是否折行（运行中可能改过窗口）
    _sz=$(term_size)
    TCOLS=${_sz##* }
    if [[ -s $QPS_STATE ]]; then
        local s_total=0 s_avg="0.0" s_peak=0 s_peakts="-" s_from="-" s_to="-"
        local s_2=0 s_3=0 s_4=0 s_5=0 s_o=0
        IFS=$'\t' read -r s_total s_avg s_peak s_peakts s_from s_to \
            s_2 s_3 s_4 s_5 s_o <"$QPS_STATE"
        printf '起 %s → 末 %s ｜ 总请求 %s\n' \
            "${s_from:--}" "${s_to:--}" "${s_total:-0}"
        printf '平均 %s/s ｜ 单秒峰值 %s（@ %s）\n' \
            "${s_avg:-0.0}" "${s_peak:-0}" "${s_peakts:--}"
        # 状态码合计较宽，窄窗口拆成两行，避免终端硬折行
        if ((TCOLS >= 60)); then
            printf '状态码合计：2xx %s ｜ 3xx %s ｜ 4xx %s ｜ 5xx %s ｜ 其他 %s ｜ 合计 %s\n' \
                "${s_2:-0}" "${s_3:-0}" "${s_4:-0}" "${s_5:-0}" "${s_o:-0}" "${s_total:-0}"
        else
            printf '状态码合计：2xx %s ｜ 3xx %s ｜ 4xx %s\n' \
                "${s_2:-0}" "${s_3:-0}" "${s_4:-0}"
            printf '            5xx %s ｜ 其他 %s ｜ 合计 %s\n' \
                "${s_5:-0}" "${s_o:-0}" "${s_total:-0}"
        fi
    fi
    exit "$rc"
}
trap 'finish 130' INT TERM

# ---------------- 交互快捷键 ----------------
# 仅 stdin 为终端时启用：q 退出、h/? 显隐帮助、a 展开/收起被截断的名称。
# 主 shell 在前台读键，监控流水线放到后台，避免后台进程读终端被 SIGTTIN 挂起。
INTERACTIVE=0
HINT="Ctrl+C 退出"
if [[ -t 0 ]]; then
    INTERACTIVE=1
    QPS_CTRL="$QPS_DIR/ctrl"
    printf 'help=0 expand=%d\n' "$EXPAND" >"$QPS_CTRL"
    HINT="q 退出 ｜ h 帮助 ｜ a 展开 ｜ Ctrl+C 退出"
fi

# ---------------- 监控流水线 ----------------
T=(tail -n 0 -F) # -F 按文件名跟随，轮转不中断
[[ $REPLAY -eq 1 ]] && T=(tail -n +1 -F)

if [[ $EXPAND -eq 1 ]]; then
    TOP_SHOW="全部（已展开）"
elif [[ $TOP_EXPLICIT -eq 1 ]]; then
    TOP_SHOW="$TOP"
else TOP_SHOW="自适应（窗口 ${TROWS}x${TCOLS}）"; fi
printf '监控目标：%s ｜ 维度：%s ｜ Top：%s ｜ %s\n' "$LOG_FILE" "$MODE" "$TOP_SHOW" "$HINT"

"${T[@]}" "$LOG_FILE" >"$QPS_FIFO" &
TAIL_PID=$!

# 单引号内是 awk 程序本体：$0/$1 等由 awk 解释，不参与 shell 展开（据此屏蔽 SC2016）
# shellcheck disable=SC2016
"$AWK" -v mode="$MODE" -v top="$TOP" -v top_explicit="$TOP_EXPLICIT" \
    -v trows="$TROWS" -v tcols="$TCOLS" -v ttyout="$TTYOUT" -v size_path="$QPS_SIZE" \
    -v sentinel="$QPS_SENTINEL" \
    -v onlyre="$RE_ONLY" -v skipre="$RE_SKIP" -v state_path="$QPS_STATE" \
    -v ctrl_path="$QPS_CTRL" -v interactive="$INTERACTIVE" -v expand="$EXPAND" \
    -v logname="$(basename -- "$LOG_FILE")" '
BEGIN {
    green = "\033[32m"; red = "\033[31m"; dim = "\033[2m"; cyan = "\033[36m"; off = "\033[0m"
    boot_hms = strftime("%H:%M:%S")
    peak_qps = 0
    peak_ts = "-"
    hlp = 0
    ex = expand + 0
    span = 0
    first_hms = ""
    cum2 = cum3 = cum4 = cum5 = cumo = 0
    load_size()
    lw = cols - 66
    if (lw < 10) lw = 10
    lname = cliphead(logname, lw)
    printf "\033[2J\033[H"
    printf "%s已启动，等待日志行…（%s ｜ %s）%s\n", dim, lname, hotkeys(), off
    fflush()
}

# 终端尺寸自适应：优先读 shell 维护的尺寸文件（支持运行中改窗口），回退 -v 传入值
function load_size(    line, a, n, r, c) {
    r = trows + 0
    c = tcols + 0
    if (size_path != "" && (getline line < size_path) > 0) {
        n = split(line, a, /[ \t]+/)
        if (n >= 2) { r = a[1] + 0; c = a[2] + 0 }
    }
    if (size_path != "") close(size_path)
    if (r < 5) r = 24
    if (c < 20) c = 80     # 20 列以下视为无有效尺寸（如 0x0 的 pty），回退默认宽度
    rows = r
    cols = c
}

function hms2s(t,    a) { split(t, a, ":"); return (a[1] + 0) * 3600 + a[2] * 60 + a[3] }

# 两个 HH:MM:SS 之间的秒差（跨零点回绕）
function gapsec(a, b,    d) {
    d = hms2s(b) - hms2s(a)
    if (d < 0) d += 86400
    return d
}

# 累计指标写入状态文件，供退出摘要使用
function wstate(    el) {
    if (state_path == "") return
    el = span
    if (el < 1) el = 1
    printf "%d\t%.1f\t%d\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\n", total_all, total_all / el, \
        peak_qps, peak_ts, (first_hms == "" ? boot_hms : first_hms), (last == "" ? boot_hms : last), \
        cum2, cum3, cum4, cum5, cumo > state_path
    close(state_path)   # 关闭重开，下次写入即截断，保证状态文件始终只有最新一行
}

# 快捷键状态文件：shell 侧按 h/a 时写入 help=0|1 expand=0|1，awk 每帧据此决定显示
function readctrl(    line) {
    if (ctrl_path == "") return
    hlp = 0
    ex = 0
    if ((getline line < ctrl_path) > 0) {
        if (line ~ /help=1/) hlp = 1
        if (line ~ /expand=1/) ex = 1
    }
    close(ctrl_path)
}

# 页脚 / 帮助中的快捷键说明（展开状态决定 a 的提示；窗口过窄时省去 Ctrl+C 提示）
function hotkeys(    s) {
    if (interactive + 0 != 1) return "Ctrl+C 退出"
    s = "q 退出 ｜ h 帮助 ｜ a " (ex ? "收起" : "展开")
    if (cols >= 56) s = s " ｜ Ctrl+C 退出"
    return s
}

# 帮助面板各行（不含颜色码）；绘制与高度估算共用同一份内容
# 面板固定在画面最上方（标题之上、与标题隔一个空行），这样标题始终与下表相邻
# 窗口过窄时改用紧凑文案，避免面板自身折行过多而挤掉数据行
function help_fill(a,    hk) {
    hk = hotkeys()
    a[1] = "帮助"
    if (cols >= 60) {
        a[2] = "  KEY    按 " mode " 维度聚合的名称（domain：域名；uri：域名/路径）"
        a[3] = "  QPS    该名称在这一秒内的请求数"
        a[4] = "  DELTA  与上一秒相比的增减：" green "+" off " 升 ｜ " red "-" off " 降 ｜ . 持平"
        a[5] = "  2xx / 3xx / 4xx / 5xx  按响应状态码分类计数；OTHER 为 0xx / 1xx / 无法解析"
        a[6] = "  TOTAL(1s) 本秒各列求和；TOTAL(ALL) 自启动至今各列累计合计"
        a[7] = "  被 -t 上限截断的名称按 a 展开（展开仍受窗口高度限制）"
        a[8] = "  窗口过窄时依次隐去 OTHER / DELTA / 状态码列，仅留 KEY + QPS；再窄只显示总值"
        a[9] = "  快捷键：" hk
        return 9
    }
    a[2] = "  KEY    名称（按 " mode " 维度聚合）"
    a[3] = "  QPS    该名称本秒请求数"
    a[4] = "  DELTA  与上一秒的增减：" green "+" off " / " red "-" off " / ."
    a[5] = "  2xx/3xx/4xx/5xx  状态码分类计数"
    a[6] = "  TOTAL(1s)/TOTAL(ALL)  本秒 / 累计求和"
    a[7] = "  快捷键：" hk
    return 7
}

# 面板之后留一个空行，与标题行分开（优先保住空行，宁可少显示一行帮助）
# limit 为面板可占用的最大行数（窗口太矮时只画能放下的部分）
function print_help(limit,    a, n, i, r, t, lim) {
    n = help_fill(a)
    lim = limit
    if (lim >= 2) lim = limit - 1      # 末尾空行优先
    t = 0
    for (i = 1; i <= n; i++) {
        r = int((dispw(a[i]) + cols - 1) / cols)
        if (r < 1) r = 1
        if (t + r > lim) break
        if (i == 1) printf "%s%s%s\n", cyan, a[i], off
        else printf "%s\n", a[i]
        t += r
    }
    if (t > 0 && limit >= 2) printf "\n"
}

# 帮助面板在给定窗口宽度下占用的行数（含折行 + 面板后的空行）
function help_h(w,    a, n, i, r, t) {
    n = help_fill(a)
    t = 1                 # 面板与标题之间的空行
    for (i = 1; i <= n; i++) {
        r = int((dispw(a[i]) + w - 1) / w)
        if (r < 1) r = 1
        t += r
    }
    return t
}

# 显示名截断：超长时保留末尾（域名尾部 / 路径深部更有辨识度）
# 截断标记用 ".."（ASCII）：awk 的 %-Ns 按字节补齐，多字节字符会导致列错位
function clip(s, w) {
    if (length(s) <= w) return s
    return ".." substr(s, length(s) - (w - 2) + 1, w - 2)
}

# 截断时保留开头（文件名 / 日志名看头部更有辨识度）
function cliphead(s, w) {
    if (length(s) <= w) return s
    return substr(s, 1, w - 2) ".."
}

# 估算字符串的终端显示宽度：以字符数为基础，非 ASCII 字符再加 1 列（宽字符占 2 列）
# "─" "…" 等虽非 ASCII 但实际只占 1 列，故先剔除后再统计；ANSI 颜色码不计宽度
function dispw(s,    t, u) {
    u = s
    gsub(/\033\[[0-9;]*[A-Za-z]/, "", u)
    t = u
    gsub(/[ -~]/, "", t)
    gsub(/[─│├└…]/, "", t)
    return length(u) + length(t)
}

function sc4(key, c) { return (key, c) in sc ? sc[key, c] : 0 }

# 时间推进到新的一秒（pend）时：冲刷上一个桶（last），存快照并绘制一帧
function flush(    d, i, j, mk, k, sum, nn, keys, el) {
    readctrl()
    load_size()
    sum = 0
    nn = 0
    for (d in count) { keys[nn++] = d; sum += count[d] }

    # 按 QPS 降序排序（选择排序，条目数小，够用）
    for (i = 0; i < nn - 1; i++) {
        mk = i
        for (j = i + 1; j < nn; j++)
            if (count[keys[j]] > count[keys[mk]]) mk = j
        if (mk != i) { k = keys[i]; keys[i] = keys[mk]; keys[mk] = k }
    }

    if (sum > peak_qps) { peak_qps = sum; peak_ts = last }
    el = span
    if (el < 1) el = 1

    # 存本帧快照：绘制只依据快照，故无新日志时（按键 / 改窗口）也能立即重绘上一帧
    # 同时各列分别求和：每请求必属且仅属一类，各列合计即该类本秒计数
    snn = nn
    ssum = sum
    sel = el
    sgap = (pend != "" ? gapsec(last, pend) : 0)
    sb2 = sb3 = sb4 = sb5 = sbo = 0
    for (i = 0; i < nn; i++) {
        d = keys[i]
        skey[i] = d
        scnt[i] = count[d]
        spd[i]  = count[d] - ((d in prev) ? prev[d] : 0)
        ss2[i] = sc4(d, "2"); ss3[i] = sc4(d, "3"); ss4[i] = sc4(d, "4")
        ss5[i] = sc4(d, "5"); sso[i] = sc4(d, "o")
        sb2 += ss2[i]; sb3 += ss3[i]; sb4 += ss4[i]; sb5 += ss5[i]; sbo += sso[i]
    }
    drawn = 1

    paint()

    wstate()
    # 供下一秒 Δ 参考
    for (d in prev) delete prev[d]
    for (i = 0; i < nn; i++) prev[keys[i]] = count[keys[i]]
    for (d in count) delete count[d]
    for (d in sc) delete sc[d]
}

# 无新日志时按当前状态重绘上一帧（响应快捷键 / 窗口尺寸变化）
function redraw() { if (drawn) paint() }

# 绘制一帧：完全依据最近一次 flush 的快照
function paint(    i, d, pd, cell, b2, b3, b4, b5, bo, nn, sum, el, gap, lim, avail, over, \
                   lw, avgv, exmark, head, mid, tline, th, sd, so, ssta, need, fixedw, keyw, fh, \
                   f_hdr, f_row, f_sum, reason) {
    readctrl()
    load_size()
    nn = snn; sum = ssum; el = sel; gap = sgap
    b2 = sb2; b3 = sb3; b4 = sb4; b5 = sb5; bo = sbo

    # 标题：按窗口宽度由宽到窄依次尝试（完整 → 紧凑 → 去掉展开标记 → 只留日志名），
    # 取第一个放得下日志名的方案；实在放不下时保留最少字符，折行由行高预算兜底
    avgv = total_all / el
    exmark = (ex ? "（已展开）" : "")
    head = "实时 QPS ｜ "
    mid = sprintf(" ｜ 均值 %.1f/s ｜ 峰值 %d/s（@ %s） ｜ 总请求 %d ｜ 名称 %d%s", \
        avgv, peak_qps, peak_ts, total_all, nn, exmark)
    lw = cols - dispw(head) - dispw(mid) - 2
    if (lw < 8) {
        head = "QPS ｜ "
        mid = sprintf(" ｜ 均 %.1f/s ｜ 峰 %d/s ｜ 总 %d ｜ 名 %d%s", avgv, peak_qps, total_all, nn, exmark)
        lw = cols - dispw(head) - dispw(mid) - 2
    }
    if (lw < 6) {      # 仍放不下：去掉“已展开”标记（展开状态由页脚 a 收起 提示）
        mid = sprintf(" ｜ 均 %.1f/s ｜ 峰 %d/s ｜ 总 %d ｜ 名 %d", avgv, peak_qps, total_all, nn)
        lw = cols - dispw(head) - dispw(mid) - 2
    }
    if (lw < 6) {      # 极窄窗口：只留日志名
        mid = ""
        lw = cols - dispw(head) - dispw(mid) - 2
    }
    if (lw < 4) lw = 4
    lname = cliphead(logname, lw)
    tline = head lname mid
    th = int((dispw(tline) + cols - 1) / cols)     # 标题实际占用的行数（窄窗口会折行）
    if (th < 1) th = 1

    # 按窗口高度决定数据行数：固定行 8（标题/表头/合计×2/页脚/末尾空行 + 预留省略行 1）
    # 预留位保证整帧换行数不超过窗口行数，避免末尾换行触发滚屏把标题顶掉
    fh = int((dispw(hotkeys()) + cols - 1) / cols)
    if (fh < 1) fh = 1
    fixed = 8 + (th - 1) + (fh - 1) + (gap > 1 ? 1 : 0)
    # 窗口太矮时压缩帮助面板：宁可少显示几行帮助，也不让整帧滚动把标题顶掉
    hh = 0
    if (hlp) {
        hh = help_h(cols)
        if (hh > rows - fixed) hh = rows - fixed
        if (hh < 1) hh = 0
    }
    over = fixed + hh
    avail = rows - over
    if (avail < 0) avail = 0
    # 行高自适应仅在输出到终端时生效；重定向到文件/管道时按 -t 显示（-t 0 则全部）
    if (ttyout + 0 != 1) {
        lim = (ex ? nn : top)
    } else if (ex)                    lim = (nn < avail ? nn : avail)     # 已展开：尽量铺满窗口
    else if (top_explicit + 0 == 1)   lim = (top < avail ? top : avail)   # 显式 -t：不超过窗口高度
    else                              lim = avail                         # 默认：随窗口高度自适应
    if (lim < 0) lim = 0

    # KEY 列目标宽度：以本帧实际要显示的名称长度为准（短名不白白占宽，长名尽量显示完整）
    need = 16
    for (i = 0; i < nn && i < lim; i++) {
        d = length(skey[i])
        if (d > need) need = d
    }
    if (need > 64) need = 64        # 聚合键本身已截到 64 字符

    # 列集合按可用宽度由多到少退让：优先保证 KEY 列放得下完整名称，放不下时退到仅 KEY + QPS
    #   完整（KEY+QPS+DELTA+状态码+OTHER）→ 去 OTHER → 去 DELTA → 仅 KEY+QPS → 仅总值
    # 行宽 = KEY + 8(QPS) + 8(DELTA) + 4×6(状态码) + 7(OTHER)
    # 再窄则连 KEY 列也放不下（KEY 下限 16 列 + QPS 8 列 = 24），只留最简单的总值指标
    if (cols < 24) {
        printf "\033[H\033[2J"
        printf "%s%-10s%7d%s\n", dim, "TOTAL(1s)", sum, off
        printf "%s%-10s%7d%s\n", dim, "TOTAL(ALL)", total_all, off
        printf "\n"
        fflush()
        return
    }
    if (cols >= need + 47)      { so = 1; sd = 1; ssta = 1 }   # 完整
    else if (cols >= need + 40) { so = 0; sd = 1; ssta = 1 }   # 去 OTHER
    else if (cols >= need + 32) { so = 0; sd = 0; ssta = 1 }   # 去 DELTA
    else                        { so = 0; sd = 0; ssta = 0 }   # 仅 KEY + QPS（名称过长时截断显示）
    fixedw = 8 + (sd ? 8 : 0) + (ssta ? 24 : 0) + (so ? 7 : 0)
    keyw = cols - fixedw
    if (keyw > 80) keyw = 80

    # 被舍弃的列以 %s 配空参数占位，保证格式串占位符与参数个数始终一一对应
    f_hdr = "%s%-" keyw "s %7s" (sd ? " %7s" : "%s") (ssta ? " %5s %5s %5s %5s" : "%s%s%s%s") (so ? " %6s" : "%s") "%s\n"
    f_row = "%-" keyw "s %7d" (sd ? " %s" : "%s") (ssta ? " %5d %5d %5d %5d" : "%s%s%s%s") (so ? " %6d" : "%s") "\n"
    f_sum = "%-" keyw "s %7d" (sd ? " %7s" : "%s") (ssta ? " %5d %5d %5d %5d" : "%s%s%s%s") (so ? " %6d" : "%s") "\n"

    printf "\033[H\033[2J"
    # 帮助面板置于画面最上方（“第一部分”）：标题与下表始终相邻，不被面板隔开
    if (hh > 0) print_help(hh)
    printf "%s%s%s%s%s%s%s\n", cyan, head, dim, lname, off, mid, off
    if (gap > 1) printf "%s（间隔 %d 秒无请求）%s\n", dim, gap, off
    printf f_hdr, dim, "KEY", "QPS", (sd ? "DELTA" : ""), \
        (ssta ? "2xx" : ""), (ssta ? "3xx" : ""), (ssta ? "4xx" : ""), (ssta ? "5xx" : ""), \
        (so ? "OTHER" : ""), off

    for (i = 0; i < nn && i < lim; i++) {
        pd = spd[i]
        if (pd > 0)      cell = sprintf("%s%+7d%s", green, pd, off)
        else if (pd < 0) cell = sprintf("%s%7d%s",  red,   pd, off)
        else             cell = sprintf("%s      .%s", dim, off)   # 无变化：手工成 7 列宽，保证对齐
        printf f_row, clip(skey[i], keyw), scnt[i], (sd ? cell : ""), \
            (ssta ? ss2[i] : ""), (ssta ? ss3[i] : ""), (ssta ? ss4[i] : ""), (ssta ? ss5[i] : ""), \
            (so ? sso[i] : "")
    }
    if (nn > lim) {
        # 提示只按“按 a 是否真的能看到更多”来给：
        #   展开态、默认自适应（无 -t）、或 -t 上限已达窗口高度 → 受窗口高度限制，只能放大窗口
        #   其余（-t 上限小于窗口高度且未展开）→ 按 a 可展开看全
        if (ttyout + 0 == 1 && (ex || top_explicit + 0 == 0 || top >= avail))
            reason = (cols < 50 ? "（窗口太矮）" : "（窗口高度不足，可放大窗口）")
        else if (interactive + 0 == 1) reason = "（按 a 展开）"
        else reason = ""
        printf "  %s… 其余 %d 项省略%s%s\n", dim, nn - lim, reason, off
    }
    # 求和行：本秒 QPS 与各状态码列分别求和；全程累计各自合计
    # 标签用 ASCII，避免 %-Ns 按字节补齐时多字节字符造成的列错位
    printf f_sum, "TOTAL(1s)", sum, "", \
        (ssta ? b2 : ""), (ssta ? b3 : ""), (ssta ? b4 : ""), (ssta ? b5 : ""), (so ? bo : "")
    printf f_sum, "TOTAL(ALL)", total_all, "", \
        (ssta ? cum2 : ""), (ssta ? cum3 : ""), (ssta ? cum4 : ""), (ssta ? cum5 : ""), (so ? cumo : "")
    printf "%s%s%s\n", dim, hotkeys(), off
    printf "\n"
    fflush()
}

{
    # 哨兵行：shell 在按键 / 窗口尺寸变化时注入，用于无新日志时立即重绘（不计入统计）
    if (sentinel != "" && $0 == sentinel) { redraw(); next }

    # 秒级时间戳：优先取日志内 time_local（回放/补读时统计准确），异常则回退当前时钟
    if (split($2, tp, ":") >= 4 && tp[2] ~ /^[0-9][0-9]$/ && tp[3] ~ /^[0-9][0-9]$/ && tp[4] ~ /^[0-9][0-9]$/)
        ts = tp[2] ":" tp[3] ":" tp[4]
    else
        ts = strftime("%H:%M:%S")

    if (last == "") {
        span = 1
        first_hms = ts
    } else {
        g = gapsec(last, ts)
        if (g > 0 && g < 7200) span += g    # 忽略乱序时间戳造成的异常间隔
    }

    if (last != "" && ts != last) { pend = ts; flush(); pend = "" }
    last = ts

    # key 提取：[req = $host$request_uri] → host（domain 模式）或 host/path（uri 模式）
    # 边界：host 终于 "/"（无 "/" 则终于空白或 "]"）；path 介于 "/" 与 "]" 之间
    host = "unknown"
    path = ""
    if ((pos = index($0, "[req = ")) > 0) {
        rest = substr($0, pos + 7)
        slash = index(rest, "/")
        i2 = index(rest, " ")
        if (i2 == 0) i2 = length(rest) + 1
        i3 = index(rest, "]")
        if (i3 == 0) i3 = length(rest) + 1
        he = (slash > 0) ? slash : i2
        if (he > i3) he = i3
        if (he > 1) host = tolower(substr(rest, 1, he - 1))
        if (slash > 0 && slash < i3)
            path = substr(rest, slash + 1, i3 - slash - 1)
    }
    if (mode == "uri") {
        if ((q = index(path, "?")) > 0) path = substr(path, 1, q - 1)
        # 聚合键固定截到 64 字符（统计口径不随窗口宽度变化），显示时再按窗口宽度截断
        key = clip(host (path == "" ? "" : "/" path), 64)
    } else {
        key = clip(host, 64)
    }

    # 状态码解析：status=NNN → 2xx/3xx/4xx/5xx；无 / 0xx / 1xx 归“其他”
    cls = "o"
    if (match($0, /status=[0-9][0-9][0-9]/)) {
        cls = substr($0, RSTART + 7, 1)
        if (cls == "0" || cls == "1") cls = "o"
    }

    # 过滤：-g 只统计命中者，-G 排除命中者
    if ((onlyre != "" && key !~ onlyre) || (skipre != "" && key ~ skipre)) {
        skipped++
        if (skipped % 500 == 0) wstate()
        next
    }

    count[key]++
    sc[key, cls]++
    if (cls == "2") cum2++
    else if (cls == "3") cum3++
    else if (cls == "4") cum4++
    else if (cls == "5") cum5++
    else cumo++
    total_all++
    if (total_all % 500 == 0) wstate()
}

END {
    wstate()
}
' <"$QPS_FIFO" \
    &

AWK_PID=$!

# ---------------- 主循环：读快捷键 / 等待流水线 ----------------
if [[ $INTERACTIVE -eq 1 ]]; then
    _help_on=0
    _expand_on=$EXPAND
    _last_size=$TERM_SIZE
    # 常开 FIFO 写端：注入哨兵行让 awk 立即重绘。用 <>（O_RDWR）打开以免无读者时阻塞；
    # awk 退出后写入只会得到 EPIPE，子 shell 内忽略 PIPE 即可。
    exec 9<>"$QPS_FIFO"
    notify_redraw() {
        [[ -n $AWK_PID ]] && kill -0 "$AWK_PID" 2>/dev/null || return 0
        (
            trap '' PIPE
            printf '%s\n' "$QPS_SENTINEL" >&9
        ) 2>/dev/null || true
    }
    while :; do
        _k=""
        IFS= read -rsn1 -t 1 _k
        _rc=$?
        if ((_rc == 0)); then
            case $_k in
                q | Q) finish 0 ;;
                h | H | '?') _help_on=$((1 - _help_on)) ;;
                a | A) _expand_on=$((1 - _expand_on)) ;;
                *) continue ;;
            esac
            printf 'help=%d expand=%d\n' "$_help_on" "$_expand_on" >"$QPS_CTRL"
            notify_redraw
        elif ((_rc <= 128)); then
            break # EOF（Ctrl+D）或读错误
        fi
        # 窗口尺寸变化检测（每秒一次，无需 SIGWINCH）；变化即更新尺寸文件并立即重绘
        _sz=$(term_size)
        if [[ $_sz != "$_last_size" ]]; then
            printf '%s\n' "$_sz" >"$QPS_SIZE"
            _last_size=$_sz
            notify_redraw
        fi
    done
    finish 0 # stdin 关闭（Ctrl+D）也正常收尾
else
    wait "$AWK_PID" 2>/dev/null
    finish "$?"
fi
