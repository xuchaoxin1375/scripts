#!/usr/bin/env bash
# 合并map配置文件,利用grep优化判断速度
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
用法: $(basename "$0") [OPTIONS] -a <file_a> -b <file_b>

参数说明:
  -a FILE          指定配置文件 A
  -b FILE          指定源文件 B
  --add            清理后整体追加 B 到 A
  -d, --dry        预览模式，只打印改动，不实际修改文件
  -h, --help       显示此帮助信息

说明:
  假设 A 和 B 的有效行第一列都已经是 .domain.com 格式。
  脚本会按第一列原样精确匹配，删除 A 中第一列也出现在 B 第一列中的行。
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
    # 提取 B 的第一列。
    # 跳过空行和注释行。
    # sort -u 可以减少 grep 的 pattern 数量。
    awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        {
            print $1
        }
    ' "$FILE_B" | sort -u > "$TMP_KEYS"
}

grep_candidate_lines() {
    # 用 B 的第一列列表，对 A 做一次性固定字符串搜索。
    # 注意：这里只是粗筛，可能命中第二列、注释、子串等，所以后面还要精确判断第一列。
    if [[ ! -s "$TMP_KEYS" ]]; then
        : > "$TMP_GREP_HITS"
        return 0
    fi

    grep -nFf "$TMP_KEYS" -- "$FILE_A" > "$TMP_GREP_HITS" || true
}

exact_check_candidates() {
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
            # grep -n 输出格式: 行号:内容
            pos = index($0, ":")
            if (pos <= 0) {
                next
            }

            line_no = substr($0, 1, pos - 1)
            content = substr($0, pos + 1)

            # 候选行里仍然跳过空行和注释行
            if (content ~ /^[[:space:]]*$/) {
                next
            }
            if (content ~ /^[[:space:]]*#/) {
                next
            }

            key = content
            sub(/^[[:space:]]+/, "", key)
            sub(/[[:space:]].*$/, "", key)

            # 精确判断：只有 A 的第一列完整等于 B 的某个第一列，才删除
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
    trim_trailing_blank_lines "$TMP_FILE" "$TMP_NORM"
    mv -- "$TMP_NORM" "$TMP_FILE"

    # 如果你希望 A 和 B 之间强制保留一个空行，可以取消下一行注释：
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