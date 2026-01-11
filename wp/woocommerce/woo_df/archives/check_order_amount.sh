#!/bin/bash

# ===== 配置区 =====
# 要查找的订单总金额
ORDER_TOTAL="45.46"

# 数据库连接信息
DB_USER="root"
DB_PASS="15a58524d3bd2e49"

# 临时文件和输出文件
TMP_DB_LIST="/tmp/db_list.txt"
OUTPUT_FILE="found_orders_by_total_sales.txt"

# 清空输出文件
> "$OUTPUT_FILE"

echo "🔍 开始查询所有数据库..."

# 获取所有非系统数据库名称
mysql -u "$DB_USER" -p"$DB_PASS" -Nse "
SELECT schema_name FROM information_schema.schemata
WHERE schema_name NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');
" > "$TMP_DB_LIST"

if [ ! -s "$TMP_DB_LIST" ]; then
    echo "❌ 没有找到任何非系统数据库，请检查 MySQL 连接信息。"
    exit 1
fi

# 逐个遍历数据库
while read -r DB_NAME; do
    echo "🔎 正在检查数据库: $DB_NAME"

    # 检查是否存在 wp_wc_orders 和 wp_wc_order_stats 表
    TABLE_CHECK=$(mysql -u "$DB_USER" -p"$DB_PASS" -Nse " \
        SELECT COUNT(*) FROM information_schema.tables \
        WHERE table_schema = '$DB_NAME' AND table_name IN ('wp_wc_orders', 'wp_wc_order_stats'); \
    " 2>/dev/null)

    if [ -z "$TABLE_CHECK" ] || [ "$TABLE_CHECK" -lt 2 ]; then
        echo "❌ 跳过（不是 WooCommerce 数据库）"
        continue
    fi

    # 查询 total_sales 匹配的订单
    RESULT=$(mysql -u "$DB_USER" -p"$DB_PASS" -Nse " \
        USE $DB_NAME; \
        SELECT CONCAT('Database: ', '$DB_NAME', ' | Order ID: ', o.id, ' | Created: ', o.date_created_gmt, ' | Status: ', o.status, ' | Total Sales: ', os.total_sales) \
        FROM wp_wc_orders o \
        JOIN wp_wc_order_stats os ON o.id = os.order_id \
        WHERE os.total_sales = $ORDER_TOTAL; \
    " 2>/dev/null)

    if [ -n "$RESULT" ]; then
        echo "$RESULT" >> "$OUTPUT_FILE"
        echo "✅ 匹配成功 -> 数据库: $DB_NAME" | tee -a "$OUTPUT_FILE"
    else
        echo "❌ 未找到匹配"
    fi

done < "$TMP_DB_LIST"

echo "✅ 查询完成，结果已保存至: $OUTPUT_FILE"
cat $OUTPUT_FILE