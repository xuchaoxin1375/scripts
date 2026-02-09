#!/bin/bash
# 列出指定服务器备份目录中的压缩包,并保存到文本文件中
find /www/wwwroot/xcx/s4-1 -name '*zst' -printf "%f\n" > result.txt
# 读取文本文件中的网站备份包名
mapfile -t dms < result.txt
# 将文本文件中的网站压缩包文件去除后缀,提取域名,然后排序去重复,
for d in "${dms[@]}"; do
    echo "${d%.com*}.com"
done | sort > domains.txt
# 如果domains.txt中的文件数量不是偶数,说明至少有站点备份不完整(比如缺失了数据库包或者根目录包)
nl domains.txt
# wc -l < domains.txt

cat domains.txt | uniq > backuped.txt
# 列出整理好的域名列表(均已备份)
nl backuped.txt

#下载或拷贝文件内容,粘贴到需要检查备份的服务器上(目标服务器),保存对应的文本文件(dms_backuped.txt)
#将目标服务器上的所有网站域名的列表拷贝并保存为文本文件(dms_all.txt)
#移除文件中多余的空格
sed 's/^[[:space:]]*//;s/[[:space:]]*$//' dms*.txt
# 使用grep计算差集
grep -Fxvf dms_backuped.txt dms_all.txt|nl

#也可以计算交集(供参考)
# grep -Fxf dms_all.txt dms_backuped.txt|nl
