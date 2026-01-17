#!/bin/bash


# 默认工作目录为当前目录
WORK_DIR="/www/server/panel/vhost/nginx"
# 默认替换字符串
REPLACE_STR=" main_format "
# 默认不启用dry-run模式
DRY_RUN=false
# 定义匹配access_log行的正则表达式模式
# > 执行效果描述: 将 access_log  /www/wwwlogs/domain.com.log;这类没有指定格式的指令替换为access_log  /www/wwwlogs/domain.com.log main_format;
# > 关于已经被替换过的文件如果再次被此函数处理:这类情况下,access_log行会被跳过,因为不再符合原始的匹配条件.

# 如果grep版本支持,可以使用perl正则: 
# access_log_pattern='\s*#?.*access_log\s+/www/wwwlogs/.*com\.log'

# 兼容性更好的正则写法(可以配合sed -E):
access_log_pattern="^[[:space:]]*#?.*access_log[[:space:]]+[^[:space:]]+\.log[[:space:]]*;"
# 强制性替换(即便已经替换过也重新替换)
access_log_pattern_force="^[[:space:]]*#?.*access_log[[:space:]]+[^[:space:]]+\.log([[:space:]]+main_format)?[[:space:]]*;"
# grep -P "$access_log_pattern" /www/server/panel/vhost/nginx/*.conf
# tpl_pattern="^[[:space:]]*#?.*(access_log[[:space:]]+[^[:space:]]+\.log)([[:space:]]*;)"
help_doc=$(cat <<EOF
用法: $0 [-d 目录] [-s 替换字符串] [--dry-run]
    -d, --directory  指定工作目录 (默认: 当前目录)
    -s, --string     指定替换字符串 (默认: main_format)
    --dry-run        预览模式，只显示将要进行的更改但不实际修改文件
    -h, --help       显示帮助信息
    -f,--force      强制执行,即便已经替换过也重新替换
示例:
默认用例:将宝塔Nginx虚拟主机配置中的access_log日志格式替换为 main_format
bash /www/sh/nginx_conf/update_nginx_vhosts_log_format.sh  # --dry-run
恢复默认日志格式(将自定义日志格式清空)
bash /www/sh/nginx_conf/update_nginx_vhosts_log_format.sh -d /www/server/panel/vhost/nginx  -s '' -f
EOF
)
# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--directory)
            WORK_DIR="$2"
            shift 2
            ;;
        -s|--string)
            REPLACE_STR="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "$help_doc"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            echo "使用 -h 或 --help 查看帮助信息"
            exit 1
            ;;
    esac
done

# 检查工作目录是否存在
if [ ! -d "$WORK_DIR" ]; then
    echo "错误: 目录 '$WORK_DIR' 不存在"
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN MODE] 预览模式: 只显示将要进行的更改但不实际修改文件"
else
    echo "执行模式: 将实际修改匹配的文件"
fi

echo "正在扫描目录: $WORK_DIR"
echo "替换字符串: $REPLACE_STR"

if [[ "$FORCE" = true ]]; then
    echo "  强制模式启用: 将重新替换所有匹配行"
    access_log_pattern="$access_log_pattern_force"
fi

# sed 替换模式串组(这部分涉及到参数,因此要放在参数解析循环之后!):
tpl_pattern="^[[:space:]]*#?.*(access_log[[:space:]]+[^[:space:]]+\.log).*;"
rep_pattern="s/$tpl_pattern/    \1 ${REPLACE_STR};/g"

# 使用find查找所有.conf文件并处理
find "$WORK_DIR" -maxdepth 1 -name "*.conf" -type f  | while read -r conf_file; do
    echo "处理文件: $conf_file"
    
    # 检查文件是否包含匹配的access_log行
    matched=$(grep -E "$access_log_pattern" "$conf_file")
    if [[ -n "$matched" ]] ; then
        
        # 显示将要被替换的行
        echo "  匹配到行:$matched"
        
        
        if [ "$DRY_RUN" = false ]; then
            # 使用sed进行替换操作
            # 匹配access_log后跟空格，然后是非空格字符加.log，最后是可选空格和分号
            # 将可选空格部分替换为两个空格加上指定字符串再加一个空格和分号,避免揉在一起导致语法错误!
            sed -i -E "$rep_pattern" "$conf_file"
            echo "  文件已修改"
        else
            echo "  [DRY-RUN] 将会被替换为:"
            # 将配置文件中匹配到的行用sed替换(预览)
            # echo "模式串: [[$rep_pattern]]"
            echo "$matched" | sed -E "$rep_pattern"
        fi
    else
        echo "  未发现需要替换的匹配行(或者已经替换过了$REPLACE_STR)，跳过。"
    fi
done

if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN MODE] 预览完成"
else
    echo "处理完成"
fi