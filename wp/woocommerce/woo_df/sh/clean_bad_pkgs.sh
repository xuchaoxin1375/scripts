#! /bin/bash
# 根据包名(部分名)清理不在需要的包文件,例如网站压缩包
FIND_BASE="/www/wwwroot/xcx/" #可以自行酌情增加精确度,比如添加服务器名到路径中
name_list_file=""
# 参数解析
args_pos=()
parse_args() {
    usage="
    $0 [options] FIND_BASE -f name_list_file
    options:
        -h, --help    显示帮助信息
        -f, --file name_list_file   包含包名的白名单文件,每行一个包名(部分名),必填
    "
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            -f | --file)
                name_list_file="$2"
                shift
                ;;
            --)
                shift
                break
                ;;
            -?*)
                echo "Unknown option: " >&2 #输出错误信息到标准错误
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
declare -a names=(
)
if [[ -f "$name_list_file" ]]; then
    echo "从名单文件 '$name_list_file' 中包名..."
    nl "$name_list_file"
    mapfile -t names < <(tr -d '\r' < "$name_list_file")
else
    echo "警告: 白名单文件 '$name_list_file' 不存在或不可读, 将使用默认的包名列表." >&2
fi
FIND_BASE="${1:-$FIND_BASE}" #如果用户提供了参数则覆盖默认值
# 检查白名单数组
# declare -p names

for name in "${names[@]}"; do
    echo "正在尝试清理包含 '$name' 的包文件..."
    # find $FIND_BASE -type f -name "$name.*"  # -exec rm -f {} \;
    find "$FIND_BASE" -type f -regextype posix-extended -regex ".*/$name(\..*)?\.(zip|zst|lz4|7z|gz|gzip)" -exec rm -fv {} +
done
