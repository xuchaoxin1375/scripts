#!/bin/bash

# =============================================================================
# mysql_import_parallel.sh - 并行、自动建库、支持免密、可指定目录/单文件导入
# dev:相比默认版本增加了进度显示:bash mysql_import_dev.sh -d /www/backups/mysql  --parallel 16
# - 文件名: xxx.sql[.gz|.zst|.zip|.7z]，数据库名为xxx
# - 支持 GNU parallel 并行导入
# =============================================================================

set -euo pipefail

DEFAULT_IMPORT_DIR="/www/backups/mysql"
DEFAULT_MYSQL_USER="root"
DEFAULT_MYSQL_HOST="localhost"
DEFAULT_MYSQL_PORT="3306"
DEFAULT_PARALLEL=1

MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_HOST=""
MYSQL_PORT=""
IMPORT_DIR=""
SINGLE_FILE=""
PARALLEL_JOBS=1
SHOW_HELP=false
DRY_RUN=false

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

log_info()  { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_dry()   { echo -e "${GREEN}[DRY-RUN]${NC} $*" >&2; }

show_help() {
cat << EOF
Usage: $0 [OPTIONS]

Parallel MySQL import from .sql files (auto create DB if missing).

OPTIONS:
  -h, --help                Show help
  -u, --user USER           MySQL user (default: $DEFAULT_MYSQL_USER)
  -p, --password PASS       MySQL password
      --host HOST           MySQL host (default: $DEFAULT_MYSQL_HOST)
      --port PORT           MySQL port (default: $DEFAULT_MYSQL_PORT)
  -d, --import-dir DIR      Import directory (default: $DEFAULT_IMPORT_DIR)
  -f, --file FILE           Import a single .sql file
      --parallel N          Parallel jobs (default: $DEFAULT_PARALLEL, requires GNU parallel)
      --dry-run             Preview actions only

EXAMPLES:
  $0 -d /path/to/dir --parallel 4
  $0 -f /path/to/dbname.sql

REQUIREMENTS:
  - GNU parallel must be installed for parallel execution
  - 支持免密登录 (如已配置my.cnf)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) SHOW_HELP=true; shift ;;
            -u|--user) MYSQL_USER="$2"; shift 2 ;;
            -p|--password) MYSQL_PASSWORD="$2"; shift 2 ;;
            --host) MYSQL_HOST="$2"; shift 2 ;;
            --port) MYSQL_PORT="$2"; shift 2 ;;
            -d|--import-dir) IMPORT_DIR="$2"; shift 2 ;;
            -f|--file) SINGLE_FILE="$2"; shift 2 ;;
            --parallel) PARALLEL_JOBS="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done
}

build_mysql_opts() {
    local opts=()
    [[ -n "$MYSQL_HOST" ]] && opts+=("--host=$MYSQL_HOST")
    [[ -n "$MYSQL_PORT" ]] && opts+=("--port=$MYSQL_PORT")
    [[ -n "$MYSQL_USER" ]] && opts+=("--user=$MYSQL_USER")
    [[ -n "$MYSQL_PASSWORD" ]] && opts+=("--password=$MYSQL_PASSWORD")
    echo "${opts[@]}"
}

check_mysql_connection() {
    local mysql_opts
    mysql_opts=$(build_mysql_opts)
    if ! mysql $mysql_opts -e "SELECT VERSION();" &>/tmp/mysql_version.txt; then
        log_error "无法连接到MySQL，请检查连接参数或my.cnf配置。"
        exit 1
    fi
    log_info "MySQL连接成功，版本信息：$(grep -v '^+' /tmp/mysql_version.txt | tail -n1)"
}

get_dbname_from_file() {
    local file="$1"
    local base
    base=$(basename "$file")
    echo "$base" | sed -E 's/\.(sql|sql\.gz|sql\.zst|sql\.zip|sql\.7z)$//' \
        | sed -E 's/\.(gz|zst|zip|7z)$//'
}

create_db_if_not_exists() {
    local db="$1"
    local mysql_opts
    mysql_opts=$(build_mysql_opts)
    if ! mysql $mysql_opts -e "USE \`$db\`;" 2>/dev/null; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "创建数据库: $db"
        else
            log_info "创建数据库: $db"
            mysql $mysql_opts -e "CREATE DATABASE IF NOT EXISTS \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
        fi
    fi
}

import_sql_file() {
    local file="$1"
    local db
    db=$(get_dbname_from_file "$file")
    # 进度信息
    local idx total
    if [[ -n "${IMPORT_PROGRESS_IDX:-}" && -n "${IMPORT_PROGRESS_TOTAL:-}" ]]; then
        idx="$IMPORT_PROGRESS_IDX"
        total="$IMPORT_PROGRESS_TOTAL"
        log_info "[进度 $idx/$total] 正在导入: $file → $db"
    else
        log_info "导入: $file → $db"
    fi
    create_db_if_not_exists "$db"
    local mysql_opts
    mysql_opts=$(build_mysql_opts)
    local import_cmd
    if [[ "$file" =~ \.sql\.gz$ ]]; then
        import_cmd="gunzip -c '$file' | mysql $mysql_opts -D '$db'"
    elif [[ "$file" =~ \.sql\.zst$ ]]; then
        import_cmd="zstd -dc '$file' | mysql $mysql_opts -D '$db'"
    elif [[ "$file" =~ \.sql\.zip$ ]]; then
        import_cmd="unzip -p '$file' | mysql $mysql_opts -D '$db'"
    elif [[ "$file" =~ \.sql\.7z$ ]]; then
        import_cmd="7z x -so '$file' | mysql $mysql_opts -D '$db'"
    else
        import_cmd="mysql $mysql_opts -D '$db' < '$file'"
    fi
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "$import_cmd"
    else
        eval "$import_cmd"
        if [[ $? -eq 0 ]]; then
            log_info "✅ $db ← $(basename "$file")"
        else
            log_error "❌ 导入失败: $file"
            return 1
        fi
    fi
}

main() {
    IMPORT_DIR="${IMPORT_DIR:-$DEFAULT_IMPORT_DIR}"
    MYSQL_USER="${MYSQL_USER:-$DEFAULT_MYSQL_USER}"
    MYSQL_HOST="${MYSQL_HOST:-$DEFAULT_MYSQL_HOST}"
    MYSQL_PORT="${MYSQL_PORT:-$DEFAULT_MYSQL_PORT}"
    PARALLEL_JOBS="${PARALLEL_JOBS:-$DEFAULT_PARALLEL}"

    if [[ "$SHOW_HELP" == true ]]; then
        show_help
        exit 0
    fi

    # 检查依赖
    if ! command -v mysql &>/dev/null; then
        log_error "mysql 命令未找到"
        exit 1
    fi
    if ! command -v parallel &>/dev/null; then
        log_error "GNU parallel 未安装，请先安装 (如: apt install parallel)"
        exit 1
    fi

    check_mysql_connection

    if [[ -n "$SINGLE_FILE" ]]; then
        if [[ ! -f "$SINGLE_FILE" ]]; then
            log_error "指定的文件不存在: $SINGLE_FILE"
            exit 1
        fi
        import_sql_file "$SINGLE_FILE"
        exit $?
    fi

    if [[ ! -d "$IMPORT_DIR" ]]; then
        log_error "指定的导入目录不存在: $IMPORT_DIR"
        exit 1
    fi

    mapfile -t sql_files < <(find "$IMPORT_DIR" -maxdepth 1 -type f -regextype posix-egrep -regex ".*\\.sql(\\.gz|\\.zst|\\.zip|\\.7z)?$")
    if [[ ${#sql_files[@]} -eq 0 ]]; then
        log_warn "未找到任何 .sql 文件"
        exit 0
    fi
    log_info "共发现 ${#sql_files[@]} 个 SQL 文件，开始导入..."

    start_time=$(date +%s)

    export -f import_sql_file get_dbname_from_file create_db_if_not_exists build_mysql_opts log_info log_error log_dry
    export MYSQL_USER MYSQL_PASSWORD MYSQL_HOST MYSQL_PORT DRY_RUN

    # 传递进度信息给每个任务
    total=${#sql_files[@]}
    for i in "${!sql_files[@]}"; do
        idx=$((i+1))
        IMPORT_PROGRESS_IDX="$idx" IMPORT_PROGRESS_TOTAL="$total" \
            parallel -j 1 --line-buffer import_sql_file ::: "${sql_files[$i]}"
    done | parallel -j "$PARALLEL_JOBS" --line-buffer cat

    end_time=$(date +%s)
    duration=$((end_time - start_time))
    hours=$((duration / 3600))
    mins=$(( (duration % 3600) / 60 ))
    secs=$((duration % 60))
    log_info "🎉 全部导入完成! 用时: ${hours}h ${mins}m ${secs}s"
}

parse_args "$@"
main
