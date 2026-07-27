#!/usr/bin/env bash
# 创建一个带有sudo使用权限的linux用户,尽量实现幂等性;
# 创建前会做判断,避免重复创建已有用户.
# 考虑安全性和便利性,默认不在内部直接命令行中设置密码;
# 如果要设置密码,建议在创建之后使用sudo passwd <username> 的方式为指定用户设置密码!
#  usage:
#       new_user_sudo [options] [username]
#  options:
#     -h, --help: 显示帮助信息
#     -p, --add-passwd: 创建用户后调用passwd 命令添加密码(不是直接将密码作为命令参数,而是从标准输入读取密码)
#     -P, --set-random-pwd: 创建用户后调用chpasswd 命令添加随机密码
#     -A, --add-sudo: 创建用户后添加sudo权限
#     -N, --no-sudo-password: 调用sudo命令时,不输入密码(慎重)
#     -s, --shell: 指定用户登录shell,默认为/bin/bash
new_user() {

    #根据需要更改要操作的用户名,例如linuxbrew
    local username=""
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
      -p, --add-passwd: 创建用户后调用passwd 命令添加密码(不是直接将密码作为命令参数,而是从标准输入读取密码)
      -P, --set-random-pwd: 创建用户后调用chpasswd 命令添加随机密码
      -A, --add-sudo: 创建用户后添加sudo权限
      -N, --no-sudo-password: 调用sudo命令时,不输入密码(慎重)
      -s, --shell: 指定用户登录shell,默认为/bin/bash

    notes:
        一个普通用户只能用 passwd 命令修改自己的密码，没有能力管理其他用户;但拥有 sudo 权限的普通用户可以.
    "
    local args_pos=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                return 0
                ;;
            -p | --add-passwd)
                add_passwd=true
                ;;
            -P | --set-random-pwd)
                add_random_passwd=true
                ;;
            -A | --add-sudo)
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
    username="$1"
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
            echo "sudo useradd -m -s $shell $username"
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
        sudo passwd "$username"
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
    # 拒绝删除 root 用户
    [ "$target_user" != root ] || {
        echo 'refusing to remove root'
        return 1
    }
    # 检查用户是否存在(id)
    id "$target_user" > /dev/null 2>&1 || {
        echo "user does not exist: $target_user"
        return 0
    }
    echo "正在清理用户 $target_user 的进程..."
    sudo pkill -u "$target_user"

    echo "正在删除用户及其家目录..."
    sudo userdel -r "$target_user" 2> /dev/null

    echo "检查残留的组信息..."
    grep "$target_user" /etc/group
}
