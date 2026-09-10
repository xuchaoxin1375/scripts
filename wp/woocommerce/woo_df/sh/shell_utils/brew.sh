#!/usr/bin/env bash
# Homebrew 安装与管理函数，可由 Bash 和 Zsh source。
#
# 统一入口是 install_brew；install_brew_cn 只提供国内镜像默认值；
# install_linuxbrew 专用于 root 创建/使用隔离账号。网络来源、操作系统和运行
# 身份是三个独立维度，不应由包装函数暗中改变安装身份。
#
# 常用场景：
#   国外 Linux 服务器，当前是 root：
#     install_linuxbrew                 # 官方源 + 专用用户
#     install_brew                      # root 下转到同一套专用用户安装
#     brewr install jq                  # 提示当前借用 linuxbrew，再降权执行
#     brew install jq                   # 仅 alias 到 brewr，不会递归
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

_brew_is_linux() { [ "$(uname -s 2> /dev/null)" = Linux ]; }
_brew_is_macos() { [ "$(uname -s 2> /dev/null)" = Darwin ]; }

_brew_need_command() {
    command -v "$1" > /dev/null 2>&1 || {
        _brew_error "required command not found: $1"
        return 1
    }
}

# Run an administrative command. Root does not need sudo; other users do.
_brew_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        command "$@"
    elif command -v sudo > /dev/null 2>&1; then
        sudo "$@"
    else
        _brew_error "this operation needs root privileges (sudo is unavailable)"
        return 1
    fi
}

_brew_user_home() {
    local target_user=$1 home_dir=''
    if command -v getent > /dev/null 2>&1; then
        home_dir=$(getent passwd "$target_user" 2> /dev/null | cut -d: -f6)
    elif _brew_is_macos; then
        home_dir=$(dscl . -read "/Users/$target_user" NFSHomeDirectory 2> /dev/null | awk '{print $2}')
    fi
    [ -n "$home_dir" ] || home_dir="/home/$target_user"
    printf '%s\n' "$home_dir"
}

_brew_find_binary() {
    local target_user=${1:-} user_home candidate dir old_ifs
    # 不要用 command -v brew：root 下的 alias/function 会伪装成已安装，
    # 再被 brewr 调回去就会循环。
    if [ -z "$target_user" ]; then
        old_ifs=$IFS
        IFS=:
        for dir in $PATH; do
            IFS=$old_ifs
            [ -n "$dir" ] || continue
            if [ -f "$dir/brew" ] && [ -x "$dir/brew" ]; then
                printf '%s\n' "$dir/brew"
                return 0
            fi
        done
        IFS=$old_ifs
    else
        user_home=$(_brew_user_home "$target_user")
        if [ -f "$user_home/.linuxbrew/bin/brew" ] && [ -x "$user_home/.linuxbrew/bin/brew" ]; then
            printf '%s\n' "$user_home/.linuxbrew/bin/brew"
            return 0
        fi
    fi
    for candidate in \
        /home/linuxbrew/.linuxbrew/bin/brew \
        /opt/homebrew/bin/brew \
        /usr/local/bin/brew; do
        if [ -f "$candidate" ] && [ -x "$candidate" ]; then
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
        if find "$prefix" -maxdepth 0 -user "$target_user" -print 2> /dev/null | grep -q .; then
            return 0
        fi
        _brew_error "$prefix already exists and is not owned by $target_user"
        return 1
    fi
    if [ -e "$prefix_parent" ] &&
        ! find "$prefix_parent" -maxdepth 0 -user "$target_user" -print 2> /dev/null | grep -q .; then
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
        owner=$(stat -c '%U' "$prefix_parent" 2> /dev/null || printf 'unknown')
        _brew_error "$prefix_parent is owned by $owner and is not accessible to $(id -un)"
        _brew_error "finish/use the dedicated installation as root with: install_linuxbrew; brewr ..."
        _brew_error 'to install as the current user, explicitly remove or transfer the existing dedicated installation first'
        return 1
    fi
    if [ -e "$prefix" ] && { [ ! -x "$prefix" ] || [ ! -w "$prefix" ]; }; then
        owner=$(stat -c '%U' "$prefix" 2> /dev/null || printf 'unknown')
        _brew_error "$prefix is owned by $owner and is not writable by $(id -un)"
        _brew_error 'refusing to take ownership of an existing Homebrew prefix automatically'
        return 1
    fi
    if [ ! -e "$prefix" ] && ! command -v sudo > /dev/null 2>&1; then
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
    ' "$target_file" > "$temp_file" || {
        rm -f "$temp_file"
        return 1
    }
    if [ -n "$content" ]; then
        {
            printf '\n%s\n' "$begin_marker"
            printf '%s\n' "$content"
            printf '%s\n' "$end_marker"
        } >> "$temp_file"
    fi
    # Redirection preserves the ownership and mode of an existing rc file.
    if command cat "$temp_file" > "$target_file"; then
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
        done << EOF
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
        *)
            _brew_error "unknown installer source: $1"
            return 2
            ;;
    esac
}

new_user_linuxbrew() {
    local username=linuxbrew login_shell=/bin/bash
    local add_password=false random_password=false add_sudo=false passwordless_sudo=false
    local sudo_group sudo_file temp_file random_value

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                cat << 'EOF'
用法：new_user_linuxbrew [选项] [用户名]

幂等创建 Linux 普通用户。用户已存在时不会报错，只按选项补密码或 sudo。
Homebrew 专用账号默认不需要本函数；root 安装时请用 install_linuxbrew 或
install_brew --user USER --create-user。默认用户名：linuxbrew。

选项：
  -h, --help                 显示本帮助
  -p, --addpasswd            创建后交互式运行 passwd
  -P, --set-random-pwd       生成一次性随机密码并打印
  -A, --addsudo              加入 sudo 或 wheel 组
  -N, --no-sudo-password     写入免密 sudo 规则（隐含 --addsudo）
  -s, --shell PATH           登录 shell，默认 /bin/bash

说明：
  专用 Homebrew 用户通常不要加 sudo。install_brew / install_linuxbrew
  创建 linuxbrew 时不会传 -A/-N。

示例：
  new_user_linuxbrew
  new_user_linuxbrew -s /bin/zsh builder
  new_user_linuxbrew -P -A deploy
EOF
                return 0
                ;;
            -p | --addpwd | --addpasswd) add_password=true ;;
            -P | --set-random-pwd) random_password=true ;;
            -A | --addsudo) add_sudo=true ;;
            -N | --no-sudo-password)
                passwordless_sudo=true
                add_sudo=true
                ;;
            -s | --shell)
                [ "$#" -ge 2 ] || {
                    _brew_error "$1 needs a value"
                    return 2
                }
                login_shell=$2
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                _brew_error "unknown option: $1"
                return 2
                ;;
            *) username=$1 ;;
        esac
        shift
    done

    _brew_is_linux || {
        _brew_error 'user creation is supported only on Linux'
        return 1
    }
    if id "$username" > /dev/null 2>&1; then
        _brew_info "user already exists: $username"
    elif command -v useradd > /dev/null 2>&1; then
        _brew_as_root useradd --create-home --shell "$login_shell" "$username" || return
    elif command -v adduser > /dev/null 2>&1; then
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
        if getent group sudo > /dev/null 2>&1; then sudo_group=sudo; else sudo_group=wheel; fi
        _brew_as_root usermod -aG "$sudo_group" "$username" || return
    fi
    if [ "$passwordless_sudo" = true ]; then
        _brew_need_command visudo || return
        temp_file=$(mktemp "${TMPDIR:-/tmp}/brew-sudoers.XXXXXX") || return 1
        printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$username" > "$temp_file"
        if ! visudo -c -f "$temp_file" > /dev/null; then
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
                cat << 'EOF'
用法：cleanup_linuxbrew_dedicated_user [选项]

清理由 root/专用用户方案创建的 linuxbrew 账号和 /home/linuxbrew，
以便普通 sudo 用户按官方方式接管标准前缀。只处理用户名 linuxbrew
和家目录 /home/linuxbrew。

选项：
  -h, --help                 显示本帮助
      --execute              真正执行；默认只预览
      --backup-dir PATH      家目录备份路径，必须在 /home/linuxbrew 之外
                             默认：/home/linuxbrew.dedicated-backup-时间戳

--execute 时会：
  1. 若 linuxbrew 仍有进程则拒绝继续；
  2. 将 /home/linuxbrew 移到备份目录（不直接 rm -rf）；
  3. 删除 linuxbrew 账号及空的同名私有组；
  4. 删除本脚本创建的 /etc/sudoers.d/linuxbrew_nopasswd；
  5. 报告其他仍引用 linuxbrew 的 sudoers 文件。

备份不会自动删除。确认新安装可用后再手工处理。

示例：
  cleanup_linuxbrew_dedicated_user
  cleanup_linuxbrew_dedicated_user --execute
  cleanup_linuxbrew_dedicated_user --execute --backup-dir /root/linuxbrew.bak

下一步通常是（以普通 sudo 用户）：
  install_brew
  或 install_brew_cn
EOF
                return 0
                ;;
            --execute) execute=true ;;
            --backup-dir)
                [ "$#" -ge 2 ] || {
                    _brew_error '--backup-dir needs a value'
                    return 2
                }
                backup_dir=$2
                shift
                ;;
            *)
                _brew_error "unknown option: $1"
                return 2
                ;;
        esac
        shift
    done

    _brew_is_linux || {
        _brew_error 'this cleanup is Linux-only'
        return 1
    }
    timestamp=$(date '+%Y%m%d-%H%M%S') || return 1
    [ -n "$backup_dir" ] || backup_dir="/home/linuxbrew.dedicated-backup-$timestamp"
    case "$backup_dir" in
        "$expected_home" | "$expected_home"/*)
            _brew_error 'backup directory must be outside /home/linuxbrew'
            return 2
            ;;
    esac
    [ ! -e "$backup_dir" ] || {
        _brew_error "backup path already exists: $backup_dir"
        return 1
    }

    if id "$target_user" > /dev/null 2>&1; then
        account_entry=$(getent passwd "$target_user") || return 1
        actual_home=$(printf '%s\n' "$account_entry" | cut -d: -f6)
        [ "$actual_home" = "$expected_home" ] || {
            _brew_error "refusing cleanup: $target_user home is $actual_home, expected $expected_home"
            return 1
        }
        process_list=$(ps -u "$target_user" -o pid=,cmd= 2> /dev/null || true)
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
    if id "$target_user" > /dev/null 2>&1; then
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
    if getent group "$target_user" > /dev/null 2>&1; then
        _brew_as_root groupdel "$target_user" || _brew_warn "group remains: $target_user"
    fi
    if [ -e /etc/sudoers.d/linuxbrew_nopasswd ]; then
        _brew_as_root rm -f /etc/sudoers.d/linuxbrew_nopasswd || return
    fi
    _brew_info 'checking for other sudoers references to linuxbrew...'
    _brew_as_root grep -RIl -- "$target_user" /etc/sudoers /etc/sudoers.d 2> /dev/null || true
    _brew_info "cleanup complete; recoverable home backup: $backup_dir"
    _brew_info 'next: run install_brew --mirror SOURCE as the normal sudo user'
}

set_brew_path_env_to_shellrc() {
    local remove=false reset=false rc_file='' brew_bin='' block_content
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                cat << 'EOF'
用法：set_brew_path_env_to_shellrc [选项]

向当前用户的 shell rc 写入一段受管理的 brew shellenv。
root 使用专用 linuxbrew 用户时不要调用本函数；请用 brewr。

选项：
  -h, --help                 显示本帮助
      --remove, --reset      删除受管理的 shellenv 块
      --rc FILE              目标 rc，默认 ~/.zshrc 或 ~/.bashrc
      --brew PATH            brew 可执行文件；默认自动查找

示例：
  set_brew_path_env_to_shellrc
  set_brew_path_env_to_shellrc --brew /home/linuxbrew/.linuxbrew/bin/brew
  set_brew_path_env_to_shellrc --remove
EOF
                return 0
                ;;
            --remove) remove=true ;;
            --reset) reset=true ;;
            --rc)
                [ "$#" -ge 2 ] || return 2
                rc_file=$2
                shift
                ;;
            --brew)
                [ "$#" -ge 2 ] || return 2
                brew_bin=$2
                shift
                ;;
            *)
                _brew_error "unknown option: $1"
                return 2
                ;;
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
        if brew_bin=$(_brew_find_binary 2> /dev/null); then
            git -C "$("$brew_bin" --repo)" remote set-url origin https://github.com/Homebrew/brew 2> /dev/null || true
        fi
    fi
}

_brew_download_installer() {
    local source_name=$1 output_file=$2 url
    url=$(_brew_installer_url "$source_name") || return
    _brew_info "downloading installer from $url"
    # 与官方安装方式一致：-fsSL。不要加很长的 connect-timeout/retry，
    # 握手慢时会在 “downloading” 这一步空等很久。
    curl -fsSL --retry 2 "$url" --output "$output_file"
}

_brew_exec_as_user() {
    local target_user=$1 user_home env_args=()
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --)
                shift
                break
                ;;
            *)
                env_args+=("$1")
                shift
                ;;
        esac
    done
    [ "$#" -gt 0 ] || {
        _brew_error 'internal error: _brew_exec_as_user needs a command'
        return 2
    }
    user_home=$(_brew_user_home "$target_user")
    # Homebrew's brew wrapper aborts unless PWD exists and is readable by the
    # target user. Root shells commonly stay in /root (0700), which produces:
    # "The current working directory must be readable to linuxbrew to run brew."
    # After dropping privileges, cd to that user's home when PWD is unusable.
    # The inner script is always bash so this stays identical under zsh.
    local inner
    inner='if [ -z "${PWD:-}" ] || [ ! -d "$PWD" ] || [ ! -r "$PWD" ]; then
    if [ -n "$1" ] && [ -d "$1" ] && [ -r "$1" ]; then
        cd -- "$1" || exit 1
    else
        cd -- /tmp || exit 1
    fi
fi
shift
exec "$@"'
    if command -v sudo > /dev/null 2>&1; then
        sudo -H -u "$target_user" env HOME="$user_home" "${env_args[@]}" \
            /bin/bash -c "$inner" bash "$user_home" "$@"
    elif [ "$(id -u)" -eq 0 ] && command -v runuser > /dev/null 2>&1; then
        runuser -u "$target_user" -- env HOME="$user_home" "${env_args[@]}" \
            /bin/bash -c "$inner" bash "$user_home" "$@"
    else
        _brew_error 'sudo or runuser is required to execute as another user'
        return 1
    fi
}

# Homebrew 在 Linux 装了自己的 glibc 后，二进制会用
# /home/linuxbrew/.linuxbrew/lib/ld.so。它不搜索 Debian 的
# /lib/x86_64-linux-gnu。部分环境会注入 LD_PRELOAD=libkeyutils.so.1
# （短名），于是 jq、readelf 等每次启动都打印：
#   ERROR: ld.so: object 'libkeyutils.so.1' from LD_PRELOAD cannot be preloaded
# 系统命令不受影响。能写前缀则拷进 prefix/lib；否则只把这一份 .so
# 放到独立目录，再 prepend 到 LD_LIBRARY_PATH，绝不要加入系统 lib。
_brew_system_keyutils() {
    local candidate
    for candidate in /lib/x86_64-linux-gnu/libkeyutils.so.1 \
        /usr/lib/x86_64-linux-gnu/libkeyutils.so.1 \
        /lib64/libkeyutils.so.1; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

_brew_compat_keyutils_preload() {
    local prefix=/home/linuxbrew/.linuxbrew
    local src dest dir
    _brew_is_linux || return 0
    [ -x "$prefix/lib/ld.so" ] || return 0
    src=$(_brew_system_keyutils) || return 0
    dest="$prefix/lib/libkeyutils.so.1"
    if [ ! -e "$dest" ] && [ -w "$prefix/lib" ]; then
        cp -L "$src" "$dest" 2> /dev/null || true
    fi
    if [ -f "$dest" ]; then
        return 0
    fi
    dir="${TMPDIR:-/tmp}/homebrew-ld-preload"
    mkdir -p "$dir" 2> /dev/null || return 0
    if [ ! -f "$dir/libkeyutils.so.1" ]; then
        cp -L "$src" "$dir/libkeyutils.so.1" 2> /dev/null || return 0
    fi
    case ":${LD_LIBRARY_PATH:-}:" in
        *":$dir:"*) ;;
        *) export LD_LIBRARY_PATH="$dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
    esac
}

# root 下 brew 只做 alias，不做 function。
# function brew { brewr } 会让 command -v brew 永远为真，也容易和 brewr 循环。
_brew_enable_root_alias() {
    local quiet=false brew_user=${BREW_USER:-linuxbrew}
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --quiet) quiet=true ;;
            *) brew_user=$1 ;;
        esac
        shift
    done
    [ "$(id -u)" -eq 0 ] || return 0
    _brew_is_linux || return 0
    id "$brew_user" > /dev/null 2>&1 || return 1
    _brew_find_binary "$brew_user" > /dev/null || return 1
    export BREW_USER=$brew_user
    _brew_compat_keyutils_preload
    unalias brew 2> /dev/null || true
    unset -f brew 2> /dev/null || true
    alias brew=brewr
    if [ "$quiet" != true ]; then
        _brew_info "root 已设置 alias brew=brewr（用户 $brew_user）"
        _brew_info "可执行：brewr install fd    或    brew install fd"
    fi
}

# 普通用户走 PATH 中的 brew；root 走 brewr，避免 Don't run this as root。
_brew_invoke() {
    if [ "$(id -u)" -eq 0 ]; then
        brewr "$@"
    else
        command brew "$@"
    fi
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
        _brew_exec_as_user "$target_user" "${env_args[@]}" -- /bin/bash "$installer"
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
                cat << 'EOF'
用法：install_brew [选项]

统一安装和配置 Homebrew。镜像、安装脚本来源、代理、操作系统、安装身份
彼此独立。Linux root 会按 install_linuxbrew 的思路借用专用用户，官方源
直接调用 install_linuxbrew。

选项：
  -h, --help                   显示本帮助
  -s, --source, --mirror NAME  运行时镜像：official|ustc|tuna|aliyun
                               默认 official
  -b, --installer-source NAME  安装脚本下载源；默认与 --mirror 相同
  -u, --user USER              实际拥有并运行 Homebrew 的非 root 用户
      --create-user            用户不存在时创建（仅 root；root 官方源安装可省略）
  -U, --update-mirror-only     只更新镜像环境变量，不安装
  -R, --reset-mirror           清除镜像并恢复官方源（不安装）
      --rc FILE                将持久配置写入 FILE（默认当前 shell 的 rc）
      --no-write-env           只配置当前 shell，不写 rc
      --non-interactive        非交互安装；普通用户还要输入 sudo 密码时不要用
      --force                  已检测到 brew 时仍重新安装
      --uninstall              运行官方卸载脚本

身份：
  普通用户：安装给自己。不要传 --user / --create-user，也不要先建 linuxbrew。
  Linux root：Homebrew 拒绝以 root 运行。未指定 --user 时默认 linuxbrew，
        用户不存在则创建（无密码、无 sudo）。官方源会调用 install_linuxbrew。
        安装后 alias brew=brewr；brewr 会提示当前借用的用户。

标准前缀（不要改装到 ~/.linuxbrew，否则可能无法用官方 bottle）：
  Linux               /home/linuxbrew/.linuxbrew
  Apple Silicon macOS /opt/homebrew
  Intel macOS         /usr/local

网络：
  国内镜像：--mirror ustc|tuna|aliyun
  走代理用官方源：先 export HTTPS_PROXY / HTTP_PROXY / ALL_PROXY
  例：HTTPS_PROXY=http://localhost:7897 install_brew

示例：
  普通用户官方源：     install_brew
  普通用户中科大镜像： install_brew_cn
  普通用户清华镜像：   install_brew --mirror tuna
  root 官方源：        install_brew    或    install_linuxbrew
  root 显式指定用户：  install_brew --user linuxbrew
  root + 国内镜像：    install_brew --mirror ustc --user linuxbrew
  只改镜像：           install_brew --mirror tuna --update-mirror-only
  恢复官方源：         install_brew --reset-mirror

相关命令：
  install_linuxbrew    root + 官方源 + 专用用户的快捷入口
  install_brew_cn      国内镜像默认入口（USTC）
  brewr                root 降权执行 brew；普通用户等于 brew
  uninstall_brew       卸载
  brew_install         install_brew 的别名

兼容：--github-mirror 已弃用，不会改写 URL。请改用代理环境变量。
EOF
                return 0
                ;;
            -s | --source | ---source | --mirror)
                [ "$#" -ge 2 ] || return 2
                mirror=$2
                shift
                ;;
            -b | --installer-source)
                [ "$#" -ge 2 ] || return 2
                installer_source=$2
                shift
                ;;
            -u | --user)
                [ "$#" -ge 2 ] || return 2
                target_user=$2
                shift
                ;;
            -U | --update-mirror-only) update_only=true ;;
            -R | --reset-mirror)
                mirror=official
                installer_source=official
                update_only=true
                ;;
            --rc)
                [ "$#" -ge 2 ] || return 2
                rc_file=$2
                shift
                ;;
            --no-write-env) write_rc=false ;;
            --create-user) create_user=true ;;
            --non-interactive) noninteractive=true ;;
            --force) force=true ;;
            --uninstall) uninstall=true ;;
            -g | --github-mirror)
                [ "$#" -ge 2 ] || return 2
                github_mirror=$2
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                _brew_error "unknown option: $1"
                return 2
                ;;
            *) mirror=$1 ;;
        esac
        shift
    done
    [ -n "$installer_source" ] || installer_source=$mirror
    # Linux root：与 install_linuxbrew 同一套身份。官方源直接调用它，
    # 避免再走一遍临时文件安装器。国内镜像则仍用下面的专用用户安装。
    if [ "$(id -u)" -eq 0 ] && _brew_is_linux && [ "$uninstall" != true ] && [ "$update_only" != true ]; then
        [ -n "$target_user" ] || target_user=${BREW_USER:-linuxbrew}
        _brew_info "当前身份是 root，Homebrew 不能直接以 root 安装或运行"
        _brew_info "将借用专用用户 $target_user（与 install_linuxbrew 相同）"
        case "$installer_source" in
            official | github)
                if [ "$force" = true ]; then
                    install_linuxbrew --force --user "$target_user"
                else
                    install_linuxbrew --user "$target_user"
                fi
                return
                ;;
            *)
                create_user=true
                write_rc=false
                noninteractive=true
                ;;
        esac
    fi
    if [ "$uninstall" = true ]; then
        if [ -z "$target_user" ] && [ "$(id -u)" -eq 0 ] && _brew_is_linux; then
            target_user=${BREW_USER:-linuxbrew}
        fi
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
    if brew_bin=$(_brew_find_binary "$target_user" 2> /dev/null) && [ "$force" != true ]; then
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
        if [ "$(id -u)" -eq 0 ]; then
            _brew_enable_root_alias "${target_user:-${BREW_USER:-linuxbrew}}" || true
            _brew_info "当前身份: root，借用用户 ${target_user:-${BREW_USER:-linuxbrew}} 查看版本"
            _brew_exec_as_user "${target_user:-${BREW_USER:-linuxbrew}}" -- "$brew_bin" --version
        else
            "$brew_bin" --version
        fi
        return 0
    fi
    if [ "$(id -u)" -eq 0 ]; then
        [ -n "$target_user" ] || {
            _brew_error 'Homebrew refuses root; pass --user USER (for example linuxbrew)'
            return 2
        }
        [ "$target_user" != root ] || {
            _brew_error 'the install user cannot be root'
            return 2
        }
        if ! id "$target_user" > /dev/null 2>&1; then
            if [ "$create_user" = true ]; then
                _brew_info "creating dedicated user $target_user (no password, no sudo)"
                new_user_linuxbrew "$target_user" || return
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
    elif [ "$(id -u)" -eq 0 ]; then
        _brew_enable_root_alias "$target_user"
        _brew_info "installed for $target_user; use brewr, or alias brew=brewr"
    else
        _brew_info "installed for $target_user; run commands with: brewr --user $target_user ..."
    fi
}

# 将HOMEBREW_BOTTLE_DOMAIN替换为官方源再下载包(应对部分情况下,包安装后但是不可用(提示找不到文件的错误))
binstall() {
    local proxy_host="http://localhost"
    local proxy_port="7890"
    local show_help=false
    local cmd_args=()
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -x|--proxy)
                if [[ -z "$2" || "$2" =~ ^- ]]; then
                    echo "Error: --proxy/-x requires an argument" >&2
                    return 1
                fi
                proxy_host="$2"
                shift 2
                ;;
            -p|--port)
                if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --port/-p requires a valid port number" >&2
                    return 1
                fi
                proxy_port="$2"
                shift 2
                ;;
            -h|--help)
                show_help=true
                shift
                ;;
            *)
                cmd_args+=("$1")
                shift
                ;;
        esac
    done
    if [[ "$show_help" == true ]]; then
        cat << EOF
用法：binstall [选项] <brew 子命令> [参数...]

通过 HTTP(S) 代理执行 brew。root 会走 brewr，不会直接以 root 调用 brew。
默认代理：${proxy_host}:${proxy_port}

选项：
  -h, --help             显示本帮助
  -x, --proxy HOST       代理主机，默认 http://localhost
  -p, --port PORT        代理端口，默认 7890
                         若 HOST 已带端口，-p 会覆盖其中的端口

环境：
  HTTP_PROXY / HTTPS_PROXY = HOST:PORT
  HOMEBREW_BOTTLE_DOMAIN   = https://ghcr.io/v2/homebrew/core

示例：
  binstall install wget
  binstall -p 7897 install gdu
  binstall -x http://127.0.0.1 -p 7897 update
  binstall --proxy socks5://localhost -p 1080 install git
EOF
        return 0
    fi

    # 检查是否有命令参数
    if [[ ${#cmd_args[@]} -eq 0 ]]; then
        echo "Error: No brew command specified" >&2
        echo "Use -h or --help for usage information" >&2
        return 1
    fi

    # 构造完整的代理地址
    local full_proxy="${proxy_host}"
    if [[ -n "$proxy_port" ]]; then
        # 如果 proxy_host 已经包含端口，添加冒号，否则直接拼接
        if [[ "$proxy_host" =~ :[0-9]+$ ]]; then
            full_proxy="${proxy_host%:*}:${proxy_port}"
        else
            full_proxy="${proxy_host}:${proxy_port}"
        fi
    fi

    echo "相关参数"
    echo -e "\t proxy_host=$proxy_host"
    echo -e "\t proxy_port=$proxy_port"
    echo -e "\t full_proxy=$full_proxy"
    HTTP_PROXY="${full_proxy}" \
        HTTPS_PROXY="${full_proxy}" \
        HOMEBREW_BOTTLE_DOMAIN="https://ghcr.io/v2/homebrew/core" \
        _brew_invoke "${cmd_args[@]}"
}

# 国内网络场景入口，只设置网络来源，不创建或切换用户。调用者后置传入的
# --mirror 或 --installer-source 可以覆盖这里的默认值。
install_brew_cn() {
    case "${1:-}" in
        -h | --help)
            cat << 'EOF'
用法：install_brew_cn [install_brew 的选项]

国内网络默认入口：镜像和安装脚本都用 USTC。
等价于：install_brew --mirror ustc --installer-source ustc [选项]

身份规则与 install_brew 相同：
  普通用户安装给自己；Linux root 与 install_brew 相同，默认借用 linuxbrew。
后置 --mirror / --installer-source 可以覆盖这里的默认值。

示例：
  install_brew_cn
  install_brew_cn --mirror tuna
  install_brew_cn --user linuxbrew --create-user

完整选项见：install_brew --help
EOF
            return 0
            ;;
    esac
    install_brew --mirror ustc --installer-source ustc "$@"
}

install_linuxbrew() {
    local username=linuxbrew brew_bin url script user_home env_args=()
    local force=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                cat << 'EOF'
用法：install_linuxbrew [-u USER] [USER]

仅供 Linux root shell：用官方安装脚本安装 Homebrew，并创建或复用专用
普通用户（默认 linuxbrew）。该用户无登录密码、无 sudo。root 通过
brewr 使用 brew；当前 shell 只设置 alias brew=brewr，不会定义 brew 函数。
install_brew 在 Linux root + 官方源时会调用本函数。

选项：
  -h, --help             显示本帮助
  -u, --user USER        专用用户名，默认 linuxbrew
      --force            已安装时仍重新跑官方安装脚本
  USER                   与 --user 相同的位置参数

说明：
  下载方式与官方相同：
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  只是改成以专用用户执行。
  普通用户不要调用本函数，也不要先创建 linuxbrew。请改用：
    install_brew
    install_brew_cn
  国内网络的 root 请用：
    install_brew --mirror ustc

系统依赖：
  Debian/Ubuntu: apt-get install build-essential procps curl file git
  Fedora/RHEL:   dnf group install 'Development Tools'; dnf install procps-ng curl file git
  Arch:          pacman -S base-devel procps-ng curl file git

示例：
  install_linuxbrew
  install_linuxbrew --user linuxbrew
  install_linuxbrew builder
EOF
                return 0
                ;;
            -u | --user)
                [ "$#" -ge 2 ] || return 2
                username=$2
                shift
                ;;
            --force) force=true ;;
            --)
                shift
                break
                ;;
            -*)
                _brew_error "unknown option: $1"
                return 2
                ;;
            *) username=$1 ;;
        esac
        shift
    done
    _brew_is_linux || {
        _brew_error 'install_linuxbrew is Linux-only'
        return 1
    }
    [ "$(id -u)" -eq 0 ] || {
        _brew_error 'install_linuxbrew is reserved for a root shell using a dedicated account'
        _brew_error 'normal users should run: install_brew (or install_brew_cn)'
        return 2
    }
    [ "$username" != root ] || {
        _brew_error 'the install user cannot be root'
        return 2
    }
    if brew_bin=$(_brew_find_binary "$username" 2> /dev/null) && [ "$force" != true ]; then
        _brew_info "Homebrew is already installed: $brew_bin"
        _brew_enable_root_alias "$username" || true
        _brew_info "当前身份: root，借用用户 $username 查看版本"
        _brew_exec_as_user "$username" -- "$brew_bin" --version
        return 0
    fi
    if ! id "$username" > /dev/null 2>&1; then
        _brew_info "creating dedicated user $username (no password, no sudo)"
        new_user_linuxbrew "$username" || return
    fi
    _brew_prepare_linux_prefix "$username" || return
    _brew_need_command curl || return
    url=$(_brew_installer_url official) || return
    _brew_info "downloading official installer from $url"
    script=$(curl -fsSL --retry 2 "$url") || {
        _brew_error 'failed to download the official Homebrew installer'
        return 1
    }
    [ -n "$script" ] || {
        _brew_error 'downloaded installer is empty'
        return 1
    }
    user_home=$(_brew_user_home "$username")
    env_args+=(NONINTERACTIVE=1)
    [ -z "${HTTPS_PROXY:-}" ] || env_args+=("HTTPS_PROXY=$HTTPS_PROXY")
    [ -z "${HTTP_PROXY:-}" ] || env_args+=("HTTP_PROXY=$HTTP_PROXY")
    [ -z "${ALL_PROXY:-}" ] || env_args+=("ALL_PROXY=$ALL_PROXY")
    [ -z "${https_proxy:-}" ] || env_args+=("https_proxy=$https_proxy")
    [ -z "${http_proxy:-}" ] || env_args+=("http_proxy=$http_proxy")
    [ -z "${all_proxy:-}" ] || env_args+=("all_proxy=$all_proxy")
    _brew_info "installing Homebrew as $username"
    _brew_exec_as_user "$username" "${env_args[@]}" -- /bin/bash -c "$script" || return
    brew_bin=$(_brew_find_binary "$username") || {
        _brew_error 'installer completed, but the brew executable was not found'
        return 1
    }
    _brew_compat_keyutils_preload
    _brew_enable_root_alias "$username"
    _brew_info "installed for $username; use: brewr install fd    or    brew install fd"
}

brewr() {
    local brew_user=${BREW_USER:-linuxbrew} brew_bin
    local args=()
    local env_args=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -u | --user | --brew-user)
                [ "$#" -ge 2 ] || {
                    _brew_error "$1 needs a value"
                    return 2
                }
                brew_user=$2
                shift
                ;;
            -h | --help)
                cat << 'EOF'
用法：brewr [-u USER] [brew 参数...]

root 降权到 BREW_USER（默认 linuxbrew），执行真正的 brew 二进制，不会
再调用名为 brew 的函数或 alias。每次会提示：当前是 root、正在借用哪个用户。
普通用户则调用 PATH 中的 brew 文件。
安装完成后当前 shell 可 alias brew=brewr，两者都不会循环。

选项：
  -h, --help                 显示本帮助
  -u, --user, --brew-user U  本次使用的专用用户，默认 $BREW_USER 或 linuxbrew

行为：
  会把当前 shell 的 Homebrew 镜像变量和 HTTP(S)_PROXY / ALL_PROXY 传过去。
  若当前目录对目标用户不可读（例如 /root 为 0700），自动改到该用户家目录
  再执行，避免：
    The current working directory must be readable to linuxbrew to run brew.

环境变量：
  BREW_USER                  默认专用用户
  BREW_QUIET=1               关闭 root 身份借用提示
  HTTPS_PROXY / HTTP_PROXY / ALL_PROXY
  HOMEBREW_* 镜像相关变量

示例：
  brewr install fd
  brewr --user linuxbrew update
  BREW_USER=linuxbrew brewr search gdu
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
    id "$brew_user" > /dev/null 2>&1 || {
        _brew_error "brew user does not exist: $brew_user"
        _brew_error "as root, create and install with: install_linuxbrew --user $brew_user"
        _brew_error "or: install_brew --user $brew_user --create-user"
        return 1
    }
    brew_bin=$(_brew_find_binary "$brew_user") || {
        _brew_error "cannot find Homebrew installed for user $brew_user"
        _brew_error "install with: install_linuxbrew --user $brew_user"
        _brew_error "or: install_brew --user $brew_user --create-user"
        return 1
    }
    if [ "${BREW_QUIET:-}" != 1 ]; then
        printf '[brew] 当前身份: root (uid %s)，借用用户 %s 执行 brew\n' "$(id -u)" "$brew_user" >&2
        if [ "${#args[@]}" -gt 0 ]; then
            printf '[brew] 命令: %s %s\n' "$brew_bin" "${args[*]}" >&2
        else
            printf '[brew] 命令: %s\n' "$brew_bin" >&2
        fi
    fi
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
    _brew_compat_keyutils_preload
    [ -z "${LD_LIBRARY_PATH:-}" ] || env_args+=("LD_LIBRARY_PATH=$LD_LIBRARY_PATH")
    _brew_exec_as_user "$brew_user" "${env_args[@]}" -- "$brew_bin" "${args[@]}"
}

uninstall_brew() {
    local installer_file target_user='' url='https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh'
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                cat << 'EOF'
用法：uninstall_brew [--user USER]

下载并运行 Homebrew 官方卸载脚本。

选项：
  -h, --help             显示本帮助
  -u, --user USER        root 时以该用户身份卸载其拥有的安装

说明：
  这不会删除 linuxbrew 系统账号。若要同时清掉专用用户和 /home/linuxbrew，
  请用 cleanup_linuxbrew_dedicated_user --execute。
  install_brew --uninstall 也会转到本函数。

示例：
  uninstall_brew
  uninstall_brew --user linuxbrew
EOF
                return 0
                ;;
            -u | --user)
                [ "$#" -ge 2 ] || return 2
                target_user=$2
                shift
                ;;
            *)
                _brew_error "unknown option: $1"
                return 2
                ;;
        esac
        shift
    done
    _brew_need_command curl || return
    installer_file=$(mktemp "${TMPDIR:-/tmp}/brew-uninstall.XXXXXX") || return 1
    _brew_info "downloading official uninstaller from $url"
    if ! curl -fsSL --retry 2 "$url" --output "$installer_file"; then
        rm -f "$installer_file"
        return 1
    fi
    _brew_run_installer "$installer_file" "$target_user" false
    local uninstall_status=$?
    rm -f "$installer_file"
    return "$uninstall_status"
}

# install_brew 的别名，兼容 brew_install --user linuxbrew --create-user 这种叫法。
brew_install() { install_brew "$@"; }

# root 仅在已经找到 linuxbrew 的 brew 文件时设置 alias。
# 未安装时不要定义 brew 函数，否则 command -v brew 会误报已安装。
_brew_compat_keyutils_preload
if [ "$(id -u)" -eq 0 ] && _brew_is_linux; then
    unset -f brew 2> /dev/null || true
    _brew_enable_root_alias --quiet 2> /dev/null || true
fi
