#!/usr/bin/env bash
# ==============================================================================
# 脚本名称:
#   merge_routes_map.sh
#
# 脚本用途:
#   根据文件 B 的第一列，清理文件 A 中第一列与 B 冲突的行。
#
# 使用前提:
#   1. 文件 A 的有效非注释行，第一列已经是 .domain.com 形式。
#   2. 文件 B 的有效非注释行，第一列也已经是 .domain.com 形式。
#   3. 本脚本不再做域名归一化、不再提取二级域名、不再检查列数。
#   4. 匹配规则是“第一列原样完全相等”。
#
# 示例:
#   A 中存在:
#       .example.com  DIRECT
#
#   B 中存在:
#       .example.com  PROXY
#
#   则 A 中这一行会被删除。
#
#   如果 A 中存在:
#       .sub.example.com  DIRECT
#
#   B 中只有:
#       .example.com      PROXY
#
#   则不会删除 .sub.example.com，因为第一列并不完全相等。
#
# 工作流程:
#   1. 从 B 中提取所有有效行的第一列，去重后写入临时 key 文件。
#   2. 使用 grep -Ff 对 A 做一次固定字符串粗筛，找出“可能包含冲突 key”的候选行。
#   3. 对 grep 命中的候选行，再用 awk 精确判断第一列是否完整等于 B 中某个 key。
#   4. 记录需要删除的 A 行号。
#   5. 根据删除行号重写 A。
#   6. 如果指定 --add，则清理完成后把整个 B 追加到 A 末尾。
#
# 为什么不直接用 grep 删除:
#   grep -Ff 只能判断某个字符串是否出现在整行中。
#   它可能命中第二列、注释内容、或者其他字段。
#   因此 grep 只用于“粗筛候选行”，真正删除仍然由 awk 检查第一列精确匹配。
#
# 相比最初版本的优化:
#   最初版本对 A/B 每一行都调用 process_line，并在其中使用 awk/sed 做列数检查、
#   域名归一化、二级域名提取和模式分支判断。这个版本去掉这些复杂逻辑，
#   只保留“第一列原样匹配”，并把大量逐行 Bash 判断改成 grep/awk 批处理。
#
# 注意:
#   如果 A 中绝大多数行都会被 grep 命中，那么 grep 粗筛带来的收益会下降。
#   如果 B 的 key 相对较少、A 很大、实际冲突很少，则这个版本通常会明显更快。
# ==============================================================================

set -euo pipefail

FILE_A=""
FILE_B=""
DRY_RUN=false
MODE="CLEAN"   # CLEAN: 只清理 A；ADD: 清理后追加 B

TMP_FILE=""
TMP_NORM=""
TMP_KEYS=""
TMP_GREP_HITS=""
TMP_DELETE_LINES=""
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
    [[ -n "${TMP_KEYS:-}" && -e "$TMP_KEYS" ]] && rm -f -- "$TMP_KEYS"
    [[ -n "${TMP_GREP_HITS:-}" && -e "$TMP_GREP_HITS" ]] && rm -f -- "$TMP_GREP_HITS"
    [[ -n "${TMP_DELETE_LINES:-}" && -e "$TMP_DELETE_LINES" ]] && rm -f -- "$TMP_DELETE_LINES"
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

匹配规则:
  只比较 A/B 有效行的第一列。
  第一列完全相等时，删除 A 中对应行。

前提:
  A/B 的有效行第一列均已是 .domain.com 形式。
  本脚本不会再做域名归一化或列数检查。
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
    TMP_KEYS=$(mktemp "${tmp_dir%/}/.sync_keys.XXXXXX")
    TMP_GREP_HITS=$(mktemp "${tmp_dir%/}/.sync_hits.XXXXXX")
    TMP_DELETE_LINES=$(mktemp "${tmp_dir%/}/.sync_delete_lines.XXXXXX")
    TMP_COUNT=$(mktemp "${tmp_dir%/}/.sync_count.XXXXXX")

    chmod --reference="$FILE_A" "$TMP_FILE" 2>/dev/null || true
}

extract_b_keys() {
    # 从 B 中提取有效行第一列。
    #
    # 跳过:
    #   1. 空行
    #   2. 以 # 开头的注释行
    #
    # sort -u 的作用:
    #   1. 去重，减少 grep 的 pattern 数量。
    #   2. B 中重复 key 较多时可以降低后续匹配成本。
    #
    # LC_ALL=C 的作用:
    #   使用 C locale，通常可以让 sort/grep 在纯 ASCII 域名场景下更快。
    awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        { print $1 }
    ' "$FILE_B" | LC_ALL=C sort -u > "$TMP_KEYS"
}

grep_candidate_lines() {
    # 使用 B 的 key 列表，对 A 做一次固定字符串粗筛。
    #
    # grep 参数说明:
    #   -n   输出行号，后续需要按行号删除。
    #   -F   固定字符串匹配，不把 . 当作正则符号。
    #   -f   从 TMP_KEYS 读取匹配模式。
    #
    # 注意:
    #   这里不是最终删除依据。
    #   grep 可能命中整行中的任意位置，所以必须再做第一列精确校验。
    if [[ ! -s "$TMP_KEYS" ]]; then
        : > "$TMP_GREP_HITS"
        return 0
    fi

    LC_ALL=C grep -nFf "$TMP_KEYS" -- "$FILE_A" > "$TMP_GREP_HITS" || true
}

exact_check_candidates() {
    # 对 grep 命中的候选行做精确判断。
    #
    # 输入:
    #   文件 1: TMP_KEYS
    #       B 的第一列 key 集合。
    #
    #   文件 2: TMP_GREP_HITS
    #       grep -nFf 输出的候选行，格式为:
    #       行号:原始内容
    #
    # 判断逻辑:
    #   1. 跳过候选中的空行和注释行。
    #   2. 提取候选行第一列。
    #   3. 只有当第一列完整存在于 B 的 key 集合时，才记录删除行号。
    #
    # 输出:
    #   TMP_DELETE_LINES:
    #       需要从 A 删除的行号。
    #
    #   TMP_COUNT:
    #       删除行数量。
    : > "$TMP_DELETE_LINES"
    : > "$TMP_COUNT"

    if [[ ! -s "$TMP_GREP_HITS" ]]; then
        printf '0\n' > "$TMP_COUNT"
        return 0
    fi

    awk \
        -v dry="$DRY_RUN" \
        -v delete_file="$TMP_DELETE_LINES" \
        -v count_file="$TMP_COUNT" \
        -v blue="$BLUE" \
        -v rc="$RC" '
        FNR == 1 {
            file_index++
        }

        file_index == 1 {
            keys[$0] = 1
            next
        }

        file_index == 2 {
            pos = index($0, ":")
            if (pos <= 0) {
                next
            }

            line_no = substr($0, 1, pos - 1)
            content = substr($0, pos + 1)

            if (content ~ /^[[:space:]]*$/) {
                next
            }

            if (content ~ /^[[:space:]]*#/) {
                next
            }

            key = content
            sub(/^[[:space:]]+/, "", key)
            sub(/[[:space:]].*$/, "", key)

            if (key in keys) {
                print line_no >> delete_file
                deleted++

                if (dry == "true") {
                    printf "%s[PREVIEW]%s 【将删除】A 中第 %d 行 -> 第一列: [%s] | 内容: '\''%s'\''\n", \
                        blue, rc, line_no, key, content > "/dev/stderr"
                }
            }

            next
        }

        END {
            print deleted + 0 > count_file
        }
    ' "$TMP_KEYS" "$TMP_GREP_HITS"
}

filter_a_by_delete_lines() {
    # 根据 TMP_DELETE_LINES 中记录的行号，重写 A。
    #
    # 如果没有需要删除的行，则直接复制 A 到 TMP_FILE。
    # 如果存在删除行，则只输出不在删除列表中的行。
    if [[ ! -s "$TMP_DELETE_LINES" ]]; then
        cat -- "$FILE_A" > "$TMP_FILE"
        return 0
    fi

    awk '
        NR == FNR {
            del[$1] = 1
            next
        }

        !(FNR in del) {
            print
        }
    ' "$TMP_DELETE_LINES" "$FILE_A" > "$TMP_FILE"
}

trim_trailing_blank_lines() {
    # 删除文件末尾多余空行。
    #
    # 用于 --add 模式:
    #   先收紧清理后的 A 末尾空行，再追加 B。
    local input_file="$1"
    local output_file="$2"

    awk '
        {
            lines[NR] = $0
        }
        END {
            last = NR
            while (last > 0 && lines[last] ~ /^[[:space:]]*$/) {
                last--
            }
            for (i = 1; i <= last; i++) {
                print lines[i]
            }
        }
    ' "$input_file" > "$output_file"
}

append_b_to_cleaned_a() {
    # 将 B 追加到清理后的 A。
    #
    # 注意:
    #   这里追加的是整个 B 文件内容，而不是只追加 B 的有效行。
    #   这与原脚本 --add 的语义保持一致。
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

    log_info "步骤 1: 从 B 中提取第一列 key..."
    extract_b_keys

    if [[ ! -s "$TMP_KEYS" ]]; then
        log_warn "B 中没有可用于匹配的有效第一列。"

        if [[ "$DRY_RUN" == true ]]; then
            if [[ "$MODE" == "ADD" ]]; then
                log_dryrun "【整体并入】仍会将 B 的全部内容追加到 A 末尾。"
            fi
            log_warn "预览结束。冲突行数: 0 行。"
            return 0
        fi

        if [[ "$MODE" == "ADD" ]]; then
            cat -- "$FILE_A" > "$TMP_FILE"
            append_b_to_cleaned_a
            mv -- "$TMP_FILE" "$FILE_A"
            TMP_FILE=""
            log_info "操作成功！B 已追加到 $FILE_A。"
        else
            log_info "没有需要清理的内容。"
        fi

        return 0
    fi

    log_info "步骤 2: 使用 grep 对 A 进行初步候选筛选..."
    grep_candidate_lines

    if [[ ! -s "$TMP_GREP_HITS" ]]; then
        log_info "grep 初筛未发现任何候选冲突行。"

        if [[ "$DRY_RUN" == true ]]; then
            if [[ "$MODE" == "ADD" ]]; then
                log_dryrun "【整体并入】文件 B ($FILE_B) 的全部内容将追加到 A 末尾，并收紧 A 尾部空行。"
            fi
            log_warn "预览结束。冲突行数: 0 行。"
            return 0
        fi

        if [[ "$MODE" == "ADD" ]]; then
            cat -- "$FILE_A" > "$TMP_FILE"
            append_b_to_cleaned_a
            mv -- "$TMP_FILE" "$FILE_A"
            TMP_FILE=""
            log_info "操作成功！B 已追加到 $FILE_A。"
        else
            log_info "没有需要删除的行，A 保持不变。"
        fi

        return 0
    fi

    log_info "步骤 3: 对 grep 候选结果进行第一列精确比对..."
    exact_check_candidates

    deleted_count=$(cat "$TMP_COUNT")

    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$MODE" == "ADD" ]]; then
            log_dryrun "【整体并入】文件 B ($FILE_B) 的全部内容将追加到 A 末尾，并收紧 A 尾部空行。"
        fi

        log_warn "预览结束。冲突行数: $deleted_count 行。"
        return 0
    fi

    if [[ "$deleted_count" -eq 0 ]]; then
        log_info "候选行精确比对后，没有发现需要删除的行。"

        if [[ "$MODE" == "ADD" ]]; then
            cat -- "$FILE_A" > "$TMP_FILE"
            append_b_to_cleaned_a
            mv -- "$TMP_FILE" "$FILE_A"
            TMP_FILE=""
            log_info "操作成功！B 已追加到 $FILE_A。"
        else
            log_info "A 保持不变。"
        fi

        return 0
    fi

    log_info "步骤 4: 正在按精确匹配结果过滤 A..."
    filter_a_by_delete_lines

    if [[ "$MODE" == "ADD" ]]; then
        log_info "步骤 5: 正在将整个 B 文件追加到清理后的 A..."
        append_b_to_cleaned_a
    fi

    mv -- "$TMP_FILE" "$FILE_A"
    TMP_FILE=""

    log_info "操作成功！已删除冲突行 $deleted_count 行，并同步更新至 $FILE_A。"
}

main "$@"