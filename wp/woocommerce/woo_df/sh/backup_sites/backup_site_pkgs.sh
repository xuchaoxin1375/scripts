#!/bin/bash


# =============================================
# 📦 服务器 A → 服务器 B 压缩包备份脚本（要求SSH 已配好免密）
# 仅备份指定目录中的压缩包，保留子目录结构
# 可选每日归档，支持多种压缩格式
# =============================================
#
# 用法:
#   bash backup_site_pkgs.sh [选项]
#
# 选项:
#   -s, --source-dir <目录>      指定源目录 (默认: /srv/uploads/uploader/files)
#   -b, --backup-server <地址>   指定备份服务器 
#   -l, --log-file <文件>        指定日志文件 (默认: 源目录/backup-to-srv.log)
#   -d, --backup-dir <目录>      指定备份目录 (默认: /www/wwwroot/xcx/s2)
#   --date-dir                   启用创建每日备份子目录 (如 2025-09-12),这不建议,对rsync检查增量不简便
#   -h, --help                   显示帮助信息
#
# 示例:
#   bash backup_site_pkgs.sh --date-dir
#   bash backup_site_pkgs.sh -s /data/files -b user@host -d /backup --date-dir
# =============================================






# -h 输出内容截止于此(暂定前30行)
# ========== 🔧 配置区（默认值，可被参数覆盖） ==========
BACKUP_SERVER="root@xxx.xxx.xxx.xxx"
SOURCE_DIR="/srv/uploads/uploader/files"
BACKUP_DIR="/www/wwwroot/xcx/s2"
LOG_FILE=""
USE_DATE_DIR=0

# ========== 🧩 支持的压缩包格式（可自行增删） ==========
INCLUDE_PATTERNS=(
    "*.zst" "*.tar.zst"
    "*.lz4"
    "*.zip"
    "*.tar.gz" "*.tgz"
    "*.tar.bz2" "*.tbz2"
    "*.tar.xz" "*.txz"
    "*.rar"
    "*.7z"
    "*.gz" "*.bz2" "*.xz"
)

# ========== 🏷️ 解析命令行参数和现实帮助 ==========
show_help() {
    echo "# 帮助文档来源: 脚本顶部注释区" >&2
    head -30 "$0" | grep '^#' | sed 's/^#//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--source-dir)
            SOURCE_DIR="$2"; shift 2;;
        -b|--backup-server)
            BACKUP_SERVER="$2"; shift 2;;
        -d|--backup-dir)
            BACKUP_DIR="$2"; shift 2;;
        -l|--log-file)
            LOG_FILE="$2"; shift 2;;
        --date-dir)
            USE_DATE_DIR=1; shift;;
        -h|--help)
            show_help;;
        *)
            echo "未知参数: $1"; show_help;;
    esac
done

# 日志文件默认值
if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="$SOURCE_DIR/backup-to-srv.log"
fi

# ========== 📝 日志函数 ==========
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}


# ========== 🚀 开始执行 ==========
log "=== 🚀 启动压缩包备份任务 ==="

# 检查源目录是否存在
if [ ! -d "$SOURCE_DIR" ]; then
    log "❌ 源目录不存在: $SOURCE_DIR"
    exit 1
fi

# 备份目标目录
if [[ "$USE_DATE_DIR" -eq 1 ]]; then
    TARGET_DIR="$BACKUP_DIR/$(date +%Y-%m-%d)"
else
    TARGET_DIR="$BACKUP_DIR"
fi

# 在服务器 B 上创建备份目录
log "📁 准备创建远程目录: $TARGET_DIR"
if ! ssh "$BACKUP_SERVER" "mkdir -p '$TARGET_DIR'" 2>> "$LOG_FILE"; then
    log "❌ 无法在 B 服务器创建目录，请检查网络或权限"
    exit 1
fi


# ========== 🔄 构建 rsync 命令 ==========
RSYNC_CMD=(
    rsync
    -avP
    # -z #压缩传输,如果已经是压缩包,可以不使用
    --prune-empty-dirs
    --include="*/"                  # 保留子目录结构（关键！）
)

for pattern in "${INCLUDE_PATTERNS[@]}"; do
    RSYNC_CMD+=(--include="$pattern")
done

RSYNC_CMD+=(--exclude="*")          # 排除其他所有文件
RSYNC_CMD+=("$SOURCE_DIR/")         # 同步目录内容（注意末尾 /）
RSYNC_CMD+=("$BACKUP_SERVER:$TARGET_DIR/")

# ========== ▶️ 执行备份 ==========
log "📤 开始同步压缩包到: $BACKUP_SERVER:$TARGET_DIR"

# 可选：取消下一行注释可试运行（不实际传输）
# RSYNC_CMD+=(--dry-run -v)

if "${RSYNC_CMD[@]}" 2>> "$LOG_FILE"; then
    log "✅ 压缩包备份成功 → $BACKUP_SERVER:$TARGET_DIR"
else
    log "❌ rsync 备份失败，请查看日志: $LOG_FILE"
    exit 1
fi

log "=== 🎉 备份任务完成 ==="