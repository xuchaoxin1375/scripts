#!/usr/bin/env bash

# ==============================================================================
# 脚本名称: upgrade_nginx.sh
# 适用系统: Ubuntu 24.04 LTS (Noble Numbat)
# 功能描述: 安全升级 Nginx 至官方最新 Stable / Mainline 版本 (支持热升级、回滚)
# ==============================================================================

set -o pipefail

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 配置参数 ---
NGINX_BRANCH="stable" # 可选: "stable" (稳定版) 或 "mainline" (主力版)
BACKUP_DIR="/etc/nginx_backup_$(date +%Y%m%d_%H%M%S)"
CODENAME="noble"      # Ubuntu 24.04 代号

# --- 日志函数 ---
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 权限与环境检查 ---
if [[ $EUID -ne 0 ]]; then
   log_error "该脚本必须以 root 权限运行，请使用: sudo $0"
   exit 1
fi

# 检查当前是否安装了 Nginx
if ! command -v nginx &> /dev/null; then
    log_error "未检测到当前系统安装了 Nginx。本脚本仅用于升级，请先确认环境。"
    exit 1
fi

CURRENT_VER=$(nginx -v 2>&1 | awk -F/ '{print $2}')
log_info "当前系统安装的 Nginx 版本为: ${BLUE}${CURRENT_VER}${NC}"

# --- 1. 前置配置语法检查 ---
log_info "正在检查现有 Nginx 配置文件的语法..."
if ! nginx -t -q; then
    log_error "当前 Nginx 配置存在语法错误，请修复后再运行升级脚本！"
    exit 1
fi
log_info "现有配置检查通过。"

# --- 2. 备份配置文件 ---
log_info "正在备份整个 /etc/nginx 目录至 ${BACKUP_DIR} ..."
if cp -r /etc/nginx "${BACKUP_DIR}"; then
    log_info "备份成功。"
else
    log_error "备份失败，脚本终止！"
    exit 1
fi

# --- 3. 配置 Nginx 官方 APT 源 ---
log_info "正在配置 Nginx 官方官方 APT 存储源 (${NGINX_BRANCH})..."

# 安装必要依赖
apt-get update -y -q > /dev/null
apt-get install -y -q curl gnupg2 ca-certificates lsb-release ubuntu-keyring > /dev/null

# 导入 Nginx 官方签名密钥
KEYRING="/usr/share/keyrings/nginx-archive-keyring.gpg"
if [ ! -f "$KEYRING" ]; then
    curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o "$KEYRING"
fi

# 写入 APT 列表源
SOURCE_FILE="/etc/apt/sources.list.d/nginx.list"
if [ "$NGINX_BRANCH" = "mainline" ]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING] https://nginx.org/packages/mainline/ubuntu/ ${CODENAME} nginx" > "$SOURCE_FILE"
else
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING] https://nginx.org/packages/ubuntu/ ${CODENAME} nginx" > "$SOURCE_FILE"
fi

# 设置 APT 优先级，确保优先使用官方源而非 Ubuntu 自带的旧源
cat <<EOF > /etc/apt/preferences.d/99nginx
Package: nginx
Pin: origin nginx.org
Pin-Priority: 900
EOF

# --- 4. 执行升级 ---
log_info "正在更新本地 APT 缓存并升级 Nginx..."
apt-get update -y -q

# 使用 Dpkg::Options 强制保留用户原有的配置文件，避免覆盖安装
APT_LISTCHANGES_FRONTEND=none apt-get install -y \
    -o Dpkg::Options::="--force-confold" \
    -o Dpkg::Options::="--force-confdef" \
    nginx

# --- 5. 热升级（无缝切换二进制文件） ---
if systemctl is-active --quiet nginx; then
    log_info "检测到 Nginx 正在运行，启动热升级以确保零断开时间..."
    
    OLD_PID=$(cat /run/nginx.pid 2>/dev/null)
    
    if [ -n "$OLD_PID" ]; then
        # 发送 USR2 信号：让 Nginx 启动一组新的 Master/Worker 进程，使用新的二进制文件
        kill -USR2 "$OLD_PID"
        sleep 2
        
        # 发送 WINCH 信号：通知旧的 Master 进程优雅地关闭它的旧 Worker 进程
        kill -WINCH "$OLD_PID"
        sleep 2
        
        log_info "热升级信号发送完毕，新旧进程已交接。"
    fi
else
    log_warn "Nginx 当前未处于运行状态，直接启动新版服务..."
    systemctl start nginx
fi

# --- 6. 升级后验证 ---
NEW_VER=$(nginx -v 2>&1 | awk -F/ '{print $2}')
log_info "升级后的 Nginx 版本为: ${BLUE}${NEW_VER}${NC}"

log_info "正在测试新版本下的配置兼容性..."
if nginx -t -q; then
    log_info "${GREEN}✔ Nginx 成功升级且配置完美兼容！${NC}"
    
    # 彻底结束旧的 Master 进程（若存在热升级）
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill -QUIT "$OLD_PID"
    fi
else
    log_error "❌ 新版本 Nginx 无法解析当前配置文件！"
    log_warn "触发自动回滚机制..."
    
    # 回滚配置
    rm -rf /etc/nginx
    cp -r "${BACKUP_DIR}" /etc/nginx
    
    log_warn "请手动运行 'apt-get install nginx=<旧版本号>' 或从备份中恢复。"
    exit 1
fi