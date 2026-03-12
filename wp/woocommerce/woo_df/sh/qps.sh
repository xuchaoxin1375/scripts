#!/bin/bash

LOG_FILE="/www/wwwlogs/spider.log"
args_pos=()
while [[ $# -gt 0 ]]; do
    usage="使用方法： [-f <日志文件>]"
    case "$1" in
        -f | --file)
            LOG_FILE="$2"
            shift
            ;;
        -h | -\? | --help)
            [[ $1 =~ -(-?h.*|\?) ]] && echo "$usage" && exit 0
            ;;
        -*)
            echo "未知参数：$1"
            echo "$usage"
            exit 1
            ;;
        *)
            args_pos+=("$1")

            ;;
    esac
    shift
done

set -- "${args_pos[@]}"
echo "[$LOG_FILE]"
# 使用 awk 实时处理
tail -f "$LOG_FILE" | awk '
{
    # 提取域名：根据你的格式，域名在 [req = 之后
    # 匹配模式：寻找包含 "req =" 的部分并取其后的域名
    match($0, /\[req = ([^/]+)/, arr);
    domain = arr[1];
    
    if (domain == "") { domain = "unknown"; }

    # 获取当前秒级时间戳
    current_time = strftime("%H:%M:%S");

    # 累加计数
    count[domain]++;
    total++;

    # 如果时间跳变，则输出上一秒的统计
    if (current_time != last_time && last_time != "") {
        printf "\033[H\033[J" # 清屏 (可选，为了保持界面整洁)
        print "--- 实时 QPS 统计 (" last_time ") ---"
        printf "%-30s %-10s\n", "域名 (Domain)", "QPS"
        print "----------------------------------------"
        
        for (d in count) {
            printf "%-30s %-10s\n", d, count[d]
            delete count[d]
        }
        
        print "----------------------------------------"
        printf "%-30s %-10s\n", "TOTAL", total
        total = 0
    }
    last_time = current_time
}'
