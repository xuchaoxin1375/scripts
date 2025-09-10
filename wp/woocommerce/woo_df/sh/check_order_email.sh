#!/bin/bash
# 使用parallel 并行查询 (需要安装 parallel:  sudo apt install parallel)
# 客户邮箱
EMAIL="mbaptistalema@gmail.com"

# 数据库连接信息
DB_USER="root"
DB_PASS="15a58524d3bd2e49"

# 临时文件保存数据库列表
TMP_DB_LIST="/tmp/db_list.txt"
OUTPUT_FILE="found_orders.txt"

# 清空输出文件
> "$OUTPUT_FILE"

echo "🔍 开始并行查询所有数据库..."

# 获取所有用户数据库名称（排除系统数据库）
mysql -u "$DB_USER" -p"$DB_PASS" -Nse "
SELECT schema_name FROM information_schema.schemata
WHERE schema_name NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');
" > "$TMP_DB_LIST"

if [ ! -s "$TMP_DB_LIST" ]; then
    echo "❌ 没有找到任何非系统数据库，请检查 MySQL 连接信息。"
    exit 1
fi

query_db() {
    DB_NAME="$1"
    TABLE_CHECK=$(mysql -u "$DB_USER" -p"$DB_PASS" -Nse " \
        SELECT COUNT(*) FROM information_schema.tables \
        WHERE table_schema = '$DB_NAME' AND table_name = 'wp_wc_orders'; \
    " 2>/dev/null)

    if [ -z "$TABLE_CHECK" ] || [ "$TABLE_CHECK" -ne 1 ]; then
        echo " 跳过 $DB_NAME（不是 WooCommerce 数据库）: "
        return
    fi

    RESULT=$(mysql -u "$DB_USER" -p"$DB_PASS" -Nse " \
        USE $DB_NAME; \
        SELECT CONCAT('Order ID: ', o.id, '  Created: ', o.date_created_gmt, '  Status: ', o.status, ' ') \
        FROM wp_wc_orders o \
        LEFT JOIN wp_wc_order_addresses ba ON o.id = ba.order_id AND ba.address_type = 'billing' \
        WHERE ba.email = '$EMAIL'; \
    " 2>/dev/null)

    if [ -n "$RESULT" ]; then
        {
            echo "=============================="
            echo "✅ 匹配成功:数据库: $DB_NAME (order email: [$EMAIL])"
            echo "$RESULT"
        } >> "$OUTPUT_FILE"

    # else
        # echo "🗑 未找到匹配: $DB_NAME"
    fi
}

export -f query_db
export DB_USER DB_PASS EMAIL OUTPUT_FILE

# 并行处理每个数据库
parallel --jobs 32 query_db :::: "$TMP_DB_LIST"

echo "🎈查询完成，结果已保存至: $OUTPUT_FILE"
cat $OUTPUT_FILE