#!/bin/bash
set -euo pipefail
echo "script version:20260104"
# ================== 默认数据库连接信息 ==================
DB_USER="root"
DB_PASS="15a58524d3bd2e49"
DB_HOST="localhost"

TMP_DB_LIST="/tmp/db_list.txt"
OUTPUT_FILE="found_orders.txt"
THREADS=64   # 默认并行数

EMAILS=()

# ================== 帮助信息函数 ==================
show_help() {
    cat <<EOF
用法: $0 [选项] [邮箱1 邮箱2 ...]

查询 WooCommerce 数据库中指定邮箱的订单信息。

选项:
  -u <user>         MySQL 用户名 (默认: $DB_USER)
  -p <password>     MySQL 密码 (默认: $DB_PASS)
  -H <host>         MySQL 主机 (默认: $DB_HOST)
  -f <文件路径>     从文件中读取邮箱 (一行一个邮箱地址)
  -o <输出文件>     输出结果文件 (默认: $OUTPUT_FILE)
  -j <并行线程数>   同时运行的最大线程数 (默认: $THREADS)
  -h, --help        显示帮助信息

示例:
  $0 -u root -p 123456 -f emails.txt
  $0 -u admin -p secret -j 8 someone@mail.com another@mail.com
EOF
}

# ================== 参数解析 ==================
ARG_EMAIL_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -u) DB_USER="$2"; shift 2 ;;
        -p) DB_PASS="$2"; shift 2 ;;
        -H) DB_HOST="$2"; shift 2 ;;
        -f) ARG_EMAIL_FILE="$2"; shift 2 ;;
        -o) OUTPUT_FILE="$2"; shift 2 ;;
        -j) THREADS="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) EMAILS+=("$1"); shift ;;
    esac
done

# ================== 邮箱来源 ==================
if [[ -n "$ARG_EMAIL_FILE" ]]; then
    if [[ ! -f "$ARG_EMAIL_FILE" ]]; then
        echo "❌ 邮箱文件不存在: $ARG_EMAIL_FILE"
        exit 1
    fi
    while IFS= read -r line; do
        line="$(echo "$line" | xargs)"   # 去掉首尾空格
        # 跳过空行、注释行（忽略前导空格）、无@行
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" != *"@"* ]]; then
            continue
        fi
        EMAILS+=("$line")
    done < "$ARG_EMAIL_FILE"
fi

if [[ ${#EMAILS[@]} -eq 0 ]]; then
    echo "❌ 未指定任何邮箱，使用 -f <文件> 或直接提供邮箱参数。"
    exit 1
fi

# ================== 执行查询 ==================
true > "$OUTPUT_FILE"
ls -l "$OUTPUT_FILE"
echo "🔍 开始并行查询所有数据库 (线程数: $THREADS)..."

mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -Nse "
SELECT schema_name FROM information_schema.schemata
WHERE schema_name NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');
" > "$TMP_DB_LIST"

if [ ! -s "$TMP_DB_LIST" ]; then
    echo "❌ 没有找到任何非系统数据库，请检查 MySQL 连接信息。"
    exit 1
fi

query_db() {
    DB_NAME="$1"
    EMAIL="$2"

    EMAIL_RAW="$(printf '%s' "$EMAIL" | xargs)"
    EMAIL_NORM="$(printf '%s' "$EMAIL_RAW" | tr '[:upper:]' '[:lower:]')"

    EMAIL_RAW_ESC=${EMAIL_RAW//"'"/"\\'"}
    EMAIL_NORM_ESC=${EMAIL_NORM//"'"/"\\'"}

    TABLES_LINE=$(mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -Nse "
        SELECT
          (SELECT table_name FROM information_schema.tables WHERE table_schema = '$DB_NAME' AND table_name LIKE '%wc_orders%' ORDER BY (table_name = 'wp_wc_orders') DESC, table_name LIMIT 1) AS wc_orders,
          (SELECT table_name FROM information_schema.tables WHERE table_schema = '$DB_NAME' AND table_name LIKE '%wc_order_addresses%' ORDER BY (table_name = 'wp_wc_order_addresses') DESC, table_name LIMIT 1) AS wc_order_addresses,
          (SELECT table_name FROM information_schema.tables WHERE table_schema = '$DB_NAME' AND table_name LIKE '%postmeta%' ORDER BY (table_name = 'wp_postmeta') DESC, table_name LIMIT 1) AS postmeta,
          (SELECT table_name FROM information_schema.tables WHERE table_schema = '$DB_NAME' AND table_name LIKE '%posts%' ORDER BY (table_name = 'wp_posts') DESC, table_name LIMIT 1) AS posts,
          (SELECT table_name FROM information_schema.tables WHERE table_schema = '$DB_NAME' AND table_name LIKE '%users%' ORDER BY (table_name = 'wp_users') DESC, table_name LIMIT 1) AS users;
    " 2>/dev/null | head -n 1 || true)

    IFS=$'\t' read -r WC_ORDERS_TABLE WC_ADDR_TABLE POSTMETA_TABLE POSTS_TABLE USERS_TABLE <<< "${TABLES_LINE:-}"

    build_sql() {
        MODE="$1"
        SQL_LOCAL="USE ${DB_NAME};"
        HAS_SEGMENT_LOCAL=0

        if [ "$MODE" = "exact" ]; then
            BILLING_ADDR_CLAUSE="ba.email = '${EMAIL_RAW_ESC}'"
            PM_EMAIL_CLAUSE="pm.meta_value = '${EMAIL_RAW_ESC}'"
            USER_EMAIL_CLAUSE="u.user_email = '${EMAIL_RAW_ESC}'"
        else
            BILLING_ADDR_CLAUSE="LOWER(TRIM(ba.email)) = '${EMAIL_NORM_ESC}'"
            PM_EMAIL_CLAUSE="LOWER(TRIM(pm.meta_value)) = '${EMAIL_NORM_ESC}'"
            USER_EMAIL_CLAUSE="LOWER(TRIM(u.user_email)) = '${EMAIL_NORM_ESC}'"
        fi

        if [ -n "${WC_ORDERS_TABLE:-}" ] && [ -n "${WC_ADDR_TABLE:-}" ]; then
            if [ "$HAS_SEGMENT_LOCAL" -eq 1 ]; then SQL_LOCAL+=" UNION ALL "; fi
            SQL_LOCAL+="SELECT CONCAT('Order ID: ', o.id, ' | Created: ', o.date_created_gmt, ' | Status: ', o.status) FROM ${WC_ORDERS_TABLE} o JOIN ${WC_ADDR_TABLE} ba ON o.id = ba.order_id AND ba.address_type = 'billing' WHERE ${BILLING_ADDR_CLAUSE}"
            HAS_SEGMENT_LOCAL=1
        fi

        if [ -n "${WC_ORDERS_TABLE:-}" ] && [ -n "${POSTMETA_TABLE:-}" ]; then
            if [ "$HAS_SEGMENT_LOCAL" -eq 1 ]; then SQL_LOCAL+=" UNION ALL "; fi
            SQL_LOCAL+="SELECT CONCAT('Order ID: ', o.id, ' | Created: ', o.date_created_gmt, ' | Status: ', o.status) FROM ${WC_ORDERS_TABLE} o JOIN ${POSTMETA_TABLE} pm ON pm.post_id = o.id WHERE pm.meta_key IN ('_billing_email','billing_email') AND ${PM_EMAIL_CLAUSE}"
            HAS_SEGMENT_LOCAL=1
        fi

        if [ -n "${WC_ORDERS_TABLE:-}" ] && [ -n "${USERS_TABLE:-}" ]; then
            if [ "$HAS_SEGMENT_LOCAL" -eq 1 ]; then SQL_LOCAL+=" UNION ALL "; fi
            SQL_LOCAL+="SELECT CONCAT('Order ID: ', o.id, ' | Created: ', o.date_created_gmt, ' | Status: ', o.status) FROM ${WC_ORDERS_TABLE} o JOIN ${USERS_TABLE} u ON u.ID = o.customer_id WHERE ${USER_EMAIL_CLAUSE}"
            HAS_SEGMENT_LOCAL=1
        fi

        if [ -n "${POSTMETA_TABLE:-}" ] && [ -n "${POSTS_TABLE:-}" ]; then
            if [ "$HAS_SEGMENT_LOCAL" -eq 1 ]; then SQL_LOCAL+=" UNION ALL "; fi
            SQL_LOCAL+="SELECT CONCAT('Order ID: ', p.ID, ' | Created: ', p.post_date_gmt, ' | Status: ', p.post_status) FROM ${POSTS_TABLE} p JOIN ${POSTMETA_TABLE} pm ON pm.post_id = p.ID WHERE p.post_type IN ('shop_order','shop_order_refund') AND pm.meta_key IN ('_billing_email','billing_email') AND ${PM_EMAIL_CLAUSE}"
            HAS_SEGMENT_LOCAL=1
        fi

        if [ -n "${POSTMETA_TABLE:-}" ] && [ -n "${POSTS_TABLE:-}" ] && [ -n "${USERS_TABLE:-}" ]; then
            if [ "$HAS_SEGMENT_LOCAL" -eq 1 ]; then SQL_LOCAL+=" UNION ALL "; fi
            SQL_LOCAL+="SELECT CONCAT('Order ID: ', p.ID, ' | Created: ', p.post_date_gmt, ' | Status: ', p.post_status) FROM ${POSTS_TABLE} p JOIN ${POSTMETA_TABLE} pm_user ON pm_user.post_id = p.ID AND pm_user.meta_key IN ('_customer_user','customer_user') JOIN ${USERS_TABLE} u ON u.ID = pm_user.meta_value WHERE p.post_type IN ('shop_order','shop_order_refund') AND ${USER_EMAIL_CLAUSE}"
            HAS_SEGMENT_LOCAL=1
        fi

        if [ "$HAS_SEGMENT_LOCAL" -ne 1 ]; then
            echo ""
            return
        fi

        echo "$SQL_LOCAL"
    }

    SQL_EXACT=$(build_sql "exact")
    if [ -n "$SQL_EXACT" ]; then
        RESULT=$(mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -Nse "$SQL_EXACT" 2>/dev/null)
    else
        RESULT=""
    fi

    if [ -z "$RESULT" ]; then
        SQL_NORM=$(build_sql "norm")
        if [ -n "$SQL_NORM" ]; then
            RESULT=$(mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -Nse "$SQL_NORM" 2>/dev/null)
        fi
    fi

    if [ -n "$RESULT" ]; then
        echo "✅ 数据库: $DB_NAME 找到邮箱 $EMAIL 的订单"
        {
            echo "=============================="
            echo "数据库: $DB_NAME (Email: $EMAIL)"
            echo "$RESULT"
        } >> "$OUTPUT_FILE"
    fi
}

export -f query_db
export DB_USER DB_PASS DB_HOST OUTPUT_FILE

EMAIL_TOTAL=${#EMAILS[@]}
EMAIL_IDX=0
# 并行调度
for EMAIL in "${EMAILS[@]}"; do
    EMAIL_IDX=$((EMAIL_IDX+1))
    echo "📧 正在查询第 $EMAIL_IDX/$EMAIL_TOTAL 个邮箱: $EMAIL"
    parallel --jobs "$THREADS" query_db ::: "$(cat "$TMP_DB_LIST")" ::: "$EMAIL"
done

echo "🎈 查询完成，结果已保存至: $OUTPUT_FILE"
cat "$OUTPUT_FILE"