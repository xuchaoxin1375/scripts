#! /bin/bash


echo "args number:$#"
# 遍历参数
# for arg in "$@"
# do
#     echo "arg:$arg"
# done

# 带编号打印参数,是和使用C风格的for循环(借助$#获取参数个数)
# for ((i=1;i<=$#;i++)) do
#     # $i是参数编号, ${!i}是第i个的取值
#     echo "arg $i:${!i}"
# done

i=1
for arg in "$@"
do
    echo "arg $i:$arg"
    i=$((i+1))
done

themes_dir="$sh/archives/themes"
src_file="/www/functions.sh"

# 遍历目录下的所有文件夹
for dir in "$themes_dir"/*/; do
    echo "[$dir]";
    if [ -d "$dir" ]; then
        \cp -v "$src_file" "$dir" -f
    fi
done