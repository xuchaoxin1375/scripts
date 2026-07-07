#!/usr/bin/env bash
# =============================================================================
# Script Name : install_fastfetch.sh
# Description : 从 GitHub 下载最新预编译包安装 fastfetch (支持多用户/系统级)
# Author      : AI Assistant
# Version     : 1.0
# =============================================================================

# 严格模式：遇到错误即退出，使用未定义变量即退出，管道命令中任何一个失败即报错
set -euo pipefail

# ========================= 常量与全局变量 =========================
FASTFETCH_REPO="fastfetch-cli/fastfetch"
TEMP_DIR="$(mktemp -d)"

# 动态决定安装目录 (在 main 函数中赋值)
INSTALL_DIR=""

# 颜色定义
if [[ -t 1 ]]; then
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_NC='\033[0m' # No Color
else
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_NC=''
fi

# ========================= 日志函数 =========================
log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $*"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_NC} $*"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_NC} $*" >&2
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $*" >&2
}

# ========================= 核心功能函数 =========================

# 检查命令是否存在
has_command() {
    command -v "$1" > /dev/null 2>&1
}

# 检查并安装必要的依赖 (curl, tar)
ensure_dependencies() {
    local missing_deps=()

    has_command curl || missing_deps+=("curl")
    has_command tar || missing_deps+=("tar")

    if [[ ${#missing_deps[@]} -ne 0 ]]; then
        log_warn "缺少必要依赖: ${missing_deps[*]}。尝试自动安装..."

        if has_command apt-get; then
            sudo apt-get update -y && sudo apt-get install -y "${missing_deps[@]}"
        elif has_command dnf; then
            sudo dnf install -y "${missing_deps[@]}"
        elif has_command pacman; then
            sudo pacman -Sy --noconfirm "${missing_deps[@]}"
        elif has_command zypper; then
            sudo zypper install -y "${missing_deps[@]}"
        elif has_command apk; then
            sudo apk add --no-cache "${missing_deps[@]}"
        else
            log_error "无法自动安装依赖，请手动安装: ${missing_deps[*]}"
            exit 1
        fi
        log_success "依赖安装完成。"
    fi
}

# 清理临时文件的钩子函数
cleanup() {
    log_info "清理临时文件..."
    rm -rf "$TEMP_DIR"
}
# 无论脚本正常结束、报错退出还是被 Ctrl+C 中断，都会执行 cleanup
trap cleanup EXIT

# 根据当前权限确定安装目录
determine_install_dir() {
    if [[ $EUID -eq 0 ]]; then
        INSTALL_DIR="/usr/local/bin"
        log_info "检测到 root 权限，将安装至系统目录: ${INSTALL_DIR}"
    else
        INSTALL_DIR="${HOME}/.local/bin"
        log_info "检测到普通用户权限，将安装至用户目录: ${INSTALL_DIR}"
        # 如果目录不存在则创建
        if [[ ! -d "$INSTALL_DIR" ]]; then
            mkdir -p "$INSTALL_DIR"
            log_info "已创建安装目录: ${INSTALL_DIR}"
        fi
    fi
}

# 获取系统架构并映射为 fastfetch 命名规范
get_architecture() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64) echo "aarch64" ;;
        *)
            log_error "不支持的系统架构: $arch"
            exit 1
            ;;
    esac
}

# 从 GitHub 下载并安装预编译二进制文件
install_from_github() {
    local target_arch
    target_arch=$(get_architecture)

    log_info "正在从 GitHub API 获取最新版本信息..."
    local api_url="https://api.github.com/repos/${FASTFETCH_REPO}/releases/latest"

    # 获取 API 响应
    local api_response latest_version
    if ! api_response=$(curl -fSL "$api_url"); then
        log_error "无法访问 GitHub API，请检查网络连接。"
        exit 1
    fi

    # 优先使用 jq 解析，不存在则回退到 grep+sed
    if has_command jq; then
        latest_version=$(echo "$api_response" | jq -r '.tag_name')
    else
        latest_version=$(echo "$api_response" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/')
    fi

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        log_error "无法获取 fastfetch 最新版本号。可能触发了 GitHub API 限流。"
        exit 1
    fi
    log_info "检测到最新版本: $latest_version"

    # 构建下载链接 (格式: fastfetch-linux-amd64.tar.gz)
    local download_url="https://github.com/${FASTFETCH_REPO}/releases/download/${latest_version}/fastfetch-linux-${target_arch}.tar.gz"

    local tar_file="${TEMP_DIR}/fastfetch.tar.gz"

    log_info "正在下载: $download_url"
    if ! curl -fsSL -o "$tar_file" "$download_url"; then
        log_error "下载失败！请检查网络连接。"
        exit 1
    fi

    log_info "正在解压文件..."
    tar -xzf "$tar_file" -C "$TEMP_DIR"

    # 解压后的目录名通常为 fastfetch-linux-${target_arch}
    local extracted_dir="${TEMP_DIR}/fastfetch-linux-${target_arch}"

    if [[ ! -d "$extracted_dir" ]]; then
        log_error "解压目录结构异常，未找到: $extracted_dir"
        exit 1
    fi

    log_info "正在安装文件到 ${INSTALL_DIR} ..."
    # 安装主程序
    install -m 755 "${extracted_dir}/usr/bin/fastfetch" "${INSTALL_DIR}/fastfetch"

    # 如果存在可选的同目录可执行文件 (如 flashfetch)，也一并安装
    if [[ -f "${extracted_dir}/usr/bin/flashfetch" ]]; then
        install -m 755 "${extracted_dir}/usr/bin/flashfetch" "${INSTALL_DIR}/flashfetch"
    fi

    log_success "文件复制完成。"
}

# 验证安装是否成功并给出后续提示
verify_and_advise() {
    log_info "正在验证安装..."
    local target_bin="${INSTALL_DIR}/fastfetch"

    if [[ -x "$target_bin" ]]; then
        local version
        version=$("$target_bin" --version 2>&1 | head -n 1)
        log_success "fastfetch 安装成功！"
        log_info "版本信息: $version"

        # 检查 PATH 环境变量是否包含安装目录
        case ":${PATH}:" in
            *":${INSTALL_DIR}:"*)
                # 在 PATH 中，无需特殊提示
                ;;
            *)
                # 不在 PATH 中，提醒用户
                log_warn "安装目录 ${INSTALL_DIR} 不在您的 PATH 环境变量中。"
                echo -e "${COLOR_YELLOW}请将以下行添加到您的 ~/.bashrc 或 ~/.zshrc 中：${COLOR_NC}"
                echo -e "  export PATH=\"\$PATH:${INSTALL_DIR}\""
                echo -e "${COLOR_YELLOW}然后执行 source ~/.bashrc (或重开终端) 后即可直接使用 fastfetch 命令。${COLOR_NC}"
                ;;
        esac
    else
        log_error "fastfetch 安装失败或文件无执行权限。"
        exit 1
    fi
}

# ========================= 主执行流程 =========================
main() {
    log_info "开始安装 fastfetch..."
    determine_install_dir
    ensure_dependencies
    install_from_github
    verify_and_advise
}

# 执行 main 函数
main "$@"

log_info "尝试运行 'fastfetch' ..."
command -v fastfetch > /dev/null 2>&1 && fastfetch
