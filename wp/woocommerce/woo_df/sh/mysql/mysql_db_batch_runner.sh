#!/bin/bash
# 定义需要执行的sql语句
usage="
usage: $0 [options]

--sql 指定sql文件的路径
-h,--help 打印此帮助
"
SQL='/www/sh/mysql/sql.sql'
# 设置并发数
DB_PASSWORD='15a58524d3bd2e49'
DB_USER='root'
CONCURRENCY=10
ARGS_POS=()
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f | --sql)
                SQL="$2"
                shift
                ;;
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            -j | --concurrency)
                CONCURRENCY="$2"
                shift
                ;;
            --db-user)
                DB_USER="$2"
                shift
                ;;
            --db-key)
                DB_PASSWORD="$2"
                shift
                ;;
            -*)
                echo "未知参数[$1]"
                echo "$usage"
                exit 1
                ;;
            *)
                ARGS_POS+=("$1")
                shift
                ;;
        esac
        shift
    done
}
parse_args "$@"
set -- "${ARGS_POS[@]}"
[[ ${#1} -gt 0 ]] && SQL="$1"

# ! [[ -f "$SQL" ]] && {
#     echo "SQL file not found: $SQL" >&2
#     exit 1
# }

# 临时测试片段
# SQL="SELECT DATABASE();" #简单打印当前链接到的数据库


# mysql选项说明
# -D, --database=name Database to use.
# -s, --silent        Be more silent. Print results with a tab as separator,
# -N, --skip-column-names
query_db() {
    local db="$1"

    # local res
    # res=$(mysql -u root -p"$KEY" -N -s -D "$db" < "$SQL" 2> /dev/null)
    # echo "$db, $res"

    mysql -u "$DB_USER" -p"$DB_PASSWORD" -N -s -D "$db" < "$SQL"  2> /dev/null
}

export -f query_db
export DB_PASSWORD SQL

# 获取所有数据库（排除系统库）
databases=$(mysql -u root -p"$DB_PASSWORD" -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|mysql|performance_schema|sys)")

echo "$databases" | xargs -P "$CONCURRENCY" -I {} bash -c 'query_db "$@"' _ {}
