#!/bin/bash

# === 默认配置 ===
PATTERN="*.conf"                         # 文件匹配模式
JUMP_MARKER="#CUSTOM"                    # 检查是否存在此标记，存在则跳过
INSERT_MARKER="#CERT-APPLY-CHECK--START" # 在此标记前插入内容
DAYS=""                                  # 默认不限制时间
WORK_DIR="/www/server/panel/vhost/nginx" # 默认工作目录
# === 显示用法 ===
usage() {
    cat <<EOF
用法: $0 [选项]

选项:
    -f <file>           指定单个配置文件
    -d <directory>      指定配置文件目录
    -p <pattern>        文件匹配模式 (默认: *.conf)
    -m <mode>           配置模式 (默认: young)
                        young - 仅包含基础配置
                        old   - 包含基础配置和限流配置
                        remove - 移除自定义配置片段
                        
    --force             强制插入配置,即使遇到已经插入过的痕迹,覆盖已经有的片段
    --dry-run           仅显示将要插入的内容,不实际修改文件
    --max-depth <n>    递归查找的最大深度 (默认: 不限制),这里调用find实现递归查找
    --jump-marker <str> 跳过标记 (默认: #CUSTOM)
    --insert-marker <str> 插入位置标记 (默认: #CERT-APPLY-CHECK--START)
    --days <n>          仅处理最近 n 天内修改的文件,默认不挑时间全部处理 (例如: --days 1 表示最近1天)
    -h, --help          显示此帮助信息

示例:
    $0 -f /path/to/site.conf
    $0 -d /etc/nginx/conf.d -p "*.conf"
    $0 -d /www -p "domain*.conf" --jump-marker "#CUSTOM" --insert-marker "#INSERT-HERE"
    $0 -d /www -p "*.conf" --days 1                    # 仅处理最近1天修改的文件

具体用例:
    宝塔用户将所有网站的nginx配置(vhost/nginx)中的conf插入公共基础配置
    bash $0 -d /www/server/panel/vhost/nginx/ 
    对于存在引导标记的配置文件,即使存在插入痕迹,强制插入(覆盖)配置片段,
    bash $0 -d /www/server/panel/vhost/nginx/ --force -m [young|old] #默认为young

涉及到的共用配置文件存放目录: /www/server/nginx/conf/ 请将配置写入其中com_...conf文件中,例如:com_basic.conf和com_limit_rate.conf

检查vhost/nginx中的各网站(.com)配置文件是否插入指定行
grep -l -E 'com_limit_rate' /www/server/panel/vhost/nginx/*.com.conf |nl

EOF
    exit 1
}

# === 参数解析 ===
FILE=""
DIR=""
MODE="young" # 默认模式为 young
MAX_DEPTH=1 # 默认递归查找的最大深度为1
FORCE=false #默认值设置为假值(字符串false,小心不要当做布尔值用)
DRY_RUN=false
COM_SEG='include /www/server/nginx/conf/com_basic.conf;'
LIMIT_SEG='include /www/server/nginx/conf/com_limit_rate.conf;'
YOUNG_SEG=$(cat <<EOF
    ${COM_SEG}\\
EOF
)
# 注意多行字符边缘(首尾)串换行符的问题(对于sed编辑有影响)
# OLD_SEG="
#     $COM_SEG
#     $LIMIT_SEG
# "
OLD_SEG=$(
    cat <<EOF
    ${COM_SEG}\\
    ${LIMIT_SEG}\\
EOF
)
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
    --force)
        FORCE=true
        shift
        ;;
    --dry-run)
        DRY_RUN=true
        shift 
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
    --max-depth)
        MAX_DEPTH="$2"
        if [[ -z "$MAX_DEPTH" || ! "$MAX_DEPTH" =~ ^[0-9]+$ ]]; then
            echo "❌ 错误: --max-depth 后需指定一个正整数"
            exit 1
        fi
        shift 2
        ;;
    -m | --mode)
        MODE="$2"
        [[ -z "$MODE" ]] && echo "❌ 错误: -m 或 --mode 后需指定模式" && exit 1
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
    -h | --help)
        usage
        ;;
    *)
        echo "❌ 未知参数: $1"
        usage
        ;;
    esac
done

# === 验证输入 ===
# if [[ -z "$FILE" && -z "$DIR" ]]; then
#     echo "❌ 必须指定 -f 或 -d"
#     usage
# fi
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
# === 编辑配置的函数(利用sed) ===
edit_conf() {
    # 参数$1表示文件
    local conf_file="$1"
    local insert_seg
    local mode="$MODE"

    if [[ $mode == "young" ]]; then
        insert_seg="$YOUNG_SEG"
    elif [[ $mode == "old" ]]; then
        insert_seg="$OLD_SEG"
    fi
    echo "将要插入到片段:[$insert_seg]"
    if [[  $DRY_RUN = true ]]; then
        echo "📝 [DRY RUN] 以下内容将被插入到文件 '$1' 的 '$INSERT_MARKER' 之前:"
        echo "----------------------------------------"
        echo "#CUSTOM-CONFIG-START"
        echo "$insert_seg"
        echo "#CUSTOM-CONFIG-END"
        echo "----------------------------------------"
        return 0
    fi

    # 使用单引号 + 每行结尾加 \ 的方式确保换行正确
# 使用 > 作为分隔符，避免与内容冲突(下面到i\\立即换行虽然美观,但是会引入空行,可以事后使用sed清除多余空行)

    cmd="\>$INSERT_MARKER>i\\
    #CUSTOM-CONFIG-START\\
$insert_seg
    #CUSTOM-CONFIG-END\\
";

# 预览sed表达式,确保没有多余的空行,否则会引起错误(unterminated address regex)
echo -n "$cmd"
# 开始编辑
    
    if sed -i.bak "$cmd" "$conf_file"; then 
        echo "✅ 成功插入配置到: $conf_file"
        echo "清理多余空行" #多个空行压缩成一个空行,但是非纯空行会被保留
        # sed -i -E 's/^\n[\n\s]*\n/\n/g' "$conf_file" # sed不支持此用法
        sed -i '/^$/N;/^\n$/D' "$conf_file"
    else
        echo "❌ 插入失败: $conf_file"
    fi
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

    # 1. 检查是否已包含跳过标记
    if grep -qF "$JUMP_MARKER" "$conf_file" ; then
        echo "      🔔 已包含 '$JUMP_MARKER'"
        if [[ $FORCE = false ]]; then
            echo "⚠️  跳过..."
            return
        else
            echo "⚠️  强制模式启用，继续处理..."
        fi
    fi

    # 2. 检查插入引导标记是否存在(如果不存在,则此文件不需要处理)
    if ! grep -qF "$INSERT_MARKER" "$conf_file" ; then
        echo "⚠️  未找到插入标记 '$INSERT_MARKER'，跳过..."
        return
    fi
    # 检查是否强制插入(覆盖已经有$INSERT_MARKER的片段)

    # 3. 使用 sed 在 INSERT_MARKER 前插入多行内容（修复换行问题）
    if [[ $FORCE = true ]] || [[ $MODE == "remove" ]]; then
        echo "⚠️  清空可能存在的老片段..."
        if [[ $DRY_RUN = true ]];then
            echo "清空老片段"
        else
            sed -i "/#CUSTOM-CONFIG-START/,/#CUSTOM-CONFIG-END/d" "$conf_file"
        fi
    fi
    if [[ $MODE != "remove" ]]; then
        edit_conf "$conf_file"
    fi


}

# === 主逻辑 ===
if [[ -n "$FILE" ]]; then
    # 🔧 [修改] 单个文件也应检查是否满足时间条件
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
    # 🔧 [修改] 构建 find 命令，支持按时间过滤
    find_cmd=(find "$DIR" -maxdepth "$MAX_DEPTH" -type f -name "$PATTERN"  -print0)

    # 如果设置了 --days，则加入 -mtime 条件
    [[ -n "$DAYS" ]] && find_cmd=(find "$DIR" -type f -name "$PATTERN" -mtime "-$DAYS" -print0)

    # 测试分钟数
    # [[ -n "$DAYS" ]] && find_cmd=(find "$DIR" -type f -name "$PATTERN" -mmin "-$DAYS" -print0)

    # 使用 while + find -print0 安全遍历文件
    while IFS= read -r -d '' conf_file; do
        process_file "$conf_file"
    done < <("${find_cmd[@]}")
fi

echo "🎉 所有文件处理完成。"
