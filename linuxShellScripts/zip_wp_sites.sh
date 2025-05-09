#!/bin/bash

# 定义变量
Archives_Dir="/www/wwwroot/xcx/archives"
Compress_Dir="/www/wwwroot/xcx/boutiquedutissu.com/wordpress"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")  # 生成时间戳，格式: YYYYMMDD_HHMMSS
ARCHIVE_NAME="${TIMESTAMP}_archive.zip" # 归档文件名称

# 定义要排除的文件/目录, 一行一个
EXCLUDE_LIST=(
    "wp-content/uploads/2025/02/*"
    "wp-content/uploads/2025/03/*"
    "wp-content/uploads/wc-imports"
#    "./cache/*"
#    "./logs/*"
)

# 定义要删除的文件/目录, 一行一个
DELETE_LIST=(
#    "wp-content/debug.log"
)

# 创建目录（如果不存在）
mkdir -p "$Archives_Dir" || { echo "❌ 目录创建失败：$Archives_Dir"; exit 1; }
echo "✅ 目录已确保存在：$Archives_Dir"

# 进入目标目录
cd "$Compress_Dir" || { echo "❌ 目录切换失败：$Compress_Dir"; exit 1; }
echo "✅ 当前目录：$(pwd)"

# 删除指定的文件/目录
for item in "${DELETE_LIST[@]}"; do
    echo "🗑️ 正在删除：$item"
    rm -rf "$item"
done
echo "✅ 指定文件/目录已删除"

# 组装 zip 排除参数
EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_LIST[@]}"; do
    EXCLUDE_ARGS+=( "\"$pattern\"")
done

# 生成完整的 zip 命令
ZIP_COMMAND="zip -r \"${Archives_Dir}/${ARCHIVE_NAME}\" . -x ${EXCLUDE_ARGS[*]}"

# 打印 zip 命令并询问用户是否继续
echo -e "\n⚠️ 即将执行以下 zip 命令：\n"
echo "$ZIP_COMMAND"
echo -e "\n❓ 按回车键继续，输入 'n' 或 'N' 取消: \c"
read -r CONFIRM
# 检查用户输入
if [[ "$CONFIRM" == "n" || "$CONFIRM" == "N" ]]; then
    echo "🚫 操作已取消"
    exit 0
fi

# 执行 zip 命令
echo "📦 正在创建 ZIP 压缩包：$ARCHIVE_NAME ..."
eval "$ZIP_COMMAND" || { echo "❌ ZIP 压缩失败"; exit 1; }
echo "✅ ZIP 压缩完成：${Archives_Dir}/${ARCHIVE_NAME}"

ls -lh "${Archives_Dir}/${ARCHIVE_NAME}"