#!/bin/bash

# MySQL 登录信息（请根据实际情况修改）
MYSQL_USER="root"
MYSQL_PASS="15a58524d3bd2e49"

# 默认保存 CSV 的目录
OUTPUT_DIR="./order_exports"
mkdir -p "$OUTPUT_DIR"

# SQL 查询文件路径（即你提供的 SQL 文件）
SQL_FILE="./woo_order_query_lite.sql"

# 获取所有 WordPress + WooCommerce 数据库名称
get_all_wx_dbs() {
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" | \
        grep -i 'wordpress\|woo' | \
        awk '{print $1}'
}

# 导出单个数据库订单数据
export_orders() {
    local db_name="$1"
    echo "Exporting orders from database: $db_name"
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -D "$db_name" -N -s -e "
        $(cat "$SQL_FILE")
    " | sed '1i order_id,date_created_gmt,date_updated_gmt,total_sales,shipping_total,net_total,total_amount,status,customer_id,currency,payment_method,payment_method_title,billing_first_name,billing_last_name,billing_email,billing_phone,billing_country,ip_address' \
        > "$OUTPUT_DIR/$db_name-orders.csv"
}

# 主逻辑
if [ -n "$1" ]; then
    # 指定了数据库名，只导出该数据库
    export_orders "$1"
else
    # 未指定数据库名，导出所有匹配的数据库
    for db in $(get_all_wx_dbs); do
        export_orders "$db"
    done
fi

echo "Export completed. CSV files are saved in: $OUTPUT_DIR"