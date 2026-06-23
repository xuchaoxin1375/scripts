#!/usr/bin/env bash

# 更新端口号
update_sshd_port() {
    local old_port=22
    local port=2222 # 自行更改端口号
    # 参数解析
    args_pos=()
    local usage
    usage="
    修改sshd_config中的端口号.

    Usage:
        $(basename "$0") [options]
    
    Options:
        -h, --help                  显示帮助信息
        -o, --old-port <old_port>   旧端口号
        -p, --port <port>           新端口号
    Example:
        $(basename "") -o 22 -p 2222
    "

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                return 0
                ;;
            -o | --old-port)
                old_port=$2
                shift
                ;;
            -p | --port)
                port=$2
                shift
                ;;
            --)
                shift
                break
                ;;
            -?*)
                echo "Unknown option:$1" >&2 #输出错误信息到标准错误
                echo "$usage" >&2
                return 2
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    # 参数解析并调整完毕

    set -- "${args_pos[@]}"

    #更安全的方案生成.bak备份,同时兼容行开头的空白和注释)
    sed -i.bak -E "s/^[[:space:]]*#?Port ${old_port}[[:space:]]*$/Port $port/" /etc/ssh/sshd_config

    echo "生成备份文件: /etc/ssh/sshd_config.bak"
    
    # 检查修改:
    grep -C 5 'Port ' /etc/ssh/sshd_config
}

enable_ssh_server() {
    echo "停止并禁用 ssh.socket"
    sudo systemctl stop ssh.socket
    sudo systemctl disable ssh.socket

    echo "启用并启动 ssh.service"
    sudo systemctl enable ssh.service
    sudo systemctl start ssh.service
}
