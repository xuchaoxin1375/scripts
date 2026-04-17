#!/bin/bash
SITE_LIST_FILE="$HOME/site_to_remove.txt"
mapfile -t sites < "$SITE_LIST_FILE"
project_roots=('/www/wwwroot' '/wwwdata/wwwroot')
cnt=0
for site in "${sites[@]}"; do
    ((cnt++))
    echo "cleaning[$cnt]:$site"
    # 扫描网站根目录
done
