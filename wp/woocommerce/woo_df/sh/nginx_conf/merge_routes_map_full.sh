#!/usr/bin/env bash

# ==============================================================================
# 脚本名称: merge_routes_map.sh
# 说明:最初版本,兼容最广泛的情况.性能较低,考虑用grep优化
# 脚本描述:
#   1. 安全地从 A 中清除与 B 冲突的行。
#   2. 可选：清理完成后，将整个 B 文件追加到 A 末尾。
#   3. 全程使用临时文件，避免同一路径在同一管道/重定向中既读又写。
# 假设我的linux设备上有一个配置文件a,里面的内容包含#...的注释行,以及普通的配置(第一列类似于domain.com,
# 其中的domain.com具体分两类情况:"空白字符domain.com",或者"非空白字符串.domain.com" ,请你提取出domain.com,记为变量dm_a
# 现在我希望编写一个脚本,读取b中的行,规律和a相仿,读取第一列,不妨记其中的一个值为提取后为dm_b,如果文件a中某普通行计算的dm_a和dm_b相同则将对应行从a中移除.
# 给出bash脚本,注释和文档完善规范;支持命令行参数,以及预览运行模式 


# ==============================================================================
# shellcheck disable=SC2094
set -euo pipefail

FILE_A=""
FILE_B=""
DRY_RUN=false
MODE="CLEAN"          # CLEAN: 纯清理, ADD: 清理后并入 B
EXPECTED_COLS=2
FORCE_MODE=false

TMP_FILE=""
TMP_NORM=""

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
}
trap cleanup EXIT

usage() {
    cat << EOF
用法: $(basename "$0") [OPTIONS] -a <file_a> -b <file_b>

参数说明:
  -a FILE          指定配置文件 A
  -b FILE          指定源文件 B
  --add            清理后整体追加 B 到 A
  --force          精确第一列模式：严格依据第一列原始文本完全匹配
  -c, --cols NUM   指定预期的有效非注释行列数，默认为: 2
  -d, --dry        预览模式，只打印改动，不实际修改文件
  -h, --help       显示此帮助信息
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
            --force)
                FORCE_MODE=true
                shift
                ;;
            -c|--cols)
                [[ $# -ge 2 ]] || { log_error "$1 缺少列数"; exit 1; }
                EXPECTED_COLS="$2"
                shift 2
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

    if ! [[ "$EXPECTED_COLS" =~ ^[1-9][0-9]*$ ]]; then
        log_error "--cols 必须是正整数。"
        exit 1
    fi
}

process_line() {
    local line="$1"
    local file_name="$2"
    local line_num="$3"

    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line//[[:space:]]/}" ]]; then
        printf 'COMMENT\n'
        return 0
    fi

    local actual_cols
    actual_cols=$(awk '{print NF; exit}' <<< "$line")

    if [[ "$actual_cols" -ne "$EXPECTED_COLS" ]]; then
        log_warn "文件 [$file_name] 第 $line_num 行列数不符合预期，预期 $EXPECTED_COLS 列，实际 $actual_cols 列 -> 内容: '$line'"
    fi

    local first_col
    first_col=$(awk '{print $1; exit}' <<< "$line")

    if [[ "$FORCE_MODE" == true ]]; then
        printf '%s\n' "$first_col"
    else
        local dm
        dm=$(sed -E 's/^\.+//; s/.*\.([^\.]+\.[^\.]+)$/\1/' <<< "$first_col")
        printf '%s\n' "$dm"
    fi
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

    chmod --reference="$FILE_A" "$TMP_FILE" 2>/dev/null || true

    declare -A b_domains

    local line
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        local key_b
        key_b=$(process_line "$line" "$(basename -- "$FILE_B")" "$line_num")

        if [[ -n "$key_b" && "$key_b" != "COMMENT" ]]; then
            b_domains["$key_b"]=1
        fi
    done < "$FILE_B"

    log_info "步骤 1: 过滤文件 A 中与 B 冲突的行..."

    local deleted_count=0
    line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        local key_a
        key_a=$(process_line "$line" "$(basename -- "$FILE_A")" "$line_num")

        if [[ -n "$key_a" && "$key_a" != "COMMENT" ]] && [[ -n "${b_domains["$key_a"]+_}" ]]; then
            deleted_count=$((deleted_count + 1))

            if [[ "$DRY_RUN" == true ]]; then
                log_dryrun "【将删除】A 中第 $line_num 行 -> 冲突凭据: [$key_a] | 内容: '$line'"
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
            # 关键改进：
            # 不使用 sed -i，也不使用 `cmd "$TMP_FILE" > "$TMP_FILE"`。
            # 先读取 TMP_FILE，写入 TMP_NORM，再用 mv 替换。
            trim_trailing_blank_lines "$TMP_FILE" "$TMP_NORM"
            mv -- "$TMP_NORM" "$TMP_FILE"

            # 这里只读取 FILE_B，追加写入 TMP_FILE；两者不是同一个文件。
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