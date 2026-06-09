#!/usr/bin/env bash
VERSION="20260605"
echo "Nginx 安装/升级脚本 v$VERSION"
# ==============================================================================
# 脚本名称: install_nginx_ubt.sh
# 适用系统: Ubuntu 20.04 (Focal) / 22.04 (Jammy) / 24.04 (Noble) 及更高版本
# 功能描述: 自动识别 Ubuntu 版本，支持全新直装或安全升级至官方最新 Stable / Mainline 版本
# 在编写自动化运维脚本时，apt-get 比 apt 更合适，也更安全。
# 一键安装:(非root 用户请考虑切换到root 用户,或者sudo bash 后再执行,或者分步执行)

# curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/tool_installer/install_nginx_ubt.sh -o ~/inu.sh && sudo bash ~/inu.sh
# ==============================================================================

set -o pipefail

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 配置参数 ---
NGINX_BRANCH="mainline" # 可选: "stable" 或 "mainline" (推荐 mainline 获取最新版)
BACKUP_DIR="/etc/nginx_backup_$(date +%Y%m%d_%H%M%S)"

# --- 日志函数 ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 1. 权限与基本环境检查 ---
if [[ $EUID -ne 0 ]]; then
    log_error "该脚本必须以 root 权限运行，请使用: sudo $0"
    exit 1
fi

# 判断是全新安装还是升级
IS_UPDATE=true
if ! command -v nginx &> /dev/null; then
    IS_UPDATE=false
    log_info "未检测到系统安装 Nginx，脚本将进入【全新直装】模式。"
else
    log_info "检测到系统已安装 Nginx，脚本将进入【安全升级】模式。"
fi

# --- 2. 动态识别 Ubuntu 版本代号 ---
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    CODENAME=$VERSION_CODENAME
    DISTRO=$ID
else
    log_error "无法读取 /etc/os-release，不支持的系统架构。"
    exit 1
fi

# 确保是 Ubuntu 系统
if [ "$DISTRO" != "ubuntu" ] || [ -z "$CODENAME" ]; then
    log_error "本脚本仅支持 Ubuntu 系统。当前检测到系统为: ${DISTRO} (${CODENAME})"
    exit 1
fi

log_info "检测到当前系统为: ${BLUE}Ubuntu ${VERSION_ID} (${CODENAME})${NC}"

if [ "$IS_UPDATE" = true ]; then
    CURRENT_VER=$(nginx -v 2>&1 | awk -F/ '{print $2}')
    log_info "当前 Nginx 版本为: ${BLUE}${CURRENT_VER}${NC}"
fi

# --- 3. 前置配置语法检查（仅限升级模式） ---
if [ "$IS_UPDATE" = true ]; then
    log_info "正在检查现有 Nginx 配置文件的语法..."
    if ! nginx -t -q; then
        log_error "当前 Nginx 配置存在语法错误，请修复后再运行升级脚本！"
        exit 1
    fi

    # --- 4. 备份配置文件 ---
    log_info "正在备份整个 /etc/nginx 目录至 ${BACKUP_DIR} ..."
    if ! cp -r /etc/nginx "${BACKUP_DIR}"; then
        log_error "备份失败，脚本终止！"
        exit 1
    fi
fi

# --- 5. 配置 Nginx 官方 APT 源 ---
log_info "正在配置 Nginx 官方 APT 存储源 (${NGINX_BRANCH})(wait a moment)..."

# 安装基础依赖
apt-get update -y -q > /dev/null
apt-get install -y -q curl gnupg2 ca-certificates lsb-release > /dev/null
if apt-cache show ubuntu-keyring &> /dev/null; then
    apt-get install -y -q ubuntu-keyring > /dev/null
fi

# 创建专用的密钥目录
mkdir -p /usr/share/keyrings

KEYRING="/usr/share/keyrings/nginx-archive-keyring.gpg"
# 下载并导入官方签名密钥
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor --yes -o "$KEYRING"

# 动态写入包含正确系统代号和架构的 APT 源列表
SOURCE_FILE="/etc/apt/sources.list.d/nginx.list"
ARCH=$(dpkg --print-architecture)

if [ "$NGINX_BRANCH" = "mainline" ]; then
    echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://nginx.org/packages/mainline/ubuntu/ ${CODENAME} nginx" > "$SOURCE_FILE"
else
    echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://nginx.org/packages/ubuntu/ ${CODENAME} nginx" > "$SOURCE_FILE"
fi

# 设置 APT 优先级，确保使用 nginx.org 官方源
cat << EOF > /etc/apt/preferences.d/99nginx
Package: *
Pin: origin nginx.org
Pin-Priority: 900
EOF

# --- 6. 执行非交互式安装或升级 ---
log_info "正在更新本地 APT 缓存并安装/升级 Nginx..."
apt-get update -y -q

# 阻止 dpkg 弹窗提问，自动保持或使用标准配置
export DEBIAN_FRONTEND=noninteractive
apt-get install -y \
    -o Dpkg::Options::="--force-confold" \
    -o Dpkg::Options::="--force-confdef" \
    nginx

# --- 7. 服务控制与热升级 ---
if [ "$IS_UPDATE" = true ]; then
    if systemctl is-active --quiet nginx; then
        log_info "检测到 Nginx 正在运行，启动热升级以确保零断开时间..."
        OLD_PID=$(cat /run/nginx.pid 2> /dev/null)

        if [ -n "$OLD_PID" ]; then
            kill -USR2 "$OLD_PID"
            sleep 2
            kill -WINCH "$OLD_PID"
            sleep 2
            log_info "热升级信号发送完毕，新旧进程已交接。"
        fi
    else
        log_warn "Nginx 当前未处于运行状态，直接启动新版服务..."
        systemctl start nginx
    fi
else
    log_info "全新安装完成，正在启动并使能 Nginx 服务..."
    systemctl enable nginx
    systemctl start nginx
fi

# --- 8. 验证与异常处理 ---
NEW_VER=$(nginx -v 2>&1 | awk -F/ '{print $2}')
log_info "当前系统的 Nginx 版本为: ${BLUE}${NEW_VER}${NC}"

log_info "正在测试配置有效性..."
if nginx -t -q; then
    log_info "${GREEN}✔ Nginx 部署成功，配置完美兼容！${NC}"
    if [ "$IS_UPDATE" = true ] && [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2> /dev/null; then
        kill -QUIT "$OLD_PID"
    fi
else
    if [ "$IS_UPDATE" = true ]; then
        log_error "❌ 新版本 Nginx 无法解析升级前的配置文件！"
        log_warn "触发自动回滚机制..."
        rm -rf /etc/nginx
        cp -r "${BACKUP_DIR}" /etc/nginx
        systemctl restart nginx
    else
        log_error "❌ 全新安装的 Nginx 配置测试未通过，请检查环境！"
    fi
    exit 1
fi
