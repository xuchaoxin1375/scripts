#!/bin/bash
# shellcheck disable=SC1091
list_file="$1" #命令行参数第一个作为域名文件列表.

source /www/sh/shell_utils.sh #导入rsync_copy函数
user="zw"
server="s3"

from_dir=/www/wwwroot/xcx/$server/$user/deployed
# 需要拉取的域名列表,建议从外部文件读取
names=(

)
for name in "${names[@]}"; do
    for pkg in "$from_dir/${name}.zst" "$from_dir/${name}.sql.zst"; do
        rsync_copy 23.239.111.114 /srv/uploads/uploader/files/recovery/$user/deployed "$pkg"
    done
done
