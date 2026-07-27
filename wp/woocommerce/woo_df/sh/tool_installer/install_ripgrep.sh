#!/usr/bin/env bash
# ripgrep 通用安装、更新和卸载脚本。
# 默认安装最新官方预编译二进制，兼顾国内网络和最小依赖。

set -Eeuo pipefail

readonly SCRIPT_VERSION="1.3.0"
readonly REPOSITORY="BurntSushi/ripgrep"
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
CHECKSUM_MODE="require"
FORCE=false
DRY_RUN=false
UNINSTALL=false
VERBOSE=false
ASSUME_YES=false
NETWORK_REGION=""
NETWORK_COUNTRY=""
TMP_DIR=""
STAGED_PATH=""
TARGET_PATH=""
ASSET_TARGET=""
RG_COMMAND=""
declare -a MIRROR_PREFIXES=()
declare -a CURL_PROXY_ARGS=()

COLOR_RESET=""
COLOR_BLUE=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_RED=""

init_colors() {
    if [[ -t 2 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then
        COLOR_RESET=$'\033[0m'; COLOR_BLUE=$'\033[34m'; COLOR_GREEN=$'\033[32m'
        COLOR_YELLOW=$'\033[33m'; COLOR_RED=$'\033[31m'
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
ripgrep 通用安装脚本

用法：
  install_ripgrep.sh [选项]

安装方式：
  -m, --method METHOD    binary（默认）、package；auto 等同 binary
  -v, --version VERSION  默认 latest，也可写 15.2.0
      --install-dir DIR  binary 安装目录；普通用户默认 ~/.local/bin，root /usr/local/bin

国内网络与校验：
      --mirror MODE      auto、direct、ghfast、ghproxy、ghproxynet 或 HTTPS 镜像前缀
                         仅用于 github.com 的 Release 页面和文件，不代理 api.github.com
      --proxy URL        curl 使用的 HTTP/HTTPS/SOCKS 代理
      --checksum MODE    require（默认）、auto 或 skip
      --sha256 HASH      使用用户提供的可信 SHA-256，优先于上游校验文件

其他选项：
  -u, --uninstall       卸载当前方式对应的 ripgrep
  -f, --force           重新安装，并允许覆盖无法识别的目标文件
  -y, --yes             自动确认升级，适合无人值守运行
  -n, --dry-run         不做持久化变更；binary 仍下载并验证临时文件
      --verbose         输出请求 URL、候选通道、校验和平台决策详情
  -h, --help            显示帮助
      --script-version  显示脚本版本

示例：
  ./install_ripgrep.sh
  ./install_ripgrep.sh -v 15.2.0 --mirror ghfast
  ./install_ripgrep.sh --proxy socks5h://127.0.0.1:7890
  sudo ./install_ripgrep.sh --method package
  ./install_ripgrep.sh --uninstall

默认只安装最新官方 rg 主程序，不依赖系统仓库版本或 Rust 工具链。
完整文档见 README.ripgrep.md。
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
            --checksum) need_value "$@"; CHECKSUM_MODE=$2; shift 2 ;;
            --checksum=*) CHECKSUM_MODE=${1#*=}; shift ;;
            --sha256) need_value "$@"; SHA256=$2; shift 2 ;;
            --sha256=*) SHA256=${1#*=}; shift ;;
            -u|--uninstall) UNINSTALL=true; shift ;;
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

    case "$METHOD" in auto|binary|package) ;; *) die "无效安装方式：$METHOD" ;; esac
    if [[ "$METHOD" == auto ]]; then
        METHOD=binary
        log_verbose "安装方式决策：requested=auto selected=binary reason=latest-prebuilt-default"
    fi
    [[ "$VERSION" == latest || "$VERSION" =~ ^[vV]?[0-9]+([.][0-9]+){1,3}([+_-][0-9A-Za-z.-]+)?$ ]] || die "无效版本：$VERSION"
    case "$CHECKSUM_MODE" in require|auto|skip) ;; *) die "无效校验模式：$CHECKSUM_MODE" ;; esac
    [[ -z "$SHA256" || "$SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "--sha256 必须是 64 位十六进制值。"
    [[ -z "$PROXY" || "$PROXY" =~ ^(https?|socks4a?|socks5h?):// ]] || die "不支持的代理 URL。"
    case "$MIRROR" in
        auto|direct|ghfast|ghproxy|ghproxynet) ;;
        https://*) CUSTOM_MIRROR=${MIRROR%/}; MIRROR=custom ;;
        *) die "无效镜像；自定义镜像必须以 https:// 开头。" ;;
    esac
    [[ -z "$PROXY" ]] || CURL_PROXY_ARGS=(--proxy "$PROXY")
    log_verbose "参数：method=$METHOD version=$VERSION mirror=$MIRROR checksum=$CHECKSUM_MODE uninstall=$UNINSTALL dry_run=$DRY_RUN force=$FORCE yes=$ASSUME_YES"
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
        left_value=$((10#${left_parts[i]:-0})); right_value=$((10#${right_parts[i]:-0}))
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
        elif [[ "${left_pre_parts[i]}" =~ ^[0-9]+$ ]]; then printf '%s\n' -1; return
        elif [[ "${right_pre_parts[i]}" =~ ^[0-9]+$ ]]; then printf '%s\n' 1; return
        elif [[ "${left_pre_parts[i]}" < "${right_pre_parts[i]}" ]]; then printf '%s\n' -1; return
        elif [[ "${left_pre_parts[i]}" > "${right_pre_parts[i]}" ]]; then printf '%s\n' 1; return
        fi
    done
    printf '%s\n' 0
}

confirm_upgrade() {
    local tool=$1 current=$2 target=$3 answer
    if [[ "$DRY_RUN" == true ]]; then
        log_info "dry-run：将请求确认把 $tool 从 $current 升级到 $target。"; return
    fi
    if [[ "$ASSUME_YES" == true ]]; then
        log_verbose "版本确认：direction=upgrade answer=yes source=--yes"; return
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

quote_command() { printf '  '; printf '%q ' "$@"; printf '\n'; }
run() {
    if [[ "$DRY_RUN" == true ]]; then
        quote_command "$@"
    else
        "$@"
    fi
}

privileged_run() {
    if ((EUID == 0)); then run "$@"; else
        command -v sudo >/dev/null 2>&1 || die "需要 root 权限，但未找到 sudo。"
        run sudo "$@"
    fi
}

require_command() { command -v "$1" >/dev/null 2>&1 || die "缺少必需命令：$1"; }

detect_os() {
    local ID="" VERSION_ID="" VERSION=""
    [[ "$(uname -s 2>/dev/null || true)" == Linux ]] || die "目前仅支持 Linux。"
    OS_ID=unknown
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

install_package() {
    local manager
    manager=$(package_manager) || die "未找到支持的包管理器，请使用 binary。"
    log_info "使用 $manager 安装 ripgrep。"
    case "$manager" in
        apt-get)
            privileged_run apt-get update
            if [[ "$ASSUME_YES" == true ]]; then privileged_run apt-get install -y ripgrep
            else privileged_run apt-get install ripgrep
            fi
            ;;
        dnf)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run dnf install -y ripgrep
            else privileged_run dnf install ripgrep
            fi
            ;;
        yum)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run yum install -y ripgrep
            else privileged_run yum install ripgrep
            fi
            ;;
        apk) privileged_run apk add --no-cache ripgrep ;;
        pacman)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run pacman -S --needed --noconfirm ripgrep
            else privileged_run pacman -S --needed ripgrep
            fi
            ;;
        zypper)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run zypper --non-interactive install ripgrep
            else privileged_run zypper install ripgrep
            fi
            ;;
        xbps-install)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run xbps-install -Sy ripgrep
            else privileged_run xbps-install -S ripgrep
            fi
            ;;
        emerge)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run emerge --ask=n sys-apps/ripgrep
            else privileged_run emerge --ask sys-apps/ripgrep
            fi
            ;;
        eopkg)
            if [[ "$ASSUME_YES" == true ]]; then privileged_run eopkg install -y ripgrep
            else privileged_run eopkg install ripgrep
            fi
            ;;
    esac
    RG_COMMAND=$(command -v rg 2>/dev/null || true)
}

remove_package() {
    local manager
    manager=$(package_manager) || die "未找到支持的包管理器。"
    case "$manager" in
        apt-get) privileged_run apt-get remove -y ripgrep ;;
        dnf) privileged_run dnf remove -y ripgrep ;;
        yum) privileged_run yum remove -y ripgrep ;;
        apk) privileged_run apk del ripgrep ;;
        pacman) privileged_run pacman -R --noconfirm ripgrep ;;
        zypper) privileged_run zypper --non-interactive remove ripgrep ;;
        xbps-install) require_command xbps-remove; privileged_run xbps-remove -Ry ripgrep ;;
        emerge) privileged_run emerge --unmerge sys-apps/ripgrep ;;
        eopkg) privileged_run eopkg remove -y ripgrep ;;
    esac
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
    local prefix url headers location parsed effective_url transport
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
        if effective_url=$(curl --fail --silent --show-error --location --head --connect-timeout 6 --max-time 30 --retry 1 \
            "${CURL_PROXY_ARGS[@]}" --dump-header "$headers" --output /dev/null \
            --write-out '%{url_effective}' "$url"); then
            log_verbose "最终 URL：$(sanitize_url "$effective_url")"
            location=$(awk 'BEGIN{IGNORECASE=1} /^location:/ {gsub("\\r", ""); value=$2} END{print value}' "$headers")
            parsed=${location##*/}; parsed=${parsed#v}
            log_verbose "latest 重定向：${location:-未返回 Location}"
            if [[ "$parsed" =~ ^[0-9]+([.][0-9]+){1,3}([+_-][0-9A-Za-z.-]+)?$ ]]; then
                VERSION=$parsed
                log_success "最新版本：$VERSION"
                log_verbose "版本决策：mechanism=release-latest-redirect endpoint=github.com api=false transport=$transport resolved=$VERSION"
                return
            fi
        fi
        log_warn "该通道无法解析最新版本。"
    done
    die "无法获取最新版；可用 --version 固定版本。"
}

detect_asset_target() {
    local arch libc=gnu
    arch=$(uname -m)
    command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl && libc=musl
    compgen -G '/lib/ld-musl-*.so.1' >/dev/null && libc=musl
    log_verbose "运行库识别：libc=$libc"
    case "$arch" in
        x86_64|amd64) ASSET_TARGET=x86_64-unknown-linux-musl ;;
        aarch64|arm64) ASSET_TARGET="aarch64-unknown-linux-$libc" ;;
        armv7l|armv7|armhf)
            [[ "$libc" == musl ]] && ASSET_TARGET=armv7-unknown-linux-musleabihf || ASSET_TARGET=armv7-unknown-linux-gnueabihf
            ;;
        i386|i486|i586|i686) ASSET_TARGET=i686-unknown-linux-gnu ;;
        s390x) ASSET_TARGET=s390x-unknown-linux-gnu ;;
        *) die "官方 Release 不支持当前架构：$arch；可尝试 --method package。" ;;
    esac
    log_info "Release 目标：$ASSET_TARGET"
    log_verbose "资产决策：machine=$arch libc=$libc target=$ASSET_TARGET"
}

download_to() {
    local original=$1 output=$2 description=$3 prefix candidate effective_url
    load_mirrors
    for prefix in "${MIRROR_PREFIXES[@]}"; do
        candidate=$(mirror_url "$prefix" "$original")
        log_info "下载$description：${prefix:-GitHub 直连}"
        log_verbose "HTTP GET：$(sanitize_url "$candidate")"
        if effective_url=$(curl --fail --show-error --location --connect-timeout 8 --max-time 600 --retry 2 --retry-delay 2 \
            "${CURL_PROXY_ARGS[@]}" --output "$output" --write-out '%{url_effective}' "$candidate"); then
            if [[ -s "$output" ]]; then
                log_verbose "最终 URL：$(sanitize_url "$effective_url")"
                log_verbose "下载通道决策：source=${prefix:-direct} url=$(sanitize_url "$candidate")"
                return 0
            fi
        fi
        rm -f -- "$output"
        log_warn "下载失败，尝试下一通道。"
    done
    return 1
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else return 1
    fi
}

verify_archive() {
    local archive=$1 original=$2 checksum_file expected actual
    if [[ -n "$SHA256" ]]; then
        expected=${SHA256,,}
        log_info "使用用户提供的 SHA-256。"
        log_verbose "校验决策：source=user-provided mode=$CHECKSUM_MODE"
    elif [[ "$CHECKSUM_MODE" == skip ]]; then
        log_warn "已按请求跳过 SHA-256 校验。"
        log_verbose "校验决策：source=none mode=skip"
        return
    else
        checksum_file="$archive.sha256"
        if download_to "$original.sha256" "$checksum_file" "官方 SHA-256 文件"; then
            expected=$(awk 'NR==1 {print $1}' "$checksum_file")
            [[ "$expected" =~ ^[0-9A-Fa-f]{64}$ ]] || die "官方校验文件格式无效。"
            expected=${expected,,}
            log_verbose "校验决策：source=upstream-sidecar mode=$CHECKSUM_MODE"
        elif [[ "$CHECKSUM_MODE" == require ]]; then
            die "无法下载官方 SHA-256 文件；可检查网络，或明确使用 --checksum skip。"
        else
            log_warn "未取得官方 SHA-256 文件，auto 模式继续进行结构和版本检查。"
            log_verbose "校验决策：source=none mode=auto action=continue"
            return
        fi
    fi
    actual=$(sha256_of "$archive") || die "缺少 sha256sum 或 shasum。"
    [[ "${actual,,}" == "$expected" ]] || die "SHA-256 不匹配（实际：$actual）。"
    log_success "SHA-256 校验通过。"
}

binary_install_dir() {
    if [[ -z "$INSTALL_DIR" ]]; then
        ((EUID == 0)) && INSTALL_DIR=/usr/local/bin || INSTALL_DIR=${HOME:?HOME 未设置}/.local/bin
    fi
    [[ "$INSTALL_DIR" == /* ]] || die "--install-dir 必须是绝对路径。"
    TARGET_PATH="$INSTALL_DIR/rg"
    log_verbose "安装目标决策：euid=$EUID install_dir=$INSTALL_DIR target=$TARGET_PATH"
}

install_binary() {
    local asset archive original extract_dir member="" binary="" found_version="" member_count=0
    require_command curl; require_command tar
    binary_install_dir
    [[ ! -d "$TARGET_PATH" || -L "$TARGET_PATH" ]] || die "安装目标是目录，拒绝覆盖：$TARGET_PATH"
    if [[ -x "$TARGET_PATH" ]]; then
        found_version=$($TARGET_PATH --version 2>/dev/null | awk 'NR==1 {print $2}' || true)
        log_verbose "现有目标：path=$TARGET_PATH version=${found_version:-unrecognized}"
        [[ -n "$found_version" || "$FORCE" == true ]] || die "$TARGET_PATH 已存在但不像 rg；请确认后使用 --force。"
    fi

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/install-ripgrep.XXXXXXXX")
    [[ "$VERSION" != latest ]] || resolve_latest_version
    VERSION=${VERSION#v}; VERSION=${VERSION#V}
    if [[ "$FORCE" == false && -n "$found_version" && "$found_version" == "$VERSION" ]]; then
        log_verbose "更新决策：local=$found_version remote=$VERSION action=skip"
        log_success "目标版本已安装：$TARGET_PATH ($found_version)"; RG_COMMAND=$TARGET_PATH; return
    fi
    [[ -z "$found_version" || "$found_version" == "$VERSION" ]] || enforce_version_policy ripgrep "$found_version" "$VERSION"
    detect_asset_target
    log_verbose "更新决策：local=${found_version:-none} remote=$VERSION action=install"
    asset="ripgrep-${VERSION}-${ASSET_TARGET}.tar.gz"
    archive="$TMP_DIR/$asset"
    original="$GITHUB_URL/releases/download/${VERSION}/${asset}"
    download_to "$original" "$archive" " $asset" || die "所有下载通道均失败。"
    verify_archive "$archive" "$original"

    extract_dir="$TMP_DIR/extracted"; mkdir -p -- "$extract_dir"
    while IFS= read -r member; do
        [[ "$member" != /* && "$member" != .. && "$member" != ../* && "$member" != */../* && "$member" != */.. ]] || die "不安全归档路径：$member"
        if [[ "$member" == */rg ]]; then binary=$member; ((member_count += 1)); fi
    done < <(tar -tzf "$archive")
    [[ "$member_count" == 1 ]] || die "归档应包含一个 rg，实际找到 $member_count 个。"
    tar -xzf "$archive" -C "$extract_dir" -- "$binary"
    binary="$extract_dir/$binary"
    [[ -f "$binary" && ! -L "$binary" ]] || die "归档中的 rg 不是常规文件。"
    chmod 0755 "$binary"
    found_version=$($binary --version 2>/dev/null | awk 'NR==1 {print $2}' || true)
    [[ "$found_version" == "$VERSION" ]] || die "程序版本不符：期望 $VERSION，实际 ${found_version:-未知}。"

    run mkdir -p -- "$INSTALL_DIR"
    if [[ "$DRY_RUN" == true ]]; then
        quote_command install -m 0755 "$binary" "$TARGET_PATH"
        log_info "dry-run：将安装 ripgrep $VERSION 到 $TARGET_PATH"
    else
        STAGED_PATH=$(mktemp "$INSTALL_DIR/.rg.install.XXXXXXXX")
        install -m 0755 "$binary" "$STAGED_PATH"
        mv -f -- "$STAGED_PATH" "$TARGET_PATH"; STAGED_PATH=""
        log_success "已安装 ripgrep $VERSION：$TARGET_PATH"
    fi
    RG_COMMAND=$TARGET_PATH
}

uninstall_binary() {
    binary_install_dir
    if [[ ! -e "$TARGET_PATH" && ! -L "$TARGET_PATH" ]]; then log_warn "目标不存在：$TARGET_PATH"; return; fi
    [[ ! -d "$TARGET_PATH" ]] || die "目标是目录，拒绝删除：$TARGET_PATH"
    run rm -f -- "$TARGET_PATH"
    log_success "已删除：$TARGET_PATH"
}

verify_result() {
    [[ "$DRY_RUN" == false ]] || { log_info "dry-run 完成，未修改安装目标。"; return; }
    [[ -n "$RG_COMMAND" && -x "$RG_COMMAND" ]] || RG_COMMAND=$(command -v rg 2>/dev/null || true)
    [[ -n "$RG_COMMAND" && -x "$RG_COMMAND" ]] || die "安装结束但未找到 rg。"
    log_success "$($RG_COMMAND --version | head -n 1)（$RG_COMMAND）"
    case ":$PATH:" in *:"$(dirname "$RG_COMMAND")":*) ;; *) log_warn "$(dirname "$RG_COMMAND") 不在 PATH 中。" ;; esac
}

main() {
    init_colors; parse_args "$@"; detect_os
    log_verbose "最终安装方式：$METHOD"
    if [[ "$UNINSTALL" == true ]]; then
        case "$METHOD" in binary) uninstall_binary ;; package) remove_package ;; esac
        return
    fi
    case "$METHOD" in
        binary) install_binary ;;
        package)
            [[ "$VERSION" == latest ]] || die "package 不能保证指定版本。"
            [[ -z "$INSTALL_DIR" ]] || die "package 不支持 --install-dir。"
            install_package
            ;;
    esac
    verify_result
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
