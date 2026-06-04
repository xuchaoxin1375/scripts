#!/usr/bin/env bash
# 使用truncate清空(指定文件)日志文件内容,会直接把文件大小变成 0，通常是最省心、最稳定的做法。
# 对于持续写入中的 Nginx access/error 日志，这也是更合适的清理方式。
dirs=(
    /www/wwwlogs
    /var/log/nginx
)
echo "[$(date +%F-%T)]Run the cleaner routine."
for logdir in "${dirs[@]}"; do
    [ -d "$logdir" ] &&
        find "$logdir" \
            -type f \
            \( -name "*access.log" -o -name "*error.log*" \) \
            -exec truncate -s 0 {} +

done
