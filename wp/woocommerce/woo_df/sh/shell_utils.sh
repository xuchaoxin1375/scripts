#!/bin/bash
# 提供一些常用的bash/zsh兼容的函数.
# 新函数添加于下方:
# ===============================

# Install ble.sh framework for bash
# 安装前检查依赖,以及避免重复安装重复插入配置项到~/.bashrc
install_blesh() {
    local BLE_REPO="https://github.com/akinomyoga/ble.sh.git"
    local BLE_DIR="$HOME/.local/share/blesh"
    local INSTALL_SRC="$HOME/.local/share/blesh/ble.sh"
    local BASHRC="$HOME/.bashrc"

    echo "--- 开始检查 ble.sh 安装环境 ---"

    # 1. 依赖检查
    for cmd in git make; do
        if ! command -v $cmd &> /dev/null; then
            echo "错误: 未找到 $cmd，请先安装后再试。"
            return 1
        fi
    done

    # 2. 避免重复下载/编译 (如果目录已存在则跳过)
    if [ ! -d "$BLE_DIR" ]; then
        echo "正在克隆并编译 ble.sh..."

        # 使用临时目录克隆，避免污染当前路径
        local TMP_DIR
        # 将仓库clone到家目录,防止wsl这类环境IO慢的问题
        TMP_DIR=$(mktemp -d ~/blesh_tmp.XXXX)
        git clone --recursive --depth 1 --shallow-submodules "$BLE_REPO" "$TMP_DIR/ble.sh"
        # 执行安装
        make -C "$TMP_DIR/ble.sh" install PREFIX=~/.local

        # 清理临时目录
        rm -rf "$TMP_DIR"
    else
        echo "提示: ble.sh 似乎已经安装在 $BLE_DIR。"
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
# 获取当前系统的发行版名称
function get_os_name() {
    # 只读取第一行并取第一个单词
    awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"'
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
            -*)
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
get_public_ip() {
    local ip
    ip=$(curl -sm 5 ipinfo.io | grep -Po '"ip": "\K[^"]*')
    echo -n "$ip"
}
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
    suggestion
Usage: confirm [OPTIONS] [PROMPT] [DEFAULT_SUGGESTION] [ASSUME_ANSWER]
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
            read -r -p "${prompt} ${yn}: " answer
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
current_shell() {

    if [ -n "$ZSH_VERSION" ]; then
        CURRENT_SHELL="zsh"
    elif [ -n "$BASH_VERSION" ]; then
        CURRENT_SHELL="bash"
    else
        CURRENT_SHELL="unknow"
    fi

    echo "$CURRENT_SHELL"
}
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
# 在非bash(zsh)或bash中可以通用的查询bash内置命令的函数
# 支持-N参数控制是否显示行号;
help() {
    local args
    local number_flag=true
    while [[ $# -gt 0 ]]; do

        case "$1" in
            -N | --no-numbers)
                number_flag=false
                ;;
            *)
                args+=("$1")
                ;;
        esac
        shift
    done
    set -- "${args[@]}"
    # 黄色的提示:当前help输出来自于bash
    YELLOW='\e[31m'
    END='\e[0m'
    shell=$(current_shell)
    tip="${YELLOW}[START]当前shell为$shell,而help输出来自于bash ${END}"

    is_shell "bash" || echo -e "$tip"
    if [[ $number_flag == true ]]; then
        help_bash "$*" | nl
    else
        help_bash "$*"
    fi
    is_shell "bash" || echo -e "$tip"

}

# 运行wp命令(借用www用户权限)
wp() {
    user='www' #修改为你的系统上存在的一个普通用户的名字,比如宝塔用户可以使用www
    echo "[INFO] Executing as user '$user':wp $*"
    sudo -u $user wp "$@"
    local EXIT_CODE=$?
    return $EXIT_CODE
}
# 运行brew命令(借用linuxbrew用户权限)
brew() {
    user='linuxbrew' #修改为你的系统上存在的一个普通用户的名字
    local ORIG_DIR="$PWD"
    echo "[INFO] Executing as user '$user' in /home/linuxbrew: brew $*"
    cd /home/$user && sudo -u $user /home/linuxbrew/.linuxbrew/bin/brew "$@"
    local EXIT_CODE=$?
    cd "$ORIG_DIR" 2> /dev/null || echo "[WARN] Could not return to original directory: $ORIG_DIR"
    return $EXIT_CODE
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
psm() {
    # 1. 检查帮助选项
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        # 使用 'cat << EOF' 来格式化多行帮助文本
        cat << EOF
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

    # 4. 获取总内存 (KiB)
    local total_mem_kb
    total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')

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
# 为常用情况创建别名
alias pscpu='psm -%cpu'
alias psmem='psm -%mem'
alias pstop='psm -%cpu 10' # 只显示前10个
