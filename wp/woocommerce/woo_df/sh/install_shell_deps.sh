#!/usr/bin/env bash
# install_shell_deps.sh —— 为 zsh / Oh My Zsh 与 shell 脚本库准备系统依赖。
#
# 覆盖范围：Debian/Ubuntu、Fedora、RHEL/CentOS、Alpine、Arch、openSUSE、
# Void、Gentoo、Solus 等 Linux 发行版，以及 macOS（Homebrew）。
# Windows 的 git-bash / MSYS2 / Cygwin 没有可安装的 zsh，只做检查并给出 WSL 指引。
#
# 本脚本只补齐 deploy_omz.sh 与 shellrc_addition.sh 的运行前提（zsh、git、curl、
# tar，macOS 另需 gnu-sed），不安装 zsh 插件、不改默认 shell、不改 shell 配置文件。
#
# 用法：
#   bash install_shell_deps.sh            # 检查并安装缺失依赖
#   bash install_shell_deps.sh --check    # 只检查，不修改系统
#   bash install_shell_deps.sh -n         # 空跑，只打印将执行的命令
#   bash install_shell_deps.sh -y         # 非交互安装
#
# 远程执行：
#   bash <(curl -sSfL https://github.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/install_shell_deps.sh)
#
# 依赖就绪后执行 deploy_omz.sh 部署 zsh 插件；两个脚本的完整说明见
# Readme@deploy_omz.md。

set -Eeuo pipefail

version=20261102.0846

ASSUME_YES=false
DRY_RUN=false
CHECK_ONLY=false
VERBOSE=false

OS_KIND=""
OS_ID="unknown"
OS_NAME=""
OS_VERSION=""
PKG_MANAGER=""
SUDO=()
declare -a INSTALL_ARGS=()
declare -a MISSING_CMDS=()
declare -a MISSING_PKGS=()
declare -a REQUIRED_CMDS=(zsh git curl tar)

COLOR_RESET=""
COLOR_BLUE=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_RED=""

usage() {
    cat <<USAGE
install_shell_deps.sh —— 为 zsh / Oh My Zsh 与 shell 脚本库安装系统依赖。

version: $version
用法：
    install_shell_deps.sh [选项]

选项：
    -c, --check            只检查依赖，不修改系统；缺失依赖时返回非零状态
    -n, --dry-run          空跑，只打印将要执行的命令
    -y, --yes              非交互安装，跳过确认并把非交互参数传给包管理器
    -v, --verbose          输出平台、包管理器和安装命令等细节
    -h, --help             显示本帮助
        --script-version   显示脚本版本

检查项：
    Linux / macOS：zsh、git、curl、tar；macOS 另需 gnu-sed（提供 gsed 命令）。

支持的包管理器：
    apt-get、dnf、yum、apk、pacman、zypper、xbps-install、emerge、eopkg、brew。

示例：
    bash install_shell_deps.sh --check
    bash install_shell_deps.sh -n
    bash install_shell_deps.sh -y
    sudo bash install_shell_deps.sh          # 无 sudo 的环境

说明：
    普通用户执行时通过 sudo 安装；macOS 的 Homebrew 不允许 root，需用普通用户运行。
    Windows 模拟层（git-bash / MSYS2 / Cygwin）缺少 zsh 时只给出 WSL 指引，不尝试安装。
USAGE
}

init_colors() {
    if [[ -t 2 && ${TERM:-dumb} != "dumb" && -z ${NO_COLOR:-} ]]; then
        COLOR_RESET=$'\033[0m'
        COLOR_BLUE=$'\033[34m'
        COLOR_GREEN=$'\033[32m'
        COLOR_YELLOW=$'\033[33m'
        COLOR_RED=$'\033[31m'
    fi
}

log_info() { printf '%s[INFO]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*" >&2; }
log_success() { printf '%s[OK]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*" >&2; }
log_warn() { printf '%s[WARN]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2; }
log_verbose() { [[ $VERBOSE == false ]] || printf '%s[VERBOSE]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*" >&2; }
die() {
    log_error "$*"
    exit 1
}

parse_args() {
    while (($#)); do
        case "$1" in
        -c | --check)
            CHECK_ONLY=true
            shift
            ;;
        -n | --dry-run)
            DRY_RUN=true
            shift
            ;;
        -y | --yes)
            ASSUME_YES=true
            shift
            ;;
        -v | --verbose)
            VERBOSE=true
            shift
            ;;
        --script-version)
            printf '%s\n' "$version"
            exit 0
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            (($# == 0)) || die "不支持位置参数：$*"
            ;;
        *) die "未知参数：$1（使用 --help 查看帮助）。" ;;
        esac
    done
    if [[ $CHECK_ONLY == true && $DRY_RUN == true ]]; then
        log_verbose "--check 与 --dry-run 同时使用，按只检查处理。"
    fi
}

command_present() {
    command -v "$1" >/dev/null 2>&1
}

detect_platform() {
    local kernel
    kernel=$(uname -s 2>/dev/null || true)
    case "$kernel" in
    Darwin) OS_KIND=macos ;;
    Linux) OS_KIND=linux ;;
    MINGW* | MSYS* | CYGWIN*) OS_KIND=windows ;;
    *) die "不支持的系统：${kernel:-未知}。" ;;
    esac

    if [[ $OS_KIND == linux ]]; then
        # os-release 中也有 NAME、VERSION 等通用变量，必须局部化。
        local ID="" NAME="" PRETTY_NAME="" VERSION_ID=""
        if [[ -r /etc/os-release ]]; then
            # shellcheck disable=SC1091
            . /etc/os-release
        fi
        OS_ID=${ID:-unknown}
        OS_NAME=${PRETTY_NAME:-${NAME:-$OS_ID}}
        OS_VERSION=${VERSION_ID:-}
        if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
            log_verbose "检测到 WSL 环境。"
        fi
    elif [[ $OS_KIND == macos ]]; then
        OS_ID=macos
        OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null || true)"
        OS_VERSION=$(sw_vers -productVersion 2>/dev/null || true)
    else
        OS_ID=windows
        OS_NAME=${OSTYPE:-windows}
    fi

    log_info "系统：${OS_NAME:-$OS_ID}；架构：$(uname -m)"
    log_verbose "平台识别：kind=$OS_KIND id=$OS_ID version=${OS_VERSION:-unknown} ostype=${OSTYPE:-unknown}"
}

detect_package_manager() {
    if [[ $OS_KIND == macos ]]; then
        command_present brew || return 1
        PKG_MANAGER=brew
        return 0
    fi
    local candidate
    for candidate in apt-get dnf yum apk pacman zypper xbps-install emerge eopkg; do
        if command_present "$candidate"; then
            PKG_MANAGER=$candidate
            return 0
        fi
    done
    return 1
}

package_for() {
    local cmd=$1
    if [[ $PKG_MANAGER == emerge ]]; then
        case "$cmd" in
        zsh) printf 'app-shells/zsh\n' ;;
        git) printf 'dev-vcs/git\n' ;;
        curl) printf 'net-misc/curl\n' ;;
        tar) printf 'app-arch/tar\n' ;;
        gsed) printf 'sys-apps/sed\n' ;;
        *) return 1 ;;
        esac
        return 0
    fi
    case "$cmd" in
    gsed) printf 'gnu-sed\n' ;;
    zsh | git | curl | tar) printf '%s\n' "$cmd" ;;
    *) return 1 ;;
    esac
}

required_commands() {
    REQUIRED_CMDS=(zsh git curl tar)
    if [[ $OS_KIND == macos ]]; then
        REQUIRED_CMDS+=(gsed)
    fi
}

collect_missing() {
    local cmd pkg
    MISSING_CMDS=()
    MISSING_PKGS=()
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if command_present "$cmd"; then
            continue
        fi
        if ! pkg=$(package_for "$cmd"); then
            log_warn "无法确定 $cmd 对应的软件包名称，请手动安装。"
            continue
        fi
        MISSING_CMDS+=("$cmd")
        MISSING_PKGS+=("$pkg")
    done
}

print_report() {
    local cmd version_text
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command_present "$cmd"; then
            log_error "缺失：$cmd"
            continue
        fi
        case "$cmd" in
        zsh) version_text=$(zsh --version 2>/dev/null | awk 'NR==1') ;;
        git) version_text=$(git --version 2>/dev/null | awk 'NR==1') ;;
        curl) version_text=$(curl --version 2>/dev/null | awk 'NR==1{print $1, $2}') ;;
        tar) version_text=$(tar --version 2>/dev/null | awk 'NR==1') ;;
        gsed) version_text=$(gsed --version 2>/dev/null | awk 'NR==1') ;;
        *) version_text="" ;;
        esac
        log_success "已安装：$cmd${version_text:+（$version_text）}"
    done
}

build_install_command() {
    INSTALL_ARGS=()
    case "$PKG_MANAGER" in
    apt-get) INSTALL_ARGS=(apt-get install) ;;
    dnf | yum) INSTALL_ARGS=("$PKG_MANAGER" install) ;;
    apk) INSTALL_ARGS=(apk add --no-cache) ;;
    pacman) INSTALL_ARGS=(pacman -S --needed) ;;
    zypper) INSTALL_ARGS=(zypper install) ;;
    xbps-install) INSTALL_ARGS=(xbps-install -S) ;;
    eopkg) INSTALL_ARGS=(eopkg install) ;;
    emerge) INSTALL_ARGS=(emerge) ;;
    brew) INSTALL_ARGS=(brew install) ;;
    *) die "未配置包管理器：$PKG_MANAGER" ;;
    esac
    if [[ $ASSUME_YES == true ]]; then
        case "$PKG_MANAGER" in
        apt-get | dnf | yum | zypper | xbps-install | eopkg) INSTALL_ARGS+=(-y) ;;
        pacman) INSTALL_ARGS+=(--noconfirm) ;;
        emerge) INSTALL_ARGS+=(--ask=n) ;;
        apk | brew) ;;
        esac
    fi
    log_verbose "安装命令模板：${INSTALL_ARGS[*]}"
}

setup_privilege() {
    SUDO=()
    if [[ $PKG_MANAGER == brew ]]; then
        if ((EUID == 0)); then
            die "Homebrew 不允许以 root 运行；请用普通用户执行本脚本。"
        fi
        return 0
    fi
    ((EUID == 0)) && return 0
    command_present sudo || die "安装依赖需要 root 权限，但未找到 sudo；请用 root 执行本脚本。"
    SUDO=(sudo)
}

quote_command() {
    printf '  '
    printf '%q ' "$@"
    printf '\n'
}

run() {
    if [[ $DRY_RUN == true ]]; then
        quote_command "$@"
    else
        "$@"
    fi
}

run_privileged() {
    run "${SUDO[@]}" "$@"
}

confirm_install() {
    local answer
    if [[ $ASSUME_YES == true ]]; then
        return 0
    fi
    if [[ $DRY_RUN == true ]]; then
        log_info "dry-run：正式执行时会请求确认。"
        return 0
    fi
    [[ -t 0 ]] || die "非交互环境请确认后添加 --yes。"
    printf '将安装：%s。继续？[y/N] ' "${MISSING_PKGS[*]}" >&2
    IFS= read -r answer || answer=""
    case "$answer" in
    y | Y | yes | YES | Yes) ;;
    *)
        log_warn "已取消安装，未修改系统。"
        exit 0
        ;;
    esac
}

install_missing() {
    local -a cmd=("${INSTALL_ARGS[@]}" "${MISSING_PKGS[@]}")
    local -a full=("${SUDO[@]}" "${cmd[@]}")
    if [[ $PKG_MANAGER == apt-get ]]; then
        log_info "刷新软件包索引：apt-get update"
        run_privileged apt-get update
    fi
    log_info "安装：${MISSING_PKGS[*]}"
    log_verbose "执行：${full[*]}"
    run_privileged "${cmd[@]}"
}

verify_after_install() {
    local cmd failed=false
    for cmd in "${MISSING_CMDS[@]}"; do
        if command_present "$cmd"; then
            log_success "安装成功：$cmd"
        else
            log_error "安装后仍找不到命令：$cmd"
            failed=true
        fi
    done
    [[ $failed == false ]]
}

handle_windows() {
    local cmd missing=()
    for cmd in zsh git curl; do
        command_present "$cmd" || missing+=("$cmd")
    done
    if ((${#missing[@]} == 0)); then
        log_success "zsh 依赖已齐备。"
        return 0
    fi
    log_error "Windows 模拟层（git-bash / MSYS2 / Cygwin）缺少：${missing[*]}"
    cat >&2 <<'EOF'

Windows 上没有可直接安装的 zsh 发行包，建议改用 WSL：

    wsl --install -d Ubuntu

进入 WSL 后执行本脚本，再执行 deploy_omz.sh：

    bash <(curl -sSfL https://github.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/install_shell_deps.sh)
    bash <(curl -sSfL https://github.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/deploy_omz.sh) -s github

若只需 bash 环境，可继续使用 git-bash，并运行 shellrc_addition.sh。
EOF
    return 2
}

main() {
    init_colors
    parse_args "$@"
    detect_platform

    if [[ $OS_KIND == windows ]]; then
        handle_windows || exit $?
        exit 0
    fi

    required_commands

    if ! detect_package_manager; then
        if [[ $OS_KIND == macos ]]; then
            die "未找到 Homebrew。请先按 https://brew.sh/ 安装，或使用仓库中的 brew_via_proxy.sh。"
        fi
        die "未找到受支持的包管理器；请手动安装：${REQUIRED_CMDS[*]}"
    fi
    log_verbose "包管理器：$PKG_MANAGER"

    collect_missing
    print_report

    if [[ $CHECK_ONLY == true ]]; then
        if ((${#MISSING_CMDS[@]} > 0)); then
            log_error "缺少依赖：${MISSING_CMDS[*]}；执行 bash $0 -y 安装。"
            exit 1
        fi
        log_success "依赖检查通过。"
        return 0
    fi

    if ((${#MISSING_CMDS[@]} == 0)); then
        log_success "依赖已齐备，无需安装。"
        return 0
    fi

    setup_privilege
    build_install_command
    confirm_install
    install_missing

    if [[ $DRY_RUN == true ]]; then
        log_info "dry-run 完成，未修改系统。"
        return 0
    fi

    verify_after_install || die "部分依赖仍未就绪，请查看上方错误并按发行版文档手动安装。"
    log_success "依赖安装完成；下一步执行 deploy_omz.sh 部署 zsh 插件。"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
