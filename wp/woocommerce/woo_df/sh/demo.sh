#! /usr/bin/env bash
# =======

cnt=1
while IFS= read -r line; do
    echo "[$((cnt++))]:Processing [$line]"
    find -L /www/wwwroot/ -mindepth 5 -maxdepth 5 -path '*'/$line/wordpress/wp-content/uploads
done < "img_dirs.txt"

#!/bin/bash

# 将所有符合条件的目录存入数组
mapfile -t dirs < <(find -L /www/wwwroot/ -mindepth 5 -maxdepth 5 -type d -path '*/wordpress/wp-content/uploads')

# 读取匹配列表并计数
cnt=1
result="result.txt"
rm "$result" -rf
while IFS= read -r pattern; do
    for dir in "${dirs[@]}"; do
        if [[ "$dir" == *"/$pattern/wordpress/wp-content/uploads" ]]; then
            echo "[$((cnt++))]:Processing [$pattern] -> $dir"
            echo "$dir" >> "$result"
        fi
    done
done < "img_dirs.txt"

# cnt=1
# mapfile -t white_list < "img_dirs.txt"
# for p in /www/wwwroot/*/*/wordpress/wp-content/uploads; do
#     echo "[$((cnt++))]:Processing [$p]"
# done
