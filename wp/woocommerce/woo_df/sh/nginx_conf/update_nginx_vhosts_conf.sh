#!/bin/bash

# === 默认配置 ===
PATTERN="*.conf"                                   # 文件匹配模式
JUMP_MARKER="#CUSTOM"                              # 检查是否存在此标记
INSERT_MARKER="#CERT-APPLY-CHECK--START"           # 在此标记前插入内容
DAYS=""                                            # 默认不限制时间
WORK_DIR="/www/server/panel/vhost/nginx"           # 默认工作目录
NEW_SITE_DAYS=14                                   # 新站点判定天数（默认14天）
COM_CONF="/www/server/nginx/conf/com.conf"         # 通用安全配置
LIMIT_CONF="/www/server/nginx/conf/limit_rate.conf" # 限流配置

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
    --days <n>          仅处理最近 n 天内修改的文件,默认不挑时间全部处理
    --new-site-days <n> 新站点判定天数 (默认: 14天)
    --com-conf <path>   通用安全配置路径 (默认: /www/server/nginx/conf/com.conf)
    --limit-conf <path> 限流配置路径 (默认: /www/server/nginx/conf/limit_rate.conf)

示例:
    $0 -f /path/to/site.conf
    $0 -d /etc/nginx/conf.d -p "*.conf"
    $0 -d /www/server/panel/vhost/nginx/ --new-site-days 7
    
具体用例:(宝塔用户将所有网站的nginx配置检查并更新)🎈
    bash /update_nginx_vhosts_conf.sh -d /www/server/panel/vhost/nginx/
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
        --days)
            DAYS="$2"
            if [[ -z "$DAYS" || ! "$DAYS" =~ ^[0-9]+$ ]]; then
                echo "❌ 错误: --days 后需指定一个正整数"
                exit 1
            fi
            shift 2
            ;;
        --new-site-days)
            NEW_SITE_DAYS="$2"
            if [[ -z "$NEW_SITE_DAYS" || ! "$NEW_SITE_DAYS" =~ ^[0-9]+$ ]]; then
                echo "❌ 错误: --new-site-days 后需指定一个正整数"
                exit 1
            fi
            shift 2
            ;;
        --com-conf)
            COM_CONF="$2"
            [[ -z "$COM_CONF" ]] && echo "❌ 错误: --com-conf 后需指定路径" && exit 1
            shift 2
            ;;
        --limit-conf)
            LIMIT_CONF="$2"
            [[ -z "$LIMIT_CONF" ]] && echo "❌ 错误: --limit-conf 后需指定路径" && exit 1
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
    echo "ℹ️ 未指定 -f 或 -d，默认使用 WORK_DIR: $WORK_DIR"
    DIR="$WORK_DIR"
fi

if [[ -n "$FILE" && ! -f "$FILE" ]]; then
    echo "❌ 文件不存在: $FILE"
    exit 1
fi

if [[ -n "$DIR" && ! -d "$DIR" ]]; then
    echo "❌ 目录不存在: $DIR"
    exit 1
fi

# === 判断文件是否为新站点 ===
is_new_site() {
    local file="$1"
    # 使用 find 检查文件是否在 NEW_SITE_DAYS 天内修改过
    if find "$file" -maxdepth 1 -type f -mtime "-$NEW_SITE_DAYS" -print -quit | grep -q .; then
        return 0  # 是新站点
    else
        return 1  # 是老站点
    fi
}

# === 删除现有的自定义配置块 ===
remove_custom_block() {
    local conf_file="$1"
    # 删除从 #CUSTOM-CONFIG-START 到 #CUSTOM-CONFIG-END 的所有内容（包括这两行）
    sed -i.bak '/#CUSTOM-CONFIG-START/,/#CUSTOM-CONFIG-END/d' "$conf_file"
}

# === 插入配置块A（仅通用安全配置） ===
insert_block_a() {
    local conf_file="$1"
    sed -i "/$INSERT_MARKER/i\\
    \\
    #CUSTOM-CONFIG-START\\
    include $COM_CONF;\\
    #CUSTOM-CONFIG-END\\
" "$conf_file"
}

# === 插入配置块B（通用安全配置 + 限流配置） ===
insert_block_b() {
    local conf_file="$1"
    sed -i "/$INSERT_MARKER/i\\
    \\
    #CUSTOM-CONFIG-START\\
    include $COM_CONF;\\
    include $LIMIT_CONF;\\
    #CUSTOM-CONFIG-END\\
" "$conf_file"
}

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

    # 检查插入标记是否存在
    if ! grep -qF "$INSERT_MARKER" "$conf_file"; then
        echo "⚠️  未找到插入标记 '$INSERT_MARKER'，跳过..."
        return
    fi

    # 判断是新站点还是老站点
    if is_new_site "$conf_file"; then
        echo "🆕 检测到新站点（${NEW_SITE_DAYS}天内）"
        site_type="new"
    else
        echo "📅 检测到老站点（超过${NEW_SITE_DAYS}天）"
        site_type="old"
    fi

    # 检查是否已包含自定义配置
    if grep -qF "$JUMP_MARKER" "$conf_file"; then
        echo "🔔 已包含自定义配置，准备更新..."
        
        # 备份原文件
        cp "$conf_file" "${conf_file}.bak" # .$(date +%Y%m%d%H%M%S)
        
        # 删除现有的自定义配置块
        remove_custom_block "$conf_file"
        
        # 根据站点类型插入相应的配置块
        if [[ "$site_type" == "new" ]]; then
            insert_block_a "$conf_file"
            echo "✅ 已更新为配置块A（仅通用安全配置）"
        else
            insert_block_b "$conf_file"
            echo "✅ 已更新为配置块B（通用安全配置 + 限流配置）"
        fi
    else
        echo "🆕 未包含自定义配置，准备插入..."
        
        # 根据站点类型插入相应的配置块
        if [[ "$site_type" == "new" ]]; then
            insert_block_a "$conf_file"
            echo "✅ 已插入配置块A（仅通用安全配置）"
        else
            insert_block_b "$conf_file"
            echo "✅ 已插入配置块B（通用安全配置 + 限流配置）"
        fi
    fi

    if [[ $? -eq 0 ]]; then
        echo "✅ 成功处理: $conf_file"
    else
        echo "❌ 处理失败: $conf_file"
    fi
}

# === 主逻辑 ===
echo "🚀 开始处理 Nginx 配置文件..."
echo "📋 配置信息："
echo "   - 新站点判定天数: $NEW_SITE_DAYS 天"
echo "   - 通用安全配置: $COM_CONF"
echo "   - 限流配置: $LIMIT_CONF"
echo ""

if [[ -n "$FILE" ]]; then
    # 处理单个文件
    if [[ -n "$DAYS" ]]; then
        # 检查文件是否在最近 DAYS 天内修改过
        if find "$FILE" -type f -mtime "-$DAYS" -print -quit | grep -q .; then
            process_file "$FILE"
        else
            echo "🕒 文件 '$FILE' 不在最近 $DAYS 天内修改，跳过..."
        fi
    else
        process_file "$FILE"
    fi
else
    # 批量处理目录中的文件
    find_cmd=(find "$DIR" -type f -name "$PATTERN" -print0)
    
    # 如果设置了 --days，则加入 -mtime 条件
    [[ -n "$DAYS" ]] && find_cmd=(find "$DIR" -type f -name "$PATTERN" -mtime "-$DAYS" -print0)
    
    # 使用 while + find -print0 安全遍历文件
    while IFS= read -r -d '' conf_file; do
        process_file "$conf_file"
    done < <("${find_cmd[@]}")
fi

echo ""
echo "🎉 所有文件处理完成。"
echo "💡 提示："
echo "   - 新站点（${NEW_SITE_DAYS}天内）仅引入通用安全配置"
echo "   - 老站点（超过${NEW_SITE_DAYS}天）引入通用安全配置 + 限流配置"
echo "   - 备份文件保存为 *.bak.时间戳 格式"