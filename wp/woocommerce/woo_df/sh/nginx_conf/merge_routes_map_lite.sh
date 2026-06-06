#!/usr/bin/env bash
# 快速版本(牺牲部分兼容性):同步两个配置文件，将 B 的内容追加到 A 中，并清理 A 中与 B 的第一列相同的行。
set -euo pipefail

FILE_A=""
FILE_B=""
DRY_RUN=false
MODE="CLEAN" # CLEAN: 只清理 A；ADD: 清理后追加 B

TMP_FILE=""
TMP_NORM=""

RC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'

log_info() { printf '%b[INFO]%b %s\n' "$GREEN" "$RC" "$*" >&2; }
log_warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$RC" "$*" >&2; }
log_error() { printf '%b[ERROR]%b %s\n' "$RED" "$RC" "$*" >&2; }
log_dryrun() { printf '%b[PREVIEW]%b %s\n' "$BLUE" "$RC" "$*" >&2; }

cleanup() {
    [[ -n "${TMP_FILE:-}" && -e "$TMP_FILE" ]] && rm -f -- "$TMP_FILE"
    [[ -n "${TMP_NORM:-}" && -e "$TMP_NORM" ]] && rm -f -- "$TMP_NORM"
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
  脚本会按第一列原样匹配，删除 A 中第一列也出现在 B 中的行。
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
                [[ $# -ge 2 ]] || {
                    log_error "-a 缺少文件路径"
                    exit 1
                }
                FILE_A="$2"
                shift 2
                ;;
            -b)
                [[ $# -ge 2 ]] || {
                    log_error "-b 缺少文件路径"
                    exit 1
                }
                FILE_B="$2"
                shift 2
                ;;
            --add)
                MODE="ADD"
                shift
                ;;
            -d | --dry)
                DRY_RUN=true
                shift
                ;;
            -h | --help)
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

# 只取第一列。
# 空行、注释行返回空字符串。
get_key() {
    local line="$1"

    case "$line" in
        "" | [[:space:]]*) ;;
    esac

    [[ "$line" =~ ^[[:space:]]*$ ]] && return 0
    [[ "$line" =~ ^[[:space:]]*# ]] && return 0

    # 第一列已保证是 .domain.com，因此无需归一化。
    printf '%s\n' "${line%%[[:space:]]*}"
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

main() {
    parse_arguments "$@"

    if [[ "$DRY_RUN" == true ]]; then
        log_warn "--- 当前运行在预览模式 Dry-run，不会修改任何物理文件 ---"
    fi

    local tmp_dir
    tmp_dir=$(dirname -- "$FILE_A")

    TMP_FILE=$(mktemp "${tmp_dir%/}/.sync_safe.XXXXXX")
    TMP_NORM=$(mktemp "${tmp_dir%/}/.sync_safe_norm.XXXXXX")

    chmod --reference="$FILE_A" "$TMP_FILE" 2> /dev/null || true

    declare -A b_domains

    local line
    local line_num=0

    # 读取 B，记录 B 的第一列。
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        key_b=$(get_key "$line")

        if [[ -n "$key_b" ]]; then
            b_domains["$key_b"]=1
        fi
    done < "$FILE_B"

    log_info "步骤 1: 过滤文件 A 中与 B 第一列冲突的行..."

    local deleted_count=0
    line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        key_a=$(get_key "$line")

        if [[ -n "$key_a" && -n "${b_domains["$key_a"]+_}" ]]; then
            deleted_count=$((deleted_count + 1))

            if [[ "$DRY_RUN" == true ]]; then
                log_dryrun "【将删除】A 中第 $line_num 行 -> 第一列: [$key_a] | 内容: '$line'"
            fi

            continue
        fi

        printf '%s\n' "$line"
    done < "$FILE_A" > "$TMP_FILE"

    if [[ "$MODE" == "ADD" ]]; then
        log_info "步骤 2: 正在将整个 B 文件追加到清理后的 A..."

        if [[ "$DRY_RUN" == true ]]; then
            log_dryrun "【整体并入】文件 B ($FILE_B) 的全部内容将追加到 A 末尾，并收紧 A 尾部空行。"
        else
            trim_trailing_blank_lines "$TMP_FILE" "$TMP_NORM"
            mv -- "$TMP_NORM" "$TMP_FILE"

            # 可选：如果你希望 A 和 B 之间一定有一个换行，可以取消下一行注释
            # printf '\n' >> "$TMP_FILE"

            cat -- "$FILE_B" >> "$TMP_FILE"
        fi
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_warn "预览结束。冲突行数: $deleted_count 行。"
        return 0
    fi

    mv -- "$TMP_FILE" "$FILE_A"
    TMP_FILE=""

    log_info "操作成功！已同步更新至 $FILE_A。"
}

main "$@"
