#!/bin/bash

# 默认工作目录为当前目录
WORK_DIR="."
# 默认替换字符串
REPLACE_STR=" main_format "
# 默认不启用dry-run模式
DRY_RUN=false

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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "用法: $0 [-d 目录] [-s 替换字符串] [--dry-run]"
            echo "  -d, --directory  指定工作目录 (默认: 当前目录)"
            echo "  -s, --string     指定替换字符串 (默认: main_format)"
            echo "  --dry-run        预览模式，只显示将要进行的更改但不实际修改文件"
            echo "  -h, --help       显示帮助信息"
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

# 使用find查找所有.conf文件并处理
find "$WORK_DIR" -maxdepth 1 -name "*.conf" -type f  | while read -r conf_file; do
    echo "处理文件: $conf_file"
    
    # 检查文件是否包含匹配的access_log行
    if grep -qE "access_log[[:space:]]+[^[:space:]]+\.log[[:space:]]*;" "$conf_file"; then
        echo "  发现匹配行，准备进行替换..."
        
        # 显示将要被替换的行
        echo "  匹配的行:"
        grep -E "access_log[[:space:]]+[^[:space:]]+\.log[[:space:]]*;" "$conf_file"
        
        if [ "$DRY_RUN" = false ]; then
            # 使用sed进行替换操作
            # 匹配access_log后跟空格，然后是非空格字符加.log，最后是可选空格和分号
            # 将可选空格部分替换为两个空格加上指定字符串再加一个空格和分号,避免揉在一起导致语法错误!
            sed -i -E "s/(access_log[[:space:]]+[^[:space:]]+\.log)([[:space:]]*;)/\1$REPLACE_STR\2/g" "$conf_file"
            echo "  文件已修改"
        else
            echo "  [DRY-RUN] 将会被替换为:"
            grep -E "access_log[[:space:]]+[^[:space:]]+\.log[[:space:]]*;" "$conf_file" | sed -E "s/(access_log[[:space:]]+[^[:space:]]+\.log)([[:space:]]*;)/\1  $REPLACE_STR \2/g"
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