#!/bin/bash
# 删除nginx日志(配合crontab使用,比如每2天删除1次)
rm /www/wwwlogs/*.log
