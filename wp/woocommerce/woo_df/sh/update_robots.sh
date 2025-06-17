#!/bin/bash

# 源robots.txt文件路径
src_robots="/www/wwwroot/robots.txt"

# 检查源文件是否存在
if [ ! -f "$src_robots" ]; then
  echo "源文件 $src_robots 不存在，请确认路径是否正确。"
  exit 1
fi

# 查找所有子目录中的 robots.txt 文件并替换
find /www/wwwroot/ -type f -name "wordpress/robots.txt" | while read -r file; do
  echo "正在处理: $file"
  cp -f "$src_robots" "$file"
done

echo "所有 robots.txt 文件已更新。"
