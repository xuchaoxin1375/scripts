#!/usr/bin/env bash
# brew包管理器相关函数
# 用户管理相关函数

# 创建一个带有sudo使用权限的linux用户,尽量实现幂等性;
# 创建前会做判断,避免重复创建已有用户.
# 考虑安全性和便利性,默认不在内部直接命令行中设置密码;
# 如果要设置密码,建议在创建之后使用sudo passwd <username> 的方式为指定用户设置密码!
#  usage:
#       new_user_sudo [options] [username]
#  options:
#     -h, --help: 显示帮助信息
#     -p, --addpwd: 创建用户后调用passwd 命令添加密码(不是直接将密码作为命令参数,而是从标准输入读取密码)
#     -P, --set-random-pwd: 创建用户后调用chpasswd 命令添加随机密码
#     -A, --addsudo: 创建用户后添加sudo权限
#     -N, --no-sudo-password: 调用sudo命令时,不输入密码(慎重)
#     -s, --shell: 指定用户登录shell,默认为/bin/bash
new_user_sudo() {

    #根据需要更改要操作的用户名,例如linuxbrew
    local username="linuxbrew"
    local add_passwd=false
    local add_random_passwd=false
    local add_sudo=false
    local no_sudo_password=false
    local shell="/bin/bash"
    # 参数解析
    usage="
    usage:
      new_user_sudo [options] [username]
    options:
      -h, --help: 显示帮助信息
      -p, --addpwd: 创建用户后调用passwd 命令添加密码(不是直接将密码作为命令参数,而是从标准输入读取密码)
      -P, --set-random-pwd: 创建用户后调用chpasswd 命令添加随机密码
      -A, --addsudo: 创建用户后添加sudo权限
      -N, --no-sudo-password: 调用sudo命令时,不输入密码(慎重)
      -s, --shell: 指定用户登录shell,默认为/bin/bash
    "
    local args_pos=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                return 0
                ;;
            -p | --addpasswd)
                add_passwd=true
                ;;
            -P | --set-random-pwd)
                add_random_passwd=true
                ;;
            -A | --addsudo)
                add_sudo=true
                ;;
            -s | --shell)
                local shell="$2"
                shift
                ;;
            -N | --no-sudo-password)
                no_sudo_password=true
                ;;
            --)
                shift
                break
                ;;
            -?*)
                echo "Unknown option: " >&2
                echo "$usage"
                return 2
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    set -- "${args_pos[@]}"
    username="${1:-linuxbrew}"
    # 参数解析并调整完毕
    if ! command -v sudo &> /dev/null; then
        echo "[sudo] command is not available."
        return 2
    elif ! command -v visudo &> /dev/null; then
        echo "[visudo] command is not available."
        return 2
    fi
    # 避免重复创建已有用户
    if id "$username" > /dev/null 2>&1; then
        echo "用户 $username 已存在，跳过创建。"
    else
        # sudo useradd -m -s /bin/bash "$username" # 配置该用户默认使用bash
        # 1. 检查 useradd 命令是否存在
        if command -v useradd > /dev/null 2>&1; then
            echo "使用 useradd 创建用户..."
            sudo useradd -m -s "$shell" "$username"

        # 2. 如果 useradd 不可用，尝试使用 adduser
        elif command -v adduser > /dev/null 2>&1; then
            echo "useradd 不可用，尝试使用 adduser..."
            # 注意：adduser 在某些发行版中是交互式的，这里使用 --disabled-password 跳过交互
            # --gecos "" 用于填充用户信息字段，避免交互
            sudo adduser --disabled-password --gecos "" --shell /bin/bash "$username"

        else
            echo "错误：系统中未找到 useradd 或 adduser 命令。"
            return 1
        fi
    fi
    if [[ $add_passwd == true ]]; then
        passwd "$username"
    elif [[ $add_random_passwd == true ]]; then
        # 生成 16 位仅包含字母和数字的随机密码
        NEW_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
        echo "高强度密码参考(请复制备用): $NEW_PASS"
        echo "$username:$NEW_PASS" | sudo chpasswd # chpasswd: 专门为脚本设计。它接收 用户名:密码 格式的标准输入
        echo "按回车键继续..."
        read -r _dummy
        echo "" # 换行，防止后续输出跟在提示词后面
    fi
    # 集中判断是否要添加到sudo组,授予sudo权限;
    if [[ $add_sudo == true ]]; then
        echo "正在添加 $username 到 sudo 组..."
        # 添加用户到 sudo 组,使其有权限调用sudo
        # 但默认情况下,每次执行 sudo 时，系统仍然会要求输入该用户自己的密码。
        usermod -aG sudo "$username"

    fi
    # 设置特定的用户（或组）在执行命令时，不需要验证密码。
    if [[ $no_sudo_password == true ]]; then
        #  创建一个包含新规则的临时文件
        echo "$username ALL=(ALL) NOPASSWD: ALL" > /tmp/new_sudo_rule

        #  使用 visudo 验证临时文件的语法
        if visudo -c -f /tmp/new_sudo_rule; then
            echo "语法正确，正在合并..."
            #  将验证通过的规则追加到 /etc/sudoers.d/ 目录下的一个新文件中
            sudo install -m 440 /tmp/new_sudo_rule /etc/sudoers.d/alice_nopasswd
            echo "✅ 用户 $username 已被授予无密码 sudo 权限。"
        else
            echo "❌ 语法错误！规则未被应用。"
            rm /tmp/new_sudo_rule
            return 1
        fi
        #  清理临时文件
        rm /tmp/new_sudo_rule
    fi

}
# 删除用户,并清理残留进程
remove_user_safe() {
    local target_user=$1
    if [ -z "$target_user" ]; then
        echo "请输入用户名再重新试一次."
        return 1
    fi

    echo "正在清理用户 $target_user 的进程..."
    sudo pkill -u "$target_user"

    echo "正在删除用户及其家目录..."
    sudo userdel -r "$target_user" 2> /dev/null

    echo "检查残留的组信息..."
    grep "$target_user" /etc/group
}
# 配置homebrew路径相关的环境变量(和镜像环境变量不同)到配置文件中
set_brew_path_env_to_shellrc() {
    # 参数解析
    local usage='
    配置homebrew路径相关的环境变量(和镜像环境变量不同)到配置文件中;
    定位到安装brew安装路径后会立即更新shell环境变量,无需手动刷新配置或重载shell
    options:
      -h, --help    显示帮助信息
      --remove      删除brew路径相关的环境变量配置
      --reset       重置brew路径相关的环境变量配置(移除旧有行,重新插入到shell配置文件末尾)
                    
    '
    local remove=false
    local reset=false
    local args_pos=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                return 0
                ;;
            --remove)
                remove=true
                ;;
            --reset)
                reset=true
                ;;
            --)
                shift
                break
                ;;
            -?*)
                echo "Unknown option: " >&2
                echo "$usage"
                return 2
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    set -- "${args_pos[@]}"
    # 参数解析并调整完毕
    # 先检测是否已经有brew shellenv相关的配置,如果有提示用户是否继续
    # 获取匹配到的文件名列表
    # result=$(grep -l '/bin/brew shellenv' ~/.bashrc ~/.zshrc 2> /dev/null)
    local result=()
    local shellrcs=(~/.bashrc ~/.zshrc ~/.bash_profile ~/.zprofile)
    while IFS= read -r file; do
        result+=("$file")
    done < <(grep -l 'brew shellenv' "${shellrcs[@]}" 2> /dev/null)
    # debug:
    # echo "result: ${result[*]}"
    # printf "%s\n" "${result[@]}"
    echo "修改前预览相关配置文件中的相关行..."
    _check_brew_shellenv_line() {
        for rc in "${shellrcs[@]}"; do
            test -e "$rc" && command grep --color -H '/bin/brew shellenv' "$rc"
        done
    }
    _check_brew_shellenv_line
    if [ "${result[*]}" -gt 0 ]; then
        echo "在以下文件[${#result[@]}]个文件中发现了配置brew shellenv行:"
        printf "%s\n" "${result[@]}"
        # 检查是否移除配置行
        if [[ $remove == true || $reset == true ]]; then
            echo "正在删除brew shellenv行..."
            for file in "${result[@]}"; do
                sed -i '/[^#]*brew shellenv/d' "$file" &&
                    echo "brew shellenv行已从${file}文件删除。"
            done
            if [[ $remove == true ]]; then
                echo "brew shellenv行已从所有相关配置文件中删除。"
                return 0
            fi
        else
            if ! confirm "是否继续添加?" "n"; then
                echo "已取消操作。"
                return 0
            fi
        fi
    fi
    echo "添加brew shellenv行到配置文件中..."

    # tuna源的方案:
    # arch=$(uname -m)
    # if is_darwin; then
    #     if [[ $arch == "arm64" ]]; then
    #         # shellcheck disable=SC2016
    #         test -r ~/.bash_profile && echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bash_profile
    #         # shellcheck disable=SC2016
    #         test -r ~/.zprofile && echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    #     fi
    # elif is_linux; then
    #     test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
    #     test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    #     test -r ~/.bash_profile && echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bash_profile
    #     test -r ~/.profile && echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.profile
    #     test -r ~/.zprofile && echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.zprofile
    # fi

    # 判断系统平台,找到正确的brew路径并执行shellenv命令生成环境变量设置语句;在通过eval注入到当前环境中;
    # 注意:下面到片段定位到brew的安装目录后会立刻执行eval命令将立刻注入和修改环境变量设置(包括PATH变量)
    # 也就是运行此函数的交互式终端能够直接运行brew(且已经能够由brew --prefix计算安装路径,替换命令字符串模板,追加到配置文件中)
    if [[ $OSTYPE == linux* ]]; then
        test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
        test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    elif [[ $OSTYPE == darwin* ]]; then
        # 针对 Apple Silicon Mac
        test -d /opt/homebrew && eval "$(/opt/homebrew/bin/brew shellenv)"
        # 针对 Intel Mac
        test -d /usr/local/bin/brew && eval "$(/usr/local/bin/brew shellenv)"
        # mac的shell启动行为和linxu的差异,额外关注.bash_profile和.zprofile
        echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bash_profile
        echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.zprofile
    fi
    # 插入到shell配置文件中以便持久化
    echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bashrc
    echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.zshrc
    # 检查配置结果:
    _check_brew_shellenv_line
    echo "如果要移除多余的brew shellenv行,请执行: set_brew_path_env_to_shellrc --reset "

}
# 卸载homebrew
uninstall_brew() {
    echo "正在下载brew卸载脚本...参考[https://github.com/Homebrew/install#uninstall-homebrew]"
    # 从github拉去卸载脚本并执行
    /bin/bash -c "$(curl -fSL "$github_mirror"https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
    # 移除默认安装目录(如果之前的安装中断或者不完整):
    echo "移除默认安装目录可能需要管理员权限,如果需要,考虑将此函数导出(export),
                然后用类似于sudo bash -c 的命令方式运行此函数,或者自行手动删除brew安装目录;"
    local brew_home
    # brew_home0=$(brew --prefix) #brew未必可用
    # 下面针对安装中途卡死或失败的的情况下执行的简单安装目录清理
    brew_home0=/home/linuxbrew
    brew_home1=/home/linuxbrew/.linuxbrew
    brew_home2=/opt/homebrew
    brew_home3=/usr/local/homebrew
    brew_homes=("$brew_home0" "$brew_home1" "$brew_home2" "$brew_home3")
    for brew_home in "${brew_homes[@]}"; do
        if [[ -d $brew_home ]]; then
            echo "尝试移除目录: [$brew_home] "
            if command -v sudo &> /dev/null; then
                echo "使用sudo权限移除目录: $brew_home"
                sudo rm -rf "$brew_home"
            else
                rm -rf "$brew_home"
            fi
        fi
    done
}
# 从当前shell会话中中删除HOMEBREW环境变量
unset_brew_envs() {
    unset HOMEBREW_BREW_GIT_REMOTE
    unset HOMEBREW_API_DOMAIN
    unset HOMEBREW_CORE_GIT_REMOTE
    unset HOMEBREW_BOTTLE_DOMAIN
}
# 从常用shell配置文件中删除HOMEBREW环境变量(todo:交互确认)
remove_brew_env_in_shellrcs() {
    unset_brew_envs
    # 1. 探测当前系统的 sed 类型
    if sed --version > /dev/null 2>&1; then
        # GNU sed 支持 --version
        sed_cmd=(sed -i)
    else
        # BSD/Mac sed 不支持 --version
        sed_cmd=(sed -i '')
    fi

    # 2. 执行循环
    for file in ~/.zshrc ~/.bashrc ~/.bash_profile; do
        if [ -f "$file" ]; then
            echo "正在清理: $file"
            "${sed_cmd[@]}" '/^[[:space:]]*export[[:space:]][[:space:]]*HOMEBREW_/d' "$file"
        fi
    done
}
# 从国内镜像源安装brew(默认中科大源镜像源)
install_brew_cn() {

    # 参数解析
    # usage: '"${FUNCNAME[0]}"' [options] # ${FUNCNAME[0]}在bash中支持,但是zsh不支持,用$funcstack[1]
    local usage='
        国内用户安装homebrew(使用镜像加速)
        usage: 
            install_brew_cn [options]
        options:
            -h, --help      显示帮助信息
            -s, --source    指定镜像源,可用镜像包括:ustc,tuna,aliyun,github;
                            ustc成功率最高;
                            tuna可能需要排队;
                            aliyun镜像方案比较老旧,容易失败;
                            github不使用国内镜像(走brew的官方默认源,如果用此方案建议设置终端代理或者镜像,否则国内会很慢甚至失败);

            -u, --user      指定brew安装用户,默认为当前用户
                            (通常(普通用户)而言,此选项是可省略的,但是对于当前用户是root的情况下,此选项是必须的),
                            推荐的值是homebrew,但也可以是其他非root名称;
            -b, --installer-source 指定brew本体的安装脚本来源(和镜像相对独立),可用值和特点参考[-s]选项;
            -R,--reset-mirror  重置为官方源(github)
            --force          强制重新设置brew环境变量(即便之前有安装设置过的迹象)
            --uninstall      卸载brew
            -g, --github-mirror  使用github镜像加速github链接
                            (默认使用:https://gh-proxy.com/,如果不可用,可以自行搜索其他github加速镜像网址)
                            如果要禁用镜像加速,请指定为空字符串""
            -U,--update-mirror-only 开关参数:仅更新brew镜像源配置,不执行安装(适用于已经安装了brew,但想要切换镜像源的情况);
                                    执行完成后,要执行brew update;
    '
    local args_pos=()
    local mirror='ustc'
    local installer_source="ustc"
    local reset_mirror=false
    local force=false
    local uninstall=false
    local update_mirror_only=false
    local github_mirror="https://gh-proxy.com/"
    local write_env_rc=true
    local user
    # 确保github镜像地址以/结尾:
    if [[ $github_mirror == http* ]]; then
        github_mirror="${github_mirror%/}/"
    fi
    # 参数解析(不建议包装到内部函数parse_args中,不然不方便执行中断,例如-h打印帮助后立即停止执行)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                return 2
                ;;
            -s | ---source | --mirror)
                mirror="$2"
                shift
                ;;
            -u | --user)
                user="$2"
                shift
                ;;
            -b | --installer-source)
                installer_source="$2"
                shift
                ;;
            -R | --reset-mirror)
                mirror="github"
                installer_source="github"
                reset_mirror=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            -g | --github-mirror)
                github_mirror="$2"
                shift
                ;;
            -U | --update-mirror-only)
                update_mirror_only=true
                ;;
            # --write-env-rc)
            #     write_env_rc=true
            --uninstall)

                uninstall=true
                ;;
            --)
                shift
                break
                ;;
            -?*)
                echo "Unknown option: " >&2
                echo "$usage"
                return 2
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    # 位置参数重排(如果有的话)
    set -- "${args_pos[@]}"
    # 检查位置参数:
    if [[ ${#args_pos[@]} -gt 1 ]]; then
        echo "错误: 不支持超过1个的位置参数: ${args_pos[*]}" >&2
        echo "$usage" >&2
        return 1
    elif [[ ${#args_pos[@]} -eq 1 ]]; then
        mirror="${args_pos[1]}"
    fi
    # 参数解析并调整完毕

    if [[ $uninstall == true ]]; then
        uninstall_brew
        return $?
    fi

    # 判断是否需要设置(镜像源)环境变量到shellrc文件中
    # HOMEBREW_BREW_GIT_REMOTE变量已经存在(且非空),同时不要求强制插入配置也不是专门要配置更新配置的情况下,则跳过环境变量配置更新操作
    if [[ $HOMEBREW_BREW_GIT_REMOTE && $force == false && $update_mirror_only == false ]]; then
        write_env_rc=false
        echo "HOMEBREW_BREW_GIT_REMOTE is already set to $HOMEBREW_BREW_GIT_REMOTE (in somewhere else), skipping adding to shellrc"
        # 显示当前相关环境变量
        set | grep '^HOMEBREW' | grep https
    fi
    # 是否重置镜像源
    if [[ $reset_mirror == true ]]; then
        echo "重置为官方源..."
        unset_brew_envs
        git -C "$(brew --repo)" remote set-url origin https://github.com/Homebrew/brew
        # 其他(tap)相关
        BREW_TAPS="$(
            BREW_TAPS="$(brew tap 2> /dev/null)"
            echo -n "${BREW_TAPS//$'\n'/:}"
        )"
        for tap in core cask{,-fonts,-versions} command-not-found services; do
            if [[ ":${BREW_TAPS}:" == *":homebrew/${tap}:"* ]]; then
                brew tap --custom-remote "homebrew/${tap}" "https://github.com/Homebrew/homebrew-${tap}"
            fi
        done

        brew update

        echo "请检查shell的配置文件,如果之前永久配置了 HOMEBREW 环境变量，还需要在对应的 ~/.bash_profile 或者 ~/.zshrc 配置文件中，将对应的 HOMEBREW 环境变量配置行注释或者删除!"

        remove_brew_env_in_shellrcs

    fi
    # 判断是否已经安装过brew:
    # command -v brew > /dev/null 2>&1
    is_brew_installed() {
        if command -v brew > /dev/null 2>&1; then
            local brew_version
            brew_version=$(brew --version 2> /dev/null)
            if [[ $brew_version ]]; then
                echo "Homebrew/Linuxbrew 已安装[$brew_version]."
                if [[ $update_mirror_only == false && $force == false ]]; then
                    echo "不执行任何操作,退出程序;"
                    return 1 # 退出安装
                fi
            else
                echo "正在准备安装homebrew..."
                return 0
            fi
        fi
    }
    is_brew_installed || exit 1
    # 设置源
    local mirror_env=""
    # ustc mirror
    local ustc_env='
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
    export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
    export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
    '
    local tuna_env='
    export HOMEBREW_INSTALL_FROM_API=1
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
    export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
    export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
    export HOMEBREW_PIP_INDEX_URL="https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple"
    '
    local aliyun_env='
    export HOMEBREW_INSTALL_FROM_API=1
    export HOMEBREW_API_DOMAIN="https://mirrors.aliyun.com/homebrew-bottles/api"
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/homebrew-core.git"
    export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles"
    '
    local github_env='
    # 官方源不使用镜像加速,或者考虑使用github加速镜像
    '
    # 选择目标镜像源
    if [[ $mirror == "tuna" || $installer_source == "tuna" ]]; then
        echo "使用tuna镜像可能要排队(高负载情况下),时间可能需要十来分钟!"
    fi
    case "$mirror" in
        ustc)
            mirror_env="$ustc_env"
            ;;
        tuna)
            mirror_env="$tuna_env"
            ;;
        aliyun)
            mirror_env="$aliyun_env"
            ;;
        github)
            mirror_env="$github_env"
            # unset HOMEBREW_BREW_GIT_REMOTE
            remove_brew_env_in_shellrcs
            if command -v brew &> /dev/null; then
                # brew update-reset "$(brew --repo)"
                git -C "$(brew --repo)" remote set-url origin https://github.com/Homebrew/brew
            fi
            ;;
        *)
            echo "Unknown mirror: $mirror. " >&2
            echo "$usage" >&2

            return 1
            ;;
    esac
    # 移除多余的换行符
    local mirror_trimed

    # shellcheck disable=SC2001
    mirror_trimed=$(
        cat << EOF
$(echo "$mirror_env" | sed 's/^[[:space:]]*//')
EOF
    )
    echo "${mirror_trimed}"

    # 按需临时执行环境变量设置语句片段
    if [[ $mirror_env ]]; then
        # source <(echo -e "${ustc_env//$'\n'/ \\$'\n'}\\")
        eval "$mirror_env"
        # 将环境变量设置语句片段转换为适合sed插入到shellrc文件中的格式
        # local mirror_forsed="${mirror_trimed//$'\n'/ \\$'\n'}\\" # bash中可以工作,但是zsh中可能会有不同效果
        # echo -e "${ustc_env//$'\n'/ \\$'\n'}\\"
    fi
    # 检查安装用户
    [[ $user ]] && new_user_sudo "$user" -N
    # 如果没有指定用户,则默认尝试当前用户
    [[ ! $user ]] && user=$(whoami)
    # 如果是root,退出安装
    if [[ $user == "root" ]]; then
        echo "请勿使用root用户安装brew,指定其他普通用户名,例如homebrew"
        exit 1
    fi
    # 从指定镜像获取脚本并开始安装brew
    start_install_brew() {
        case "$installer_source" in
            ustc)
                echo "使用中科大镜像源安装homebrew..."
                sudo -u "$user" /bin/bash -c "$(curl -fsSL https://mirrors.ustc.edu.cn/misc/brew-install.sh)"
                ;;
            tuna)
                echo "使用清华大学镜像源安装homebrew..."
                # 从镜像下载安装脚本并安装 Homebrew / Linuxbrew
                git clone --depth=1 https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.git ~/brew-install
                sudo -u "$user" /bin/bash ~/brew-install/install.sh
                rm -rf ~/brew-install

                ;;
            aliyun)
                # 从阿里云下载安装脚本并安装 Homebrew
                sudo -u "$user" git clone https://mirrors.aliyun.com/homebrew/install.git brew-install
                /bin/bash brew-install/install.sh
                rm -rf brew-install
                ;;
            github)
                echo "使用官方源安装homebrew..."
                # 也可从 GitHub 获取官方安装脚本安装 Homebrew / Linuxbrew
                sudo -u "$user" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

                ;;
        esac
    }

    # 定义内部函数:幂等地添加brew 镜像相关的环境变量到指定文件中
    _set_brew_mirror_env_to_shellrc() {
        # local shellrc="$1"
        for shellrc in "$@"; do
            ! [[ -f "$shellrc" ]] && touch "$shellrc"
            if [ -f "$shellrc" ]; then
                # break
                sed -i '/# >>> brew mirror env/,/# <<< brew mirror env/d' "$shellrc"
                echo "正在将brew镜像环境变量添加到shell配置文件 [$shellrc] 中..."
                # sed方案
                #                 sed -i '$a\
                # # >>> brew mirror env\
                # '"$mirror_forsed"'
                # # <<< brew mirror env\
                # ' "$shellrc"
                # 重定向追加的方案
                cat << EOF >> "$shellrc"
# >>> brew mirror env
$mirror_trimed
# <<< brew mirror env
EOF
            fi
        done
    }
    # 判断是否需要插入到shellrc文件中(用户可能已经通过别的方式导入相关的环境变量)
    set_brew_mirror_env_to_shellrc() {
        if [[ $write_env_rc == true ]]; then
            if [[ $mirror ]]; then
                echo "正在将brew镜像环境变量添加到shellrc文件中..."
                # 对于bash用户
                _set_brew_mirror_env_to_shellrc ~/.bashrc ~/.zshrc ~/.bash_profile
            # 对于macos,可能需要写入.bash_profile
            # 对于 zsh 用户
            # _set_brew_mirror_env_to_shellrc ~/.zshrc
            else
                echo "没有指定镜像源,跳过添加brew镜像环境变量到shellrc文件中..."
            fi
        fi
    }

    echo "更新镜像源环境变量配置到常用shellrc中..."
    set_brew_mirror_env_to_shellrc
    # 开始安装
    if [[ $update_mirror_only == true ]]; then
        echo "跳过后续的安装操作(更新完homebrew镜像环境变量后需要执行brew update)..."
        return 0
    else
        start_install_brew
    fi
    # set_brew_mirror_env_to_shellrc
    set_brew_path_env_to_shellrc
    # 查看PATH环境变量中是否包含了brew的路径
    echo "$PATH" | tr ':' '\n' | grep brew
    # /home/linuxbrew/.linuxbrew/bin
    # /home/linuxbrew/.linuxbrew/sbin

}

install_linuxbrew() {

    local usage
    usage=$(
        cat << EOF
安装homebrew(linuxbrew for linux root user.)
此脚本适用于国外服务器(或网络条件好的情况),尤其是只有root用户的情况下,可考虑创建brew专用用户;
    默认使用默认用户名linuxbrew,如果指定用户名不存在,则创建
    用户名：建议简单明确，如 linuxbrew 或 brew。
    权限：该用户需要能通过 sudo 执行安装任务，但严禁拥有免密登录你个人账户的权限。
    Shell：建议设置为标准的 /bin/bash（因为 Brew 的安装脚本大量使用 Bash）。
    家目录：必须有独立的 /home/linuxbrew，因为 Linuxbrew 默认最理想的安装路径是 /home/linuxbrew/.linuxbrew（这可以让你直接使用官方提供的预编译 Binary，而不需要从源码编译，节省大量时间）。

usage:
    install_linuxbrew [options] [username]

    注意:相关依赖不会自动安装(当依赖程序不存在是请自行安装,例如使用系统自带包管理器安装)
    
    国内网络用户(非root用户户下):如果没条件配置代理(或者代理设置不便)
    对于个人电脑,考虑国内方案:
    - 本文shell模块提供的方案: source <(curl -fsSL https://raw.giteeusercontent.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/shell_utils/brew.sh)
    - https://brew-cn.mintimate.cn/
    - https://gitee.com/cunkai/HomebrewCN #cn方案
install_brew_cn # 添加-h选项查看帮助(默认使用ustc源安装)
    对于linux用户,使用上述方案可能卡住要多试几下(过程中并非全程快速下载,部分组件依然可能因为网络耗时);

options:
    -u,--user <username> 指定用户名(默认为linuxbrew)
    -h,--help 显示帮助
documents:
    https://docs.brew.sh/
    https://docs.brew.sh/Homebrew-on-Linux
reference
    - uninstall:https://github.com/homebrew/install#uninstall-homebrew
mirror:
    - https://mirrors.ustc.edu.cn/help/brew.git.html
    - https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/
    - https://developer.aliyun.com/mirror/homebrew
requirements:
    安装系统依赖：在运行 Homebrew 安装脚本前，确保系统已安装必要的构建工具。根据你的 Linux 发行版运行相应命令：

- Debian 或 Ubuntu: sudo apt-get install build-essential procps curl file git
- Fedora: sudo dnf group install development-tools 和 sudo dnf install procps-ng curl file
- CentOS Stream 或 RHEL: sudo dnf group install 'Development Tools' 和 sudo dnf install procps-ng curl file
- Arch Linux: sudo pacman -S base-devel procps-ng curl file git

EOF
    )
    # 参数解析

    # 安装linuxbrew时使用的用户(优先考虑当前用户安装,如果不是root的话)

    # 检查当前用户是否为root
    if [ "$(id -u)" -ne 0 ]; then
        echo "请使用root用户执行此脚本"
        local username="${1:-linuxbrew}"
    else
        # 为当前用户安装
        local username="${1:-$(whoami)}"
    fi

    local args_pos=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u | --user)
                username="$2"
                shift
                ;;
            -h | --help)
                echo "$usage"
                return 0
                ;;
            --)
                shift
                break # -- 后面的都是普通参数,使用break结束选项参数的解析.
                ;;
            -?*)
                echo "Unknown option: " >&2
                show_help
                return 2
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    set -- "${args_pos[@]}"
    # 参数解析并调整完毕

    echo "checking username [$username]..."
    # 判断是否已经安装过brew:
    if command -v brew > /dev/null 2>&1; then
        echo "Homebrew/Linuxbrew 已安装;如果需要重新安装,请移除brew(查看帮助中的链接)."
        brew --version
        return 1 # 退出安装
    else
        echo "正在准备安装homebrew..."
    fi
    echo "检查安装用户..."
    # 默认创建的是无密码(锁定)用户,只能通过 su - username 切换的方式登录该用户
    new_user_sudo "$username" -N
    # 使用指定的已存在的非root用户(但是能够使用sudo的用户,例如linuxbrew)安装brew:
    # /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    sudo -u "$username" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # 插入brew的配置片段到shell rc
    local shell_rc_to_config
    if [[ ${#args_pos} -gt 0 ]]; then
        shell_rc_to_config=("${args_pos[@]}")
    else
        shell_rc_to_config=(bash zsh)
    fi
    # if confirm "insert brew config to shell rc?"; then
    # fi
    test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
    test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    # 计算需要插入的shell rc片段
    for shellname in "${shell_rc_to_config[@]}"; do
        # eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" #被插入的片段参考
        # 判断相关片段是否已经存在于配置文件,如果不存在,则插入
        grep -q '^[^#].*brew shellenv' ~/."$shellname"rc ||
            echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/."$shellname"rc
        # echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.zshrc
        # 查看相关配置是否插入成功
        grep -Hn 'brew shellenv' ~/."$shellname"rc
    done
    echo "[INFO]:Reload shell rc file to take effect..."
    # exec "$0" # 不要在函数中直接执行此行,交互式中才可以
    echo "[INFO]:Run command: exec \$SHELL"
    # 针对常用shell尝试自动刷新配置生效
    is_shell "zsh" && exec zsh
    is_shell "bash" && exec bash

}
# 运行brew命令(借用linuxbrew用户权限)
# 为了防止和macos brew冲突,这里不直接命名为brew,而是增加后缀作区分;
# 可以在别名配置或者shell配置文件中判断系统类型,然后按需设置brew别名
# brew(linuxbrew)拒绝root用户直接运行,并且默认安装路径是/home/linuxbrew/.linuxbrew
# 添加brew配置到PATH
# - Run these commands in your terminal to add Homebrew to your PATH:
# echo >> /home/cxxu/.zshrc
# echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"' >> /home/cxxu/.zshrc
# eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"
brewr() {
    # 检查当前是否为 root 用户 (UID 0)
    # 默认的用户身份从环境变量中读取,如果没有
    local BREW_USER="${BREW_USER:-linuxbrew}"
    local usage='
    usage:
        brewr [options]
    options
        -u,--user,--brew-user 指定用户身份运行brew
        -h,--help 打印帮助信息
    
    '
    local extra_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u | --user | --brew-user)
                BREW_USER="$2"
                shift
                ;;
            -h | --help)
                echo "$usage"
                return 0
                ;;
            # -?*) # 为了传递完整参数列表(包括选项)给brew,这里不建议捕获-?*)
            #     echo "Invalid option"
            #     echo "$usage"
            #     return 2
            #     ;;
            *)
                extra_args+=("$1")
                ;;
        esac
        shift
    done
    set -- "${extra_args[@]}"
    echo "brew params:[$*]" >&2
    if [ "$(id -u)" -eq 0 ]; then
        # 如果未设置 BREW_USER，则给出提示并退出
        if [ -z "$BREW_USER" ]; then
            echo "[ERROR] Brew cannot run as root. Please set BREW_USER environment variable."
            echo "
            Set environment variable: 
                export BREW_USER='your_username'
            Write it to your shellrc file to make it permanent.
            "
            return 1
        fi

        # 执行逻辑：切换到指定用户运行
        local ORIG_DIR="$PWD"
        echo "[INFO]:brew for root user [mod from linuxbrew]."
        echo "[INFO]:Executing as '$BREW_USER': brew $*"

        # 建议切换到该用户的家目录，避免权限报错
        cd "/home/$BREW_USER" 2> /dev/null || return 1
        # 使用指定用户身份执行标准安装的brew
        sudo -u "$BREW_USER" /home/linuxbrew/.linuxbrew/bin/brew "$@"
        local EXIT_CODE=$?

        cd "$ORIG_DIR" 2> /dev/null || return 1
        return $EXIT_CODE
    else
        # 如果不是 root 用户，直接调用原始的 brew 命令
        # 注意避免递归调用!
        command brew "$@"
    fi
}
