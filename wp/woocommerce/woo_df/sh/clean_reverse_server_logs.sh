#!/usr/bin/env bash
# 使用truncate清空(指定文件)日志文件内容,会直接把文件大小变成 0，通常是最省心、最稳定的做法。
# 对于持续写入中的 Nginx access/error 日志，这也是更合适的清理方式。
dirs=(
    /www/wwwlogs
    /var/log/nginx
)
echo "[$(date +%F-%T)]Run the cleaner routine."
for logdir in "${dirs[@]}"; do
    if [ -d "$logdir" ]; then
        find "$logdir" \
            -type f \
            \( -name "*access.log*" -o -name "*error.log*" \) \
            -exec sh -c '
                for file do
                    echo "[$(date +%F-%T)] Truncating: $file"
                    truncate -s 0 "$file"
                done
            ' sh {} +
    else
        echo "[$(date +%F-%T)] Skip missing directory: $logdir"
    fi
done
# 查看磁盘使用情况
df -h # 关注/ (根目录即可)