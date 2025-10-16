#!/bin/bash
# 定义需要执行的sql语句
# SQL="SELECT DATABASE();" #简单打印当前链接到的数据库
SQL=$(
cat << eof
-- 查询运费
-- select * from wp_options
-- WHERE option_name LIKE 'woocommerce_flat_rate_%_settings';

-- 设置运费
UPDATE wp_options
SET option_value = REPLACE(option_value, '"cost";s:1:"0"', '"cost";s:5:"14.98"')
WHERE option_name LIKE 'woocommerce_flat_rate_%_settings';

eof

)

key='15a58524d3bd2e49'
# 获取所有数据库（排除系统库）
databases=$(mysql -u root -p$key -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|mysql|performance_schema|sys)")

for db in $databases; do
    echo "=== Executing on database: $db ==="
    mysql -u root -p$key -D "$db" -e "$SQL"
done