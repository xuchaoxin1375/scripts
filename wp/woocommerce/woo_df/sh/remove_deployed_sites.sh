#!/bin/bash
# 每周日0点执行一次归档目录的删除操作,crontab 语句如下:
# 0 0 * * 0 bash /www/sh/remove_deployed_sites.sh

# 此脚本的命令如下
# rm -rf /srv/uploads/uploader/deployed 
find /srv/uploads/uploader/files -maxdepth 2 -name 'deployed' -type d  -exec rm -v -rf {} \;