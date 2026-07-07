#!/usr/bin/env bash
# Fastfetch 通用安装、更新与卸载脚本 v5
# 支持 GitHub 直连、gh-proxy.com、ghfast.top 和自定义镜像前缀。

set -Eeuo pipefail

readonly REPOSITORY="fastfetch-cli/fastfetch"
readonly GITHUB_API_URL="https://api.github.com/repos/${REPOSITORY}/releases/latest"
readonly GH_PROXY_PREFIX="https://gh-proxy.com"
readonly GHFAST_PREFIX="https://ghfast.top"

MIRROR_MODE="auto"
MIRROR_WAS_SET=false
UNINSTALL=false
CUSTOM_MIRROR_PREFIX=""
INSTALL_DIR=""
TARGET_PATH=""
TMP_DIR=""
API_JSON_FILE=""
DOWNLOAD_URL=""
ARCH=""
ASSET_NAME=""
REMOTE_TAG=""
REMOTE_VERSION=""
LOCAL_VERSION=""
LOCAL_BINARY=""
STAGED_PATH=""
declare -a PREFIX_CANDIDATES=()

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

log_info() {
    printf '%s[INFO]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*" >&2
}

log_success() {
    printf '%s[SUCCESS]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*" >&2
}

log_warn() {
    printf '%s[WARN]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
}

log_error() {
    printf '%s[ERROR]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2
}

die() {
    log_error "$*"
    exit 1
}

usage() {
    cat <<USAGE
用法：
  $0 [选项]

选项：
  -u, --uninstall   卸载由本脚本安装在当前用户目标目录中的 Fastfetch。
                    普通用户删除 ~/.local/bin/fastfetch；
                    root 用户删除 /usr/local/bin/fastfetch。
                    不会删除 Fastfetch 配置文件。
  --mirror MODE     指定 GitHub 下载源模式，默认 auto。
                    MODE 可为：
                      auto      自动探测直连、gh-proxy.com、ghfast.top
                      direct    强制直连 GitHub
                      ghproxy   强制使用 https://gh-proxy.com
                      ghfast    强制使用 https://ghfast.top
                      URL       使用自定义镜像前缀（必须以 http:// 或 https:// 开头）
  -h, --help        显示本帮助信息

示例：
  ./$0
  ./$0 --mirror direct
  ./$0 --mirror ghproxy
  ./$0 --mirror=https://example.com/github-proxy
  ./$0 --uninstall
  sudo ./$0 --uninstall

安装位置：
  root 用户：/usr/local/bin/fastfetch
  普通用户：~/.local/bin/fastfetch
USAGE
}

cleanup() {
    if [[ -n "$STAGED_PATH" && -e "$STAGED_PATH" ]]; then
        rm -f -- "$STAGED_PATH"
    fi

    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf -- "$TMP_DIR"
    fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

parse_args() {
    while (($# > 0)); do
        case "$1" in
            -u|--uninstall)
                UNINSTALL=true
                shift
                ;;
            --mirror)
                (($# >= 2)) || die "--mirror 缺少参数。"
                MIRROR_WAS_SET=true
                MIRROR_MODE=$2
                shift 2
                ;;
            --mirror=*)
                MIRROR_WAS_SET=true
                MIRROR_MODE=${1#*=}
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                (($# == 0)) || die "不支持位置参数：$*"
                ;;
            *)
                die "未知参数：$1。使用 --help 查看帮助。"
                ;;
        esac
    done

    if [[ "$UNINSTALL" == true && "$MIRROR_WAS_SET" == true ]]; then
        die "--uninstall 不能与 --mirror 同时使用。"
    fi

    case "$MIRROR_MODE" in
        auto|direct|ghproxy|ghfast)
            ;;
        http://*|https://*)
            CUSTOM_MIRROR_PREFIX=$MIRROR_MODE
            MIRROR_MODE="custom"
            ;;
        "")
            die "镜像模式不能为空。"
            ;;
        *)
            die "无效的镜像模式：$MIRROR_MODE。自定义镜像必须以 http:// 或 https:// 开头。"
            ;;
    esac
}

require_linux() {
    local kernel_name
    kernel_name=$(uname -s 2>/dev/null || true)
    [[ "$kernel_name" == "Linux" ]] || die "该脚本仅支持 Linux，当前系统为：${kernel_name:-unknown}。"
}

append_unique() {
    local item=$1
    shift
    local existing

    for existing in "$@"; do
        [[ "$existing" == "$item" ]] && return 1
    done
    return 0
}

select_package_manager() {
    local manager
    for manager in apt-get dnf pacman zypper apk; do
        if command -v "$manager" >/dev/null 2>&1; then
            printf '%s\n' "$manager"
            return 0
        fi
    done
    return 1
}

package_for_command() {
    local command_name=$1

    case "$command_name" in
        curl)
            printf '%s\n' "curl"
            ;;
        tar)
            printf '%s\n' "tar"
            ;;
        grep)
            printf '%s\n' "grep"
            ;;
        gzip)
            printf '%s\n' "gzip"
            ;;
        find)
            printf '%s\n' "findutils"
            ;;
        cat|chmod|cut|head|install|mkdir|mktemp|mv|rm|tr|uname)
            printf '%s\n' "coreutils"
            ;;
        *)
            printf '%s\n' "$command_name"
            ;;
    esac
}

install_missing_dependencies() {
    local -a required_commands=(
        curl tar gzip grep cut find install mktemp head tr mkdir chmod mv rm cat uname
    )
    local -a missing_commands=()
    local -a packages=()
    local -a privilege=()
    local command_name package_name manager

    for command_name in "${required_commands[@]}"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            missing_commands+=("$command_name")
        fi
    done

    ((${#missing_commands[@]} == 0)) && return 0

    log_warn "缺少依赖：${missing_commands[*]}，准备尝试自动安装。"

    manager=$(select_package_manager) || die "未找到受支持的包管理器（apt/dnf/pacman/zypper/apk），请手动安装缺失依赖。"

    if ((EUID != 0)); then
        command -v sudo >/dev/null 2>&1 || die "安装系统依赖需要 root 权限，但当前系统未找到 sudo。"
        privilege=(sudo)
    fi

    for command_name in "${missing_commands[@]}"; do
        package_name=$(package_for_command "$command_name")
        if append_unique "$package_name" "${packages[@]}"; then
            packages+=("$package_name")
        fi
    done

    log_info "使用 $manager 安装软件包：${packages[*]}"
    case "$manager" in
        apt-get)
            "${privilege[@]}" apt-get update
            "${privilege[@]}" apt-get install -y "${packages[@]}"
            ;;
        dnf)
            "${privilege[@]}" dnf install -y "${packages[@]}"
            ;;
        pacman)
            "${privilege[@]}" pacman -Sy --noconfirm --needed "${packages[@]}"
            ;;
        zypper)
            "${privilege[@]}" zypper --non-interactive install -y "${packages[@]}"
            ;;
        apk)
            "${privilege[@]}" apk add --no-cache "${packages[@]}"
            ;;
        *)
            die "内部错误：不支持的包管理器 $manager。"
            ;;
    esac

    for command_name in "${required_commands[@]}"; do
        command -v "$command_name" >/dev/null 2>&1 || die "依赖安装后仍找不到命令：$command_name。"
    done
}

detect_architecture() {
    local machine
    machine=$(uname -m)

    case "$machine" in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="aarch64"
            ;;
        armv7l|armv7)
            ARCH="armv7l"
            ;;
        *)
            die "不支持的 CPU 架构：$machine。目前支持 x86_64、aarch64、armv7l。"
            ;;
    esac

    ASSET_NAME="fastfetch-linux-${ARCH}.tar.gz"
    log_info "检测到系统架构：$machine -> $ARCH"
}

determine_install_path() {
    if ((EUID == 0)); then
        INSTALL_DIR="/usr/local/bin"
    else
        [[ -n "${HOME:-}" ]] || die "无法确定用户主目录：HOME 未设置。"
        INSTALL_DIR="$HOME/.local/bin"
    fi

    TARGET_PATH="$INSTALL_DIR/fastfetch"
}

prepare_install_directory() {
    mkdir -p -- "$INSTALL_DIR"
    log_info "安装目标：$TARGET_PATH"
}

uninstall_fastfetch() {
    local path_fastfetch=""
    local remaining_fastfetch=""
    local version=""

    log_info "卸载目标：$TARGET_PATH"

    if [[ ! -e "$TARGET_PATH" && ! -L "$TARGET_PATH" ]]; then
        log_warn "未在目标位置发现 Fastfetch：$TARGET_PATH"

        path_fastfetch=$(command -v fastfetch 2>/dev/null || true)
        if [[ -n "$path_fastfetch" && "$path_fastfetch" != "$TARGET_PATH" ]]; then
            log_warn "PATH 中仍存在另一个 Fastfetch：$path_fastfetch"
            log_warn "该文件不属于本次卸载目标，未进行删除。"
        fi
        return 0
    fi

    if [[ -d "$TARGET_PATH" && ! -L "$TARGET_PATH" ]]; then
        die "卸载目标是目录而不是文件，拒绝删除：$TARGET_PATH"
    fi

    if [[ -x "$TARGET_PATH" ]]; then
        version=$(extract_version_from_binary "$TARGET_PATH")
        if [[ -n "$version" ]]; then
            log_info "检测到 Fastfetch 版本：$version"
        else
            log_warn "无法读取目标文件的 Fastfetch 版本号，但仍将按 --uninstall 请求删除该文件。"
        fi
    fi

    rm -f -- "$TARGET_PATH" || die "无法删除 Fastfetch：$TARGET_PATH"

    if [[ -e "$TARGET_PATH" || -L "$TARGET_PATH" ]]; then
        die "卸载失败，目标文件仍然存在：$TARGET_PATH"
    fi

    log_success "已卸载 Fastfetch：$TARGET_PATH"
    log_info "Fastfetch 配置文件未删除。"

    remaining_fastfetch=$(command -v fastfetch 2>/dev/null || true)
    if [[ -n "$remaining_fastfetch" && "$remaining_fastfetch" != "$TARGET_PATH" ]]; then
        log_warn "PATH 中仍存在另一个 Fastfetch：$remaining_fastfetch"
    fi
}

build_url_with_prefix() {
    local prefix=$1
    local original_url=$2

    if [[ -z "$prefix" ]]; then
        printf '%s\n' "$original_url"
        return 0
    fi

    while [[ "$prefix" == */ ]]; do
        prefix=${prefix%/}
    done

    printf '%s/%s\n' "$prefix" "$original_url"
}

prefix_label() {
    local prefix=$1

    case "$prefix" in
        "")
            printf '%s\n' "GitHub 直连"
            ;;
        "$GH_PROXY_PREFIX")
            printf '%s\n' "gh-proxy.com"
            ;;
        "$GHFAST_PREFIX")
            printf '%s\n' "ghfast.top"
            ;;
        *)
            printf '%s\n' "$prefix"
            ;;
    esac
}

load_prefix_candidates() {
    PREFIX_CANDIDATES=()

    case "$MIRROR_MODE" in
        auto)
            PREFIX_CANDIDATES=("" "$GH_PROXY_PREFIX" "$GHFAST_PREFIX")
            ;;
        direct)
            PREFIX_CANDIDATES=("")
            ;;
        ghproxy)
            PREFIX_CANDIDATES=("$GH_PROXY_PREFIX")
            ;;
        ghfast)
            PREFIX_CANDIDATES=("$GHFAST_PREFIX")
            ;;
        custom)
            PREFIX_CANDIDATES=("$CUSTOM_MIRROR_PREFIX")
            ;;
        *)
            die "内部错误：未知镜像模式 $MIRROR_MODE。"
            ;;
    esac
}

fetch_release_metadata() {
    local prefix api_url label http_code

    API_JSON_FILE="$TMP_DIR/release.json"
    load_prefix_candidates

    for prefix in "${PREFIX_CANDIDATES[@]}"; do
        api_url=$(build_url_with_prefix "$prefix" "$GITHUB_API_URL")
        label=$(prefix_label "$prefix")
        log_info "探测版本 API：$label"

        http_code=$(
            curl --silent --show-error --location \
                --connect-timeout 5 --max-time 20 \
                --retry 1 --retry-delay 1 \
                --header 'Accept: application/vnd.github+json' \
                --header 'X-GitHub-Api-Version: 2022-11-28' \
                --user-agent '$0' \
                --output "$API_JSON_FILE" \
                --write-out '%{http_code}' \
                "$api_url" 2>/dev/null || true
        )

        if [[ "$http_code" == "200" ]] && grep -q '"tag_name"' "$API_JSON_FILE"; then
            log_success "版本 API 可用：$label"
            return 0
        fi

        if [[ "$http_code" == "403" ]]; then
            log_warn "$label 返回 HTTP 403，可能触发 GitHub API 限流或被网络策略拦截。"
        else
            log_warn "$label API 探测失败（HTTP ${http_code:-000}）。"
        fi
    done

    die "无法从 GitHub 或指定镜像获取 Fastfetch 最新版本信息。"
}

parse_release_metadata() {
    local asset_url=""

    if command -v jq >/dev/null 2>&1; then
        log_info "使用 jq 解析 GitHub Release JSON。"
        REMOTE_TAG=$(jq -r '.tag_name // empty' "$API_JSON_FILE")
        asset_url=$(
            jq -r --arg asset "$ASSET_NAME" \
                '.assets[]? | select(.name == $asset) | .browser_download_url' \
                "$API_JSON_FILE" | head -n 1
        )
    else
        log_info "未检测到 jq，使用 grep + cut 解析 GitHub Release JSON。"
        REMOTE_TAG=$(
            tr ',' '\n' < "$API_JSON_FILE" \
                | grep -m 1 '"tag_name"' \
                | cut -d '"' -f 4 \
                || true
        )
        asset_url=$(
            tr ',' '\n' < "$API_JSON_FILE" \
                | grep '"browser_download_url"' \
                | grep -F "/${ASSET_NAME}\"" \
                | head -n 1 \
                | cut -d '"' -f 4 \
                || true
        )
    fi

    [[ -n "$REMOTE_TAG" && "$REMOTE_TAG" != "null" ]] || die "无法从 API 响应中解析最新版本号。"

    REMOTE_VERSION=${REMOTE_TAG#v}
    REMOTE_VERSION=${REMOTE_VERSION#V}

    if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
        log_warn "API 响应中未找到 $ASSET_NAME，改用标准 Release 下载地址。"
        asset_url="https://github.com/${REPOSITORY}/releases/download/${REMOTE_TAG}/${ASSET_NAME}"
    fi

    DOWNLOAD_URL=$asset_url
    log_info "远程最新版本：$REMOTE_VERSION"
}

extract_version_from_binary() {
    local binary_path=$1
    local version_output version_number

    version_output=$("$binary_path" --version 2>/dev/null || true)
    version_number=$(
        printf '%s\n' "$version_output" \
            | grep -Eo '[vV]?[0-9]+([.][0-9]+){1,3}' \
            | head -n 1 \
            | tr -d 'vV' \
            || true
    )
    printf '%s\n' "$version_number"
}

is_elf_binary() {
    local file_path=$1
    local magic=""

    [[ -f "$file_path" ]] || return 1
    IFS= read -r -N 4 magic < "$file_path" || true
    [[ "$magic" == $'\x7fELF' ]]
}

find_extracted_fastfetch_binary() {
    local extract_root=$1
    local candidate relative_path

    # 官方 tar 包的主程序通常位于 */usr/bin/fastfetch。优先搜索该路径，
    # 避免误选 */bash-completion/completions/fastfetch 等同名脚本。
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        if is_elf_binary "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi

        relative_path=${candidate#"$extract_root"/}
        log_warn "忽略同名但不是 ELF 二进制的文件：$relative_path"
    done < <(
        find "$extract_root" -type f -path '*/usr/bin/fastfetch' -print
        find "$extract_root" -type f -name 'fastfetch' ! -path '*/usr/bin/fastfetch' -print
    )

    return 1
}

show_candidate_version_output() {
    local binary_path=$1
    local output exit_status

    if output=$("$binary_path" --version 2>&1); then
        exit_status=0
    else
        exit_status=$?
    fi

    printf '%s\n' '----- 解压出的 fastfetch --version 输出开始 -----' >&2
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" >&2
    else
        printf '%s\n' '(命令没有产生任何输出)' >&2
    fi
    printf '%s\n' '----- 解压出的 fastfetch --version 输出结束 -----' >&2

    return "$exit_status"
}

show_fastfetch_v_output() {
    local binary_path=$1
    local version_output exit_status

    log_info "尝试运行以下命令以展示旧程序的实际输出：$binary_path -v"
    if version_output=$("$binary_path" -v 2>&1); then
        exit_status=0
    else
        exit_status=$?
    fi

    printf '%s\n' '----- fastfetch -v 输出开始 -----' >&2
    if [[ -n "$version_output" ]]; then
        printf '%s\n' "$version_output" >&2
    else
        printf '%s\n' '(命令没有产生任何输出)' >&2
    fi
    printf '%s\n' '----- fastfetch -v 输出结束 -----' >&2

    if ((exit_status != 0)); then
        log_warn "fastfetch -v 返回非零状态：$exit_status"
    fi
}

confirm_remove_and_reinstall() {
    local binary_path=$1
    local answer

    if [[ ! -t 0 ]]; then
        die "无法解析现有 Fastfetch 的版本号，且当前不是交互式终端，不能确认是否删除旧文件。请在交互式终端中重新运行脚本。"
    fi

    while true; do
        printf '是否尝试移除旧文件 %s，并重新安装 Fastfetch（覆盖安装）？[y/N] '             "$binary_path" >&2
        if ! IFS= read -r answer; then
            answer=""
        fi

        case "$answer" in
            y|Y|yes|YES|Yes)
                break
                ;;
            n|N|no|NO|No|"")
                log_warn "用户取消覆盖安装，未对旧文件进行修改。"
                exit 0
                ;;
            *)
                log_warn "请输入 y 或 n。"
                ;;
        esac
    done

    if rm -f -- "$binary_path" 2>/dev/null; then
        :
    elif ((EUID != 0)) && command -v sudo >/dev/null 2>&1; then
        log_info "直接删除失败，尝试使用 sudo 移除旧文件。"
        sudo rm -f -- "$binary_path"
    else
        die "无法移除旧文件：$binary_path。请检查文件权限后重试。"
    fi

    if [[ -e "$binary_path" || -L "$binary_path" ]]; then
        die "旧文件仍然存在，无法继续覆盖安装：$binary_path"
    fi

    log_success "已移除旧文件：$binary_path"
    LOCAL_BINARY=""
    LOCAL_VERSION=""
}

detect_local_version() {
    local installed_binary=""

    if [[ -x "$TARGET_PATH" ]]; then
        installed_binary=$TARGET_PATH
    elif command -v fastfetch >/dev/null 2>&1; then
        installed_binary=$(command -v fastfetch)
    fi

    if [[ -n "$installed_binary" ]]; then
        LOCAL_BINARY=$installed_binary

        if ! is_elf_binary "$installed_binary"; then
            log_warn "检测到名为 fastfetch 的文件，但它不是 Linux ELF 二进制：$installed_binary"
            show_fastfetch_v_output "$installed_binary"
            confirm_remove_and_reinstall "$installed_binary"
            return 0
        fi

        LOCAL_VERSION=$(extract_version_from_binary "$installed_binary")
        if [[ -n "$LOCAL_VERSION" ]]; then
            log_info "已安装版本：$LOCAL_VERSION（$installed_binary）"
        else
            log_warn "检测到 Fastfetch ELF 文件，但无法解析其版本号：$installed_binary"
            show_fastfetch_v_output "$installed_binary"
            confirm_remove_and_reinstall "$installed_binary"
        fi
    else
        log_info "未检测到已安装的 Fastfetch。"
    fi
}

select_download_channel() {
    local prefix candidate_url label

    load_prefix_candidates

    for prefix in "${PREFIX_CANDIDATES[@]}"; do
        candidate_url=$(build_url_with_prefix "$prefix" "$DOWNLOAD_URL")
        label=$(prefix_label "$prefix")
        log_info "探测文件下载通道：$label"

        if curl --fail --silent --show-error --location \
            --range 0-0 \
            --connect-timeout 5 --max-time 20 \
            --retry 1 --retry-delay 1 \
            --user-agent '$0' \
            --output /dev/null \
            "$candidate_url" 2>/dev/null; then
            DOWNLOAD_URL=$candidate_url
            log_success "文件下载通道可用：$label"
            return 0
        fi

        log_warn "$label 下载探测失败。"
    done

    die "无法通过 GitHub 或指定镜像下载 $ASSET_NAME。"
}

download_and_install() {
    local archive_path extract_dir binary_path=""
    local relative_path extracted_version staged_version

    archive_path="$TMP_DIR/$ASSET_NAME"
    extract_dir="$TMP_DIR/extracted"
    mkdir -p -- "$extract_dir"

    log_info "正在下载：$DOWNLOAD_URL"
    curl --fail --show-error --location \
        --connect-timeout 10 --max-time 300 \
        --retry 3 --retry-delay 2 \
        --user-agent '$0' \
        --output "$archive_path" \
        "$DOWNLOAD_URL"

    [[ -s "$archive_path" ]] || die "下载完成，但文件为空：$archive_path"

    log_info "正在解压安装包。"
    tar -xzf "$archive_path" -C "$extract_dir"

    binary_path=$(find_extracted_fastfetch_binary "$extract_dir" || true)
    [[ -n "$binary_path" ]] || die "解压后未找到有效的 Fastfetch ELF 二进制文件。"

    relative_path=${binary_path#"$extract_dir"/}
    log_info "选中主程序：$relative_path"

    chmod 0755 "$binary_path"
    extracted_version=$(extract_version_from_binary "$binary_path")
    if [[ -z "$extracted_version" ]]; then
        show_candidate_version_output "$binary_path" || true
        die "解压出的文件虽然是 ELF，但无法运行或无法读取 Fastfetch 版本号；未覆盖现有文件。"
    fi

    if [[ "$extracted_version" != "$REMOTE_VERSION" ]]; then
        die "安装包内 Fastfetch 版本为 $extracted_version，与预期版本 $REMOTE_VERSION 不一致；未覆盖现有文件。"
    fi

    # 先写入同目录临时文件并完成校验，最后再原子替换目标文件，
    # 避免下载包异常时破坏原有 Fastfetch。
    STAGED_PATH=$(mktemp "$INSTALL_DIR/.fastfetch.install.XXXXXX")
    install -m 0755 "$binary_path" "$STAGED_PATH"

    if ! is_elf_binary "$STAGED_PATH"; then
        die "复制后的暂存文件不是有效的 ELF 二进制；未覆盖现有文件。"
    fi

    staged_version=$(extract_version_from_binary "$STAGED_PATH")
    if [[ "$staged_version" != "$REMOTE_VERSION" ]]; then
        die "暂存文件版本校验失败（读取到：${staged_version:-空}）；未覆盖现有文件。"
    fi

    mv -f -- "$STAGED_PATH" "$TARGET_PATH"
    STAGED_PATH=""

    [[ -x "$TARGET_PATH" ]] || die "安装校验失败：$TARGET_PATH 不存在或不可执行。"
    is_elf_binary "$TARGET_PATH" || die "安装校验失败：$TARGET_PATH 不是 ELF 二进制文件。"
}

check_path_and_print_hint() {
    local shell_name profile_file export_command

    case ":${PATH:-}:" in
        *":$INSTALL_DIR:"*)
            log_success "$INSTALL_DIR 已位于 PATH 中。"
            return 0
            ;;
    esac

    log_warn "$INSTALL_DIR 当前不在 PATH 中。"
    shell_name=${SHELL:-}
    shell_name=${shell_name##*/}

    if [[ "$INSTALL_DIR" == "${HOME:-}/.local/bin" ]]; then
        export_command="export PATH=\"\$HOME/.local/bin:\$PATH\""
    else
        export_command="export PATH=\"$INSTALL_DIR:\$PATH\""
    fi

    if [[ -z "${HOME:-}" ]]; then
        printf '请在 Shell 配置文件中加入：\n  %s\n' "$export_command" >&2
        return 0
    fi

    case "$shell_name" in
        zsh)
            profile_file="$HOME/.zshrc"
            ;;
        fish)
            printf '请执行以下命令将安装目录加入 PATH：\n  fish_add_path %q\n' "$INSTALL_DIR" >&2
            return 0
            ;;
        bash)
            profile_file="$HOME/.bashrc"
            ;;
        *)
            profile_file="$HOME/.profile"
            ;;
    esac

    printf '请执行以下命令将安装目录加入 PATH：\n' >&2
    printf '  printf '\''%%s\\n'\'' '\''%s'\'' >> %q\n' "$export_command" "$profile_file" >&2
    printf '  source %q\n' "$profile_file" >&2
}

verify_installation() {
    local installed_version

    installed_version=$(extract_version_from_binary "$TARGET_PATH")
    [[ -n "$installed_version" ]] || die "Fastfetch 已复制到目标位置，但无法正常读取版本号。"

    log_success "Fastfetch $installed_version 已安装到 $TARGET_PATH"
    check_path_and_print_hint

    log_info "正在运行 Fastfetch："
    if ! "$TARGET_PATH"; then
        log_warn "Fastfetch 已安装，但自动运行返回了非零状态。可稍后手动执行：$TARGET_PATH"
    fi
}

main() {
    init_colors
    parse_args "$@"
    require_linux
    determine_install_path

    if [[ "$UNINSTALL" == true ]]; then
        uninstall_fastfetch
        return 0
    fi

    install_missing_dependencies
    detect_architecture
    prepare_install_directory

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/install-fastfetch.XXXXXX")

    fetch_release_metadata
    parse_release_metadata
    detect_local_version

    if [[ -n "$LOCAL_VERSION" && "$LOCAL_VERSION" == "$REMOTE_VERSION" ]]; then
        log_success "当前已是最新版本 $LOCAL_VERSION，无需下载。"
        if [[ "$LOCAL_BINARY" == "$TARGET_PATH" ]]; then
            check_path_and_print_hint
        fi
        log_info "正在运行 Fastfetch："
        "$LOCAL_BINARY" || log_warn "Fastfetch 自动运行返回了非零状态。"
        return 0
    fi

    if [[ -n "$LOCAL_VERSION" ]]; then
        log_info "准备更新：$LOCAL_VERSION -> $REMOTE_VERSION"
    else
        log_info "准备安装 Fastfetch $REMOTE_VERSION"
    fi

    select_download_channel
    download_and_install
    verify_installation
}

main "$@"
