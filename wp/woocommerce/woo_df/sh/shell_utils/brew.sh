#!/usr/bin/env bash
# Homebrew 安装与管理函数，可由 Bash 和 Zsh source。
#
# 统一入口是 install_brew；install_brew_cn 只提供国内镜像默认值；
# install_linuxbrew 专用于 root 创建/使用隔离账号。网络来源、操作系统和运行
# 身份是三个独立维度，不应由包装函数暗中改变安装身份。
#
# 常用场景：
#   国外 Linux 服务器，当前是 root：
#     install_linuxbrew                 # 创建/使用 linuxbrew 用户
#     brewr install jq                  # root 借用该用户运行 brew
#
#   国内 Linux 或 macOS，当前是普通用户：
#     install_brew_cn --mirror ustc
#     install_brew_cn --mirror tuna --update-mirror-only
#     install_brew_cn --mirror official --update-mirror-only
#
# 也可以使用官方源配合代理。调用前设置 HTTPS_PROXY、HTTP_PROXY 或
# ALL_PROXY 即可；这些变量会在 root 通过 brewr 切换用户时被显式传递。
#
# Homebrew 的受支持前缀不是当前用户的家目录：Linux 使用
# /home/linuxbrew/.linuxbrew，Apple Silicon macOS 使用 /opt/homebrew，Intel
# macOS 使用 /usr/local。不要默认改装到 ~/.linuxbrew；非标准前缀可能无法
# 使用官方 bottle，导致大量软件从源码编译。Linux 普通用户安装到标准前缀
# 时通常需要 sudo；没有 sudo 时应明确失败，而不是悄悄换到家目录。

_brew_info() { printf '[brew] %s\n' "$*"; }
_brew_warn() { printf '[brew] warning: %s\n' "$*" >&2; }
_brew_error() { printf '[brew] error: %s\n' "$*" >&2; }

_brew_is_linux() { [ "$(uname -s 2>/dev/null)" = Linux ]; }
_brew_is_macos() { [ "$(uname -s 2>/dev/null)" = Darwin ]; }

_brew_need_command() {
    command -v "$1" >/dev/null 2>&1 || {
        _brew_error "required command not found: $1"
        return 1
    }
}

# Run an administrative command. Root does not need sudo; other users do.
_brew_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        command "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        _brew_error "this operation needs root privileges (sudo is unavailable)"
        return 1
    fi
}

_brew_user_home() {
    local target_user=$1 home_dir=''
    if command -v getent >/dev/null 2>&1; then
        home_dir=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    elif _brew_is_macos; then
        home_dir=$(dscl . -read "/Users/$target_user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    fi
    [ -n "$home_dir" ] || home_dir="/home/$target_user"
    printf '%s\n' "$home_dir"
}

_brew_find_binary() {
    local target_user=${1:-} user_home candidate path_brew
    if [ -z "$target_user" ]; then
        path_brew=$(command -v brew 2>/dev/null || true)
        if [ -n "$path_brew" ] && [ -x "$path_brew" ]; then
            printf '%s\n' "$path_brew"
            return 0
        fi
    fi
    [ -n "$target_user" ] && user_home=$(_brew_user_home "$target_user")
    for candidate in \
        "$user_home/.linuxbrew/bin/brew" \
        /home/linuxbrew/.linuxbrew/bin/brew \
        /opt/homebrew/bin/brew \
        /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

_brew_default_rc() {
    case "${SHELL##*/}" in
        zsh) printf '%s\n' "$HOME/.zshrc" ;;
        bash) printf '%s\n' "$HOME/.bashrc" ;;
        *)
            if _brew_is_macos; then
                printf '%s\n' "$HOME/.zprofile"
            else
                printf '%s\n' "$HOME/.profile"
            fi
            ;;
    esac
}

# Linux 的官方 bottle 只支持固定前缀。root 使用专用账号安装时，先以 root
# 准备这个目录，再降权运行安装器。已有且属于其他用户的前缀绝不自动 chown，
# 避免破坏另一套 Homebrew 安装。
_brew_prepare_linux_prefix() {
    local target_user=$1 prefix=/home/linuxbrew/.linuxbrew
    local prefix_parent=${prefix%/*} target_group
    _brew_is_linux || return 0
    target_group=$(id -gn "$target_user") || return 1

    if [ -e "$prefix" ]; then
        if find "$prefix" -maxdepth 0 -user "$target_user" -print 2>/dev/null | grep -q .; then
            return 0
        fi
        _brew_error "$prefix already exists and is not owned by $target_user"
        return 1
    fi
    if [ -e "$prefix_parent" ] &&
        ! find "$prefix_parent" -maxdepth 0 -user "$target_user" -print 2>/dev/null | grep -q .; then
        _brew_error "$prefix_parent already exists and is not owned by $target_user"
        return 1
    fi
    _brew_as_root install -d -o "$target_user" -g "$target_group" "$prefix_parent" || return
    _brew_as_root install -d -o "$target_user" -g "$target_group" "$prefix"
}

# 普通用户不能接管另一个用户拥有的标准前缀。尤其是 /home/linuxbrew 权限为
# 750 时，test -d 无法看到内部目录，安装器随后会在 cd 失败后产生误导性错误。
# 在联网下载安装器之前明确终止，并保留已有安装的所有权。
_brew_check_linux_prefix_access() {
    local prefix=/home/linuxbrew/.linuxbrew prefix_parent=/home/linuxbrew owner='unknown'
    _brew_is_linux || return 0
    [ "$(id -u)" -ne 0 ] || return 0

    if [ -e "$prefix_parent" ] && [ ! -x "$prefix_parent" ]; then
        owner=$(stat -c '%U' "$prefix_parent" 2>/dev/null || printf 'unknown')
        _brew_error "$prefix_parent is owned by $owner and is not accessible to $(id -un)"
        _brew_error "finish/use the dedicated installation as root with: install_linuxbrew; brewr ..."
        _brew_error 'to install as the current user, explicitly remove or transfer the existing dedicated installation first'
        return 1
    fi
    if [ -e "$prefix" ] && { [ ! -x "$prefix" ] || [ ! -w "$prefix" ]; }; then
        owner=$(stat -c '%U' "$prefix" 2>/dev/null || printf 'unknown')
        _brew_error "$prefix is owned by $owner and is not writable by $(id -un)"
        _brew_error 'refusing to take ownership of an existing Homebrew prefix automatically'
        return 1
    fi
    if [ ! -e "$prefix" ] && ! command -v sudo >/dev/null 2>&1; then
        _brew_error 'the standard Linux prefix needs root privileges, but sudo is unavailable'
        _brew_error 'Homebrew is not automatically installed into ~/.linuxbrew; see shell_utils/Readme.md'
        return 1
    fi
}

# Replace or remove a block delimited by exact marker lines. A temporary file is
# used so this works with both GNU sed (Linux) and BSD sed (macOS).
_brew_replace_block() {
    local target_file=$1 block_name=$2 content=${3-}
    local begin_marker="# >>> $block_name >>>"
    local end_marker="# <<< $block_name <<<"
    local temp_file

    mkdir -p "$(dirname "$target_file")" || return 1
    touch "$target_file" || return 1
    temp_file=$(mktemp "${TMPDIR:-/tmp}/brew-rc.XXXXXX") || return 1
    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { skip = 1; next }
        $0 == end { skip = 0; next }
        # Migrate blocks written by the previous brew.sh implementation.
        $0 == "# >>> brew mirror env" { skip = 1; next }
        $0 == "# <<< brew mirror env" { skip = 0; next }
        !skip { print }
    ' "$target_file" >"$temp_file" || {
        rm -f "$temp_file"
        return 1
    }
    if [ -n "$content" ]; then
        {
            printf '\n%s\n' "$begin_marker"
            printf '%s\n' "$content"
            printf '%s\n' "$end_marker"
        } >>"$temp_file"
    fi
    # Redirection preserves the ownership and mode of an existing rc file.
    if command cat "$temp_file" >"$target_file"; then
        rm -f "$temp_file"
    else
        rm -f "$temp_file"
        return 1
    fi
}

_brew_mirror_env() {
    case "$1" in
        official | github)
            return 0
            ;;
        ustc)
            printf '%s\n' \
                'export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"' \
                'export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"' \
                'export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"' \
                'export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"'
            ;;
        tuna)
            printf '%s\n' \
                'export HOMEBREW_INSTALL_FROM_API="1"' \
                'export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"' \
                'export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"' \
                'export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"' \
                'export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"' \
                'export HOMEBREW_PIP_INDEX_URL="https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple"'
            ;;
        aliyun)
            printf '%s\n' \
                'export HOMEBREW_INSTALL_FROM_API="1"' \
                'export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/brew.git"' \
                'export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/homebrew-core.git"' \
                'export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles"' \
                'export HOMEBREW_API_DOMAIN="https://mirrors.aliyun.com/homebrew-bottles/api"'
            ;;
        *)
            _brew_error "unknown mirror: $1 (expected official, ustc, tuna, or aliyun)"
            return 2
            ;;
    esac
}

_brew_export_mirror_env() {
    local mirror=$1 line name value
    unset_brew_envs
    [ "$mirror" = official ] || [ "$mirror" = github ] || {
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            name=${line#export }
            name=${name%%=*}
            value=${line#*=}
            value=${value#\"}
            value=${value%\"}
            export "$name=$value"
        done <<EOF
$(_brew_mirror_env "$mirror")
EOF
    }
}

_brew_installer_url() {
    case "$1" in
        official | github) printf '%s\n' 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' ;;
        ustc) printf '%s\n' 'https://mirrors.ustc.edu.cn/misc/brew-install.sh' ;;
        tuna) printf '%s\n' 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' ;;
        aliyun) printf '%s\n' 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' ;;
        *) _brew_error "unknown installer source: $1"; return 2 ;;
    esac
}

new_user_sudo() {
    local username=linuxbrew login_shell=/bin/bash
    local add_password=false random_password=false add_sudo=false passwordless_sudo=false
    local sudo_group sudo_file temp_file random_value

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                cat <<'EOF'
Usage: new_user_sudo [options] [username]

Create a Linux user idempotently. Despite the legacy function name, sudo
access is granted only when --addsudo is specified.

  -p, --addpasswd          run passwd interactively after creation
  -P, --set-random-pwd    generate and set a random password (printed once)
  -A, --addsudo           add the user to the sudo/wheel group
  -N, --no-sudo-password grant passwordless sudo (implies --addsudo)
  -s, --shell PATH        login shell (default: /bin/bash)
EOF
                return 0
                ;;
            -p | --addpwd | --addpasswd) add_password=true ;;
            -P | --set-random-pwd) random_password=true ;;
            -A | --addsudo) add_sudo=true ;;
            -N | --no-sudo-password) passwordless_sudo=true; add_sudo=true ;;
            -s | --shell)
                [ "$#" -ge 2 ] || { _brew_error "$1 needs a value"; return 2; }
                login_shell=$2
                shift
                ;;
            --) shift; break ;;
            -*) _brew_error "unknown option: $1"; return 2 ;;
            *) username=$1 ;;
        esac
        shift
    done

    _brew_is_linux || { _brew_error 'user creation is supported only on Linux'; return 1; }
    if id "$username" >/dev/null 2>&1; then
        _brew_info "user already exists: $username"
    elif command -v useradd >/dev/null 2>&1; then
        _brew_as_root useradd --create-home --shell "$login_shell" "$username" || return
    elif command -v adduser >/dev/null 2>&1; then
        _brew_as_root adduser --disabled-password --gecos '' --shell "$login_shell" "$username" || return
    else
        _brew_error 'neither useradd nor adduser is available'
        return 1
    fi

    if [ "$add_password" = true ]; then
        _brew_as_root passwd "$username" || return
    elif [ "$random_password" = true ]; then
        _brew_need_command openssl || return
        random_value=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)
        printf '%s:%s\n' "$username" "$random_value" | _brew_as_root chpasswd || return
        _brew_warn "temporary password for $username: $random_value"
    fi

    if [ "$add_sudo" = true ]; then
        if getent group sudo >/dev/null 2>&1; then sudo_group=sudo; else sudo_group=wheel; fi
        _brew_as_root usermod -aG "$sudo_group" "$username" || return
    fi
    if [ "$passwordless_sudo" = true ]; then
        _brew_need_command visudo || return
        temp_file=$(mktemp "${TMPDIR:-/tmp}/brew-sudoers.XXXXXX") || return 1
        printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$username" >"$temp_file"
        if ! visudo -c -f "$temp_file" >/dev/null; then
            rm -f "$temp_file"
            _brew_error 'generated sudoers rule failed validation'
            return 1
        fi
        sudo_file="/etc/sudoers.d/${username}_nopasswd"
        _brew_as_root install -o root -g root -m 0440 "$temp_file" "$sudo_file" || {
            rm -f "$temp_file"
            return 1
        }
        rm -f "$temp_file"
        _brew_warn "$username now has passwordless sudo via $sudo_file"
    fi
}

remove_user_safe() {
    local target_user=${1:-}
    [ -n "$target_user" ] || { _brew_error 'usage: remove_user_safe USER'; return 2; }
    [ "$target_user" != root ] || { _brew_error 'refusing to remove root'; return 1; }
    id "$target_user" >/dev/null 2>&1 || { _brew_info "user does not exist: $target_user"; return 0; }
    _brew_as_root pkill -u "$target_user" >/dev/null 2>&1 || true
    _brew_as_root userdel -r "$target_user"
}

# 清理早期方案创建的专用 linuxbrew 用户，为普通 sudo 用户按官方方式安装释放
# /home/linuxbrew 标准前缀。默认仅预览；执行时移动家目录而不是直接删除，便于
# 恢复。此函数刻意只处理用户名 linuxbrew 和家目录 /home/linuxbrew。
cleanup_linuxbrew_dedicated_user() {
    local execute=false target_user=linuxbrew expected_home=/home/linuxbrew
    local backup_dir='' account_entry='' actual_home='' process_list=''
    local timestamp

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                cat <<'EOF'
用法：cleanup_linuxbrew_dedicated_user [--execute] [--backup-dir PATH]

清理由旧版 root/专用用户方案创建的 linuxbrew 账号和 /home/linuxbrew，
从而允许当前普通 sudo 用户使用 Homebrew 官方标准安装流程。

默认只显示将执行的操作，不修改系统。--execute 将：
  1. 拒绝在 linuxbrew 仍有运行进程时继续；
  2. 将 /home/linuxbrew 移到带时间戳的备份目录；
  3. 删除 linuxbrew 账号及空的同名私有组；
  4. 删除本脚本创建的 linuxbrew_nopasswd sudoers 文件；
  5. 报告其他仍引用 linuxbrew 的 sudoers 文件。

备份不会自动删除。确认新安装正常后再由管理员手工处理。
EOF
                return 0
                ;;
            --execute) execute=true ;;
            --backup-dir)
                [ "$#" -ge 2 ] || { _brew_error '--backup-dir needs a value'; return 2; }
                backup_dir=$2
                shift
                ;;
            *) _brew_error "unknown option: $1"; return 2 ;;
        esac
        shift
    done

    _brew_is_linux || { _brew_error 'this cleanup is Linux-only'; return 1; }
    timestamp=$(date '+%Y%m%d-%H%M%S') || return 1
    [ -n "$backup_dir" ] || backup_dir="/home/linuxbrew.dedicated-backup-$timestamp"
    case "$backup_dir" in
        "$expected_home" | "$expected_home"/*)
            _brew_error 'backup directory must be outside /home/linuxbrew'
            return 2
            ;;
    esac
    [ ! -e "$backup_dir" ] || { _brew_error "backup path already exists: $backup_dir"; return 1; }

    if id "$target_user" >/dev/null 2>&1; then
        account_entry=$(getent passwd "$target_user") || return 1
        actual_home=$(printf '%s\n' "$account_entry" | cut -d: -f6)
        [ "$actual_home" = "$expected_home" ] || {
            _brew_error "refusing cleanup: $target_user home is $actual_home, expected $expected_home"
            return 1
        }
        process_list=$(ps -u "$target_user" -o pid=,cmd= 2>/dev/null || true)
        if [ -n "$process_list" ]; then
            _brew_error "$target_user still has running processes:"
            printf '%s\n' "$process_list" >&2
            return 1
        fi
    fi

    _brew_info "account: ${account_entry:-not present}"
    if [ -e "$expected_home" ]; then
        _brew_info "home will be moved: $expected_home -> $backup_dir"
    else
        _brew_info "home is not present: $expected_home"
    fi
    _brew_info 'known sudoers rule will be removed if present: /etc/sudoers.d/linuxbrew_nopasswd'
    if [ "$execute" != true ]; then
        _brew_info 'dry run only; review the paths, then rerun with --execute'
        return 0
    fi

    # Acquire credentials before the first state change.
    _brew_as_root true || return
    if [ -e "$expected_home" ]; then
        _brew_as_root mv -- "$expected_home" "$backup_dir" || return
    fi
    if id "$target_user" >/dev/null 2>&1; then
        if ! _brew_as_root userdel "$target_user"; then
            _brew_error 'userdel failed; attempting to restore the original home path'
            if [ -e "$backup_dir" ] && [ ! -e "$expected_home" ]; then
                _brew_as_root mv -- "$backup_dir" "$expected_home" || true
            fi
            return 1
        fi
    fi
    if [ -e "$backup_dir" ]; then
        _brew_as_root chown root:root "$backup_dir" || return
        _brew_as_root chmod 0700 "$backup_dir" || return
    fi
    if getent group "$target_user" >/dev/null 2>&1; then
        _brew_as_root groupdel "$target_user" || _brew_warn "group remains: $target_user"
    fi
    if [ -e /etc/sudoers.d/linuxbrew_nopasswd ]; then
        _brew_as_root rm -f /etc/sudoers.d/linuxbrew_nopasswd || return
    fi
    _brew_info 'checking for other sudoers references to linuxbrew...'
    _brew_as_root grep -RIl -- "$target_user" /etc/sudoers /etc/sudoers.d 2>/dev/null || true
    _brew_info "cleanup complete; recoverable home backup: $backup_dir"
    _brew_info 'next: run install_brew --mirror SOURCE as the normal sudo user'
}

set_brew_path_env_to_shellrc() {
    local remove=false reset=false rc_file='' brew_bin='' block_content
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                cat <<'EOF'
Usage: set_brew_path_env_to_shellrc [--remove|--reset] [--rc FILE] [--brew PATH]

Write one managed `brew shellenv` block to the current shell's rc file.
EOF
                return 0
                ;;
            --remove) remove=true ;;
            --reset) reset=true ;;
            --rc) [ "$#" -ge 2 ] || return 2; rc_file=$2; shift ;;
            --brew) [ "$#" -ge 2 ] || return 2; brew_bin=$2; shift ;;
            *) _brew_error "unknown option: $1"; return 2 ;;
        esac
        shift
    done
    : "$reset" # --reset is retained as a compatibility synonym for replacement.
    [ -n "$rc_file" ] || rc_file=$(_brew_default_rc)
    if [ "$remove" = true ]; then
        _brew_replace_block "$rc_file" 'homebrew shellenv' ''
        _brew_info "removed managed shellenv block from $rc_file"
        return
    fi
    [ -n "$brew_bin" ] || brew_bin=$(_brew_find_binary) || {
        _brew_error 'cannot locate brew; pass --brew PATH'
        return 1
    }
    block_content="eval \"\$($brew_bin shellenv)\""
    _brew_replace_block "$rc_file" 'homebrew shellenv' "$block_content" || return
    eval "$("$brew_bin" shellenv)" || return
    _brew_info "updated Homebrew PATH in $rc_file and the current shell"
}

unset_brew_envs() {
    unset HOMEBREW_INSTALL_FROM_API HOMEBREW_BREW_GIT_REMOTE
    unset HOMEBREW_CORE_GIT_REMOTE HOMEBREW_BOTTLE_DOMAIN
    unset HOMEBREW_API_DOMAIN HOMEBREW_PIP_INDEX_URL
}

remove_brew_env_in_shellrcs() {
    local rc_file=${1:-$(_brew_default_rc)}
    unset_brew_envs
    _brew_replace_block "$rc_file" 'homebrew mirror env' '' || return
    _brew_info "removed managed mirror block from $rc_file"
}

_brew_set_mirror() {
    local mirror=$1 rc_file=$2 write_rc=$3 mirror_content=''
    mirror_content=$(_brew_mirror_env "$mirror") || return
    _brew_export_mirror_env "$mirror" || return
    if [ "$write_rc" = true ]; then
        _brew_replace_block "$rc_file" 'homebrew mirror env' "$mirror_content" || return
        _brew_info "configured mirror '$mirror' in $rc_file"
    else
        _brew_info "configured mirror '$mirror' for the current shell only"
    fi
    if [ "$mirror" = official ] || [ "$mirror" = github ]; then
        local brew_bin
        if brew_bin=$(_brew_find_binary 2>/dev/null); then
            git -C "$("$brew_bin" --repo)" remote set-url origin https://github.com/Homebrew/brew 2>/dev/null || true
        fi
    fi
}

_brew_download_installer() {
    local source_name=$1 output_file=$2 url
    url=$(_brew_installer_url "$source_name") || return
    _brew_info "downloading installer from $url"
    curl --fail --location --show-error --retry 3 --connect-timeout 15 \
        "$url" --output "$output_file"
}

_brew_run_installer() {
    local installer=$1 target_user=${2:-} noninteractive=${3:-false}
    local env_args=()
    [ "$noninteractive" != true ] || env_args+=("NONINTERACTIVE=1")
    [ -z "${HOMEBREW_INSTALL_FROM_API:-}" ] || env_args+=("HOMEBREW_INSTALL_FROM_API=$HOMEBREW_INSTALL_FROM_API")
    [ -z "${HOMEBREW_BREW_GIT_REMOTE:-}" ] || env_args+=("HOMEBREW_BREW_GIT_REMOTE=$HOMEBREW_BREW_GIT_REMOTE")
    [ -z "${HOMEBREW_CORE_GIT_REMOTE:-}" ] || env_args+=("HOMEBREW_CORE_GIT_REMOTE=$HOMEBREW_CORE_GIT_REMOTE")
    [ -z "${HOMEBREW_BOTTLE_DOMAIN:-}" ] || env_args+=("HOMEBREW_BOTTLE_DOMAIN=$HOMEBREW_BOTTLE_DOMAIN")
    [ -z "${HOMEBREW_API_DOMAIN:-}" ] || env_args+=("HOMEBREW_API_DOMAIN=$HOMEBREW_API_DOMAIN")
    [ -z "${HOMEBREW_PIP_INDEX_URL:-}" ] || env_args+=("HOMEBREW_PIP_INDEX_URL=$HOMEBREW_PIP_INDEX_URL")
    [ -z "${HTTPS_PROXY:-}" ] || env_args+=("HTTPS_PROXY=$HTTPS_PROXY")
    [ -z "${HTTP_PROXY:-}" ] || env_args+=("HTTP_PROXY=$HTTP_PROXY")
    [ -z "${ALL_PROXY:-}" ] || env_args+=("ALL_PROXY=$ALL_PROXY")
    [ -z "${https_proxy:-}" ] || env_args+=("https_proxy=$https_proxy")
    [ -z "${http_proxy:-}" ] || env_args+=("http_proxy=$http_proxy")
    [ -z "${all_proxy:-}" ] || env_args+=("all_proxy=$all_proxy")
    chmod 0755 "$installer" || return
    if [ -n "$target_user" ] && [ "$target_user" != "$(id -un)" ]; then
        _brew_as_root chown "$target_user" "$installer" || return
        if command -v sudo >/dev/null 2>&1; then
            sudo -H -u "$target_user" env "${env_args[@]}" /bin/bash "$installer"
        elif [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
            runuser -u "$target_user" -- env HOME="$(_brew_user_home "$target_user")" "${env_args[@]}" /bin/bash "$installer"
        else
            _brew_error 'sudo or runuser is required to install as another user'
            return 1
        fi
    else
        env "${env_args[@]}" /bin/bash "$installer"
    fi
}

install_brew() {
    local mirror=official installer_source='' target_user='' rc_file=''
    local update_only=false write_rc=true force=false uninstall=false github_mirror=''
    local create_user=false noninteractive=false already_installed=false
    local installer_file brew_bin

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                cat <<'EOF'
用法：install_brew [选项]

统一安装和配置 Homebrew。镜像、代理、操作系统和安装用户彼此独立。
使用代理时选择 official，并提前导出 HTTPS_PROXY/ALL_PROXY。

  -s, --source, --mirror NAME  official|ustc|tuna|aliyun，默认 official
  -b, --installer-source NAME  单独指定安装脚本来源；默认与 mirror 相同
  -u, --user USER              root 指定实际安装和运行 brew 的非 root 用户
      --create-user            指定用户不存在时创建（仅 root）
  -U, --update-mirror-only     只更新镜像环境变量，不安装
  -R, --reset-mirror           清除镜像配置并恢复官方源
      --rc FILE                将持久配置写入 FILE
      --no-write-env           只配置当前 shell，不写入 rc 文件
      --non-interactive        非交互安装；普通用户需要 sudo 密码时不要使用
      --force                  即使已经找到 brew 也重新安装
      --uninstall              运行官方卸载脚本

标准安装前缀：Linux 为 /home/linuxbrew/.linuxbrew，Apple Silicon macOS 为
/opt/homebrew，Intel macOS 为 /usr/local。普通 Linux 用户通常需要 sudo。
不默认安装到 ~/.linuxbrew，因为非标准前缀可能无法使用预编译 bottle。

身份规则：普通用户只能安装给自己，不要传 --create-user，也不需要创建
linuxbrew 账号。只有当前调用者就是 root 时，才能组合使用
--user USER --create-user；Homebrew 命令随后由 root 通过 brewr 间接执行。

兼容选项 --github-mirror 已弃用。请改用代理环境变量。
EOF
                return 0
                ;;
            -s | --source | ---source | --mirror) [ "$#" -ge 2 ] || return 2; mirror=$2; shift ;;
            -b | --installer-source) [ "$#" -ge 2 ] || return 2; installer_source=$2; shift ;;
            -u | --user) [ "$#" -ge 2 ] || return 2; target_user=$2; shift ;;
            -U | --update-mirror-only) update_only=true ;;
            -R | --reset-mirror) mirror=official; installer_source=official; update_only=true ;;
            --rc) [ "$#" -ge 2 ] || return 2; rc_file=$2; shift ;;
            --no-write-env) write_rc=false ;;
            --create-user) create_user=true ;;
            --non-interactive) noninteractive=true ;;
            --force) force=true ;;
            --uninstall) uninstall=true ;;
            -g | --github-mirror) [ "$#" -ge 2 ] || return 2; github_mirror=$2; shift ;;
            --) shift; break ;;
            -*) _brew_error "unknown option: $1"; return 2 ;;
            *) mirror=$1 ;;
        esac
        shift
    done
    [ -n "$installer_source" ] || installer_source=$mirror
    if [ "$uninstall" = true ]; then
        if [ -n "$target_user" ]; then
            uninstall_brew --user "$target_user"
        else
            uninstall_brew
        fi
        return
    fi
    if [ "$create_user" = true ]; then
        [ "$(id -u)" -eq 0 ] || {
            _brew_error '--create-user is only for a root shell managing a dedicated Homebrew account'
            _brew_error 'normal users should omit --user/--create-user and install Homebrew for themselves'
            return 2
        }
        [ -n "$target_user" ] || {
            _brew_error '--create-user requires --user USER'
            return 2
        }
    fi
    if [ "$(id -u)" -ne 0 ] && [ -n "$target_user" ] && [ "$target_user" != "$(id -un)" ]; then
        _brew_error 'a normal user cannot install Homebrew for another user'
        _brew_error 'omit --user to install for the current user'
        return 2
    fi
    if brew_bin=$(_brew_find_binary "$target_user" 2>/dev/null) && [ "$force" != true ]; then
        already_installed=true
    fi
    # 仅更新镜像或使用可访问的既有安装时不需要检查前缀；真正下载安装前预检，
    # 避免失败安装把无效配置写入当前用户的 rc 文件。
    if [ "$update_only" != true ] && [ "$already_installed" != true ]; then
        _brew_check_linux_prefix_access || return
    fi
    [ -z "$github_mirror" ] || _brew_warn '--github-mirror is deprecated and intentionally not injected into URLs'
    [ -n "$rc_file" ] || rc_file=$(_brew_default_rc)
    _brew_set_mirror "$mirror" "$rc_file" "$write_rc" || return
    if [ "$update_only" = true ]; then
        _brew_info 'mirror configuration updated; run brew update when ready'
        return 0
    fi
    if [ "$already_installed" = true ]; then
        _brew_info "Homebrew is already installed: $brew_bin"
        "$brew_bin" --version
        return 0
    fi
    if [ "$(id -u)" -eq 0 ]; then
        [ -n "$target_user" ] || {
            _brew_error 'Homebrew refuses root; pass --user USER (for example linuxbrew)'
            return 2
        }
        [ "$target_user" != root ] || { _brew_error 'the install user cannot be root'; return 2; }
        if ! id "$target_user" >/dev/null 2>&1; then
            if [ "$create_user" = true ]; then
                new_user_sudo "$target_user" || return
            else
                _brew_error "user does not exist: $target_user (use --create-user to create it)"
                return 2
            fi
        fi
        _brew_prepare_linux_prefix "$target_user" || return
        # 切换到专用用户后不能交互输入 root 的 sudo 密码。
        noninteractive=true
    fi

    _brew_need_command curl || return
    installer_file=$(mktemp "${TMPDIR:-/tmp}/brew-install.XXXXXX") || return 1
    if ! _brew_download_installer "$installer_source" "$installer_file"; then
        rm -f "$installer_file"
        return 1
    fi
    _brew_run_installer "$installer_file" "$target_user" "$noninteractive"
    local install_status=$?
    rm -f "$installer_file"
    [ "$install_status" -eq 0 ] || return "$install_status"

    brew_bin=$(_brew_find_binary "$target_user") || {
        _brew_error 'installer completed, but the brew executable was not found'
        return 1
    }
    if [ -z "$target_user" ] || [ "$target_user" = "$(id -un)" ]; then
        set_brew_path_env_to_shellrc --rc "$rc_file" --brew "$brew_bin"
    else
        _brew_info "installed for $target_user; root can run commands with: brewr --user $target_user ..."
    fi
}

# 国内网络场景入口，只设置网络来源，不创建或切换用户。调用者后置传入的
# --mirror 或 --installer-source 可以覆盖这里的默认值。
install_brew_cn() {
    install_brew --mirror ustc --installer-source ustc "$@"
}

install_linuxbrew() {
    local username
    if [ "$(id -u)" -eq 0 ]; then username=linuxbrew; else username=$(id -un); fi
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                cat <<'EOF'
用法：install_linuxbrew [-u USER] [USER]

仅供 Linux root shell 使用：从官方源安装 Homebrew，并创建或复用专用普通
用户（默认 linuxbrew）。该用户不会获得 sudo；root 通过 brewr 使用 brew。

普通用户不要调用本函数，也不要创建 linuxbrew 账号。请改用：
  install_brew [网络选项]
或：
  install_brew_cn [网络选项]

系统依赖：
  Debian/Ubuntu: apt-get install build-essential procps curl file git
  Fedora/RHEL:   dnf group install 'Development Tools'; dnf install procps-ng curl file git
  Arch:          pacman -S base-devel procps-ng curl file git
EOF
                return 0
                ;;
            -u | --user) [ "$#" -ge 2 ] || return 2; username=$2; shift ;;
            --) shift; break ;;
            -*) _brew_error "unknown option: $1"; return 2 ;;
            *) username=$1 ;;
        esac
        shift
    done
    _brew_is_linux || { _brew_error 'install_linuxbrew is Linux-only'; return 1; }
    [ "$(id -u)" -eq 0 ] || {
        _brew_error 'install_linuxbrew is reserved for a root shell using a dedicated account'
        _brew_error 'normal users should run: install_brew (or install_brew_cn)'
        return 2
    }
    install_brew --mirror official --installer-source official --user "$username" \
        --create-user --no-write-env --non-interactive
}

brewr() {
    local brew_user=${BREW_USER:-linuxbrew} brew_bin user_home
    local args=()
    local env_args=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -u | --user | --brew-user)
                [ "$#" -ge 2 ] || { _brew_error "$1 needs a value"; return 2; }
                brew_user=$2
                shift
                ;;
            -h | --help)
                cat <<'EOF'
Usage: brewr [-u USER] BREW_ARGUMENTS...

As root, execute Homebrew as BREW_USER (default: linuxbrew). As a normal user,
execute the brew found in PATH. Set BREW_USER to change the persistent default.
EOF
                return 0
                ;;
            *) args+=("$1") ;;
        esac
        shift
    done

    if [ "$(id -u)" -ne 0 ]; then
        command brew "${args[@]}"
        return
    fi
    id "$brew_user" >/dev/null 2>&1 || {
        _brew_error "brew user does not exist: $brew_user"
        return 1
    }
    brew_bin=$(_brew_find_binary "$brew_user") || {
        _brew_error "cannot find Homebrew installed for user $brew_user"
        return 1
    }
    user_home=$(_brew_user_home "$brew_user")
    # sudo normally filters these variables. Passing only Homebrew and proxy
    # settings keeps mirror/proxy behavior consistent with the root shell.
    [ -z "${HOMEBREW_INSTALL_FROM_API:-}" ] || env_args+=("HOMEBREW_INSTALL_FROM_API=$HOMEBREW_INSTALL_FROM_API")
    [ -z "${HOMEBREW_BREW_GIT_REMOTE:-}" ] || env_args+=("HOMEBREW_BREW_GIT_REMOTE=$HOMEBREW_BREW_GIT_REMOTE")
    [ -z "${HOMEBREW_CORE_GIT_REMOTE:-}" ] || env_args+=("HOMEBREW_CORE_GIT_REMOTE=$HOMEBREW_CORE_GIT_REMOTE")
    [ -z "${HOMEBREW_BOTTLE_DOMAIN:-}" ] || env_args+=("HOMEBREW_BOTTLE_DOMAIN=$HOMEBREW_BOTTLE_DOMAIN")
    [ -z "${HOMEBREW_API_DOMAIN:-}" ] || env_args+=("HOMEBREW_API_DOMAIN=$HOMEBREW_API_DOMAIN")
    [ -z "${HOMEBREW_PIP_INDEX_URL:-}" ] || env_args+=("HOMEBREW_PIP_INDEX_URL=$HOMEBREW_PIP_INDEX_URL")
    [ -z "${HTTPS_PROXY:-}" ] || env_args+=("HTTPS_PROXY=$HTTPS_PROXY")
    [ -z "${HTTP_PROXY:-}" ] || env_args+=("HTTP_PROXY=$HTTP_PROXY")
    [ -z "${ALL_PROXY:-}" ] || env_args+=("ALL_PROXY=$ALL_PROXY")
    [ -z "${https_proxy:-}" ] || env_args+=("https_proxy=$https_proxy")
    [ -z "${http_proxy:-}" ] || env_args+=("http_proxy=$http_proxy")
    [ -z "${all_proxy:-}" ] || env_args+=("all_proxy=$all_proxy")
    if command -v sudo >/dev/null 2>&1; then
        sudo -H -u "$brew_user" env HOME="$user_home" "${env_args[@]}" "$brew_bin" "${args[@]}"
    elif command -v runuser >/dev/null 2>&1; then
        runuser -u "$brew_user" -- env HOME="$user_home" "${env_args[@]}" "$brew_bin" "${args[@]}"
    else
        _brew_error 'sudo or runuser is required to execute brew as another user'
        return 1
    fi
}

uninstall_brew() {
    local installer_file target_user='' url='https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh'
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                printf '%s\n' 'Usage: uninstall_brew [--user USER]'
                return 0
                ;;
            -u | --user) [ "$#" -ge 2 ] || return 2; target_user=$2; shift ;;
            *) _brew_error "unknown option: $1"; return 2 ;;
        esac
        shift
    done
    _brew_need_command curl || return
    installer_file=$(mktemp "${TMPDIR:-/tmp}/brew-uninstall.XXXXXX") || return 1
    _brew_info "downloading official uninstaller from $url"
    if ! curl --fail --location --show-error --retry 3 "$url" --output "$installer_file"; then
        rm -f "$installer_file"
        return 1
    fi
    _brew_run_installer "$installer_file" "$target_user" false
    local uninstall_status=$?
    rm -f "$installer_file"
    return "$uninstall_status"
}
