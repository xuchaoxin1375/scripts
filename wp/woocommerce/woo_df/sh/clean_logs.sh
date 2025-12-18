#!/bin/bash
# 删除nginx日志(配合crontab使用,比如每2天删除1次)
# rm /www/wwwlogs/*.log
pattern="/www/wwwlogs/*.log"
# 将所有*.log日志文件内容置空
for log in $pattern ; do
    echo "" > "$log";
    # 将文件所有者更改为www
    chown www:www "$log";
done
