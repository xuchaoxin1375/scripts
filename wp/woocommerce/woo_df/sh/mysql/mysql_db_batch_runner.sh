#!/bin/bash
# 定义需要执行的sql语句
# SQL="SELECT DATABASE();" #简单打印当前链接到的数据库
SQL=$(
# 指定sql片段
    cat << eof
SELECT post_title
FROM wp_posts 
WHERE post_type = 'product' 
AND post_status = 'private';
eof

)
export SQL

key='15a58524d3bd2e49'
# 获取所有数据库（排除系统库）
databases=$(mysql -u root -p$key -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|mysql|performance_schema|sys)")

# 设置并发数
CONCURRENCY=1
echo "$databases" | xargs -P $CONCURRENCY -I {} \
    sh -c "res=\$(mysql -u root -p'$key' -N -s -D '{}' -e \"\$SQL\"); echo \"{}, \$res\"" 2> /dev/null

# echo "$databases" | xargs -P 1 -I {} \
#     sh -c "echo -n '{}:' ; mysql -u root -p'$key' -D '{}' -e \"\$SQL\";echo 'done!'" 2> /dev/null

# echo "$databases" | xargs  -P $CONCURRENCY -I {} \
#     mysql -u root -p"$key" -D "{}" -e "$SQL"

# for db in $databases; do
#     echo "=== Executing on database: $db ==="
#     # continue
#     mysql -u root -p$key -D "$db" -e "$SQL"
# done