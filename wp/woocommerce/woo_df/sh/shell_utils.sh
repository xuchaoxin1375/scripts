#!/bin/bash
# 提供一些常用的bash/zsh兼容的函数.
# 新函数添加于下方:
# ===============================
echo "Loading shell_utils.sh..."
# 临时清理历史遗留配置(2026.5月份后移除)
cleanrc() {

    sed -i '/^# Load additional shell configs$/d; 
        /^# shellcheck source=\/www\/sh\/shell_utils\.sh$/d; 
        /^# >>>custom additional shell>>>$/d; 
        /^# <<<custom additional shell<<<$/d; 
        /^# >>>additional shell configs>>>$/d; 
        /^# <<<additional shell configs<<<$/d;
        /^source \/www\/sh\/shellrc_addition\.sh$/d
' ~/.bashrc ~/.zshrc
}
# 列出bash中所有名字以指定字符串开头的变量
list_var_start_with_eval() {
    local var_prefix="$1"
    # 1. 获取所有变量名
    # 2. 筛选出以 $var_prefix 开¡头的变量
    # 3. 循环并使用 eval 提取值
    for item in $(compgen -v); do
        if [[ $item == $var_prefix* ]]; then
            # 使用 eval 动态解析变量的值
            eval "value=\$$item"
            # shellcheck disable=SC2154
            echo "$item=$value"
        fi
    done
}
# 判断当前系统是否为macos(darwin内核)
is_darwin() {

    if [[ $OSTYPE == "darwin"* ]]; then
        return 0
    else
        return 1
    fi
}
# 判断当前系统是否为linux(可能是linux-gnu,linux-musl)
is_linux() {
    if [[ $OSTYPE == "linux"* ]]; then
        return 0
    else
        return 1
    fi
}
is_alpine() {
    if [[ $(get_os_name) == 'Alpine'* ]]; then
        return 0
    else
        return 1
    fi
}
# 查看当前shell中PATH环境变量的取值,对于多值变量换行显示
# 对于非PATH变量,则使用建议使用echo $env_var | tr ':' '\n'
# 或 printenv $env_var | tr ':' '\n' 来查看指定变量的方式查看指定变量
print_env_path() {

    echo "$PATH" | tr ':' '\n'
}
# 查看指定环境变量取值,分割:换行显示
# 不指定值,则打印PATH环境变量
# examples:
#   print_env "$PATH" #建议带上双引号,放置带有空格的变量值单词分割后显示不准确
#   print_env PATH #支持直接传递变量名,但是可靠性不保证(支持bash)
#   print_env "$fpath" -s " " #指定分隔符为空格
print_env() {
    local env
    local separator=':'
    # 参数解析
    # shellcheck disable=SC2016
    usage='
查看指定环境变量取值,分割:换行显示
不指定值,则打印PATH环境变量

Usage: print_env [options] [env]
Options:
    -s [separator]  指定分隔符,默认为":"
    -h,--help       显示帮助信息


examples:
  print_env "$PATH" #建议带上双引号,放置带有空格的变量值单词分割后显示不准确
  print_env PATH #支持直接传递变量名,但是可靠性不保证(支持bash)
  print_env "$fpath" -s " " #指定分隔符为空格
  
'
    local args_pos=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                return 0
                ;;
            -s | --separator)
                separator="$2"
                shift
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
    env="$*"
    # 参数解析并调整完毕
    # echo "value: $env"
    # 定义空参数时的默认行为:
    [[ -z "$env" ]] && env="$PATH"
    # 判断传入的是否为一个变量名,例如PATH,如果是变量名,则获取变量值,以便后续格式化
    # 通过间接易用计算获取变量值(bash语法),zsh用自己的语法
    # Bash 使用：${!var}
    # Zsh 使用：${(P)var},其中 (P) 代表 Parameter expansion
    if ! [[ $env =~ .*[:/].* ]]; then
        if [[ $BASH_VERSION ]]; then
            if [[ -n ${!env+is_var_name} ]]; then # -n选项可以省略
                # echo "$env is a variable name"
                env="${!env}"
            else
                # echo "$env is value of var"
                :
            fi
        # elif [[ $ZSH_VERSION ]]; then
        #     # zsh 专用语法导致shfmt无法执行代码格式化;(todo:将此部分代码移动到zsh专用脚本文件中)
        #     # shellcheck disable=SC2296
        #     if [[ -n ${(P)env+is_var_name} ]]; then
        #         # echo "$env is a variable name"
        #         env="${(P)env}"
        #     else
        #         # echo "$env is value of var"
        #         :
        #     fi
        fi
    fi
    # echo "value: $env"
    echo "$env" | tr "$separator" '\n'
}
# 添加路径到PATH变量中(幂等操作,防止重复添加相同路径造成冗余)
# 对语句 [[ ":$PATH:" != *":/your/path:"* ]] && export PATH="/your/path:$PATH" 的函数封装
add_to_path() {
    # 1. 检查参数是否为空
    if [ -z "$1" ]; then
        return 1
    fi

    # 2. 移除路径末尾可能存在的斜杠（为了匹配的一致性）
    local target_dir="${1%/}"

    # 3. 判断当前 PATH 中是否已包含该路径
    # 使用 [[ :$PATH: == *:$target_dir:* ]] 这种技巧可以精准匹配，
    # 避免子字符串干扰（例如 /usr/bin 匹配到 /bin）
    [[ ":$PATH:" != *":$target_dir:"* ]] && export PATH="$target_dir:$PATH"
    case ":$PATH:" in
        *:"$target_dir":*)
            # 已存在，不做任何操作
            ;;
        *)
            # 不存在，添加到头部
            export PATH="$target_dir:$PATH"
            ;;
    esac
}
# 移除多余空行(大片空行压缩)
remove_redundant_blank_lines() {

    local file="$1"
    sed -i '/^$/N;/^\n$/D' "$file"
}
# 代理配置函数
proxy() {
    # 你的代理地址和端口
    local host_name="localhost"
    local port="7897"
    local proxy_addr=""
    local args_pos=()
    usage="
usage:
    proxy {on|off|status} [OPTIONS]
options:
    -H,--hostname: 代理服务器主机名 (默认: $host_name)
    -p,--proxy: 代理服务器端口 (默认: $port)
    -c,--check: 检查代理是否能够访问指定网站(例如访问google)
    -g: 检查是否能够访问google(设置check_url)
"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -H | --hostname)
                host_name="$2"
                shift
                ;;
            -p | --proxy)
                port="$2"
                shift
                ;;
            -c | --check)
                check_url="$2"
                ;;
            -g)
                check_url="https://www.google.com"

                ;;
            --help)
                echo "$usage"
                return 1
                ;;
            -?*)
                echo "错误: 未知选项 " >&2
                echo "$usage"
                return 2
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    proxy_addr="${host_name}:${port}"
    echo "代理地址: [$proxy_addr]"
    set -- "${args_pos[@]}"
    case $1 in
        on)
            export http_proxy="http://$proxy_addr"
            export https_proxy="http://$proxy_addr"
            export all_proxy="socks5://$proxy_addr"
            echo -e "\033[32m[✔] 已开启终端代理 ($proxy_addr)\033[0m"
            ;;
        off)
            unset http_proxy https_proxy all_proxy
            echo -e "\033[31m[✘] 已关闭终端代理\033[0m"
            ;;
        status)
            if [ -z "$http_proxy" ]; then
                echo -e "当前状态：\033[31m未设置代理\033[0m"
            else
                echo -e "当前状态：\033[32m代理运行中 -> $http_proxy\033[0m"
            fi
            ;;
        *)
            echo "用法: proxy {on|off|status}"
            ;;
    esac
    if [[ $check_url ]]; then
        echo "检查代理是否可用："
        curl -L -m 5 "$check_url" && echo "OK" || echo "Failed!"
    fi
}
# 带有日期时间的简单日志函数,在调试代码时可以代替echo让输出和时间线挂钩
log() {
    local dt
    dt="$(date +%F-%T.%3N)"
    echo "[$dt] $*"
    # echo "[$(date +%F-%T.%3N)] $*"
}

# 使用GNU版本的命令工具集代替macos自带的bsd版工具;
# 通过定义需要添加到 PATH 的 GNU 路径来覆盖系统默认版本的优先级
# 如果没有使用brew安装过,也可以自动快速跳过;
# 例如：/opt/homebrew/opt/coreutils/libexec/gnubin
# macOS 某些自带的系统脚本（.sh）可能依赖 BSD 特有的参数。如果全局强制覆盖，极少数情况下会导致系统工具行为异常。
# 折中方案： 仅针对最常用的 coreutils、sed、grep进行覆盖(findutils,tar)。
set_gnu_instead_bsd() {

    # 如果不是darwin内核(macos),则跳过处理
    if ! is_darwin; then
        return 1
    fi
    echo "Using gnu tool instead bsd version ..."
    GNU_PATHS=(
        "${HOMEBREW_PREFIX}/opt/coreutils/libexec/gnubin"
        "${HOMEBREW_PREFIX}/opt/findutils/libexec/gnubin"
        "${HOMEBREW_PREFIX}/opt/gnu-tar/libexec/gnubin"
        "${HOMEBREW_PREFIX}/opt/gnu-sed/libexec/gnubin"
        "${HOMEBREW_PREFIX}/opt/grep/libexec/gnubin"
    )
    # GNU_PATH=""
    for p in "${GNU_PATHS[@]}"; do
        # 防止已有PATH路径片段重复添加，同时路径存在才添加
        if [[ ":$PATH:" != *":$p:"* ]] && [[ -d $p ]]; then
            PATH="$p:$PATH"
            # GNU_PATH="$p:$GNU_PATH"
        fi
    done
    echo "Set GNU Man pages" #可选
    # export PATH="$GNU_PATH:$PATH"
    export PATH
    export MANPATH="${HOMEBREW_PREFIX}/opt/coreutils/libexec/gnuman:$MANPATH"
}
install_gnu_tools() {
    echo "正在通过 Homebrew 安装 GNU 全家桶..."

    # 核心工具集：ls, cp, mv, cat 等
    brew install coreutils
    # 常用增强工具
    brew install findutils gnu-sed gnu-tar gnu-which gawk gnutls grep

    echo "安装完成！正在配置环境变量..."

    # 获取 Homebrew 的前缀路径 (M系列芯片通常是 /opt/homebrew)
    # HOMEBREW_PREFIX=$(brew --prefix)
    HOMEBREW_PREFIX=${HOMEBREW_PREFIX:-"$(brew --prefix)"}

}
# 检测当前IP是否为中国IP
# shellcheck disable=SC2120
is_china_ip() {
    local verbose=false
    local target=""
    usage="
usage:
    is_china_ip [OPTIONS] [IP]
options:
    -v,--verbose: 显示详细信息
"
    # 参数解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v | --verbose)
                verbose=true
                shift
                ;;
            -h)
                echo "$usage"
                return 1
                ;;
            *)
                # 指定要查询的ip,如果没指定,则查询本机公网ip
                target="$1"
                shift
                ;;
        esac
    done
    # 定义超时
    local time_out="${1:-3}"
    # 一次性请求所有数据
    local response
    response=$(curl -s -m "$time_out" "https://ipinfo.io/${target}")

    # 提取字段
    local ip
    local country
    # 要求ggrep和cut命令
    ip=$(echo "$response" | grep -oE '"ip": *"[^"]+"' | cut -d'"' -f4)
    country=$(echo "$response" | grep -oE '"country": *"[^"]+"' | cut -d'"' -f4)
    # 方案2: 使用 curl 获取数据指定字段(但是要花费2次请求)
    # ip=$(curl -s "https://ipinfo.io/${target}/ip")
    # country=$(curl -s "https://ipinfo.io/${target}/country")

    if [[ "$verbose" == true ]]; then
        echo "---- IP Info ----"
        echo "Target: ${target:-"Localhost"}"
        echo "Public IP: $ip"
        echo "Country: $country"
        echo "-----------------"
    fi

    if [[ "$country" == "CN" ]]; then
        [[ "$verbose" == true ]] && echo "Result: This is a China IP."
        return 0
    else
        [[ "$verbose" == true ]] && echo "Result: This is NOT a China IP."
        return 1
    fi
}
# 覆盖式创建指定路径的符号链接(兼容gnu ln和bsd ln)
# 效果在路径sym_path创建指向target的符号链接(如果sym_path已存在(无论是什么类型文件或目录)，则覆盖)
# 效果:创建符号链接[$2:sym_path]->[$1:target]
# example:
#   ln_update_sym "$SH_SCRIPT_DIR" "$SH_SYM"
ln_update_sym() {
    local target="$1"
    local sym_path="$2"
    [[ -e $sym_path ]] && rm -rf "$sym_path"
    # 单纯使用-nf仍然和gnu ln的 -T选项效果有差别
    ln -snfv "$target" "$sym_path" || {
        echo "[error]:创建符号链接[$sym_path]->[$target] 失败" >&2
        return 1
    }
}
# 从原码编译安装zsh5.9
install_zsh_bymake_short() {
    # 安装依赖
    sudo apt install -y libncurses-dev libpcre2-dev
    cd ~ || exit 1

    # 下载编译
    wget https://sourceforge.net/projects/zsh/files/zsh/5.9/zsh-5.9.tar.xz
    tar xf zsh-5.9.tar.xz
    cd zsh-5.9 || exit 1
    ./configure --prefix=/usr/local
    make -j"$(nproc)"
    sudo make install

    # 验证
    /usr/local/bin/zsh --version
}
# zsh安装器,安装指定版本的zsh,支持指定安装选项
install_zsh_bymake() {
    set -euo pipefail
    usage="
    install_zsh_bymake - Build and install Zsh from source (Linux)

    USAGE:
        install_zsh_bymake [OPTIONS] [VERSION] [PREFIX] [SRC_DIR]
    OPTIONS:
        -h,--help       Print this help message and exit

    DESCRIPTION:
        Compile and install Zsh from source code with automatic dependency handling.
        Designed for reproducibility, idempotency, and cross-distribution compatibility.

    PARAMETERS:
        VERSION     Zsh version to install (default: 5.9)
        PREFIX      Installation prefix (default: /usr/local)
                    Example: /usr/local, /opt/zsh

        SRC_DIR     Source code directory (default: $HOME/src)
                    Used to store downloaded and extracted source files

    FEATURES:
        - Idempotent installation (safe to run multiple times)
        - Automatic dependency installation (apt / yum / dnf)
        - Parallel build using all CPU cores
        - Download caching (avoids repeated downloads)
        - Optional default shell configuration

    EXAMPLES:
        # Install default version (5.9)
        install_zsh_bymake

        # Install specific version
        install_zsh_bymake 5.8

        # Custom install location
        install_zsh_bymake 5.9 /opt/zsh

        # Full customization
        install_zsh_bymake 5.9 /opt/zsh /tmp/build

    FILES:
        Source archive:
            zsh-<VERSION>.tar.xz

        Install path:
            <PREFIX>/bin/zsh

    POST-INSTALL:
        After installation, you may need to re-login for the new shell to take effect.

        To manually switch shell:
            chsh -s <PREFIX>/bin/zsh

    NOTES:
        - Root privileges (sudo) are required for installation
        - Internet connection is required for downloading source code
        - Build tools (gcc, make) will be installed automatically if missing

    TROUBLESHOOTING:
        If build fails:
            - Ensure dependencies are installed
            - Check available disk space
            - Verify network connectivity

        If zsh is not default:
            - Ensure <PREFIX>/bin/zsh is listed in /etc/shells

    SEE ALSO:
        zsh --version
        man zsh
    "
    # 参数解析
    local args_pos=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                return 0
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
    # ===== 参数（configurable parameters）=====
    local ZSH_VERSION="${1:-5.9}"
    local PREFIX="${2:-/usr/local}"
    local SRC_DIR="${3:-$HOME/src}"
    local BUILD_DIR="$SRC_DIR/zsh-$ZSH_VERSION"
    local TAR_FILE="zsh-$ZSH_VERSION.tar.xz"
    local DOWNLOAD_URL="https://downloads.sourceforge.net/project/zsh/zsh/$ZSH_VERSION/$TAR_FILE"

    echo "==> [INFO] Install Zsh $ZSH_VERSION from source"

    # ===== 检查是否已安装（idempotency）=====
    if command -v zsh > /dev/null 2>&1; then
        local CURRENT_VERSION
        CURRENT_VERSION="$(zsh --version | awk '{print $2}')"
        if [ "$CURRENT_VERSION" = "$ZSH_VERSION" ]; then
            echo "==> [SKIP] Zsh $ZSH_VERSION already installed"
            return 0
        else
            echo "==> [INFO] Existing Zsh version: $CURRENT_VERSION (will upgrade)"
        fi
    fi

    # ===== 安装依赖（dependency management）=====
    if command -v apt > /dev/null 2>&1; then
        sudo apt update
        sudo apt install -y \
            build-essential \
            libncurses-dev \
            libpcre2-dev \
            wget \
            xz-utils
    elif command -v yum > /dev/null 2>&1; then
        sudo yum groupinstall -y "Development Tools"
        sudo yum install -y ncurses-devel pcre2-devel wget xz
    elif command -v dnf > /dev/null 2>&1; then
        sudo dnf groupinstall -y "Development Tools"
        sudo dnf install -y ncurses-devel pcre2-devel wget xz
    else
        echo "[ERROR] Unsupported package manager"
        return 1
    fi

    # ===== 准备源码目录（workspace）=====
    mkdir -p "$SRC_DIR"
    cd "$SRC_DIR"

    # ===== 下载源码（download with cache）=====
    if [ ! -f "$TAR_FILE" ]; then
        echo "==> [INFO] Downloading $TAR_FILE"
        wget -O "$TAR_FILE" "$DOWNLOAD_URL"
    else
        echo "==> [CACHE] Using existing $TAR_FILE"
    fi

    # ===== 解压（clean build）=====
    rm -rf "$BUILD_DIR"
    tar xf "$TAR_FILE"
    cd "$BUILD_DIR"

    # ===== 配置（configure step）=====
    ./configure \
        --prefix="$PREFIX" \
        --enable-multibyte \
        --with-tcsetpgrp

    # ===== 编译（parallel build）=====
    make -j"$(nproc)"

    # ===== 安装（install step）=====
    sudo make install

    # ===== 验证（verification）=====
    if [ -x "$PREFIX/bin/zsh" ]; then
        "$PREFIX/bin/zsh" --version
    else
        echo "[ERROR] Installation failed"
        return 1
    fi

    # ===== 设置默认 shell（optional but recommended）=====
    if ! grep -q "$PREFIX/bin/zsh" /etc/shells; then
        echo "$PREFIX/bin/zsh" | sudo tee -a /etc/shells
    fi

    chsh -s "$PREFIX/bin/zsh" || true

    echo "==> [DONE] Zsh $ZSH_VERSION installed successfully"
}
# Install ble.sh framework for bash
# 安装前检查依赖,以及避免重复安装重复插入配置项到~/.bashrc
install_blesh() {
    local BLE_REPO="https://github.com/akinomyoga/ble.sh.git"
    local BLE_DIR="$HOME/.local/share/blesh"
    local INSTALL_SRC="$HOME/.local/share/blesh/ble.sh"
    local BASHRC="$HOME/.bashrc"

    echo "--- 开始检查 ble.sh 安装环境 ---"

    # 1. 依赖检查
    required_tools=(
        git
        make
    )
    if is_darwin; then
        required_tools+=(gawk)
        if command -v brew &> /dev/null; then
            echo "Try to use brew to install 'gawk'"
            brew install gawk
        fi
    fi
    if is_alpine; then
        required_tools+=(gawk)
        if command -v apk &> /dev/null; then
            echo "Try to use apk to install 'gawk'"
            sudo apk add gawk
        fi
    fi
    for cmd in "${required_tools[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then

            echo "错误: 未找到 $cmd，请先安装后再试(install_blesh)。"
            return 1
        fi
    done

    # 2. 避免重复下载/编译 (如果目录已存在则跳过)
    if [ ! -d "$BLE_DIR" ]; then
        echo "正在克隆并编译 ble.sh..."

        # 使用临时目录克隆，避免污染当前路径
        local TMP_DIR
        # 将仓库clone到家目录,防止wsl这类环境IO慢的问题
        # TMP_DIR=$(mktemp -d ~/blesh_tmp.XXXX) # ash 中X的数量为6,过少不行
        TMP_DIR=$(mktemp -p ~ -d blesh_tmp.XXXXXX)
        git clone --recursive --depth 1 --shallow-submodules "$BLE_REPO" "$TMP_DIR/ble.sh"
        # 执行安装
        make -C "$TMP_DIR/ble.sh" install PREFIX=~/.local

        # 清理临时目录
        rm -rf "$TMP_DIR"
    else
        echo "提示: ble.sh 似乎已经安装在 $BLE_DIR"
    fi

    # 3. 幂等性添加 source 命令到 .bashrc
    local SOURCE_LINE="[[ \$- == *i* ]] && source -- \"$INSTALL_SRC\""

    if grep -Fq "$INSTALL_SRC" "$BASHRC"; then
        echo "提示: .bashrc 中已存在 ble.sh 配置，跳过写入。"
    else
        echo "正在向 .bashrc 添加启动配置..."
        # 换行确保不会追加到已有内容的行尾
        echo -e "\n# ble.sh setup\n$SOURCE_LINE" >> "$BASHRC"
        echo "配置已成功添加。"
    fi

    echo "--- 安装/检查完成 ---"
    echo "请执行 'source ~/.bashrc' 或重新打开终端以激活 ble.sh。"
}
# 安装跨平台跨shell补全项目argc-completions
# 默认为bash安装补全(注意,bash下和blesh可能会有冲突,酌情使用)
# 默认不会向shell的配置文件插入激活argc_completions的代码,需要手动输入选项激活
# 该项目依赖于(argc,yq)国内网络下载可能较慢(从github下载)
install_argc_completions() {
    local shell="${1:-bash}"
    local install_dir="${repos:-$HOME}"

    local force=false
    local usage="
usage:
    install_argc_completions [OPTIONS] [--shell=<shell>]
options:
    --force: 尝试即使在国内ip下直连github安装;
    --shell=<shell>: 指定要安装的shell,默认为bash 
    可用shell:bash/zsh/powershell/fish/nushell/elvish/xonsh/tcsh
"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s | --shell)
                shell="$2"
                shift
                ;;
            -f | --force)
                force=true
                ;;
            --help | -h)
                echo "$usage"
                return 0
                ;;
            -?*)
                echo "unknown option: $1"
                echo "$usage"
                return 2
                ;;
            *)
                shell="$1"
                ;;
        esac
        shift
    done

    echo "installing argc-completions to [$install_dir] ..."
    if is_china_ip; then
        echo "[warning]: In China, downloading from github may be slow."
        echo "Try use proxy instead of connecting to github directly!"
        if [[ $force == "false" ]]; then
            echo "use --force to install anyway"
            return 1
        fi
    fi
    echo "[info]: install_dir is [$install_dir]."
    cd "$install_dir" || return 1

    git clone https://github.com/sigoden/argc-completions.git
    cd argc-completions || return 1
    ./scripts/download-tools.sh
    # bash/zsh/powershell/fish/nushell/elvish/xonsh/tcsh
    ./scripts/setup-shell.sh "$shell"
}
alias is_macos=is_darwin
# 获取当前系统的发行版名称
# shellcheck disable=SC2120
function get_os_name() {
    local out_name=false
    local out_version=false
    local os_file="/etc/os-release"
    local usage="
    获取当前系统的发行版名称或版本号。默认无参数时，只输出发行版名称。
usage:
    get_os_name [OPTIONS]
options:
    -o: 输出名称和版本号
    --id: 仅输出版本号
    "
    # 处理参数
    if [[ $# -eq 0 ]]; then
        # 默认行为：只输出名称
        out_name=true
    else
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -o)
                    out_name=true
                    out_version=true
                    shift
                    ;;
                --id)
                    out_version=true
                    shift
                    ;;
                *)
                    echo "Unknown option: "
                    return 1
                    ;;
            esac
        done
    fi
    local name
    local version

    if is_darwin; then
        # 提取名称
        name=$(sw_vers -productName)

        # 提取版本号
        version=$(sw_vers -productVersion)

    elif [[ -f "$os_file" ]]; then
        # name="debug"
        # version="debug"
        # # 提取变量值
        name=$(grep -E '^NAME=' "$os_file" | cut -d'=' -f2 | tr -d '"')
        version=$(grep -E '^VERSION_ID=' "$os_file" | cut -d'=' -f2 | tr -d '"')
    elif osinfo=$(uname -a); then
        name="${osinfo%% *}"
    else
        name="unknown"
        version=""
    fi
    # 根据布尔值决定输出内容
    if [[ "$out_name" == true && "$out_version" == true ]]; then
        echo "$name $version"
    elif [[ "$out_version" == true ]]; then
        echo "$version"
    else
        echo "$name"
    fi
}
# 检测数组中是否包含指定元素
# Arguments:
#   -e : 待查找的元素
#   -a : 数组名称
#   -p : 匹配模式,默认为精确匹配
# Return:
#   0: 存在
#   1: 不存在
is_in_array() {
    local element array_name item
    local -n array_ref
    local use_pattern=0
    local args_pos=()
    # 解析参数
    usage="
usage:
    is_in_array ELEMENT ARRAY_NAME [-p]
或: is_in_array -e ELEMENT -a ARRAY_NAME [-p]

example:
    shs=(/www/sh/*.sh)
    is_in_array '*plugins*' shs -p && echo yes
"
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e | --element)
                element="$2"
                shift
                ;;
            -a | --array)
                array_name="$2"
                shift
                ;;
            -p | --pattern)
                use_pattern=1

                ;;
            -?*)
                echo "错误: 未知选项 $1" >&2
                return 2
                ;;
            *)
                # 位置参数模式
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    set -- "${args_pos[@]}"
    [[ ! $element ]] && element="$1"
    [[ ! $array_name ]] && array_name="$2"

    [[ -z $element || -z $array_name ]] && {
        echo "$usage" >&2
        return 2
    }

    array_ref="$array_name"

    for item in "${array_ref[@]}"; do
        if ((use_pattern)); then
            # 模式匹配（支持通配符）
            # shellcheck disable=SC2053
            [[ $item == $element ]] && return 0
        else
            # 精确匹配
            [[ $item == "$element" ]] && return 0
        fi
    done

    return 1
}
# 尝试获取本机公网ip
# get_public_ip() {
#     local ip
#     ip=$(curl -sm 5 ipconfig.me)
#     ip=$(curl -sm 5 ipinfo.io | grep -Po '"ip": "\K[^"]*')
#     echo -n "$ip"
# }
get_public_ip() {

    local time_out="${1:-2}"

    local ip
    _curl() {
        curl -sL -m "$time_out" "$@"
    }
    # 按照优先级尝试不同的源(串行查询)
    ip=$(_curl https://ifconfig.me) ||
        ip=$(_curl ipinfo.io/ip) ||
        ip=$(_curl https://icanhazip.com) ||
        ip=$(_curl https://1.1.1.1/cdn-cgi/trace | grep -Po '^ip=\K.*') ||
        ip=$(_curl https://whatismyip.akamai.com) ||
        return 1

    if [ -n "$ip" ]; then
        echo -n "$ip"
    else
        return 1 # 全部失败时返回错误码
    fi
}
# 并行查询多个源获取公网IP,哪个先返回就用哪个,提高获取速度(适合网络环境不稳定的情况)
# 默认超时2秒;使用ip=$(get_public_ip_fast 2> /dev/null)
get_public_ip_fast() {
    local time_out="${1:-2}"
    local tmp_dir
    tmp_dir=$(mktemp -d) || return 1

    # 所有查询源
    local -a urls=(
        "https://ifconfig.me"
        "https://icanhazip.com"
        "https://ipinfo.io/ip"
        "https://whatismyip.akamai.com"
        "https://api.ipify.org"
    )

    # 特殊源：需要后处理
    local cloudflare_url="https://1.1.1.1/cdn-cgi/trace"

    local -a pids=()

    # 每个源启动一个后台子进程，获取成功就写入文件
    for i in "${!urls[@]}"; do
        (
            result=$(curl -sL -m "$time_out" "${urls[$i]}" 2> /dev/null)
            # 验证：非空且像一个 IP 地址（v4 或 v6）
            if [[ "$result" =~ ^[0-9a-fA-F.:]+$ ]]; then
                echo -n "$result" > "$tmp_dir/$i"
            fi
        ) &

        pids+=($!)
    done

    # Cloudflare 特殊处理
    (
        result=$(curl -sL -m "$time_out" "$cloudflare_url" 2> /dev/null | grep -Po '^ip=\K.*')
        if [[ "$result" =~ ^[0-9a-fA-F.:]+$ ]]; then
            echo -n "$result" > "$tmp_dir/cf"
        fi
    ) &
    pids+=($!)

    # 轮询等待：任一进程产出结果就立即返回
    local ip=""
    local elapsed=0
    local poll_interval=0.05 # 50ms 轮询间隔

    while ((elapsed < time_out * 1000)); do
        for f in "$tmp_dir"/*; do
            if [[ -f "$f" ]]; then
                ip=$(< "$f")
                if [[ -n "$ip" ]]; then
                    # 杀掉所有剩余后台进程
                    kill "${pids[@]}" 2> /dev/null
                    wait "${pids[@]}" 2> /dev/null
                    rm -rf "$tmp_dir"
                    echo -n "$ip"
                    return 0
                fi
            fi
        done

        # 检查是否所有进程都已结束（全部失败）
        local all_done=true
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2> /dev/null; then
                all_done=false
                break
            fi
        done
        $all_done && break

        sleep "$poll_interval"
        elapsed=$((elapsed + 50))
    done

    # 超时：清理
    kill "${pids[@]}" 2> /dev/null
    wait "${pids[@]}" 2> /dev/null
    rm -rf "$tmp_dir"
    return 1
}
get_public_ip_quick() {
    local timeout="${1:-2}"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT
    set +m # 关键：抑制后台任务 "[1]+ Done" 提示

    local -a urls=(
        https://ifconfig.me
        https://icanhazip.com
        https://ipinfo.io/ip
        https://whatismyip.akamai.com
        https://api.ipify.org
    )
    local -a pids=()

    # 启动所有源
    for i in "${!urls[@]}"; do
        (
            local ip
            ip=$(curl -sL -m "$timeout" "${urls[$i]}" 2> /dev/null)
            [[ "$ip" =~ ^[0-9a-fA-F.:]+$ ]] && echo -n "$ip" > "$tmp_dir/$i"
        ) &
        pids+=($!)
    done

    # Cloudflare 特殊源
    (
        local ip
        ip=$(curl -sL -m "$timeout" https://1.1.1.1/cdn-cgi/trace 2> /dev/null | grep -Po '^ip=\K.*')
        [[ "$ip" =~ ^[0-9a-fA-F.:]+$ ]] && echo -n "$ip" > "$tmp_dir/cf"
    ) &
    pids+=($!)

    # 超时保护（后台独立运行，不阻塞主逻辑）
    (
        sleep "$timeout"
        kill "${pids[@]}" 2> /dev/null
    ) &
    local timer=$!

    # 事件驱动轮询：替代 sleep 0.05
    local ip=""
    while kill -0 "${pids[@]}" 2> /dev/null; do
        wait -n 2> /dev/null
        for f in "$tmp_dir"/*; do
            [[ -f "$f" && -s "$f" ]] && {
                ip=$(< "$f")
                break 2
            }
        done
    done

    kill "$timer" 2> /dev/null
    wait "${pids[@]}" 2> /dev/null

    [[ -n "$ip" ]] && {
        echo -n "$ip"
        return 0
    }
    return 1
}
alias get_ip_public=get_public_ip

# 获取系统readline库版本
get_readline_version_info() {

    find /usr/lib /lib -name "libreadline*" 2> /dev/null | head -10
}

# ============ 询问是否继续(支持定制跳过询问) ============
# Arguments:
#   $1 prompt 向用户展示的提示信息
#   $2 default 决定提示符的输入选择部分的内容是(y,Y),(n,N),
#               或其他情况时,分别对应提示[Y/n],[y/N],[y/n]
#   $3 assume_answer 是否跳过用户交互直接回答此变量对应的选项
# Return:
#  0 if yes, 1 if no;
# Examples :
# $ confirm "是否继续执行?" "y"
#       是否继续执行? [y/N]: (如果直接回车,会自动选择N)
#
# $ yes|confirm  contin?  && echo "yes,continue"
# yes,continue
#
# $ confirm -v "continue this operation?" "y"
# continue this operation? [Y/n]:
# return 0
confirm() {
    local prompt
    local default_suggestion
    local assume_answer
    # 处理可能出现的选项
    local verbose=false
    local usage="
    Usage: 
        confirm [OPTIONS] [PROMPT] [DEFAULT_SUGGESTION] [ASSUME_ANSWER]
        confirm [OPTIONS] [PROMPT] [y|Y|n|N] [ASSUME_ANSWER]

    Arguments:
        PROMPT                      The message to display to the user.
        DEFAULT_SUGGESTION          Presentation of default choice:
                                    y or Y -> [Y/n] (Default is Yes)
                                    n or N -> [y/N] (Default is No)
                                    (Omitting means no default, requiring explicit input)->[y/n]
        ASSUME_ANSWER               Automatic answer if user presses Enter (y/n).

    Options:
        -v, --verbose    Show detailed process.
        -h, --help       Show this help message.
    examples:

    "
    # echo "解析函数参数..."
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in

            -h | --help)
                echo "$usage"
                return 0
                ;;
            -v | --verbose)
                verbose=true
                ;;
            -?*)
                echo "错误: 未知选项 '$1'" >&2
                echo "$usage" >&2
                return 2
                ;;
            *)
                # 收集位置参数
                positional+=("$1")

                ;;
        esac
        shift
        # echo "分析下一个参数[$1]..."
    done
    set -- "${positional[@]}"
    prompt="${1:-Continue ?}"
    default_suggestion="${2:-}"
    assume_answer="${3:-}"
    # debug:
    # echo "[$*]"
    # echo "检查位置参数..."
    local rc
    # 🔑 如果指定了自动回答，直接返回值
    if [[ -n "$assume_answer" ]]; then
        echo "${prompt} → 自动回答: ${assume_answer}"
        # 设置返回值rc
        [[ "$assume_answer" =~ ^y(es)?$ ]] && rc=0 || rc=1
        # if [[ "$verbose" = true ]]; then echo "return $rc"; fi
        # return $rc
    fi
    # 如果命令行没有指定自动回答,则要求用户交互,交互方式可以定义3类(至少要求输入一个回车)
    if [[ -z $rc ]]; then

        # 构造提示符的输入选择部分
        # (对于y,Y表示偏好为自动输入yes(return 0),如果是n,N,偏好是自动输入no(return 1))
        local yn
        case "$default_suggestion" in
            y | Y) yn="[Y/n]" ;;
            n | N) yn="[y/N]" ;;
            *) yn="[y/n]" ;; # 表示要求用户必须输入可用值
        esac

        # 交互式询问（支持重试）
        while true; do
            # read -r -p "${prompt} ${yn}: " answer #bash 写法,zsh不支持这种用法,而是有自己的方式
            # 为了兼容性,这里拆成2步,使用echo打印提示
            echo "${prompt} ${yn}: "
            read -r answer
            answer="${answer:-$default_suggestion}" # 用户直接回车则取默认值
            case "${answer,,}" in                   # ${,,} 转小写 (bash 4+)
                y | yes)
                    rc=0
                    # echo "回答yes"
                    break
                    ;;
                n | no)
                    rc=1
                    # echo "回答no"
                    break
                    ;;
                *) echo "请输入 y(Y) 或 n(N)" ;;
            esac
        done
    fi
    # 统一返回
    if [[ "$verbose" = true ]]; then echo "return $rc"; fi
    return $rc
}
# 判断符号链接是否有效
check_symboliclink() {
    local target="$1"

    # 1. 首先检查它是否是一个符号链接
    if [ ! -L "$target" ]; then
        echo "错误: '$target' 不是一个符号链接。" >&2
        return 2
    fi

    # 2. 检查符号链接指向的目标是否存在
    # -e 会跟随链接检查目标文件的存在性
    if [ -e "$target" ]; then
        echo "有效: 符号链接 '$target' 指向的目标存在。"
        return 0
    else
        echo "无效: 符号链接 '$target' 已断开（指向的目标不存在）。" >&2
        return 1
    fi
}
# 判断路径是否为空目录
is_empty_dir() {
    local method="glob" # 默认方式
    local dir=""
    local verbose=false

    # ---------------------- 解析参数 ----------------------
    local usage="用法: is_empty_dir [-m method] [-v] <directory>
选项:
    -m <method>   判断方式: glob | ls | find | read (默认: glob)
    -v            显示详细信息
    -h            显示帮助
"

    local OPTIND=1
    while getopts ":m:vh" opt; do
        case "$opt" in
            m) method="$OPTARG" ;;
            v) verbose=true ;;
            h)
                echo "$usage"
                return 0
                ;;
            :)
                echo "错误: -$OPTARG 需要参数" >&2
                return 2
                ;;
            *)
                echo "错误: 未知选项 -$OPTARG" >&2
                echo "$usage" >&2
                return 2
                ;;
        esac
    done
    shift $((OPTIND - 1))
    dir="$1"

    # ---------------------- 参数校验 ----------------------
    if [[ -z "$dir" ]]; then
        echo "错误: 未指定目录" >&2
        echo "$usage" >&2
        return 2
    fi

    if [[ ! -d "$dir" ]]; then
        echo "错误: '$dir' 不是一个有效目录" >&2
        return 2
    fi

    if [[ ! -r "$dir" ]]; then
        echo "错误: '$dir' 不可读" >&2
        return 2
    fi

    # ---------------------- 判断方法 ----------------------
    local result # 0=空, 1=非空

    case "$method" in
        glob)
            # 纯 Bash，利用 glob 展开到数组
            local files
            local orig_nullglob orig_dotglob
            orig_nullglob=$(shopt -p nullglob)
            orig_dotglob=$(shopt -p dotglob)
            shopt -s nullglob dotglob
            files=("$dir"/*)
            $orig_nullglob # 恢复原始设置
            $orig_dotglob
            ((${#files[@]} == 0)) && result=0 || result=1
            ;;

        ls)
            # 使用 ls -A 判断
            if [[ -z "$(ls -A "$dir" 2> /dev/null)" ]]; then
                result=0
            else
                result=1
            fi
            ;;

        find)
            # 使用 find，找到第一个条目即停止
            if [[ -z "$(find "$dir" -maxdepth 1 -mindepth 1 -print -quit 2> /dev/null)" ]]; then
                result=0
            else
                result=1
            fi
            ;;

        read)
            # 使用 find + read 组合
            if find "$dir" -maxdepth 1 -mindepth 1 -print0 -quit 2> /dev/null | read -r -d '' _; then
                result=1
            else
                result=0
            fi
            ;;

        *)
            echo "错误: 未知方式 '$method'" >&2
            echo "可选: glob | ls | find | read" >&2
            return 2
            ;;
    esac

    # ---------------------- 输出结果 ----------------------
    if $verbose; then
        local status
        ((result == 0)) && status="dir is empty" || status="dir not empty "
        echo "[方式: $method] '$dir' -> $status"
    fi

    return $result
}
###################################
# 检查 MySQL 是否可连通
# 按需修改参数，免密登录直接调用 check_mysql 即可
# mysql "${args[@]}" --connect-timeout=3 -e "SELECT 1" &> /dev/null
# arguments:
#   -H: mysql服务主机
#   -P: mysql服务端口
#   -u: mysql用户名
#   -p: mysql密码
# examples:
#   check_mysql                                    # 免密登录(依赖 .my.cnf 或 mysql_config_editor)
#   check_mysql -u root -p "123456"                # 指定用户名密码
#   check_mysql -u root -p "123456" -H 10.0.0.1    # 指定主机
#   check_mysql -u root -p "123456" -H 10.0.0.1 -P 3307  # 指定端口
# 完整用例
# if check_mysql -u root -p "123456" -H 127.0.0.1 -P 3306; then
#     echo "MySQL 连接成功"
# else
#     echo "MySQL 连接失败"
# fi
##################
check_mysql() {
    local host="" port="" user="" pass="" verbose=0 args=()
    local usage="用法: ${FUNCNAME[0]} [-H host] [-P port] [-u user] [-p pass] [-v]"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -H | -P | -u)
                # 这三个选项必须有参数值
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "错误: 选项 $1 需要一个参数值。"
                    return 1
                fi
                case "$1" in
                    -H) host="$2" ;;
                    -P) port="$2" ;;
                    -u) user="$2" ;;
                esac
                shift 2
                ;;

            # -p 单独处理，支持三种形式：-p123 / -p 123 / -p（空密码）
            -p)
                # -p 后面跟空格的情况
                if [[ -n "$2" && "$2" != -* ]]; then
                    pass="$2"
                    shift 2
                else
                    # 没有密码参数，可以交互输入或设为空
                    read -rsp "请输入密码: " pass
                    echo
                    shift
                fi
                ;;
            -p*)
                # -p123 连写形式
                pass="${1#-p}"
                shift
                ;;

            -v)
                verbose=1
                shift
                ;;
            --help)
                echo "$usage"
                return 0
                ;;
            *)
                echo "未知选项: $1"
                echo "$usage"
                return 1
                ;;
        esac
    done

    [[ -n "$host" ]] && args+=(-h "$host")
    [[ -n "$port" ]] && args+=(-P "$port")
    [[ -n "$user" ]] && args+=(-u "$user")
    [[ -n "$pass" ]] && args+=(-p"$pass")

    if ((verbose)); then
        echo "--- check_mysql ---"
        echo "  host : ${host:-<default>}"
        echo "  port : ${port:-<default>}"
        echo "  user : ${user:-<default>}"
        echo "  pass : ${pass:+****}"
        echo -n "  result: "
    fi

    local out rc
    out=$(mysql "${args[@]}" --connect-timeout=3 -e "SELECT VERSION() AS version, CURRENT_USER() AS user;" 2>&1)
    rc=$?

    if ((verbose)); then
        if ((rc == 0)); then
            echo -e "OK"
            echo "$out"
        else
            echo -e "FAIL"
            echo "$out"
        fi
        echo "-------------------"
    fi

    return $rc
}

######################################
# 调用rsync从已知主机拷贝(镜像)目录结构到指定位置
# Description:
#   考虑到rsync的参数过多，且不方便记忆，这里将常用参数封装起来;
#   对rsync的简单包装,构造rsync命令行,带有常用参数
#   TODO:增加参数选项解析.
# Globals:
#   None
# Arguments:
#   $1 - remote_host (ip)
#   $2 - local_path (/srv/uploads/...)
#   $3 - remote_path (/www/wwwroot/...)
#   $4 - remote_user ('root' is default)
# Outputs:
#  None
# Returns:
#   0 on success, non-zero on error
# Example:
#
######################################
rsync_copy() {
    remote_host="$1"
    # 本地路径
    local_path="$2"
    # 远程路径
    remote_path="$3"
    # 远程主机
    # 远程主机使用的登录用户名(默认root)
    user=${4:-'root'}
    echo "[$user]"
    # if [[ "${#4}" -ne 0 ]]; then
    #   user="$4"
    # fi
    if [[ $1 =~ ^(-h|--help|[[:space:]]*)$ ]]; then
        echo $'
      # Arguments:
      #   1 - remote_host (ip)
      #   2 - local_path (/srv/uploads/...)
      #   3 - remote_path (/www/wwwroot/...)
      #   4 - remote_user ('root' is default)
'
        return 1
    fi
    #准备
    authority="$user"@"$remote_host"
    remote_full_path="$authority":"$remote_path"

    mkdir -p "$local_path"

    rsync -avP --size-only "$remote_full_path" "$local_path"
}

# 将一个每秒钟打印1个数字,可以指定最多打印的次数(从1开始打印)
# demo_job.sh
demo_job() {
    # JID=$(date +%N)
    local max=${1:-20}          # 默认运行 20 秒
    local JID=${2:-$(date +%s)} # 默认使用当前时间戳作为作业 ID
    local i=1
    # 根据调用时间的纳秒部分生成一个随机 ID,以区分不同的作业实例
    echo "--- [$JID]作业开始 (PID: $$, 预计运行时间: ${max}s) ---"
    while [ $i -le "$max" ]; do
        # 打印当前秒数和进程 ID
        printf "[$JID][$(date +%F-%T)]任务进度: [%2d/%2d] \n" $i "$max"
        sleep 1
        ((i++))
    done
    echo "--- [$JID]作业完成 ---"
}
######################################
# 字符串小写处理(有多种实现)
# 输入多个单词,则全部转换为小写
# 虽然bash提供了内置的 `${var,,}` 语法来转换为小写,但使用函数的方式写法更方便
# `-n` 可以控制是否对原字符串做更改(如果传入的是一个字符串变量的情况下)
# 使用此选项效果相当于s="$(lower $s)"
#
#  延伸:类似的可以实现小写转大写函数upper(),或者增加1个选项来控制是转大写还是转小写
#  但是单独的函数名比较符合使用习惯.和其他语言更相近.
# Notes:
# 利用bash(v4+版本)语法实现
# echo "${input,,}"
# 利用tr实现
# echo  "$input" | tr '[:upper:]' '[:lower:]'
#
# Arguments:
#   $1 - description
# Returns:
#   0 on success, non-zero on error
# Example:
# lower "Hello WORLD"  # 输出: hello world
# s="StringS";lower -n s # 输出:strings (注意使用-n时请配合变量名使用,而不是引用变量名! 例如: lower -n $s 是错误写法)
######################################
lower() {
    local ref_mode=false
    # 单个函数选项判断,可以直接使用if,shift组合(不使用case和循环,如果要设计2个参数就需要循环)
    if [[ "$1" == "-n" ]]; then
        ref_mode=true
        shift
    fi

    # 引用模式：直接修改传入的变量名
    if [ "$ref_mode" = true ]; then
        # 使用 local -n 创建一个指向目标变量的引用
        # echo "变量ref模式"
        local -n input="$1"
    else
        # 否则，创建一个临时变量并返回结果
        local input="$*"
    fi
    # 核心代码
    input="${input,,}"
    echo "$input"
}
######################################
# Description:
# 移除字符串边缘空白
# Globals:
#   None
# Arguments:
#   $1 - 字符串
#
# Outputs:
#   返回一个字符串，该字符串是输入字符串的边缘空白被删除后的结果。
# Returns:
#   0 on success, non-zero on error
# Example:
#
######################################
trim() {
    local var="$*"
    # 移除开头空格
    var="${var#"${var%%[![:space:]]*}"}"
    # 移除结尾空格
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

#######################################
# 检查系统中是否存在指定的依赖命令。
# Arguments:
#   1 - 待检查的命令名称 (string)。
# Outputs:
#   如果命令不存在，则向 STDERR 输出一条错误消息。
# Returns:
#   0 如果命令已找到。
#   1 如果命令不存在。
#######################################
check_dependency() {
    local cmd
    local verbose=true
    args_pos=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -q | --quiet | --silent)
                verbose=false
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    set -- "${args_pos[@]}"
    cmd="$1"
    # command -v "$cmd" &>/dev/null
    if ! command -v "$cmd" > /dev/null 2>&1; then
        [[ $verbose == true ]] && echo "错误: 缺少必要的依赖命令 '$cmd'，请先安装。" >&2
        return 1
    else
        [[ $verbose == true ]] && echo "[$cmd]已安装"
    fi
    return 0
}
# 判断当前shell
# 要在脚本内部准确判断当前运行环境，最健壮的方法是利用各 Shell 的内置变量
# shellcheck disable=SC2120
current_shell() {
    # set -x
    local full=false
    local CURRENT_SHELL
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v | --verbose)
                full=true
                ;;
        esac
        shift
    done
    local current_shell_version=""
    if [ -n "$ZSH_VERSION" ]; then
        CURRENT_SHELL="zsh"
        current_shell_version="$ZSH_VERSION"
    elif [ -n "$BASH_VERSION" ]; then
        CURRENT_SHELL="bash"
        current_shell_version="${BASH_VERSION%%(*}"
    else
        CURRENT_SHELL="unknown"
    fi

    if [ "$full" = true ]; then
        CURRENT_SHELL+=" $current_shell_version"
    fi
    echo "$CURRENT_SHELL"
    # set -x
}
# export -f current_shell
# 判断当前shell是否为指定的shell
is_shell() {
    local shell_name="$1"
    current_shell=$(current_shell)
    # if ! [[ "$current_shell" =~ .*"$shell_name" ]]; then
    if [[ "$current_shell" == "$shell_name" ]]; then
        return 0
    else
        return 1
    fi
}
# 获取bash内置命令的帮助
help_bash() {
    # cmd="$1"
    bash -c "help $* "
}

#  列出linux系统上各种类型用户的详细信息（类似表格输出）
# 基于getent passwd 的输出改造
get_user_list_linux() {

    printf "%-20s %-8s %-8s %-20s %-10s\n" "USERNAME" "UID" "GID" "HOME" "SHELL"
    getent passwd | awk -F: '{ printf "%-20s %-8s %-8s %-20s %-10s\n", $1, $3, $4, $6, $7 }' | sort
}
# 列出系统上的(主要是人为创建的)用户信息,从/etc/passwd
get_user_list_from_passwd() {
    awk -F: '$3 >= 1000 && $3 < 65534 {printf "%-20s %-30s %s\n", $1, $6, $7}' /etc/passwd
}
# 使用column 命令解析结果并控制排版
get_user_list_from_passwd_by_column() {

    (
        printf "USERNAME:PASS:UID:GID:DESCRIPTION:HOME:SHELL\n"
        cat /etc/passwd
    ) | column -t -s:
}
# 运行wp命令(借用www用户权限)
wp() {
    user='www' #修改为你的系统上存在的一个普通用户的名字,比如宝塔用户可以使用www
    echo "[INFO] Executing as user '$user':wp $*"
    sudo -u $user wp "$@"
    local EXIT_CODE=$?
    return $EXIT_CODE
}
# 创建一个带有sudo使用权限的linux用户,尽量实现幂等性;
# 考虑安全性,不支持直接命令行中设置密码
# 如果要设置密码,建议在创建之后使用sudo passwd <username> 的方式为指定用户设置密码!
# parameter:
#   username: 用户名
new_user_sudo() {
    #根据需要更改要操作的用户名,例如linuxbrew
    local username="${1:-linuxbrew}"
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
            sudo useradd -m -s /bin/bash "$username"

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

    passwd "$username"
    usermod -aG sudo "$username"

    # 1. 创建一个包含新规则的临时文件
    echo "$username ALL=(ALL) NOPASSWD: ALL" > /tmp/new_sudo_rule

    # 2. 使用 visudo 验证临时文件的语法
    if visudo -c -f /tmp/new_sudo_rule; then
        echo "语法正确，正在合并..."
        # 3. 将验证通过的规则追加到 /etc/sudoers.d/ 目录下的一个新文件中
        sudo install -m 440 /tmp/new_sudo_rule /etc/sudoers.d/alice_nopasswd
        echo "✅ 用户 alice 已被授予无密码 sudo 权限。"
    else
        echo "❌ 语法错误！规则未被应用。"
        rm /tmp/new_sudo_rule
        return 1
    fi

    # 4. 清理临时文件
    rm /tmp/new_sudo_rule

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
            -b, --installer-source 指定brew本体的安装脚本来源(和镜像相对独立),可用值和特点参考[-s]选项;
            --reset-mirror  重置为官方源(github)
            --force          强制重新设置brew环境变量(即便之前有安装设置过的迹象)
            --uninstall      卸载brew
            -g, --github-mirror  使用github镜像加速github链接
                            (默认使用:https://gh-proxy.com/,如果不可用,可以自行搜索其他github加速镜像网址)
                            如果要禁用镜像加速,请指定为空字符串""
            --update-mirror-only 开关参数:仅更新brew镜像源配置,不执行安装(适用于已经安装了brew,但想要切换镜像源的情况);
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
            -b | --installer-source)
                installer_source="$2"
                shift
                ;;
            --reset-mirror)
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
            --update-mirror-only)
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
    _uninstall_brew() {
        echo "正在下载brew卸载脚本...参考[https://github.com/Homebrew/install#uninstall-homebrew]"
        # 从github拉去卸载脚本并执行
        /bin/bash -c "$(curl -fSL "$github_mirror"https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
        # 移除默认安装目录(如果之前的安装中断或者不完整):
        echo "移除默认安装目录可能需要管理员权限,如果需要,考虑将此函数导出(export),
                然后用类似于sudo bash -c 的命令方式运行此函数,或者自行手动删除brew安装目录;"
        local brew_home
        # brew_home0=$(brew --prefix) #brew未必可用
        # 下面针对安装中途卡死或失败的的情况下执行的简单安装目录清理
        brew_home1=/home/linuxbrew/.linuxbrew
        brew_home2=/opt/homebrew
        brew_home3=/usr/local/homebrew
        brew_homes=("$brew_home1" "$brew_home2" "$brew_home3")
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
    if [[ $uninstall == true ]]; then
        _uninstall_brew
        return $?
    fi
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

    # 判断是否需要设置环境变量到shellrc文件中
    if [[ $HOMEBREW_BREW_GIT_REMOTE && $force == false && $update_mirror_only == false ]]; then
        write_env_rc=false
        echo "HOMEBREW_BREW_GIT_REMOTE is already set to $HOMEBREW_BREW_GIT_REMOTE (in somewhere else), skipping adding to shellrc"
        # 显示当前相关环境变量
        set | grep '^HOMEBREW' | grep https
    fi
    # 是否重置镜像源
    if [[ $reset_mirror == true ]]; then
        echo "重置为官方源..."
        unset HOMEBREW_BREW_GIT_REMOTE
        git -C "$(brew --repo)" remote set-url origin https://github.com/Homebrew/brew

        unset HOMEBREW_API_DOMAIN
        unset HOMEBREW_CORE_GIT_REMOTE
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
        echo "使用tuna镜像可能需要排队(高负载情况下),时间可能需要十来分钟!"
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
            unset HOMEBREW_BREW_GIT_REMOTE
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
    # 从指定镜像获取脚本并开始安装brew
    start_install_brew() {
        case "$installer_source" in
            ustc)
                echo "使用中科大镜像源安装homebrew..."
                /bin/bash -c "$(curl -fsSL https://mirrors.ustc.edu.cn/misc/brew-install.sh)"
                ;;
            tuna)
                echo "使用清华大学镜像源安装homebrew..."
                # 从镜像下载安装脚本并安装 Homebrew / Linuxbrew
                git clone --depth=1 https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.git ~/brew-install
                /bin/bash ~/brew-install/install.sh
                rm -rf ~/brew-install

                ;;
            aliyun)
                # 从阿里云下载安装脚本并安装 Homebrew
                git clone https://mirrors.aliyun.com/homebrew/install.git brew-install
                /bin/bash brew-install/install.sh
                rm -rf brew-install
                ;;
            github)
                echo "使用官方源安装homebrew..."
                # 也可从 GitHub 获取官方安装脚本安装 Homebrew / Linuxbrew
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

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
    # 配置homebrew路径相关的环境变量(和镜像环境���量不同)到配置文件中
    set_brew_path_env_to_shellrc() {
        arch=$(uname -m)
        if is_darwin; then
            if [[ $arch == "arm2" ]]; then
                # shellcheck disable=SC2016
                test -r ~/.bash_profile && echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bash_profile
                # shellcheck disable=SC2016
                test -r ~/.zprofile && echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            fi
        elif is_linux; then
            test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
            test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            test -r ~/.bash_profile && echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bash_profile
            test -r ~/.profile && echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.profile
            test -r ~/.zprofile && echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.zprofile
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

}
install_linuxbrew() {

    local usage
    usage=$(
        cat << EOF
usage:
    install_linuxbrew [options] [username]
        默认使用默认用户名linuxbrew,如果指定用户名不存在,则创建
    此脚本适用于国外服务器(或网络条件好的情况),尤其是只有root用户的情况下,可考虑创建brew专用用户;

    注意:相关依赖不会自动安装(当依赖程序不存在是请自行安寨跟,例如使用系统自带包管理器安装)
    
    国内网络用户(非root用户户下):如果没条件配置代理(或者代理设置不便)
    对于个人电脑,考虑国内方案:
    - https://brew-cn.mintimate.cn/
    - https://gitee.com/cunkai/HomebrewCN #cn方案
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
    local username="${1:-linuxbrew}" # 安装linuxbrew时使用的用户
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
    new_user_sudo "$username"
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

# 强力删除:能够将标志位是i的文件(目录)更改为可删除,然后删除掉指定目标
# 这是一个简化版本(使用rm1或rm2更可靠)
# 用法: rmx <目标文件或目录>
rmx() {
    if [ $# -eq 0 ]; then
        echo "用法: rmx <目标文件或目录>"
        return 1
    fi
    for target in "$@"; do
        if [ -e "$target" ]; then
            echo "[INFO] 尝试去除 $target 的 i 标志..."
            sudo chattr -R -ia "$target"
            echo "[INFO] 强力删除 $target ..."
            sudo rm -rf "$target"
        else
            echo "[WARN] 目标不存在: $target"
        fi
    done
    return 0
}
#######################################
# 强力删除指定的文件或目录。
# 该函数会尝试移除文件的不可修改属性 (immutable) 和权限限制，
# 然后执行强制递归删除。
# Arguments:
#   待删除的文件或目录路径（支持多个参数）。
# Returns:
#   0 如果所有目标都被成功删除。
#   1 如果未提供参数或删除失败。
#######################################
rm1() {
    # 检查是否输入了参数
    if [[ $# -eq 0 ]]; then
        echo "Error: No arguments provided." >&2
        echo "Usage: rm1 <path> [path...]" >&2
        return 1
    fi

    local exit_code=0
    # 为了支持同时处理多个文件/目录,使用循环遍历此函数的所有参数
    for target in "$@"; do
        # 删除前判断目标是否存在(文件/目录/符号链接等)
        if [[ -e "$target" ]]; then
            echo "Force removing: $target"

            # 1. 移除特殊属性 (-i 不可修改, -a 仅追加)
            # 使用 sudo 确保有权修改属性
            sudo chattr -R -ia "$target" 2> /dev/null

            # 2. 修改权限，确保 root 拥有完全控制权
            sudo chmod -R 777 "$target" 2> /dev/null

            # 3. 递归强制删除
            sudo rm -rf "$target"

            # 检查结果
            if [[ -e "$target" ]]; then
                echo "FAILED: $target still exists." >&2
                exit_code=1
            else
                echo "SUCCESS: $target has been removed."
            fi
        else
            echo "Skip: $target does not exist."
        fi
    done

    return $exit_code
}

rm2() {
    # 强力删除文件或目录（移除 immutable 属性后删除）
    # 用法: rm2 [-f] <目标文件或目录>...
    #   -f: 跳过确认提示

    local force=false
    local errors=0

    # 解析选项
    if [[ "$1" == "-f" ]]; then
        force=true
        shift
    fi

    if [[ $# -eq 0 ]]; then
        echo "用法: rmx [-f] <目标文件或目录>..." >&2
        return 1
    fi

    for target in "$@"; do
        # 检查存在性（包括断开的符号链接）
        if [[ ! -e "$target" && ! -L "$target" ]]; then
            echo "[WARN] 目标不存在: $target" >&2
            ((errors++))
            continue
        fi

        # 安全确认（除非 -f）
        if [[ "$force" != true ]]; then
            read -r -p "[WARN] 确定要强制删除 '$target'? [y/N] " confirm
            [[ "$confirm" != [yY] ]] && continue
        fi

        echo "[INFO] 处理: $target"

        # 移除 immutable 属性（根据类型选择是否递归）
        if [[ -d "$target" ]]; then
            sudo chattr -R -i -- "$target" 2> /dev/null
        else
            sudo chattr -i -- "$target" 2> /dev/null
        fi
        # 注意: 非 ext 文件系统会失败，忽略错误

        # 执行删除
        if sudo rm -rf -- "$target"; then
            echo "[OK] 已删除: $target"
        else
            echo "[ERROR] 删除失败: $target" >&2
            ((errors++))
        fi
    done

    return $((errors > 0 ? 1 : 0))
}
# 进程监控函数psm
psm_gnu() {
    # 1. 检查帮助选项
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        # 使用 'cat << EOF' 来格式化多行帮助文本
        cat <<- EOF
    用法: psm [排序字段] [行数]

    功能:
    显示当前系统的进程状态, 类似于 top, 但提供了高精度的内存百分比计算。

    参数:
    [排序字段]   (可选) 指定 'ps' 命令用于排序的字段。
                必须包含 '-' (降序) 或 '+' (升序)。
                注意: 按内存排序请使用 '-rss'。
                (为了方便, '-mem' 或 '-%mem' 会被自动转换为 '-rss')
                默认: -%cpu

    [行数]       (可选) 指定显示进程的行数 (不包括表头)。
                默认: 20

    选项:
    -h, --help   显示此帮助信息并退出。

    示例:
    psm            # 按 CPU 降序显示前 20 个进程
    psm -rss 10    # 按 RSS 内存占用降序显示前 10 个进程
    psm +pid 50    # 按 PID 升序显示前 50 个进程
EOF
        return 0 # 成功退出函数
    fi

    # 2. 处理函数参数
    local sort_field="${1:--%cpu}"
    local lines="${2:-20}"

    # 3. 智能处理内存排序
    #    如果用户输入 -%mem 或 -mem, 自动帮他转换为 -rss
    if [[ "$sort_field" == "-%mem" || "$sort_field" == "-mem" ]]; then
        sort_field="-rss"
    fi

    # 4. 取总内存 (KiB)
    local total_mem_kb
    # total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 方案
        total_mem_kb=$(($(sysctl -n hw.memsize) / 1024))
    else
        # Linux 方案
        total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    fi

    # 4.1. 检查是否成功获取
    if [ -z "$total_mem_kb" ] || [ "$total_mem_kb" -eq 0 ]; then
        echo "错误: 无法从 /proc/meminfo 读取总内存。" >&2
        return 1
    fi

    # 5. 执行 ps 和 awk 命令 (核心逻辑不变)
    ps -eo user,pid,%cpu,rss,vsz,nlwp,stat,start_time,cmd --sort="$sort_field" |
        head -n "$((lines + 1))" |
        awk -v total_mem="$total_mem_kb" '
    NR==1 {
        # 表头
        printf "%-12s %-8s %-6s %-6s %-12s %-12s %-6s %-8s %-10s %-s\n",
               $1,$2,$3,"%MEM","RSS(MB)","VSZ(MB)",$6,$7,$8,"CMD";
        next
    }
    {
        # 字段索引: $3=%CPU, $4=RSS(KiB), $5=VSZ(KiB), $6=NLWP, ...

        # 手动计算 %MEM
        mem_perc = ($4 / total_mem) * 100;
        
        rss_mb=$4/1024; 
        vsz_mb=$5/1024;
        
        cmd=$9; for(i=10;i<=NF;i++) cmd=cmd" "$i;
        if(length(cmd)>50) cmd=substr(cmd,1,47)"...";
        
        # 打印格式化输出, %MEM 使用 %.2f (保留两位小数)
        printf "%-12s %-8s %-6.1f %-6.2f %-12.1f %-12.1f %-6s %-8s %-10s %-s\n",
               $1,$2,$3,mem_perc,rss_mb,vsz_mb,$6,$7,$8,cmd
    }'
}
# 按进程名统计内存占用 (从高到低排序)
psmem_group() {
    local lines=${1:-20} # 如果没有提供参数，默认显示前 20 行
    printf "\n%-15s | %-5s | %s\n" "MEMORY (MB)" "COUNT" "PROCESS"
    printf "%-15s-|-%-5s-|-%s\n" "---------------" "-----" "-------------------------"
    ps -e -c -o rss=,command= | awk '{
        rss=$1; $1=""; sub(/^[ \t]+/, ""); 
        sum[$0]+=rss; count[$0]++
    } END {
        for (cmd in sum) 
            printf "%12.2f MB | %5d | %s\n", sum[cmd]/1024, count[cmd], cmd
    }' | sort -nr | head -n "$lines"
    echo ""
}
# 登出(结束当前用户所有进程)
logout_killall() {
    sudo killall -u "$(whoami)"
}
# 快速注销当前用户
logout_soft() {
    echo "正在注销当前用户并清理进程..."
    # 优先尝试 AppleScript 强制注销
    osascript -e 'tell application "System Events" to  «event aevtlout»'

    # 如果 5 秒后还没登出（可能有程序卡死），则执行强制清理
    sleep 5 && launchctl bootout "user/$(id -u)"
}
# 按照资源占用从高到低的顺序列出进程(可选内存和cpu占用,其中内存使用合适的精度和单位显示)
psm() {
    # 1. 帮助
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat << EOF
用法: psm [排序字段] [行数]

功能:
  显示当前系统进程状态, 提供高精度内存百分比计算。

参数:
  [排序字段]   (可选) 排序字段, 需带符号:
               '-' 降序, '+' 升序
               常用: -%cpu(默认) | -rss | -vsz | +pid
               别名: -mem / -%mem 自动转换为 -rss
  [行数]       (可选) 显示行数 (不含表头), 默认 20

选项:
  -h, --help   显示帮助并退出

示例:
  psm               # 按 CPU 降序显示前 20 个进程
  psm -rss 10       # 按内存降序显示前 10 个进程
  psm +pid 50       # 按 PID 升序显示前 50 个进程
EOF
        return 0
    fi

    # 2. 参数处理
    local sort_field="${1:--%cpu}"
    local lines="${2:-20}"

    # 3. 内存排序别名
    if [[ "$sort_field" == "-%mem" || "$sort_field" == "-mem" ]]; then
        sort_field="-rss"
    fi

    # 4. 平台判断
    local os_type
    if [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macos"
    else
        os_type="linux"
    fi

    # 5. 获取总内存 (KiB)
    local total_mem_kb
    if [[ "$os_type" == "macos" ]]; then
        total_mem_kb=$(($(sysctl -n hw.memsize) / 1024))
    else
        total_mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    fi

    if [[ -z "$total_mem_kb" || "$total_mem_kb" -eq 0 ]]; then
        echo "错误: 无法获取系统总内存。" >&2
        return 1
    fi

    # 6. 构造 ps 命令并输出
    if [[ "$os_type" == "macos" ]]; then
        _psm_macos "$sort_field" "$lines" "$total_mem_kb"
    else
        _psm_linux "$sort_field" "$lines" "$total_mem_kb"
    fi
}

# ── Linux 分支 ──────────────────────────────────────────────
_psm_linux() {
    local sort_field="$1" lines="$2" total_mem_kb="$3"

    ps -eo user,pid,%cpu,rss,vsz,nlwp,stat,start_time,cmd \
        --sort="$sort_field" |
        head -n $((lines + 1)) |
        awk -v total_mem="$total_mem_kb" '
        NR==1 {
            printf "%-12s %-8s %-6s %-7s %-10s %-10s %-6s %-8s %-10s %s\n",
                   "USER","PID","%CPU","%MEM","RSS(MB)","VSZ(MB)",
                   "NLWP","STAT","STARTED","CMD"
            next
        }
        {
            mem_perc = ($4 / total_mem) * 100
            rss_mb   = $4 / 1024
            vsz_mb   = $5 / 1024
            cmd = $9; for(i=10;i<=NF;i++) cmd=cmd" "$i
            if(length(cmd)>45) cmd=substr(cmd,1,42)"..."
            printf "%-12s %-8s %-6.1f %-7.2f %-10.1f %-10.1f %-6s %-8s %-10s %s\n",
                   $1,$2,$3,mem_perc,rss_mb,vsz_mb,$6,$7,$8,cmd
        }
    '
}

# ── macOS 分支 ──────────────────────────────────────────────
_psm_macos() {
    local sort_field="$1" lines="$2" total_mem_kb="$3"

    local field_name order
    if [[ "$sort_field" == -* ]]; then
        field_name="${sort_field#-}"
        order="desc"
    else
        field_name="${sort_field#+}"
        order="asc"
    fi

    ps -eo user,pid,%cpu,rss,vsz,stat,start,command |
        awk -v total_mem="$total_mem_kb" \
            -v field="$field_name" \
            -v order="$order" \
            -v maxlines="$lines" '
        BEGIN {
            col["user"]=1; col["pid"]=2; col["cpu"]=3; col["%cpu"]=3
            col["rss"]=4;  col["vsz"]=5; col["stat"]=6
            col["start"]=7; col["command"]=8; col["cmd"]=8
        }

        NR==1 { next }

        {
            cmd = $8
            for (i=9; i<=NF; i++) cmd = cmd " " $i

            # ✅ 用 (row, col) 复合键模拟二维数组
            rows[NR, 1] = $1
            rows[NR, 2] = $2
            rows[NR, 3] = $3
            rows[NR, 4] = $4
            rows[NR, 5] = $5
            rows[NR, 6] = $6
            rows[NR, 7] = $7
            rows[NR, 8] = cmd
            row_ids[NR] = NR
            total_rows++
        }

        END {
            printf "%-12s %-8s %-6s %-7s %-10s %-10s %-6s %-10s %s\n", \
                   "USER","PID","%CPU","%MEM","RSS(MB)","VSZ(MB)", \
                   "STAT","STARTED","CMD"

            sort_col = (field in col) ? col[field] : 3

            # 冒泡排序 row_ids 数组
            n = total_rows
            for (i = 1; i <= n; i++) {
                for (j = 1; j <= n - i; j++) {
                    ri = row_ids[j]
                    rj = row_ids[j+1]

                    # 判断是否为字符串列
                    if (sort_col==1 || sort_col==6 || sort_col==7 || sort_col==8) {
                        a = rows[ri, sort_col]
                        b = rows[rj, sort_col]
                        need_swap = (order=="desc") ? (a < b) : (a > b)
                    } else {
                        a = rows[ri, sort_col] + 0
                        b = rows[rj, sort_col] + 0
                        need_swap = (order=="desc") ? (a < b) : (a > b)
                    }

                    if (need_swap) {
                        tmp = row_ids[j]
                        row_ids[j] = row_ids[j+1]
                        row_ids[j+1] = tmp
                    }
                }
            }

            # 输出前 maxlines 行
            printed = 0
            for (i = 1; i <= n && printed < maxlines; i++) {
                ri = row_ids[i]
                mem_perc = (rows[ri, 4] / total_mem) * 100
                rss_mb   =  rows[ri, 4] / 1024
                vsz_mb   =  rows[ri, 5] / 1024
                cmd      =  rows[ri, 8]
                if (length(cmd) > 45) cmd = substr(cmd, 1, 42) "..."
                printf "%-12s %-8s %-6.1f %-7.2f %-10.1f %-10.1f %-6s %-10s %s\n", \
                       rows[ri,1], rows[ri,2], rows[ri,3], mem_perc, \
                       rss_mb, vsz_mb, rows[ri,6], rows[ri,7], cmd
                printed++
            }
        }
    '
}
# 为常用情况创建别名
alias pscpu='psm -%cpu'
alias psmem='psm -%mem'
alias pstop='psm -%cpu 10' # 只显示前10个
