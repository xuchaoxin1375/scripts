#!/usr/bin/env bash
# =============================================================================
# Description : 从 GitHub 下载最新预编译包安装 fastfetch (支持多用户/镜像源)
# Version     : 3.0
# =============================================================================

set -euo pipefail

# ========================= 常量 =========================
FASTFETCH_REPO="fastfetch-cli/fastfetch"
TEMP_DIR="$(mktemp -d)"

# 全局状态变量 (在流程中赋值)
INSTALL_DIR=""
MIRROR_PREFIX=""

# ========================= 颜色 =========================
if [[ -t 1 ]]; then
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[1;33m'
    C_BLUE='\033[0;34m'
    C_NC='\033[0m'
else
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_BLUE=''
    C_NC=''
fi

# ========================= 日志 =========================
log_info() { echo -e "${C_BLUE}[INFO]${C_NC} $*"; }
log_success() { echo -e "${C_GREEN}[OK]${C_NC} $*"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_NC} $*" >&2; }
log_error() { echo -e "${C_RED}[ERROR]${C_NC} $*" >&2; }

# ========================= 基础工具 =========================
has_command() { command -v "$1" > /dev/null 2>&1; }

cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

# ========================= 参数解析 =========================
parse_args() {
    MIRROR_MODE="auto"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mirror)
                [[ $# -lt 2 ]] && {
                    log_error "--mirror 需要一个参数"
                    exit 1
                }
                MIRROR_MODE="$2"
                shift 2
                ;;
            -h | --help)
                cat << EOF
用法: $0 [选项]
选项:
  --mirror <MODE>   指定下载源, MODE 可选:
      auto          自动探测最佳源 (默认)
      direct        直连 GitHub
      ghproxy       使用 https://gh-proxy.com/ 镜像
      ghfast        使用 https://ghfast.top/ 镜像
      <URL>         自定义镜像前缀 (需含协议, 例如 https://gh-proxy.com/)
  -h, --help        显示此帮助

示例:

# 默认: 自动探测最佳源 (直连失败自动切镜像)
$0

# 强制走 gh-proxy 镜像
$0 --mirror ghproxy

# 直连 GitHub
$0 --mirror direct

# 使用自定义镜像前缀
$0 --mirror https://ghfast.top/

EOF
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done
}

# ========================= 镜像源选择 =========================
select_mirror() {
    local api_url="https://api.github.com/repos/${FASTFETCH_REPO}/releases/latest"

    case "$MIRROR_MODE" in
        direct)
            MIRROR_PREFIX=""
            log_info "下载源: 直连 GitHub"
            ;;
        ghproxy)
            MIRROR_PREFIX="https://gh-proxy.com/"
            log_info "下载源: gh-proxy.com 镜像"
            ;;
        ghfast)
            MIRROR_PREFIX="https://ghfast.top/"
            log_info "下载源: ghfast.top 镜像"
            ;;
        auto)
            log_info "自动探测可用下载源 (依次测试连通性)..."
            # 候选源: 直连在前, 失败再走镜像
            local candidates=("" "https://gh-proxy.com/" "https://ghfast.top/" "https://mirror.ghproxy.com/")
            for prefix in "${candidates[@]}"; do
                local test_url="${prefix}${api_url}"
                if curl -fsSL --connect-timeout 5 --max-time 12 -o /dev/null "$test_url" 2> /dev/null; then
                    MIRROR_PREFIX="$prefix"
                    if [[ -z "$prefix" ]]; then
                        log_success "直连 GitHub 可用"
                    else
                        log_success "使用镜像源: ${prefix}"
                    fi
                    return
                fi
                if [[ -z "$prefix" ]]; then
                    log_warn "直连 GitHub 不可达, 尝试镜像..."
                else
                    log_warn "镜像 ${prefix} 不可达, 尝试下一个..."
                fi
            done
            log_error "所有源均不可用, 请检查网络或使用 --mirror <URL> 指定镜像"
            exit 1
            ;;
        *)
            # 自定义镜像前缀
            MIRROR_PREFIX="$MIRROR_MODE"
            [[ "$MIRROR_PREFIX" != */ ]] && MIRROR_PREFIX="${MIRROR_PREFIX}/"
            log_info "下载源: 自定义镜像 ${MIRROR_PREFIX}"
            ;;
    esac
}

# ========================= 依赖检查 =========================
ensure_dependencies() {
    local missing=()
    has_command curl || missing+=("curl")
    has_command tar || missing+=("tar")
    [[ ${#missing[@]} -eq 0 ]] && return

    log_warn "缺少依赖: ${missing[*]}, 尝试自动安装..."
    if has_command apt-get; then
        sudo apt-get update -y && sudo apt-get install -y "${missing[@]}"
    elif has_command dnf; then
        sudo dnf install -y "${missing[@]}"
    elif has_command pacman; then
        sudo pacman -Sy --noconfirm "${missing[@]}"
    elif has_command zypper; then
        sudo zypper install -y "${missing[@]}"
    elif has_command apk; then
        sudo apk add --no-cache "${missing[@]}"
    else
        log_error "无法自动安装依赖, 请手动安装: ${missing[*]}"
        exit 1
    fi
    log_success "依赖安装完成"
}

# ========================= 安装目录判定 =========================
determine_install_dir() {
    if [[ $EUID -eq 0 ]]; then
        INSTALL_DIR="/usr/local/bin"
        log_info "安装目录 (系统级): ${INSTALL_DIR}"
    else
        INSTALL_DIR="${HOME}/.local/bin"
        if [[ ! -d "$INSTALL_DIR" ]]; then
            mkdir -p "$INSTALL_DIR"
            log_info "已创建安装目录: ${INSTALL_DIR}"
        fi
        log_info "安装目录 (用户级): ${INSTALL_DIR}"
    fi
}

# ========================= 架构映射 =========================
get_architecture() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "aarch64" ;;
        *)
            log_error "不支持的架构: $(uname -m)"
            exit 1
            ;;
    esac
}

# ========================= 核心安装 =========================
install_from_github() {
    local target_arch
    target_arch=$(get_architecture)

    local api_url="${MIRROR_PREFIX}https://api.github.com/repos/${FASTFETCH_REPO}/releases/latest"
    log_info "获取最新版本信息..."
    local api_response latest_version
    if ! api_response=$(curl -fsSL --connect-timeout 10 --max-time 30 "$api_url"); then
        log_error "无法访问 GitHub API (源: ${MIRROR_PREFIX:-直连})"
        exit 1
    fi

    # 优先 jq, 回退正则
    if has_command jq; then
        latest_version=$(echo "$api_response" | jq -r '.tag_name')
    else
        latest_version=$(echo "$api_response" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')
    fi

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        log_error "无法解析版本号 (可能触发 API 限流)"
        exit 1
    fi
    log_info "最新版本: ${latest_version}"

    local download_url="${MIRROR_PREFIX}https://github.com/${FASTFETCH_REPO}/releases/download/${latest_version}/fastfetch-linux-${target_arch}.tar.gz"
    local tar_file="${TEMP_DIR}/fastfetch.tar.gz"

    log_info "开始下载: ${download_url}"
    # 显示下载进度条: 不使用 -s, 保留 -f -L
    if ! curl -fL --connect-timeout 15 --retry 2 -o "$tar_file" "$download_url"; then
        log_error "下载失败! 请检查网络或尝试 --mirror ghproxy"
        exit 1
    fi
    log_success "下载完成"

    log_info "解压中..."
    tar -xzf "$tar_file" -C "$TEMP_DIR"

    local extracted_dir="${TEMP_DIR}/fastfetch-linux-${target_arch}"
    if [[ ! -d "$extracted_dir" ]]; then
        log_error "解压目录异常: ${extracted_dir}"
        exit 1
    fi

    log_info "安装文件到 ${INSTALL_DIR} ..."
    install -m 755 "${extracted_dir}/usr/bin/fastfetch" "${INSTALL_DIR}/fastfetch"
    if [[ -f "${extracted_dir}/usr/bin/flashfetch" ]]; then
        install -m 755 "${extracted_dir}/usr/bin/flashfetch" "${INSTALL_DIR}/flashfetch"
    fi
    log_success "文件复制完成"
}

# ========================= 验证与提示 =========================
verify_and_advise() {
    local target_bin="${INSTALL_DIR}/fastfetch"
    if [[ ! -x "$target_bin" ]]; then
        log_error "fastfetch 安装失败或无执行权限"
        exit 1
    fi

    local version
    version=$("$target_bin" --version 2>&1 | head -n1)
    log_success "fastfetch 安装成功!"
    log_info "版本: ${version}"

    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*) ;;
        *)
            log_warn "安装目录 ${INSTALL_DIR} 不在 PATH 中"
            echo -e "${C_YELLOW}请将以下内容添加到 ~/.bashrc 或 ~/.zshrc:${C_NC}"
            echo -e "  export PATH=\"\$PATH:${INSTALL_DIR}\""
            echo -e "${C_YELLOW}然后执行 source ~/.bashrc (或重开终端) 后即可使用 fastfetch${C_NC}"
            ;;
    esac
}

# ========================= 主流程 =========================
main() {
    parse_args "$@"
    log_info "开始安装 fastfetch..."
    select_mirror
    ensure_dependencies
    determine_install_dir
    install_from_github
    verify_and_advise
}

main "$@"
log_info "尝试运行 'fastfetch' ..."
command -v fastfetch > /dev/null 2>&1 && fastfetch
