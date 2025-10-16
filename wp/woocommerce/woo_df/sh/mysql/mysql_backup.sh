#!/bin/bash

# =============================================================================
# mysql_backup_parallel.sh - 并行、无时间戳、仅数据备份（兼容 5.7 → 8.0+）
# 基本用法:bash mysql_backup.sh -d /www/backups/mysql  --parallel 4 
# - 文件名: dbname.sql[.ext]
# - 仅使用 GNU parallel 实现并行(不要开太高,硬盘可能受不了)
# - 仅备份表结构 + 数据（无 routines/triggers/events）
# =============================================================================

set -euo pipefail

DEFAULT_BACKUP_DIR="/var/backups/mysql"
DEFAULT_MYSQL_USER="root"
DEFAULT_MYSQL_HOST="localhost"
DEFAULT_MYSQL_PORT="3306"
DEFAULT_COMPRESS="none"
DEFAULT_PARALLEL=1

DRY_RUN=false
BACKUP_DIR=""
MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_HOST=""
MYSQL_PORT=""
SHOW_HELP=false
EXCLUDE_SYSTEM_DB=true
COMPRESS_FORMAT=""
PARALLEL_JOBS=1

SYSTEM_DATABASES=("mysql" "information_schema" "performance_schema" "sys")

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

Parallel MySQL data-only backup with fixed filename (no timestamp).

OPTIONS:
  -h, --help                Show help
  -u, --user USER           MySQL user (default: $DEFAULT_MYSQL_USER)
  -p, --password PASS       MySQL password
      --host HOST           MySQL host (default: $DEFAULT_MYSQL_HOST)
      --port PORT           MySQL port (default: $DEFAULT_MYSQL_PORT)
  -d, --backup-dir DIR      Backup directory (default: $DEFAULT_BACKUP_DIR)
      --compress FMT        Compression: gz, zst, zip, 7z, none (default: none)
      --parallel N          Parallel jobs (default: $DEFAULT_PARALLEL, requires GNU parallel)
      --dry-run             Preview actions (sequential)
      --include-system      Include system DBs (not recommended)
      --exclude-db NAME     Exclude DB (can be repeated)

FILE NAMING:
  dbname.sql          (none)
  dbname.sql.gz       (gz)
  dbname.sql.zst      (zst)
  dbname.sql.zip      (zip)
  dbname.sql.7z       (7z)

REQUIREMENTS:
  - GNU parallel must be installed for parallel execution

EOF
}

parse_args() {
    local exclude_dbs=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) SHOW_HELP=true; shift ;;
            -u|--user) MYSQL_USER="$2"; shift 2 ;;
            -p|--password) MYSQL_PASSWORD="$2"; shift 2 ;;
            --host) MYSQL_HOST="$2"; shift 2 ;;
            --port) MYSQL_PORT="$2"; shift 2 ;;
            -d|--backup-dir) BACKUP_DIR="$2"; shift 2 ;;
            --compress) COMPRESS_FORMAT="$2"; shift 2 ;;
            --parallel) PARALLEL_JOBS="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --include-system) EXCLUDE_SYSTEM_DB=false; shift ;;
            --exclude-db) exclude_dbs+=("$2"); shift 2 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ ${#exclude_dbs[@]} -gt 0 ]]; then
        SYSTEM_DATABASES+=("${exclude_dbs[@]}")
    fi
}

build_mysql_opts() {
    local opts=()
    [[ -n "$MYSQL_HOST" ]] && opts+=("--host=$MYSQL_HOST")
    [[ -n "$MYSQL_PORT" ]] && opts+=("--port=$MYSQL_PORT")
    [[ -n "$MYSQL_USER" ]] && opts+=("--user=$MYSQL_USER")
    [[ -n "$MYSQL_PASSWORD" ]] && opts+=("--password=$MYSQL_PASSWORD")
    echo "${opts[@]}"
}

get_compress_info() {
    local fmt="${1:-none}"
    case "$fmt" in
        gz)   echo "gzip:.sql.gz" ;;
        zst)  echo "zstd:.sql.zst" ;;
        zip)  echo "zip:.sql.zip" ;;
        7z)   echo "7z:.sql.7z" ;;
        none|"") echo "cat:.sql" ;;
        *) log_error "Unsupported format: $fmt"; exit 1 ;;
    esac
}

check_compress_dependencies() {
    local cmd
    case "$COMPRESS_FORMAT" in
        gz) cmd="gzip" ;;
        zst) cmd="zstd" ;;
        zip) cmd="zip" ;;
        7z) cmd="7z" ;;
        none|"") return 0 ;;
        *) log_error "Invalid compress"; exit 1 ;;
    esac
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Compression tool '$cmd' not installed"
        exit 1
    fi
}

# Core backup function (no timestamp in filename)
backup_database() {
    local db="$1"

    IFS=':' read -r cmd ext <<< "$(get_compress_info "$COMPRESS_FORMAT")"
    local filename="${BACKUP_DIR}/${db}${ext}"

    local mysql_opts
    mysql_opts=$(build_mysql_opts)

    if [[ -f "$filename" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "[SKIP] $db → $(basename \"$filename\") 已存在, 跳过备份"
        else
            log_info "[SKIP] $db → $(basename \"$filename\") 已存在, 跳过备份"
        fi
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$cmd" == "cat" ]]; then
            log_dry "mysqldump $mysql_opts --single-transaction  '$db' > '$filename'"
        elif [[ "$cmd" == "zip" ]]; then
            log_dry "mysqldump $mysql_opts --single-transaction  '$db' | zip -j '$filename' -"
        elif [[ "$cmd" == "7z" ]]; then
            log_dry "mysqldump $mysql_opts --single-transaction  '$db' | 7z a -si '$filename'"
        else
            log_dry "mysqldump $mysql_opts --single-transaction  '$db' | $cmd > '$filename'"
        fi
    else
        if [[ "$cmd" == "cat" ]]; then
            mysqldump $mysql_opts --single-transaction  "$db" > "$filename"
        elif [[ "$cmd" == "zip" ]]; then
            mysqldump $mysql_opts --single-transaction  "$db" | zip -j "$filename" -
        elif [[ "$cmd" == "7z" ]]; then
            mysqldump $mysql_opts --single-transaction  "$db" | 7z a -si "$filename"
        else
            mysqldump $mysql_opts --single-transaction  "$db" | "$cmd" > "$filename"
        fi

        if [[ $? -eq 0 ]]; then
            log_info "✅ $db → $(basename \"$filename\")"
        else
            log_error "❌ Failed: $db"
            return 1
        fi
    fi
}

main() {
    BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    MYSQL_USER="${MYSQL_USER:-$DEFAULT_MYSQL_USER}"
    MYSQL_HOST="${MYSQL_HOST:-$DEFAULT_MYSQL_HOST}"
    MYSQL_PORT="${MYSQL_PORT:-$DEFAULT_MYSQL_PORT}"
    COMPRESS_FORMAT="${COMPRESS_FORMAT:-$DEFAULT_COMPRESS}"
    PARALLEL_JOBS="${PARALLEL_JOBS:-$DEFAULT_PARALLEL}"

    # Validate parallel jobs
    if ! [[ "$PARALLEL_JOBS" =~ ^[1-9][0-9]*$ ]]; then
        log_error "--parallel must be a positive integer"
        exit 1
    fi

    if [[ "$SHOW_HELP" == true ]]; then
        show_help
        exit 0
    fi

    # Check essential dependencies
    if ! command -v mysqldump &> /dev/null; then
        log_error "mysqldump not found"
        exit 1
    fi
    check_compress_dependencies

    # GNU parallel is REQUIRED for parallel execution
    if [[ "$DRY_RUN" == false ]] && ! command -v parallel &> /dev/null; then
        log_error "GNU parallel is required but not installed. Please install it (e.g., 'apt install parallel')."
        exit 1
    fi

    # Create backup dir
    if [[ ! -d "$BACKUP_DIR" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Will create: $BACKUP_DIR"
        else
            mkdir -p "$BACKUP_DIR"
            log_info "Created: $BACKUP_DIR"
        fi
    fi

    # Get database list
    log_info "Fetching databases..."
    mapfile -t databases < <(mysql $(build_mysql_opts) -Nse "SHOW DATABASES;" 2>/dev/null | while read -r db; do
        local skip=false
        if [[ "$EXCLUDE_SYSTEM_DB" == true ]]; then
            for sys in "${SYSTEM_DATABASES[@]}"; do
                [[ "$db" == "$sys" ]] && skip=true && break
            done
        fi
        [[ "$skip" == false ]] && echo "$db"
    done)

    if [[ ${#databases[@]} -eq 0 ]]; then
        log_warn "No databases to backup"
        exit 0
    fi

    log_info "Backing up ${#databases[@]} DBs"

    if [[ "$DRY_RUN" == true ]]; then
        # Dry-run is sequential for clarity
        for db in "${databases[@]}"; do
            backup_database "$db"
        done
        log_dry "Dry-run completed"
    else
        # Parallel execution (GNU parallel only)
        export -f backup_database get_compress_info build_mysql_opts log_info log_error
        export BACKUP_DIR COMPRESS_FORMAT DRY_RUN
        printf '%s\n' "${databases[@]}" | parallel -j "$PARALLEL_JOBS" --line-buffer backup_database
        log_info "🎉 All backups completed!"
    fi
}

parse_args "$@"
main