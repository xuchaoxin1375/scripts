#!/usr/bin/env bash
VERSION="20260605"
SCRIPT_NAME="$(basename "$0")"
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
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

# --- 配置参数 ---
NGINX_BRANCH="${NGINX_BRANCH:-mainline}" # 可选: "stable" 或 "mainline" (推荐 mainline 获取最新版)
BACKUP_DIR="/etc/nginx_backup_$(date +%Y%m%d_%H%M%S)"
ACTION="install"            # install | uninstall
UNINSTALL_MODE="remove"     # remove (保留配置) | purge (彻底清除配置)
KEEP_SOURCE=false           # 卸载时是否保留 nginx.org APT 源/密钥
ASSUME_YES=false            # 卸载时是否跳过二次确认

# --- 日志函数 ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 卸载函数 ---
do_uninstall() {
    local mode="$1" # remove | purge
    local cur_ver="未知"
    if command -v nginx &> /dev/null; then
        cur_ver=$(nginx -v 2>&1 | awk -F/ '{print $2}')
    fi
    if ! command -v nginx &> /dev/null && ! dpkg -l 2>/dev/null | grep -qE '^ii\s+nginx'; then
        log_warn "未检测到 Nginx (命令与 dpkg 包均不存在),无需卸载。"
        return 0
    fi

    log_info "当前 Nginx 版本为: ${BLUE}${cur_ver}${NC},卸载模式: ${BLUE}${mode}${NC}"
    if [ -d /etc/nginx ]; then
        log_info "正在备份 /etc/nginx 至 ${BACKUP_DIR} ..."
        if ! cp -r /etc/nginx "${BACKUP_DIR}"; then
            log_error "备份失败,终止卸载以保护现有配置!"
            return 1
        fi
        log_info "备份完成: ${BACKUP_DIR}"
    else
        log_warn "未发现 /etc/nginx 目录,跳过备份。"
    fi

    if [[ "$ASSUME_YES" != true ]]; then
        local tip="卸载 Nginx 软件包(保留 /etc/nginx 配置)"
        [[ "$mode" == "purge" ]] && tip="彻底清除 Nginx(含 /etc/nginx、日志/缓存,已备份到 ${BACKUP_DIR})"
        echo -e "${YELLOW}[WARN]${NC} 即将${tip},继续吗? [y/N] " >&2
        read -r reply < /dev/tty || reply="n"
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            log_info "已取消卸载。"
            return 0
        fi
    fi

    export DEBIAN_FRONTEND=noninteractive
    log_info "正在停止并禁用 nginx 服务..."
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    if [ -f /run/nginx.pid ]; then
        local pid
        pid=$(cat /run/nginx.pid 2>/dev/null || true)
        if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
            log_warn "仍有残留 master 进程 ${pid},发送 QUIT..."
            kill -QUIT "$pid" 2>/dev/null || true
            sleep 2
        fi
    fi

    log_info "正在执行 apt-get ${mode} (wait a moment)..."
    if [[ "$mode" == "purge" ]]; then
        apt-get purge -y -q nginx nginx-common nginx-core nginx-full nginx-light nginx-extras nginx-doc 2>&1 | tail -n 5 || true
    else
        apt-get remove -y -q nginx nginx-common nginx-core nginx-full nginx-light nginx-extras 2>&1 | tail -n 5 || true
    fi
    apt-get autoremove -y -q 2>&1 | tail -n 3 || true

    if [[ "$mode" == "purge" ]]; then
        log_warn "正在删除残留配置与缓存..."
        rm -rf /etc/nginx /var/log/nginx /var/cache/nginx
        # 注意:不删除 /var/www 与备份目录,避免误删站点数据
    fi

    if [[ "$KEEP_SOURCE" == true ]]; then
        log_info "按 --keep-source 保留 nginx.org APT 源/密钥。"
    else
        log_info "正在清理 nginx.org APT 源/优先级/密钥..."
        rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx /usr/share/keyrings/nginx-archive-keyring.gpg
        apt-get update -y -q || true
    fi

    if command -v nginx &> /dev/null; then
        log_error "卸载后仍检测到 nginx 命令,请手动检查: dpkg -l | grep nginx"
        return 1
    fi
    log_info "${GREEN}✔ Nginx ${mode} 完成!${NC} 配置备份位于: ${BLUE}${BACKUP_DIR}${NC} (如存在)"
    return 0
}

# --- 帮助与版本函数 ---
show_version() {
    echo "Nginx 安装/升级/卸载脚本 v${VERSION}"
}

show_help() {
    cat << EOF
${BLUE}Nginx 安装/升级/卸载脚本 v${VERSION}${NC}
自动识别 Ubuntu 版本,全新直装或安全升级至 nginx.org 官方最新版本,亦可安全卸载。

${GREEN}用法:${NC}
  sudo bash ${SCRIPT_NAME} [选项]
  sudo ./${SCRIPT_NAME} [选项]
  bash ${SCRIPT_NAME} -h | --help

${GREEN}选项:${NC}
  -h, --help              显示此完整帮助并退出(无需 root 权限)
  -V, --version           显示脚本版本号并退出(无需 root 权限)
  -b, --branch <分支>     指定 Nginx 分支: stable | mainline
                          (默认: mainline; 也可用环境变量 NGINX_BRANCH 覆盖,仅安装/升级有效)
      --branch=<分支>     同上,等号写法
      --stable            快捷写法,等价于 --branch stable
      --mainline          快捷写法,等价于 --branch mainline
      --uninstall         卸载 Nginx 软件包,保留 /etc/nginx 配置(需 root)
                          默认同时移除 nginx.org APT 源/优先级/密钥,先备份配置到
                          /etc/nginx_backup_YYYYMMDD_HHMMSS
      --purge             彻底清除:卸载软件包 + 删除 /etc/nginx、日志/缓存(需 root)
                          操作前同样先备份到 /etc/nginx_backup_YYYYMMDD_HHMMSS
      --keep-source       卸载/清除时保留 nginx.org APT 源
                          (/etc/apt/sources.list.d/nginx.list,
                           /etc/apt/preferences.d/99nginx, keyring)
  -y, --yes               卸载/清除时跳过二次确认,直接执行(适合自动化)

${GREEN}运行模式:${NC}
  1. 【全新直装】未检测到 nginx 命令且无卸载选项时触发:
     安装官方源最新 Nginx,执行 systemctl enable + start。
  2. 【安全升级】已检测到 nginx 命令且无卸载选项时触发:
     先 nginx -t 检查语法 -> 备份 /etc/nginx -> 换官方源
     -> 非交互升级 -> 热升级/重启 -> nginx -t 验证,失败自动回滚。
  3. 【卸载 remove】传入 --uninstall 时触发:
     备份 /etc/nginx -> systemctl stop/disable -> apt-get remove
     -> autoremove -> 默认删除官方源并 apt-get update,保留 /etc/nginx。
  4. 【彻底清除 purge】传入 --purge 时触发:
     同卸载,但额外 apt-get purge + 删除 /etc/nginx、/var/log/nginx、
     /var/cache/nginx。备份仍保留,可手动恢复。

${GREEN}执行流程(安装/升级):${NC}
  1. root 权限检查 (EUID 必为 0,帮助/版本选项除外)
  2. 识别 /etc/os-release 中的 ID=ubuntu 与 VERSION_CODENAME
     (如 focal/jammy/noble),非 Ubuntu 直接退出
  3. 升级模式下先 nginx -t -q,语法错误则终止,避免带病升级
  4. 升级模式下 cp -r /etc/nginx 至 ${BLUE}/etc/nginx_backup_YYYYMMDD_HHMMSS${NC}
  5. 配置官方 APT 源:
       mainline: https://nginx.org/packages/mainline/ubuntu/
       stable  : https://nginx.org/packages/ubuntu/
     密钥: https://nginx.org/keys/nginx_signing.key
           -> /usr/share/keyrings/nginx-archive-keyring.gpg
     源文件: /etc/apt/sources.list.d/nginx.list (按 \$(dpkg --print-architecture) 与代号动态写入)
     优先级: /etc/apt/preferences.d/99nginx (Pin origin nginx.org, Pin-Priority 900)
  6. DEBIAN_FRONTEND=noninteractive + --force-confold/--force-confdef 非交互安装
  7. 升级模式且服务运行中: kill -USR2 -> -WINCH 热升级(零断开);
     未运行则 systemctl start; 全新安装则 enable + start
  8. nginx -v 确认新版本 + nginx -t 验证,升级失败则 rm -rf /etc/nginx
     并从备份恢复 + systemctl restart (全新安装失败则直接退出 1)

${GREEN}示例:${NC}
  sudo bash ${SCRIPT_NAME}                    # 默认 mainline 分支,一键安装/升级
  sudo bash ${SCRIPT_NAME} --branch stable    # 跟踪 stable 分支
  sudo bash ${SCRIPT_NAME} -b mainline        # 显式跟踪 mainline 分支
  sudo NGINX_BRANCH=stable bash ${SCRIPT_NAME} # 用环境变量指定分支
  bash ${SCRIPT_NAME} -h                      # 查看帮助(无需 sudo)
  bash ${SCRIPT_NAME} --help                  # 同上
  bash ${SCRIPT_NAME} -V                      # 查看版本号
  sudo bash ${SCRIPT_NAME} --uninstall        # 卸载软件包,保留 /etc/nginx 配置(会二次确认)
  sudo bash ${SCRIPT_NAME} --uninstall -y     # 卸载,不确认(自动化)
  sudo bash ${SCRIPT_NAME} --purge            # 彻底清除(含配置/日志/缓存,先备份)
  sudo bash ${SCRIPT_NAME} --purge --keep-source # 彻底清除但保留 nginx.org 源

  # 一键远程安装:
  curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/tool_installer/install_nginx_ubt.sh -o ~/inu.sh && sudo bash ~/inu.sh
  curl -SfL <url> -o ~/inu.sh && sudo bash ~/inu.sh --branch stable

${GREEN}注意事项:${NC}
  * 必须以 root 运行实际安装/升级/卸载 (sudo \$0);仅 -h/--help/-V/--version 可普通用户运行。
  * 仅支持 Ubuntu (依赖 /etc/os-release, VERSION_CODENAME, dpkg 架构检测)。
  * 脚本使用 apt-get 而非 apt,适合自动化运维;全程 -q,关键步骤有 INFO/WARN/ERROR 日志。
  * 升级前请自行确保 nginx -t 通过,脚本也会前置检查;备份目录形如 /etc/nginx_backup_* ,失败自动回滚。
  * 热升级依赖 /run/nginx.pid;若无 pid 文件则跳过信号发送;最后用 kill -QUIT 回收旧 master。
  * 安装依赖: curl gnupg2 ca-certificates lsb-release (及 ubuntu-keyring,如 apt-cache 可见)。
  * 卸载/清除前会自动备份 /etc/nginx 到 /etc/nginx_backup_* ;--purge 会删除
    /etc/nginx、/var/log/nginx、/var/cache/nginx,但备份保留可手动恢复。
  * 卸载默认删除 nginx.org 源(/etc/apt/sources.list.d/nginx.list、
    /etc/apt/preferences.d/99nginx、keyring);如需保留请加 --keep-source。

${GREEN}退出码:${NC}
  0  成功,或正常显示帮助/版本后退出
  1  权限不足/非 Ubuntu/备份失败/配置语法错误/升级后验证失败等
  2  命令行用法错误 (未知选项、缺参数、分支名非法)

项目: wp/woocommerce/woo_df/sh/tool_installer/install_nginx_ubt.sh
版本: ${VERSION}
EOF
}

# --- 参数解析 (必须位于 root 检查之前,使 -h/--help 免 root 可用) ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -V|--version)
            show_version
            exit 0
            ;;
        -b|--branch)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                log_error "选项 $1 缺少参数,需要: stable 或 mainline"
                echo "用法: sudo bash ${SCRIPT_NAME} [-b stable|mainline] [-h] [-V]" >&2
                exit 2
            fi
            NGINX_BRANCH="$2"
            shift 2
            ;;
        --branch=*)
            NGINX_BRANCH="${1#*=}"
            if [[ -z "$NGINX_BRANCH" ]]; then
                log_error "选项 --branch 缺少参数,需要: stable 或 mainline"
                exit 2
            fi
            shift
            ;;
        --stable)
            NGINX_BRANCH="stable"
            shift
            ;;
        --mainline)
            NGINX_BRANCH="mainline"
            shift
            ;;
        --uninstall|--remove)
            ACTION="uninstall"
            UNINSTALL_MODE="remove"
            shift
            ;;
        --purge)
            ACTION="uninstall"
            UNINSTALL_MODE="purge"
            shift
            ;;
        --keep-source)
            KEEP_SOURCE=true
            shift
            ;;
        -y|--yes|--assume-yes)
            ASSUME_YES=true
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            log_error "未知选项: $1"
            echo "请使用 -h/--help 查看用法。" >&2
            exit 2
            ;;
        *)
            log_error "未知参数: $1"
            echo "请使用 -h/--help 查看用法。" >&2
            exit 2
            ;;
    esac
done

# 校验分支取值
if [[ "$NGINX_BRANCH" != "stable" && "$NGINX_BRANCH" != "mainline" ]]; then
    log_error "非法分支: ${NGINX_BRANCH},仅支持: stable | mainline"
    echo "请使用 -h/--help 查看用法。" >&2
    exit 2
fi

echo "Nginx 安装/升级/卸载脚本 v$VERSION"

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

# --- 卸载模式:提前分流,直接退出,不走安装流程 ---
if [[ "$ACTION" == "uninstall" ]]; then
    log_info "脚本将进入【安全卸载 ${UNINSTALL_MODE}】模式。"
    do_uninstall "$UNINSTALL_MODE"
    exit $?
fi

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
