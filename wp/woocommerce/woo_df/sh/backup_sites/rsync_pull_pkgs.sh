#!/bin/bash
# 适用于服务器迁移场景
# 老服务器上将网站包导出使用get_site_pkgs.sh ,可以指定白名单导出(可选立即推送到备份服务器上);
# 新服务器上使用本脚本拉取指定的网站包到指定目录中.
VERSION=20260531
# shellcheck disable=SC1091
source /www/sh/shell_utils.sh #导入rsync_copy函数
list_file=""                  # ./pull_pkgs.txt
remote_host=""                # 192.168...
user=""                       #zsh
server=""                     # s3
adminer=""                    # xcx
port=22

local_dir=""
remote_dir=""
# 参数解析
args_pos=()
usage="
拉取指定的网站包到指定目录中.version:$VERSION
Usage:
    $(basename "$0") [options]
Options:
    -h, --help                  显示帮助信息
    -f, --list-file <file>      指定要拉取的网站包列表文件,eg: pkg_list.txt
    -r, --remote-host <host>    指定远程主机,eg: xcx
    -u, --user <user>           指定网站所属人员,eg: zlj
    -p, --port <port>           指定备份服务器的端口,default: 22
    -s, --server <server>       指定原服务器(被迁出)的名字,eg: s3
    -a, --adminer <adminer>     指定网站管理员,eg: xcx
"
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            -f | -l | --list-file)
                list_file="$2"
                shift
                ;;
            -r | --remote-host)
                remote_host="$2"
                shift
                ;;
            -u | --user)
                user="$2"
                shift
                ;;
            -p | --port)
                port="$2"
                shift
                ;;
            -s | --server)
                server="$2"
                shift
                ;;
            -a | --adminer)
                adminer="$2"
                shift
                ;;
            --)
                shift
                break
                ;;
            -?*)
                echo "Unknown option: $1" >&2 #输出错误信息到标准错误
                echo "$usage" >&2
                exit 2 #直接退出脚本
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    # 参数解析并调整完毕
}
parse_args "$@"

set -- "${args_pos[@]}"

# 构造本地路径和远程路径
local_dir="/srv/uploads/uploader/recovery/$user/deployed"
remote_dir=/www/wwwroot/$adminer/$server/$user/deployed
# 打印并检查参数:
echo "user: $user"
echo "server: $server"
echo "local_dir: $local_dir"
echo "remote_dir: $remote_dir"
echo "list_file: $list_file"
# echo "args_pos: ${args_pos[*]}"

# 提起url字符串中的主域名
get_main_domain() {
    echo "$1" |
        sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#\?.*##; s#:.*##; s#^www\.##' |
        grep -oE '([^.]+\.[^.]+)$'
}

# 需要拉取的域名列表,建议从外部文件读取
# names=(
# )
mapfile -t names < <(tr -d '\r' < "$list_file") # 从文件中读取域名列表,去除可能的\r字符

for name in "${names[@]}"; do
    name=$(get_main_domain "$name")
    for pkg in "$remote_dir/${name}.zst" "$remote_dir/${name}.sql.zst"; do
        rsync_copy -W -p "$port" "$remote_host" "$local_dir" "$pkg"
    done
done
