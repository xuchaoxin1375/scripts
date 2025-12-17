#! /bin/bash
myfiles=("n1","n 2","m n  3")
# Double quote array expansions to avoid re-splitting elements.
# echo ${myfiles[@]} #缺少引号包裹的数组扩展表达式是危险的,对于数组中包含空格的字符串元素,在数组变量展开时发生重分割引发错误

echo "${myfiles[@]}" #坚持使用引号包裹数组扩展表达式,确保不会因为空格导致错误(即便数组中的字符串都不包含空格,也应该坚持使用引号包裹)

# files=("baz", "foo bar", "*" ,"/*/*/*/*")
files=("baz" "foo bar" "*" )
echo ${files[@]}