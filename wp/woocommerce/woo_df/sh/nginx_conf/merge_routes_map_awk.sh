#!/usr/bin/env bash
# ==============================================================================
# 尽可能用纯awk来提高处理效率.
# 脚本用途:
#   根据文件 B 的第一列，清理文件 A 中第一列与 B 冲突的行。
#
# 适用场景:
#   1. 文件 B 通常远小于文件 A。
#   2. A/B 的有效非注释行第一列已经统一为 .domain.com 格式。
#   3. 只需要按照第一列“原样完全相等”进行删除判断。
#
# 匹配规则:
#   - 从 B 中读取有效行第一列，放入 awk 关联数组。
#   - 扫描 A 时，如果 A 的有效行第一列存在于 B 的 key 集合中，则删除该行。
#   - 空行和注释行不会被删除。
#
# 有效行定义:
#   - 非空行
#   - 非以 # 开头的注释行
#
# 示例:
#   A:
#       .example.com DIRECT
#       .test.com    DIRECT
#
#   B:
#       .example.com PROXY
#
#   结果:
#       A 中 .example.com 这一行会被删除。
#       .test.com 会保留。
#
# 性能说明:
#   这是“纯 awk 核心处理”版本。
#   核心过滤逻辑只启动一次 awk：
#
#       awk 先读取 B -> 建立 key 集合
#       awk 再读取 A -> 判断第一列并输出保留行
#
#   相比原始 Bash 逐行循环 + 每行调用 awk/sed 的方式，
#   这个版本能显著减少进程创建、管道、命令替换和字符串处理开销。
#
# 与 grep + awk 版本的区别:
#   grep + awk 版本适合“想先快速判断有没有候选命中”的场景。
#   但它通常至少需要扫描 A 一次，真正删除时还可能再扫描 A 一次。
#
#   当前纯 awk 版本只需要:
#       读取 B 一次
#       扫描 A 一次
#
#   因此在 B 远小于 A 的常见场景下，纯 awk 版本通常更稳、更直接。
#
# 安全性:
#   - 不会在同一路径上同时读写。
#   - 所有修改先写入临时文件。
#   - 成功后再用 mv 替换 A。
#   - 支持 dry-run 预览模式。
#
# 参数:
#   -a FILE      指定待清理文件 A
#   -b FILE      指定源文件 B
#   --add        清理 A 后，将整个 B 追加到 A 末尾
#   -d, --dry    预览模式，只显示将删除的行，不修改文件
#   -h, --help   显示帮助信息
# ==============================================================================

set -euo pipefail

FILE_A=""
FILE_B=""
DRY_RUN=false
MODE="CLEAN"   # CLEAN: 只清理 A；ADD: 清理后追加 B

TMP_FILE=""
TMP_NORM=""
TMP_COUNT=""

RC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'

log_info()   { printf '%b[INFO]%b %s\n' "$GREEN" "$RC" "$*" >&2; }
log_warn()   { printf '%b[WARN]%b %s\n' "$YELLOW" "$RC" "$*" >&2; }
log_error()  { printf '%b[ERROR]%b %s\n' "$RED" "$RC" "$*" >&2; }
log_dryrun() { printf '%b[PREVIEW]%b %s\n' "$BLUE" "$RC" "$*" >&2; }

cleanup() {
    [[ -n "${TMP_FILE:-}" && -e "$TMP_FILE" ]] && rm -f -- "$TMP_FILE"
    [[ -n "${TMP_NORM:-}" && -e "$TMP_NORM" ]] && rm -f -- "$TMP_NORM"
    [[ -n "${TMP_COUNT:-}" && -e "$TMP_COUNT" ]] && rm -f -- "$TMP_COUNT"
}
trap cleanup EXIT

usage() {
    cat << EOF
用法:
  $(basename "$0") [OPTIONS] -a <file_a> -b <file_b>

参数:
  -a FILE          指定待清理文件 A
  -b FILE          指定源文件 B
  --add            清理 A 后，将整个 B 文件追加到 A 末尾
  -d, --dry        预览模式，只打印将要删除的行，不实际修改文件
  -h, --help       显示帮助信息

前提:
  A/B 的有效行第一列均已是 .domain.com 形式。
  本脚本不会再做域名归一化、二级域提取或列数检查。

匹配规则:
  只比较 A/B 有效行的第一列。
  第一列完全相等时，删除 A 中对应行。
EOF
    exit 1
}

parse_arguments() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a)
                [[ $# -ge 2 ]] || { log_error "-a 缺少文件路径"; exit 1; }
                FILE_A="$2"
                shift 2
                ;;
            -b)
                [[ $# -ge 2 ]] || { log_error "-b 缺少文件路径"; exit 1; }
                FILE_B="$2"
                shift 2
                ;;
            --add)
                MODE="ADD"
                shift
                ;;
            -d|--dry)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "未知参数: $1"
                usage
                ;;
        esac
    done

    if [[ -z "$FILE_A" || -z "$FILE_B" ]]; then
        log_error "必须同时指定 -a 和 -b 参数。"
        usage
    fi

    if [[ ! -f "$FILE_A" || ! -f "$FILE_B" ]]; then
        log_error "输入文件不存在，请检查 -a 或 -b 路径。"
        exit 1
    fi

    if [[ "$FILE_A" -ef "$FILE_B" ]]; then
        log_error "FILE_A 和 FILE_B 指向同一个文件，拒绝执行。"
        exit 1
    fi
}

init_tmp_files() {
    local tmp_dir
    tmp_dir=$(dirname -- "$FILE_A")

    TMP_FILE=$(mktemp "${tmp_dir%/}/.sync_safe.XXXXXX")
    TMP_NORM=$(mktemp "${tmp_dir%/}/.sync_safe_norm.XXXXXX")
    TMP_COUNT=$(mktemp "${tmp_dir%/}/.sync_count.XXXXXX")

    chmod --reference="$FILE_A" "$TMP_FILE" 2>/dev/null || true
}

filter_a_by_b_keys() {
    # 核心处理函数。
    #
    # 这是本脚本的主要优化点：
    #   只启动一次 awk。
    #
    # awk 处理流程:
    #   1. 第一个输入文件是 B。
    #      - 跳过空行和注释行。
    #      - 读取第一列 $1。
    #      - 存入 keys[$1]。
    #
    #   2. 第二个输入文件是 A。
    #      - 保留空行和注释行。
    #      - 对有效行取第一列 $1。
    #      - 如果 $1 存在于 keys，则删除。
    #      - 否则原样输出。
    #
    # dry-run:
    #   - 不输出清理后的文件。
    #   - 只打印将删除的行。
    #
    # 非 dry-run:
    #   - 输出清理后的 A 到 TMP_FILE。
    #
    # 删除数量:
    #   - 写入 TMP_COUNT，主流程再读取。
    awk \
        -v dry="$DRY_RUN" \
        -v count_file="$TMP_COUNT" \
        -v blue="$BLUE" \
        -v rc="$RC" '
        FNR == 1 {
            file_index++
        }

        file_index == 1 {
            # 正在读取 B。
            if ($0 ~ /^[[:space:]]*$/) {
                next
            }

            if ($0 ~ /^[[:space:]]*#/) {
                next
            }

            keys[$1] = 1
            next
        }

        file_index == 2 {
            # 正在读取 A。
            if ($0 ~ /^[[:space:]]*$/) {
                if (dry != "true") {
                    print
                }
                next
            }

            if ($0 ~ /^[[:space:]]*#/) {
                if (dry != "true") {
                    print
                }
                next
            }

            key = $1

            if (key in keys) {
                deleted++

                if (dry == "true") {
                    printf "%s[PREVIEW]%s 【将删除】A 中第 %d 行 -> 第一列: [%s] | 内容: '\''%s'\''\n", \
                        blue, rc, FNR, key, $0 > "/dev/stderr"
                }

                next
            }

            if (dry != "true") {
                print
            }

            next
        }

        END {
            print deleted + 0 > count_file
        }
    ' "$FILE_B" "$FILE_A" > "$TMP_FILE"
}

trim_trailing_blank_lines() {
    # 删除文件末尾多余空行。
    #
    # 这个实现不会把整个文件一次性存入数组。
    # 它只缓存连续空行，因此比“把全部行存进 awk 数组再倒序判断”的方式更省内存。
    #
    # 用途:
    #   --add 模式下，先收紧清理后的 A 尾部空行，再追加 B。
    local input_file="$1"
    local output_file="$2"

    awk '
        /^[[:space:]]*$/ {
            blanks = blanks $0 ORS
            next
        }

        {
            printf "%s", blanks
            blanks = ""
            print
        }
    ' "$input_file" > "$output_file"
}

append_b_to_cleaned_a() {
    # 将整个 B 文件追加到清理后的 A。
    #
    # 注意:
    #   追加的是 B 的完整内容，包括注释行和空行。
    #   这与原始脚本 --add 的语义保持一致。
    trim_trailing_blank_lines "$TMP_FILE" "$TMP_NORM"
    mv -- "$TMP_NORM" "$TMP_FILE"

    # 如果希望 A 和 B 之间强制保留一个空行，可以取消下一行注释:
    # printf '\n' >> "$TMP_FILE"

    cat -- "$FILE_B" >> "$TMP_FILE"
}

main() {
    parse_arguments "$@"
    init_tmp_files

    if [[ "$DRY_RUN" == true ]]; then
        log_warn "--- 当前运行在预览模式 Dry-run，不会修改任何物理文件 ---"
    fi

    log_info "步骤 1: 使用 awk 读取 B 第一列，并流式过滤 A..."
    filter_a_by_b_keys

    local deleted_count
    IFS= read -r deleted_count < "$TMP_COUNT"

    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$MODE" == "ADD" ]]; then
            log_dryrun "【整体并入】文件 B ($FILE_B) 的全部内容将追加到 A 末尾，并收紧 A 尾部空行。"
        fi

        log_warn "预览结束。冲突行数: $deleted_count 行。"
        return 0
    fi

    if [[ "$MODE" == "ADD" ]]; then
        log_info "步骤 2: 正在将整个 B 文件追加到清理后的 A..."
        append_b_to_cleaned_a
    fi

    if [[ "$deleted_count" -eq 0 && "$MODE" == "CLEAN" ]]; then
        rm -f -- "$TMP_FILE"
        TMP_FILE=""
        log_info "没有发现需要删除的行，A 保持不变。"
        return 0
    fi

    mv -- "$TMP_FILE" "$FILE_A"
    TMP_FILE=""

    if [[ "$MODE" == "ADD" ]]; then
        log_info "操作成功！已删除冲突行 $deleted_count 行，并已将 B 追加到 $FILE_A。"
    else
        log_info "操作成功！已删除冲突行 $deleted_count 行，并同步更新至 $FILE_A。"
    fi
}

main "$@"