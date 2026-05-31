#! /bin/bash
# 获取url字符串中的主域名(适用于普通域名(单段后缀))
# EXAMPLES:
#   get_main_domain "https://www.example.com/news/index.html" # 输出: example.com
#   get_main_domain "http://sub.domain.example.com?v=1"       # 输出: example.com
#   get_main_domain "www.example.com"                         # 输出: example.com
#   get_main_domain "example.com"                             # 输出: example.com
#   get_main_domain "http://example.com/"                     # 输出: example.com
get_main_domain() {
    echo "$1" |
        sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#\?.*##; s#:.*##; s#^www\.##' |
        grep -oE '([^.]+\.[^.]+)$'
}
