#!/bin/bash

# === 默认配置 ===
PATTERN="*.conf"                                   # 文件匹配模式
JUMP_MARKER="#CUSTOM"                              # 检查是否存在此标记，存在则跳过
INSERT_MARKER="#CERT-APPLY-CHECK--START"           # 在此标记前插入内容

# === 显示用法 ===
usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -f <file>           指定单个配置文件
    -d <directory>      指定配置文件目录
    -p <pattern>        文件匹配模式 (默认: *.conf)
    --jump-marker <str> 跳过标记 (默认: #CUSTOM)
    --insert-marker <str> 插入位置标记 (默认: #CERT-APPLY-CHECK--START)

示例:
    $0 -f /path/to/site.conf
    $0 -d /etc/nginx/conf.d -p "*.conf"
    $0 -d /www -p "domain*.conf" --jump-marker "#CUSTOM" --insert-marker "#INSERT-HERE"

EOF
    exit 1
}

# === 参数解析 ===
FILE=""
DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -f)
            FILE="$2"
            [[ -z "$FILE" ]] && echo "❌ 错误: -f 后需指定文件" && exit 1
            shift 2
            ;;
        -d)
            DIR="$2"
            [[ -z "$DIR" ]] && echo "❌ 错误: -d 后需指定目录" && exit 1
            shift 2
            ;;
        -p)
            PATTERN="$2"
            [[ -z "$PATTERN" ]] && echo "❌ 错误: -p 后需指定模式" && exit 1
            shift 2
            ;;
        --jump-marker)
            JUMP_MARKER="$2"
            [[ -z "$JUMP_MARKER" ]] && echo "❌ 错误: --jump-marker 后需指定字符串" && exit 1
            shift 2
            ;;
        --insert-marker)
            INSERT_MARKER="$2"
            [[ -z "$INSERT_MARKER" ]] && echo "❌ 错误: --insert-marker 后需指定字符串" && exit 1
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "❌ 未知参数: $1"
            usage
            ;;
    esac
done

# === 验证输入 ===
if [[ -z "$FILE" && -z "$DIR" ]]; then
    echo "❌ 必须指定 -f 或 -d"
    usage
fi

if [[ -n "$FILE" && ! -f "$FILE" ]]; then
    echo "❌ 文件不存在: $FILE"
    exit 1
fi

if [[ -n "$DIR" && ! -d "$DIR" ]]; then
    echo "❌ 目录不存在: $DIR"
    exit 1
fi

# === 处理单个文件的函数 ===
process_file() {
    local conf_file="$1"

    if [[ ! -f "$conf_file" ]]; then
        echo "⚠️  跳过: 文件不存在 -> $conf_file"
        return
    fi

    if [[ ! -r "$conf_file" ]]; then
        echo "❌ 无读取权限: $conf_file"
        return
    fi

    if [[ ! -w "$conf_file" ]]; then
        echo "❌ 无写入权限: $conf_file"
        return
    fi

    echo "📄 处理文件: $conf_file"

    # 1. 检查是否已包含跳过标记
    if grep -qF "$JUMP_MARKER" "$conf_file"; then
        echo "🔔 已包含 '$JUMP_MARKER'，跳过..."
        return
    fi

    # 2. 检查插入标记是否存在
    if ! grep -qF "$INSERT_MARKER" "$conf_file"; then
        echo "⚠️  未找到插入标记 '$INSERT_MARKER'，跳过..."
        return
    fi

    # 3. 使用 sed 在 INSERT_MARKER 前插入多行内容（修复换行问题）
    # 使用单引号 + 每行结尾加 \ 的方式确保换行正确
    sed -i.bak "/$INSERT_MARKER/i\\
    \\
    #CUSTOM-CONFIG-START\\
    include /www/server/nginx/conf/com.conf;\\
    #CUSTOM-CONFIG-END\\
" "$conf_file"

    if [[ $? -eq 0 ]]; then
        echo "✅ 成功插入配置到: $conf_file"
    else
        echo "❌ 插入失败: $conf_file"
    fi
}

# === 主逻辑 ===
if [[ -n "$FILE" ]]; then
    # 处理单个文件
    process_file "$FILE"
else
    # 使用 while + find -print0 避免文件名含空格问题（可选增强）
    while IFS= read -r -d '' conf_file; do
        process_file "$conf_file"
    done < <(find "$DIR" -type f -name "$PATTERN" -print0)
fi

echo "🎉 所有文件处理完成。"