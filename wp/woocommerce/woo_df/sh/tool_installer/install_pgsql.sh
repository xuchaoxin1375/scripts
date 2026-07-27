#!/usr/bin/env bash
#
# install_pgsql.sh - 在 Debian/Ubuntu 上安装 PostgreSQL
#
# 实现依据（访问日期：2026-07-27）：
#   https://www.postgresql.org/download/linux/debian/
#   https://www.postgresql.org/download/linux/ubuntu/
#   https://apt.postgresql.org/
#
# 脚本默认配置 PostgreSQL Global Development Group (PGDG) 官方 APT 仓库，
# 使用官方 ASCII 签名密钥和 deb822 格式的软件源。也可以通过
# --source distro 仅使用 Debian/Ubuntu 自带的软件仓库。
#
# 安全边界：本脚本不会删除数据库、集群或配置文件，也不会修改数据库密码、
# postgresql.conf 或 pg_hba.conf。重复运行时，仅更新本脚本管理的 PGDG 源文件；
# 如果发现内容不同的既有源文件，会先创建带时间戳的备份。
#
# 默认组件说明：server 模式安装 postgresql[-VERSION] 服务端包。Debian/Ubuntu
# 会通过包依赖同时安装相同版本的命令行客户端、libpq 运行库、postgresql-common
# 集群管理工具，以及 SSL、时区和语言环境等运行依赖。安装过程通常会创建
# VERSION/main 集群和 postgres 系统用户，并由 postgresql.service 管理服务。
# 脚本不安装图形界面、第三方扩展或开发头文件，除非用户显式要求相关包。

set -Eeuo pipefail
IFS=$'\n\t'

readonly PROGRAM_NAME=${0##*/}
readonly DEFAULT_REPO_URL="https://apt.postgresql.org/pub/repos/apt"
readonly DEFAULT_KEY_URL="https://www.postgresql.org/media/keys/ACCC4CF8.asc"
readonly PGDG_SOURCE_FILE="/etc/apt/sources.list.d/pgdg.sources"
readonly PGDG_KEY_FILE="/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc"

SOURCE="pgdg"
PG_VERSION="auto"
INSTALL_MODE="server"
REPO_URL=$DEFAULT_REPO_URL
KEY_URL=$DEFAULT_KEY_URL
CODENAME=""
ARCHITECTURE=""
APT_PROXY=""
WITH_CONTRIB=0
WITH_DOCS=0
WITH_DEV=0
ENABLE_SERVICE=1
START_SERVICE=1
ASSUME_YES=0
DRY_RUN=0
SKIP_APT_UPDATE=0
REPO_ONLY=0
NO_INSTALL_RECOMMENDS=0
ALLOW_DERIVATIVE=0
ALLOW_INSECURE_HTTP=0
declare -a EXTRA_PACKAGES=()
declare -a ROOT_PREFIX=()
declare -a APT_OPTIONS=()
declare -a TEMP_FILES=()

usage() {
    cat <<'EOF'
用法：
  install_pgsql.sh [选项]

在 Debian 或 Ubuntu 上安装 PostgreSQL。默认启用 PGDG 官方 APT 仓库并安装
其当前稳定版服务端；使用 --version 可锁定大版本。

新手建议：
  默认服务端组件足以用于学习、开发和普通应用。为了避免将来 PGDG 元包跟随
  新的大版本，建议明确锁定版本，例如：

  sudo ./install_pgsql.sh --version 18 --yes

默认 server 模式包含：
  * PostgreSQL 数据库服务器及 postgresql.service 服务
  * 同版本命令行客户端 psql
  * pg_dump、pg_restore、pg_basebackup 等备份恢复工具
  * pg_ctlcluster、pg_lsclusters 等 Debian/Ubuntu 集群管理工具
  * libpq 运行库，以及 SSL、时区和语言环境等必要依赖
  * 通常自动创建的 VERSION/main 集群、postgres 系统用户和 postgres 数据库
  * 当前 Debian/Ubuntu 包提供的标准 contrib 扩展文件

默认不包含或不执行：
  * pgAdmin 等图形化管理工具
  * PostGIS、TimescaleDB、pgvector 等第三方扩展
  * 离线文档和用于编译扩展的开发头文件
  * 数据库密码设置、业务用户或业务数据库创建
  * 远程访问设置，以及 postgresql.conf、pg_hba.conf 的修改

默认连接行为：
  新建集群通常仅监听本机 5432 端口，本地管理员可通过系统用户 postgres 登录。
  实际监听地址和认证规则以 postgresql.conf、pg_hba.conf 为准。

核心选项：
  -v, --version VERSION       PostgreSQL 大版本（如 16、17、18）或 auto（默认）
  -s, --source SOURCE         软件源：pgdg（默认）或 distro（发行版自带）
  -m, --mode MODE             安装模式：server（默认）或 client
      --with-contrib          安装对应版本的 contrib 扩展包
      --with-docs             安装对应版本的离线文档包
      --with-dev              安装开发头文件；server 模式还安装服务端开发包
      --extra-package NAME    追加安装一个 APT 包，可重复指定
      --repo-only             只配置 PGDG 仓库，不安装 PostgreSQL

可选组件如何选择：
  --with-contrib  请求安装对应版本的标准扩展包。较新的 Debian/Ubuntu 包通常已
                  由服务端包提供这些文件；保留此选项用于跨版本兼容。
  --with-docs     安装离线 HTML 文档；能访问官网时通常不需要。
  --with-dev      安装 libpq 和服务端开发头文件；仅编译程序或扩展时需要。
  --mode client   只安装连接远程数据库所需的客户端，本机不运行数据库服务。
  --extra-package 安装脚本未内置的第三方或辅助 APT 包；使用前应确认包来源。

仓库与系统选项：
      --codename NAME         覆盖自动识别的发行版代号
      --architecture ARCH     覆盖 dpkg 架构（如 amd64、arm64、ppc64el）
      --repo-url URL          覆盖 PGDG 仓库地址
      --key-url URL           覆盖 PGDG 签名密钥地址
      --proxy URL             为 curl 和 APT 使用 HTTP/HTTPS 代理
      --skip-apt-update       不执行安装前的 apt-get update
      --no-install-recommends 不安装 APT 推荐包
      --allow-derivative      允许在 Debian/Ubuntu 衍生发行版上运行
      --allow-insecure-http   允许自定义仓库或密钥使用 HTTP（不推荐）

服务与执行选项：
      --no-start              安装完成后停止 PostgreSQL 服务
      --no-enable             不设置开机启动，并在安装后禁用服务
  -y, --yes                   非交互安装，向 APT 传递 -y
  -n, --dry-run               仅显示将执行的操作，不修改系统
  -h, --help                  显示本帮助

示例：
  # 从 PGDG 安装当前稳定版服务端（适合临时测试）
  sudo ./install_pgsql.sh --yes

  # 固定安装 PostgreSQL 18（推荐用于长期使用）
  sudo ./install_pgsql.sh --version 18 --yes

  # 安装 PostgreSQL 17、contrib 和开发文件（用于编译扩展）
  sudo ./install_pgsql.sh --version 17 --with-contrib --with-dev --yes

  # 使用 Ubuntu/Debian 自带版本
  sudo ./install_pgsql.sh --source distro --yes

  # 仅安装 18 版客户端，并使用代理
  ./install_pgsql.sh -v 18 --mode client --proxy http://127.0.0.1:7890 -y

  # 查看完整执行计划，不进行任何修改
  ./install_pgsql.sh --version 18 --with-docs --dry-run

安装后检查：
  pg_lsclusters                    # 查看集群、端口和运行状态
  sudo systemctl status postgresql # 查看 systemd 服务状态
  sudo -u postgres psql            # 以数据库管理员身份进入 psql

  在 psql 中输入 \q 并回车即可退出。脚本不会自动设置 postgres 数据库密码。

说明：
  * VERSION=auto 时安装 postgresql 或 postgresql-client 元包；具体大版本由所选
    仓库决定。需要可重复部署时，应明确指定大版本。
  * --source distro 的可用版本取决于发行版，不保证每个大版本都存在。
  * Debian 的 APT 安装过程通常会自动创建 main 集群。--no-start 会在安装后
    停止服务，但无法保证安装过程中从未短暂启动。脚本不会删除该集群。
  * 可通过标准环境变量 DEBIAN_FRONTEND、http_proxy、https_proxy 控制底层工具。
EOF
}

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

quote_command() {
    printf '  '
    printf '%q ' "$@"
    printf '\n'
}

run() {
    if ((DRY_RUN)); then
        quote_command "$@"
    else
        "$@"
    fi
}

run_root() {
    run "${ROOT_PREFIX[@]}" "$@"
}

cleanup() {
    local file
    for file in "${TEMP_FILES[@]}"; do
        [[ -n $file && -e $file ]] && rm -f -- "$file"
    done
}

on_error() {
    local exit_code=$?
    local line_no=$1

    # ERR 会被 errtrace 继承到命令替换；仅由最外层 shell 输出一次错误。
    if ((BASH_SUBSHELL > 0)); then
        return "$exit_code"
    fi
    printf '[ERROR] 第 %s 行执行失败（退出码 %s）。\n' "$line_no" "$exit_code" >&2
    exit "$exit_code"
}

trap cleanup EXIT
trap 'on_error "$LINENO"' ERR

require_value() {
    (($# >= 2)) || die "选项 $1 缺少参数；请运行 --help 查看用法。"
}

parse_args() {
    while (($#)); do
        case $1 in
            -v | --version)
                require_value "$@"
                PG_VERSION=$2
                shift 2
                ;;
            -s | --source)
                require_value "$@"
                SOURCE=$2
                shift 2
                ;;
            -m | --mode)
                require_value "$@"
                INSTALL_MODE=$2
                shift 2
                ;;
            --with-contrib)
                WITH_CONTRIB=1
                shift
                ;;
            --with-docs)
                WITH_DOCS=1
                shift
                ;;
            --with-dev)
                WITH_DEV=1
                shift
                ;;
            --extra-package)
                require_value "$@"
                EXTRA_PACKAGES+=("$2")
                shift 2
                ;;
            --repo-only)
                REPO_ONLY=1
                shift
                ;;
            --codename)
                require_value "$@"
                CODENAME=$2
                shift 2
                ;;
            --architecture)
                require_value "$@"
                ARCHITECTURE=$2
                shift 2
                ;;
            --repo-url)
                require_value "$@"
                REPO_URL=${2%/}
                shift 2
                ;;
            --key-url)
                require_value "$@"
                KEY_URL=$2
                shift 2
                ;;
            --proxy)
                require_value "$@"
                APT_PROXY=$2
                shift 2
                ;;
            --skip-apt-update)
                SKIP_APT_UPDATE=1
                shift
                ;;
            --no-install-recommends)
                NO_INSTALL_RECOMMENDS=1
                shift
                ;;
            --allow-derivative)
                ALLOW_DERIVATIVE=1
                shift
                ;;
            --allow-insecure-http)
                ALLOW_INSECURE_HTTP=1
                shift
                ;;
            --no-start)
                START_SERVICE=0
                shift
                ;;
            --no-enable)
                ENABLE_SERVICE=0
                shift
                ;;
            -y | --yes)
                ASSUME_YES=1
                shift
                ;;
            -n | --dry-run)
                DRY_RUN=1
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            --)
                shift
                (($# == 0)) || die "不接受位置参数：$*"
                ;;
            -*) die "未知选项：$1；请运行 --help 查看用法。" ;;
            *) die "不接受位置参数：$1" ;;
        esac
    done
}

validate_options() {
    [[ $SOURCE == pgdg || $SOURCE == distro ]] || die "--source 只能是 pgdg 或 distro。"
    [[ $INSTALL_MODE == server || $INSTALL_MODE == client ]] || die "--mode 只能是 server 或 client。"
    [[ $PG_VERSION == auto || $PG_VERSION =~ ^[0-9]{1,2}$ ]] || die "--version 必须是大版本数字或 auto。"
    [[ -z $CODENAME || $CODENAME =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "无效的发行版代号：$CODENAME"
    [[ -z $ARCHITECTURE || $ARCHITECTURE =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "无效的架构：$ARCHITECTURE"

    local package
    for package in "${EXTRA_PACKAGES[@]}"; do
        [[ $package =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9][a-z0-9_-]*)?$ ]] || die "无效的 APT 包名：$package"
    done

    if [[ -n $APT_PROXY && ! $APT_PROXY =~ ^https?://[^[:space:]]+$ ]]; then
        die "--proxy 必须是 HTTP/HTTPS URL。"
    fi

    if ((ALLOW_INSECURE_HTTP == 0)); then
        [[ $REPO_URL == https://* ]] || die "仓库 URL 必须使用 HTTPS；确有需要时指定 --allow-insecure-http。"
        [[ $KEY_URL == https://* ]] || die "密钥 URL 必须使用 HTTPS；确有需要时指定 --allow-insecure-http。"
    fi

    ((REPO_ONLY == 0)) || [[ $SOURCE == pgdg ]] || die "--repo-only 只能与 --source pgdg 一起使用。"
}

load_os_release() {
    [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release，无法识别发行版。"

    # shellcheck disable=SC1091
    source /etc/os-release
    local detected_id=${ID:-}
    local detected_like=${ID_LIKE:-}

    if [[ $detected_id != debian && $detected_id != ubuntu ]]; then
        if ((ALLOW_DERIVATIVE)) && [[ " $detected_like " == *" debian "* ]]; then
            warn "检测到 Debian 衍生发行版 '$detected_id'；将使用其报告的 Debian 兼容信息。"
        else
            die "仅支持 Debian/Ubuntu（当前：${detected_id:-unknown}）；衍生版可尝试 --allow-derivative。"
        fi
    fi

    if [[ -z $CODENAME ]]; then
        CODENAME=${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}
    fi
    [[ -n $CODENAME ]] || die "无法识别发行版代号；请通过 --codename 显式指定。"

    log "检测到系统：${PRETTY_NAME:-$detected_id}，代号：$CODENAME"
}

prepare_environment() {
    command -v apt-get >/dev/null 2>&1 || die "未找到 apt-get。"
    command -v dpkg >/dev/null 2>&1 || die "未找到 dpkg。"

    if [[ -z $ARCHITECTURE ]]; then
        ARCHITECTURE=$(dpkg --print-architecture)
    fi

    if ((EUID == 0)); then
        ROOT_PREFIX=()
    elif command -v sudo >/dev/null 2>&1; then
        ROOT_PREFIX=(sudo)
    elif ((DRY_RUN)); then
        ROOT_PREFIX=(sudo)
        warn "未找到 sudo；dry-run 仍以 sudo 展示命令。实际执行需要 root。"
    else
        die "请以 root 运行，或安装 sudo 并确保当前用户具有 sudo 权限。"
    fi

    APT_OPTIONS=(
        -o Dpkg::Use-Pty=0
        -o DPkg::Lock::Timeout=120
    )
    if [[ -n $APT_PROXY ]]; then
        APT_OPTIONS+=(
            -o "Acquire::http::Proxy=$APT_PROXY"
            -o "Acquire::https::Proxy=$APT_PROXY"
        )
    fi
}

apt_get() {
    local -a command=(apt-get "${APT_OPTIONS[@]}")
    ((ASSUME_YES)) && command+=(-y)
    command+=("$@")
    run_root env DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}" "${command[@]}"
}

curl_download() {
    local url=$1
    local output=$2
    local -a command=(curl --fail --show-error --silent --location --retry 3 --connect-timeout 15)
    [[ -n $APT_PROXY ]] && command+=(--proxy "$APT_PROXY")
    command+=(--output "$output" "$url")
    run "${command[@]}"
}

check_pgdg_distribution() {
    local release_url="${REPO_URL}/dists/${CODENAME}-pgdg/Release"
    local -a command=(curl --fail --show-error --silent --location --head --retry 2 --connect-timeout 15)
    [[ -n $APT_PROXY ]] && command+=(--proxy "$APT_PROXY")
    command+=("$release_url")

    if ((DRY_RUN)); then
        quote_command "${command[@]}"
    elif ! "${command[@]}" >/dev/null; then
        die "PGDG 仓库不支持代号 '$CODENAME'，或无法访问：$release_url"
    fi
}

install_prerequisites() {
    log "安装仓库配置依赖：curl、ca-certificates"
    apt_get install curl ca-certificates
}

write_pgdg_source() {
    local source_content
    source_content=$(
        cat <<EOF
# Managed by $PROGRAM_NAME. Local edits may be replaced after a backup.
Types: deb
URIs: $REPO_URL
Suites: ${CODENAME}-pgdg
Architectures: $ARCHITECTURE
Components: main
Signed-By: $PGDG_KEY_FILE
EOF
    )

    if ((DRY_RUN)); then
        log "将写入 $PGDG_SOURCE_FILE："
        printf '%s\n' "$source_content"
        return
    fi

    local temp_file
    temp_file=$(mktemp)
    TEMP_FILES+=("$temp_file")
    printf '%s\n' "$source_content" >"$temp_file"

    if [[ -e $PGDG_SOURCE_FILE ]] && ! cmp -s "$temp_file" "$PGDG_SOURCE_FILE"; then
        local backup
        backup="${PGDG_SOURCE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
        warn "现有 PGDG 源配置不同，备份为 $backup"
        run_root cp --preserve=mode,ownership,timestamps -- "$PGDG_SOURCE_FILE" "$backup"
    fi

    if [[ ! -e $PGDG_SOURCE_FILE ]] || ! cmp -s "$temp_file" "$PGDG_SOURCE_FILE"; then
        run_root install -o root -g root -m 0644 "$temp_file" "$PGDG_SOURCE_FILE"
    else
        log "PGDG 源配置已是最新，无需修改。"
    fi
}

configure_pgdg_repository() {
    check_pgdg_distribution
    install_prerequisites

    log "下载 PostgreSQL 官方仓库签名密钥"
    if ((DRY_RUN)); then
        run_root install -d -o root -g root -m 0755 "${PGDG_KEY_FILE%/*}"
        curl_download "$KEY_URL" "/tmp/apt.postgresql.org.asc"
        quote_command "${ROOT_PREFIX[@]}" install -o root -g root -m 0644 /tmp/apt.postgresql.org.asc "$PGDG_KEY_FILE"
    else
        local key_temp
        key_temp=$(mktemp)
        TEMP_FILES+=("$key_temp")
        curl_download "$KEY_URL" "$key_temp"
        grep -q -- 'BEGIN PGP PUBLIC KEY BLOCK' "$key_temp" || die "下载内容不是有效的 ASCII PGP 公钥。"
        run_root install -d -o root -g root -m 0755 "${PGDG_KEY_FILE%/*}"
        if [[ ! -e $PGDG_KEY_FILE ]] || ! cmp -s "$key_temp" "$PGDG_KEY_FILE"; then
            run_root install -o root -g root -m 0644 "$key_temp" "$PGDG_KEY_FILE"
        else
            log "PGDG 签名密钥已是最新，无需修改。"
        fi
    fi

    write_pgdg_source
}

build_package_list() {
    declare -ga PACKAGES=()
    local suffix=""
    [[ $PG_VERSION != auto ]] && suffix="-$PG_VERSION"

    # server 包会通过 Debian/Ubuntu 包依赖带上同版本 client 和公共管理工具；
    # client 模式则只提供连接、备份和恢复工具，不创建本地数据库服务。
    if [[ $INSTALL_MODE == server ]]; then
        PACKAGES+=("postgresql${suffix}")
    else
        PACKAGES+=("postgresql-client${suffix}")
    fi

    # 新版本中 contrib 可能由 server 包直接 Provides；显式加入仍可让 APT
    # 在不同 Debian/Ubuntu/PostgreSQL 包版本间解析正确的提供者。
    ((WITH_CONTRIB)) && PACKAGES+=("postgresql-contrib${suffix}")
    ((WITH_DOCS)) && PACKAGES+=("postgresql-doc${suffix}")
    if ((WITH_DEV)); then
        # libpq-dev 用于客户端程序；server-dev 用于编译服务端 C 扩展。
        PACKAGES+=(libpq-dev)
        if [[ $INSTALL_MODE == server ]]; then
            if [[ $PG_VERSION == auto ]]; then
                PACKAGES+=(postgresql-server-dev-all)
            else
                PACKAGES+=("postgresql-server-dev${suffix}")
            fi
        fi
    fi
    PACKAGES+=("${EXTRA_PACKAGES[@]}")
}

update_package_index() {
    if ((SKIP_APT_UPDATE)); then
        warn "已按要求跳过 apt-get update；缓存过旧时可能无法找到软件包。"
    else
        log "更新 APT 软件包索引"
        apt_get update
    fi
}

verify_packages_available() {
    ((DRY_RUN)) && return
    local package candidate
    for package in "${PACKAGES[@]}"; do
        # 不在 awk 中提前退出，否则 pipefail 会把 apt-cache 的 SIGPIPE (141)
        # 当成安装检查失败。
        candidate=$(apt-cache policy -- "$package" | awk '/Candidate:/ && !found {candidate=$2; found=1} END {if (found) print candidate}')
        [[ -n $candidate && $candidate != '(none)' ]] || die "APT 中没有可安装的包 '$package'。请检查版本、发行版代号和软件源。"
    done
}

install_packages() {
    build_package_list
    log "准备安装软件包：${PACKAGES[*]}"
    verify_packages_available

    local -a install_args=(install)
    ((NO_INSTALL_RECOMMENDS)) && install_args+=(--no-install-recommends)
    install_args+=("${PACKAGES[@]}")
    apt_get "${install_args[@]}"
}

systemd_is_usable() {
    command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

configure_service() {
    [[ $INSTALL_MODE == server ]] || return 0

    if ! systemd_is_usable; then
        warn "当前环境未运行 systemd，跳过开机启动设置。"
        if ((START_SERVICE == 0)) && command -v pg_ctlcluster >/dev/null 2>&1; then
            local version cluster status
            while read -r version cluster _ _ status _; do
                [[ $status == online ]] && run_root pg_ctlcluster "$version" "$cluster" stop
            done < <(pg_lsclusters --no-header 2>/dev/null || true)
        elif ((START_SERVICE)); then
            warn "请使用 pg_ctlcluster 手动确认或启动 PostgreSQL 集群。"
        fi
        return
    fi

    if ((ENABLE_SERVICE)); then
        log "启用 PostgreSQL 开机启动"
        run_root systemctl enable postgresql.service
    else
        log "禁用 PostgreSQL 开机启动"
        run_root systemctl disable postgresql.service
    fi

    if ((START_SERVICE)); then
        log "启动 PostgreSQL 服务"
        run_root systemctl start postgresql.service
    else
        log "停止 PostgreSQL 服务"
        run_root systemctl stop postgresql.service
    fi
}

report_result() {
    if ((DRY_RUN)); then
        log "dry-run 完成：系统未被修改。"
        return
    fi

    if ((REPO_ONLY)); then
        log "PGDG 仓库配置完成：$PGDG_SOURCE_FILE"
        return
    fi

    local psql_version
    psql_version=$(psql --version 2>/dev/null || true)
    log "安装完成${psql_version:+：$psql_version}"
    if [[ $INSTALL_MODE == server ]] && command -v pg_lsclusters >/dev/null 2>&1; then
        pg_lsclusters || true
    fi
}

main() {
    parse_args "$@"
    validate_options
    load_os_release
    prepare_environment

    log "安装计划：source=$SOURCE, version=$PG_VERSION, mode=$INSTALL_MODE, arch=$ARCHITECTURE"
    if [[ $SOURCE == pgdg ]]; then
        configure_pgdg_repository
    fi

    update_package_index
    if ((REPO_ONLY == 0)); then
        install_packages
        configure_service
    fi
    report_result
}

main "$@"
