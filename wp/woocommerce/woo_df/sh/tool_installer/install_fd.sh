#!/usr/bin/env bash
# fd 通用安装、更新和卸载脚本。
# 默认安装最新 GitHub Release 预编译二进制；也支持发行版仓库。

set -Eeuo pipefail

readonly SCRIPT_VERSION="1.4.0"
readonly REPOSITORY="sharkdp/fd"
readonly GITHUB_URL="https://github.com/${REPOSITORY}"
readonly GHFAST_PREFIX="https://ghfast.top"
readonly GHPROXY_PREFIX="https://gh-proxy.com"
readonly GHPROXY_NET_PREFIX="https://ghproxy.net"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly SCRIPT_DIR

METHOD="binary"
VERSION="latest"
MIRROR="auto"
CUSTOM_MIRROR=""
PROXY=""
INSTALL_DIR=""
SHA256=""
FORCE=false
DRY_RUN=false
UNINSTALL=false
NO_ALIAS=false
VERBOSE=false
ASSUME_YES=false
NETWORK_REGION=""
NETWORK_COUNTRY=""
TMP_DIR=""
STAGED_PATH=""
TARGET_PATH=""
ASSET_TARGET=""
FD_COMMAND=""
declare -a MIRROR_PREFIXES=()
declare -a CURL_PROXY_ARGS=()

COLOR_RESET=""
COLOR_BLUE=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_RED=""

init_colors() {
    if [[ -t 2 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
        COLOR_RESET=$'\033[0m'
        COLOR_BLUE=$'\033[34m'
        COLOR_GREEN=$'\033[32m'
        COLOR_YELLOW=$'\033[33m'
        COLOR_RED=$'\033[31m'
    fi
}

log_info()    { printf '%s[INFO]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*" >&2; }
log_success() { printf '%s[OK]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*" >&2; }
log_warn()    { printf '%s[WARN]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2; }
log_error()   { printf '%s[ERROR]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2; }
die()         { log_error "$*"; exit 1; }
log_verbose() { [[ "$VERBOSE" == false ]] || printf '%s[VERBOSE]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*" >&2; }

sanitize_url() {
    local value=$1 scheme remainder
    if [[ "$value" =~ ^([^:]+://)([^/@]+@)(.*)$ ]]; then
        scheme=${BASH_REMATCH[1]}; remainder=${BASH_REMATCH[3]}
        value="${scheme}***@${remainder}"
    fi
    [[ "$value" != *\?* ]] || value="${value%%\?*}?[query-redacted]"
    printf '%s\n' "$value"
}

usage() {
    cat <<'USAGE'
fd 通用安装脚本

用法：
  install_fd.sh [选项]

安装方式：
  -m, --method METHOD    binary（默认）、package；auto 等同 binary
  -v, --version VERSION  Release 版本；默认 latest，可写 10.4.2 或 v10.4.2
      --install-dir DIR  binary 的安装目录；默认普通用户 ~/.local/bin，root /usr/local/bin

国内网络与下载：
      --mirror MODE      auto（默认）、direct、ghfast、ghproxy、ghproxynet 或 HTTPS URL
                         仅用于 github.com 的 Release 页面和文件，不代理 api.github.com
      --proxy URL        curl 使用的 HTTP/HTTPS/SOCKS5 代理，如 http://127.0.0.1:7890
      --sha256 HASH      校验 binary 下载包的 SHA-256（指定后必须匹配）

其他选项：
  -u, --uninstall       卸载；建议同时明确指定 package 或 binary
      --no-alias        package 安装后不为 Debian/Ubuntu 的 fdfind 创建 fd 链接
  -f, --force           重新安装，并允许替换冲突的 fd 链接/目标
  -y, --yes             自动确认升级，适合无人值守运行
  -n, --dry-run         不做持久化变更；binary 仍会下载并验证临时文件
      --verbose         输出请求 URL、候选通道、版本和平台决策详情
  -h, --help            显示帮助
      --script-version  显示脚本版本

示例：
  ./install_fd.sh
  ./install_fd.sh --method binary --mirror auto
  ./install_fd.sh -m binary -v 10.4.2 --proxy socks5h://127.0.0.1:7890
  sudo ./install_fd.sh -m package
  ./install_fd.sh --uninstall --method binary

说明：
  默认从 GitHub Release 安装最新预编译二进制，不受系统仓库版本影响。
  --proxy 仅传给本脚本的 curl。包管理器代理请按发行版方式配置，或导出
  http_proxy/https_proxy 后运行。完整文档见 README.fd.md。
USAGE
}

cleanup() {
    [[ -z "$STAGED_PATH" || ! -e "$STAGED_PATH" ]] || rm -f -- "$STAGED_PATH"
    [[ -z "$TMP_DIR" || ! -d "$TMP_DIR" ]] || rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

need_value() { (($# >= 2)) || die "$1 缺少参数。"; }

parse_args() {
    while (($#)); do
        case "$1" in
            -m|--method) need_value "$@"; METHOD=$2; shift 2 ;;
            --method=*) METHOD=${1#*=}; shift ;;
            -v|--version) need_value "$@"; VERSION=$2; shift 2 ;;
            --version=*) VERSION=${1#*=}; shift ;;
            --mirror) need_value "$@"; MIRROR=$2; shift 2 ;;
            --mirror=*) MIRROR=${1#*=}; shift ;;
            --proxy) need_value "$@"; PROXY=$2; shift 2 ;;
            --proxy=*) PROXY=${1#*=}; shift ;;
            --install-dir) need_value "$@"; INSTALL_DIR=$2; shift 2 ;;
            --install-dir=*) INSTALL_DIR=${1#*=}; shift ;;
            --sha256) need_value "$@"; SHA256=$2; shift 2 ;;
            --sha256=*) SHA256=${1#*=}; shift ;;
            -u|--uninstall) UNINSTALL=true; shift ;;
            --no-alias) NO_ALIAS=true; shift ;;
            -f|--force) FORCE=true; shift ;;
            -y|--yes) ASSUME_YES=true; shift ;;
            -n|--dry-run) DRY_RUN=true; shift ;;
            --verbose) VERBOSE=true; shift ;;
            --script-version) printf '%s\n' "$SCRIPT_VERSION"; exit 0 ;;
            -h|--help) usage; exit 0 ;;
            --) shift; (($# == 0)) || die "不支持位置参数：$*" ;;
            *) die "未知参数：$1（使用 --help 查看帮助）。" ;;
        esac
    done

    case "$METHOD" in auto|package|binary) ;; *) die "无效安装方式：$METHOD" ;; esac
    [[ "$VERSION" =~ ^[vV]?[0-9]+([.][0-9]+){1,3}([+_-][0-9A-Za-z.-]+)?$ || "$VERSION" == latest ]] ||
        die "无效版本号：$VERSION"
    [[ -z "$SHA256" || "$SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "--sha256 必须是 64 位十六进制值。"
    [[ -z "$PROXY" || "$PROXY" =~ ^(https?|socks4a?|socks5h?):// ]] || die "不支持的代理 URL：$PROXY"

    case "$MIRROR" in
        auto|direct|ghfast|ghproxy|ghproxynet) ;;
        https://*) CUSTOM_MIRROR=${MIRROR%/}; MIRROR=custom ;;
        *) die "无效镜像：$MIRROR；自定义镜像必须以 https:// 开头。" ;;
    esac

    [[ -z "$PROXY" ]] || CURL_PROXY_ARGS=(--proxy "$PROXY")
    log_verbose "参数：method=$METHOD version=$VERSION mirror=$MIRROR uninstall=$UNINSTALL dry_run=$DRY_RUN force=$FORCE yes=$ASSUME_YES"
    if [[ -n "$PROXY" ]]; then
        log_verbose "curl 代理：$(sanitize_url "$PROXY")"
    else
        log_verbose "curl 代理：未显式指定（仍尊重 curl 标准代理环境变量）"
        log_proxy_environment
    fi
}

log_proxy_environment() {
    local name value
    for name in HTTPS_PROXY https_proxy ALL_PROXY all_proxy HTTP_PROXY http_proxy; do
        value=${!name:-}
        if [[ -n "$value" ]]; then
            log_verbose "检测到代理环境变量 $name=$(sanitize_url "$value")"
        fi
    done
}

compare_versions() {
    local left=${1#v} right=${2#v} left_main right_main left_pre="" right_pre=""
    local -a left_parts=() right_parts=() left_pre_parts=() right_pre_parts=()
    local i left_value right_value max_parts

    left=${left%%+*}; right=${right%%+*}
    left=${left/_/-}; right=${right/_/-}
    left_main=${left%%-*}; right_main=${right%%-*}
    [[ "$left" != *-* ]] || left_pre=${left#*-}
    [[ "$right" != *-* ]] || right_pre=${right#*-}
    IFS=. read -r -a left_parts <<< "$left_main"
    IFS=. read -r -a right_parts <<< "$right_main"
    max_parts=${#left_parts[@]}
    ((${#right_parts[@]} <= max_parts)) || max_parts=${#right_parts[@]}

    for ((i = 0; i < max_parts; i++)); do
        left_value=$((10#${left_parts[i]:-0}))
        right_value=$((10#${right_parts[i]:-0}))
        ((left_value < right_value)) && { printf '%s\n' -1; return; }
        ((left_value > right_value)) && { printf '%s\n' 1; return; }
    done

    [[ "$left_pre" != "$right_pre" ]] || { printf '%s\n' 0; return; }
    [[ -n "$left_pre" ]] || { printf '%s\n' 1; return; }
    [[ -n "$right_pre" ]] || { printf '%s\n' -1; return; }
    IFS=. read -r -a left_pre_parts <<< "$left_pre"
    IFS=. read -r -a right_pre_parts <<< "$right_pre"
    max_parts=${#left_pre_parts[@]}
    ((${#right_pre_parts[@]} <= max_parts)) || max_parts=${#right_pre_parts[@]}
    for ((i = 0; i < max_parts; i++)); do
        [[ -n "${left_pre_parts[i]:-}" ]] || { printf '%s\n' -1; return; }
        [[ -n "${right_pre_parts[i]:-}" ]] || { printf '%s\n' 1; return; }
        if [[ "${left_pre_parts[i]}" =~ ^[0-9]+$ && "${right_pre_parts[i]}" =~ ^[0-9]+$ ]]; then
            left_value=$((10#${left_pre_parts[i]})); right_value=$((10#${right_pre_parts[i]}))
            ((left_value < right_value)) && { printf '%s\n' -1; return; }
            ((left_value > right_value)) && { printf '%s\n' 1; return; }
        elif [[ "${left_pre_parts[i]}" =~ ^[0-9]+$ ]]; then
            printf '%s\n' -1; return
        elif [[ "${right_pre_parts[i]}" =~ ^[0-9]+$ ]]; then
            printf '%s\n' 1; return
        elif [[ "${left_pre_parts[i]}" < "${right_pre_parts[i]}" ]]; then
            printf '%s\n' -1; return
        elif [[ "${left_pre_parts[i]}" > "${right_pre_parts[i]}" ]]; then
            printf '%s\n' 1; return
        fi
    done
    printf '%s\n' 0
}

confirm_upgrade() {
    local tool=$1 current=$2 target=$3 answer
    if [[ "$DRY_RUN" == true ]]; then
        log_info "dry-run：将请求确认把 $tool 从 $current 升级到 $target。"
        return
    fi
    if [[ "$ASSUME_YES" == true ]]; then
        log_verbose "版本确认：direction=upgrade answer=yes source=--yes"
        return
    fi
    [[ -t 0 ]] || die "检测到升级 $current -> $target；非交互环境请确认后添加 --yes。"
    printf '确认将 %s 从 %s 升级到 %s？[y/N] ' "$tool" "$current" "$target" >&2
    IFS= read -r answer || answer=""
    case "$answer" in
        y|Y|yes|YES|Yes) log_verbose "版本确认：direction=upgrade answer=yes source=interactive" ;;
        *) log_warn "用户取消升级，未修改现有版本。"; exit 0 ;;
    esac
}

enforce_version_policy() {
    local tool=$1 current=$2 target=$3 comparison
    comparison=$(compare_versions "$current" "$target")
    case "$comparison" in
        -1)
            log_verbose "版本策略：local=$current target=$target direction=upgrade allowed=true"
            confirm_upgrade "$tool" "$current" "$target"
            ;;
        0) return ;;
        1)
            log_verbose "版本策略：local=$current target=$target direction=downgrade allowed=false"
            die "不支持降级 $tool：当前 $current，目标 $target。"
            ;;
        *) die "无法比较版本：$current 与 $target" ;;
    esac
}

quote_command() {
    printf '  '
    printf '%q ' "$@"
    printf '\n'
}

run() {
    if [[ "$DRY_RUN" == true ]]; then
        quote_command "$@"
    else
        "$@"
    fi
}

privileged_run() {
    if ((EUID == 0)); then
        run "$@"
    else
        command -v sudo >/dev/null 2>&1 || die "该操作需要 root 权限，但未找到 sudo。"
        run sudo "$@"
    fi
}

require_command() { command -v "$1" >/dev/null 2>&1 || die "缺少必需命令：$1"; }

detect_os() {
    # os-release 中也有 VERSION 等通用变量，必须局部化，避免覆盖脚本选项。
    local ID="" VERSION_ID="" VERSION=""
    [[ "$(uname -s 2>/dev/null || true)" == Linux ]] || die "目前仅支持 Linux。macOS 请使用 brew install fd。"
    OS_ID="unknown"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID=${ID:-unknown}
    fi
    log_info "系统：$OS_ID${VERSION_ID:+ $VERSION_ID}；架构：$(uname -m)"
    log_verbose "平台识别：os_id=$OS_ID version_id=${VERSION_ID:-unknown} kernel=$(uname -s) machine=$(uname -m)"
}

package_manager() {
    local manager
    for manager in apt-get dnf yum apk pacman zypper xbps-install emerge eopkg; do
        command -v "$manager" >/dev/null 2>&1 && { printf '%s\n' "$manager"; return; }
    done
    return 1
}

package_name_for() {
    case "$1" in
        apt-get) [[ "$OS_ID" == alt ]] && printf 'fd\n' || printf 'fd-find\n' ;;
        dnf|yum) printf 'fd-find\n' ;;
        apk|pacman|zypper|xbps-install|emerge|eopkg) printf 'fd\n' ;;
        *) return 1 ;;
    esac
}

create_debian_alias() {
    local source alias_dir alias_path existing=""
    [[ "$NO_ALIAS" == false ]] || return 0
    source=$(command -v fdfind 2>/dev/null || true)
    if [[ -z "$source" && "$DRY_RUN" == true ]]; then source=/usr/bin/fdfind; fi
    [[ -n "$source" ]] || die "fd-find 已安装，但未找到 fdfind 命令。"

    if ((EUID == 0)); then alias_dir=/usr/local/bin; else alias_dir=${HOME:?HOME 未设置}/.local/bin; fi
    alias_path="$alias_dir/fd"
    [[ -e "$alias_path" || -L "$alias_path" ]] && existing=$(readlink "$alias_path" 2>/dev/null || true)
    if [[ -n "$existing" && "$existing" == "$source" ]]; then
        log_info "fd 别名已存在：$alias_path -> $source"
        FD_COMMAND=$alias_path
        return
    fi
    if [[ -e "$alias_path" || -L "$alias_path" ]]; then
        [[ "$FORCE" == true ]] || die "$alias_path 已存在；请先确认其用途，或使用 --force 替换。"
    fi
    run mkdir -p -- "$alias_dir"
    run ln -sfn -- "$source" "$alias_path"
    FD_COMMAND=$alias_path
    log_success "已创建 Debian/Ubuntu 兼容别名：$alias_path -> $source"
}

install_package() {
    local manager package
    manager=$(package_manager) || return 1
    package=$(package_name_for "$manager") || return 1
    log_info "使用 $manager 安装发行版软件包 $package。"
    case "$manager" in
        apt-get)
            privileged_run apt-get update
            if [[ "$ASSUME_YES" == true ]]; then privileged_run apt-get install -y "$package"
            else privileged_run apt-get install "$package"
            fi
            create_debian_alias
            ;;
        dnf)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run dnf install -y "$package"
            else privileged_run dnf install "$package"
            fi
            ;;
        yum)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run yum install -y "$package"
            else privileged_run yum install "$package"
            fi
            ;;
        apk) privileged_run apk add --no-cache "$package" ;;
        pacman)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run pacman -S --needed --noconfirm "$package"
            else privileged_run pacman -S --needed "$package"
            fi
            ;;
        zypper)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run zypper --non-interactive install "$package"
            else privileged_run zypper install "$package"
            fi
            ;;
        xbps-install)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run xbps-install -Sy "$package"
            else privileged_run xbps-install -S "$package"
            fi
            ;;
        emerge)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run emerge --ask=n sys-apps/fd
            else privileged_run emerge --ask sys-apps/fd
            fi
            ;;
        eopkg)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run eopkg install -y "$package"
            else privileged_run eopkg install "$package"
            fi
            ;;
    esac
    [[ -n "$FD_COMMAND" ]] || FD_COMMAND=$(command -v fd 2>/dev/null || true)
}

remove_package() {
    local manager package
    manager=$(package_manager) || die "未找到支持的包管理器。"
    package=$(package_name_for "$manager") || die "无法确定 fd 软件包名称。"
    log_info "使用 $manager 卸载 $package。"
    case "$manager" in
        apt-get) privileged_run apt-get remove -y "$package" ;;
        dnf) privileged_run dnf remove -y "$package" ;;
        yum) privileged_run yum remove -y "$package" ;;
        apk) privileged_run apk del "$package" ;;
        pacman) privileged_run pacman -R --noconfirm "$package" ;;
        zypper) privileged_run zypper --non-interactive remove "$package" ;;
        xbps-install) command -v xbps-remove >/dev/null || die "缺少 xbps-remove"; privileged_run xbps-remove -Ry "$package" ;;
        emerge) privileged_run emerge --unmerge sys-apps/fd ;;
        eopkg) privileged_run eopkg remove -y "$package" ;;
    esac
    remove_managed_alias
}

remove_managed_alias() {
    local alias_dir alias_path target
    if ((EUID == 0)); then alias_dir=/usr/local/bin; else alias_dir=${HOME:?HOME 未设置}/.local/bin; fi
    alias_path="$alias_dir/fd"
    if [[ -L "$alias_path" ]]; then
        target=$(readlink "$alias_path" 2>/dev/null || true)
        if [[ "$target" == */fdfind ]]; then
            run rm -f -- "$alias_path"
            log_success "已删除 fdfind 兼容链接：$alias_path"
        fi
    fi
}

detect_network_region() {
    local helper="$SCRIPT_DIR/../shell_utils/net_is_cn.sh" status
    if [[ -n "$NETWORK_REGION" ]]; then return 0; fi
    if [[ ! -r "$helper" ]]; then
        NETWORK_REGION=unknown
        NETWORK_COUNTRY=UNKNOWN
        log_warn "未找到网络区域检测工具：$helper；auto 将优先直连。"
        return 0
    fi

    # shellcheck source=shell_utils/net_is_cn.sh
    source "$helper"
    if [[ -n "$PROXY" ]]; then
        if NETWORK_COUNTRY=$(HTTPS_PROXY="$PROXY" https_proxy="$PROXY" net_is_cn --print); then status=0; else status=$?; fi
    else
        if NETWORK_COUNTRY=$(net_is_cn --print); then status=0; else status=$?; fi
    fi
    case "$status" in
        0) NETWORK_REGION=cn ;;
        1) NETWORK_REGION=global ;;
        *) NETWORK_REGION=unknown; NETWORK_COUNTRY=${NETWORK_COUNTRY:-UNKNOWN} ;;
    esac
    log_verbose "网络区域决策：country=$NETWORK_COUNTRY region=$NETWORK_REGION helper=$helper"
}

load_mirrors() {
    case "$MIRROR" in
        auto)
            detect_network_region
            if [[ "$NETWORK_REGION" == cn ]]; then
                MIRROR_PREFIXES=("$GHFAST_PREFIX" "$GHPROXY_PREFIX" "$GHPROXY_NET_PREFIX" "")
            else
                MIRROR_PREFIXES=("" "$GHFAST_PREFIX" "$GHPROXY_PREFIX" "$GHPROXY_NET_PREFIX")
            fi
            ;;
        direct) MIRROR_PREFIXES=("") ;;
        ghfast) MIRROR_PREFIXES=("$GHFAST_PREFIX") ;;
        ghproxy) MIRROR_PREFIXES=("$GHPROXY_PREFIX") ;;
        ghproxynet) MIRROR_PREFIXES=("$GHPROXY_NET_PREFIX") ;;
        custom) MIRROR_PREFIXES=("$CUSTOM_MIRROR") ;;
    esac
    if [[ "$MIRROR" == auto ]]; then
        if [[ "$NETWORK_REGION" == cn ]]; then
            log_verbose "镜像决策：mode=auto country=$NETWORK_COUNTRY candidates=ghfast,gh-proxy,ghproxy.net,direct"
        else
            log_verbose "镜像决策：mode=auto country=$NETWORK_COUNTRY candidates=direct,ghfast,gh-proxy,ghproxy.net"
        fi
    else
        log_verbose "镜像决策：mode=$MIRROR candidates=${#MIRROR_PREFIXES[@]}"
    fi
}

mirror_url() {
    local prefix=${1%/} original=$2

    # GitHub 文件镜像通常不完整支持 REST API。API 请求只能直连，或由
    # curl 的 --proxy/标准代理环境变量转发，禁止拼接镜像前缀。
    if [[ "$original" == https://api.github.com/* && -n "$prefix" ]]; then
        log_error "拒绝通过 GitHub 文件镜像访问 api.github.com；请使用直连或 --proxy。"
        return 2
    fi

    [[ -n "$prefix" ]] && printf '%s/%s\n' "$prefix" "$original" || printf '%s\n' "$original"
}

resolve_latest_version() {
    local prefix url headers location version effective_url transport
    load_mirrors
    headers="$TMP_DIR/latest.headers"
    for prefix in "${MIRROR_PREFIXES[@]}"; do
        url=$(mirror_url "$prefix" "$GITHUB_URL/releases/latest")
        if [[ -n "$prefix" ]]; then
            transport="file-mirror"
            log_info "解析 latest 重定向（github.com，非 api.github.com）；访问通道：GitHub 文件镜像 $prefix"
        else
            transport="direct"
            log_info "解析 latest 重定向（github.com，非 api.github.com）；访问通道：GitHub 直连"
        fi
        log_verbose "HTTP HEAD：$(sanitize_url "$url")"
        if effective_url=$(curl --fail --silent --show-error --location --head \
            --connect-timeout 6 --max-time 30 --retry 1 \
            "${CURL_PROXY_ARGS[@]}" --dump-header "$headers" --output /dev/null \
            --write-out '%{url_effective}' "$url"); then
            log_verbose "最终 URL：$(sanitize_url "$effective_url")"
            location=$(awk 'BEGIN{IGNORECASE=1} /^location:/ {gsub("\\r", ""); value=$2} END{print value}' "$headers")
            version=${location##*/}
            version=${version#v}
            log_verbose "latest 重定向：${location:-未返回 Location}"
            if [[ "$version" =~ ^[0-9]+([.][0-9]+){1,3}([+_-][0-9A-Za-z.-]+)?$ ]]; then
                VERSION=$version
                log_success "最新版本：$VERSION"
                log_verbose "版本决策：mechanism=release-latest-redirect endpoint=github.com api=false transport=$transport resolved=$VERSION"
                return
            fi
        fi
        log_warn "该通道无法解析最新版本。"
    done
    die "无法获取最新版。可使用 --version 指定版本，或检查 --mirror/--proxy。"
}

detect_asset_target() {
    local arch libc=gnu
    arch=$(uname -m)
    command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl && libc=musl
    compgen -G '/lib/ld-musl-*.so.1' >/dev/null && libc=musl
    log_verbose "运行库识别：libc=$libc"
    case "$arch" in
        x86_64|amd64) ASSET_TARGET="x86_64-unknown-linux-$libc" ;;
        aarch64|arm64) ASSET_TARGET="aarch64-unknown-linux-$libc" ;;
        i386|i486|i586|i686) ASSET_TARGET="i686-unknown-linux-$libc" ;;
        armv7l|armv7|armhf)
            [[ "$libc" == musl ]] && ASSET_TARGET="arm-unknown-linux-musleabihf" || ASSET_TARGET="arm-unknown-linux-gnueabihf"
            ;;
        *) die "GitHub Release 不支持当前架构：$arch；可尝试 --method package。" ;;
    esac
    log_info "Release 目标：$ASSET_TARGET"
    log_verbose "资产决策：machine=$arch libc=$libc target=$ASSET_TARGET"
}

download_release() {
    local asset archive original prefix candidate effective_url ok=false
    asset="fd-v${VERSION}-${ASSET_TARGET}.tar.gz"
    archive="$TMP_DIR/$asset"
    original="$GITHUB_URL/releases/download/v${VERSION}/${asset}"
    load_mirrors
    for prefix in "${MIRROR_PREFIXES[@]}"; do
        candidate=$(mirror_url "$prefix" "$original")
        log_info "下载 $asset：${prefix:-GitHub 直连}"
        log_verbose "HTTP GET：$(sanitize_url "$candidate")"
        if effective_url=$(curl --fail --show-error --location --connect-timeout 8 --max-time 600 \
            --retry 2 --retry-delay 2 "${CURL_PROXY_ARGS[@]}" --output "$archive" \
            --write-out '%{url_effective}' "$candidate"); then
            ok=true
            log_verbose "最终 URL：$(sanitize_url "$effective_url")"
            log_verbose "下载通道决策：source=${prefix:-direct} url=$(sanitize_url "$candidate")"
            break
        fi
        rm -f -- "$archive"
        log_warn "下载失败，尝试下一通道。"
    done
    [[ "$ok" == true && -s "$archive" ]] || die "所有下载通道均失败。"
    verify_sha256 "$archive"
    printf '%s\n' "$archive"
}

verify_sha256() {
    local file=$1 actual
    [[ -n "$SHA256" ]] || { log_warn "未提供 --sha256；将通过压缩包结构和程序版本做完整性检查。"; return; }
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        die "指定了 --sha256，但系统没有 sha256sum 或 shasum。"
    fi
    [[ "${actual,,}" == "${SHA256,,}" ]] || die "SHA-256 校验失败（实际：$actual）。"
    log_success "SHA-256 校验通过。"
}

binary_install_dir() {
    if [[ -z "$INSTALL_DIR" ]]; then
        if ((EUID == 0)); then INSTALL_DIR=/usr/local/bin; else INSTALL_DIR=${HOME:?HOME 未设置}/.local/bin; fi
    fi
    [[ "$INSTALL_DIR" == /* ]] || die "--install-dir 必须是绝对路径。"
    TARGET_PATH="$INSTALL_DIR/fd"
    log_verbose "安装目标决策：euid=$EUID install_dir=$INSTALL_DIR target=$TARGET_PATH"
}

install_binary() {
    local archive extract_dir member binary found_version="" member_count=0
    require_command curl
    require_command tar
    binary_install_dir
    [[ ! -d "$TARGET_PATH" || -L "$TARGET_PATH" ]] || die "安装目标是目录，拒绝覆盖：$TARGET_PATH"
    if [[ -x "$TARGET_PATH" ]]; then
        found_version=$($TARGET_PATH --version 2>/dev/null | awk '{print $2}' || true)
        log_verbose "现有目标：path=$TARGET_PATH version=${found_version:-unrecognized}"
        [[ -n "$found_version" || "$FORCE" == true ]] || die "$TARGET_PATH 已存在但不像 fd；请确认后使用 --force 覆盖。"
    fi
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/install-fd.XXXXXXXX")
    [[ "$VERSION" != latest ]] || resolve_latest_version
    VERSION=${VERSION#v}; VERSION=${VERSION#V}
    if [[ "$FORCE" == false && -n "$found_version" && "$found_version" == "$VERSION" ]]; then
        log_verbose "更新决策：local=$found_version remote=$VERSION action=skip"
        log_success "目标版本已安装：$TARGET_PATH ($found_version)"
        FD_COMMAND=$TARGET_PATH
        return
    fi
    [[ -z "$found_version" || "$found_version" == "$VERSION" ]] || enforce_version_policy fd "$found_version" "$VERSION"
    detect_asset_target
    log_verbose "更新决策：local=${found_version:-none} remote=$VERSION action=install"
    archive=$(download_release)
    extract_dir="$TMP_DIR/extracted"
    mkdir -p -- "$extract_dir"

    # 只提取官方形式的唯一 */fd 文件。拒绝绝对路径、路径穿越和链接，
    # 避免归档中的其他成员影响临时目录。
    while IFS= read -r member; do
        [[ "$member" != /* && "$member" != ".." && "$member" != ../* &&
           "$member" != */../* && "$member" != */.. ]] || die "压缩包包含不安全路径：$member"
        if [[ "$member" == */fd ]]; then
            binary=$member
            ((member_count += 1))
        fi
    done < <(tar -tzf "$archive")
    [[ "$member_count" == 1 ]] || die "压缩包应包含一个 fd 文件，实际找到 $member_count 个。"
    tar -xzf "$archive" -C "$extract_dir" -- "$binary"
    binary="$extract_dir/$binary"
    [[ -f "$binary" && ! -L "$binary" ]] || die "压缩包中的 fd 不是常规文件。"
    chmod 0755 "$binary"
    found_version=$($binary --version 2>/dev/null | awk '{print $2}' || true)
    [[ "$found_version" == "$VERSION" ]] || die "程序版本不符：期望 $VERSION，实际 ${found_version:-未知}。"

    run mkdir -p -- "$INSTALL_DIR"
    if [[ "$DRY_RUN" == true ]]; then
        quote_command install -m 0755 "$binary" "$TARGET_PATH"
        log_info "dry-run：将安装 fd $VERSION 到 $TARGET_PATH"
    else
        STAGED_PATH=$(mktemp "$INSTALL_DIR/.fd.install.XXXXXXXX")
        install -m 0755 "$binary" "$STAGED_PATH"
        mv -f -- "$STAGED_PATH" "$TARGET_PATH"
        STAGED_PATH=""
        log_success "已安装 fd $VERSION：$TARGET_PATH"
    fi
    FD_COMMAND=$TARGET_PATH
}

uninstall_binary() {
    binary_install_dir
    if [[ ! -e "$TARGET_PATH" && ! -L "$TARGET_PATH" ]]; then
        log_warn "目标不存在：$TARGET_PATH"
        return
    fi
    [[ ! -d "$TARGET_PATH" ]] || die "目标是目录，拒绝删除：$TARGET_PATH"
    run rm -f -- "$TARGET_PATH"
    log_success "已删除：$TARGET_PATH"
}

choose_auto_method() {
    METHOD=binary
    log_info "auto 使用最新版优先策略：binary"
    log_verbose "安装方式决策：requested=auto selected=binary reason=latest-prebuilt-default"
}

verify_result() {
    [[ "$DRY_RUN" == false ]] || { log_info "dry-run 完成，未修改系统。"; return; }
    [[ -n "$FD_COMMAND" && -x "$FD_COMMAND" ]] || FD_COMMAND=$(command -v fd 2>/dev/null || true)
    [[ -n "$FD_COMMAND" && -x "$FD_COMMAND" ]] || die "安装命令已结束，但未找到可执行的 fd。"
    log_success "$($FD_COMMAND --version)（$FD_COMMAND）"
    case ":${PATH}:" in *:"$(dirname "$FD_COMMAND")":*) ;; *) log_warn "$(dirname "$FD_COMMAND") 不在 PATH 中。" ;; esac
}

main() {
    init_colors
    parse_args "$@"
    detect_os
    [[ "$METHOD" != auto ]] || choose_auto_method
    log_verbose "最终安装方式：$METHOD"

    if [[ "$UNINSTALL" == true ]]; then
        case "$METHOD" in package) remove_package ;; binary) uninstall_binary ;; esac
        return
    fi

    case "$METHOD" in
        package)
            [[ "$VERSION" == latest ]] || die "package 模式不能保证指定版本；请使用 binary。"
            [[ -z "$INSTALL_DIR" ]] || die "package 模式不支持 --install-dir。"
            package_manager >/dev/null 2>&1 || die "当前发行版不支持 package 模式，请改用 --method binary。"
            install_package
            ;;
        binary) install_binary ;;
    esac
    verify_result
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
