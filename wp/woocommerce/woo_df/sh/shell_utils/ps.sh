#!/usr/bin/env bash
# 进程监控函数psm
psm_gnu() {
    # 1. 检查帮助选项
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        # 使用 'cat << EOF' 来格式化多行帮助文本
        cat <<- EOF
    用法: psm [排序字段] [行数]

    功能:
    显示当前系统的进程状态, 类似于 top, 但提供了高精度的内存百分比计算。

    参数:
    [排序字段]   (可选) 指定 'ps' 命令用于排序的字段。
                必须包含 '-' (降序) 或 '+' (升序)。
                注意: 按内存排序请使用 '-rss'。
                (为了方便, '-mem' 或 '-%mem' 会被自动转换为 '-rss')
                默认: -%cpu

    [行数]       (可选) 指定显示进程的行数 (不包括表头)。
                默认: 20

    选项:
    -h, --help   显示此帮助信息并退出。

    示例:
    psm            # 按 CPU 降序显示前 20 个进程
    psm -rss 10    # 按 RSS 内存占用降序显示前 10 个进程
    psm +pid 50    # 按 PID 升序显示前 50 个进程
EOF
        return 0 # 成功退出函数
    fi

    # 2. 处理函数参数
    local sort_field="${1:--%cpu}"
    local lines="${2:-20}"

    # 3. 智能处理内存排序
    #    如果用户输入 -%mem 或 -mem, 自动帮他转换为 -rss
    if [[ "$sort_field" == "-%mem" || "$sort_field" == "-mem" ]]; then
        sort_field="-rss"
    fi

    # 4. 取总内存 (KiB)
    local total_mem_kb
    # total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 方案
        total_mem_kb=$(($(sysctl -n hw.memsize) / 1024))
    else
        # Linux 方案
        total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    fi

    # 4.1. 检查是否成功获取
    if [ -z "$total_mem_kb" ] || [ "$total_mem_kb" -eq 0 ]; then
        echo "错误: 无法从 /proc/meminfo 读取总内存。" >&2
        return 1
    fi

    # 5. 执行 ps 和 awk 命令 (核心逻辑不变)
    ps -eo user,pid,%cpu,rss,vsz,nlwp,stat,start_time,cmd --sort="$sort_field" |
        head -n "$((lines + 1))" |
        awk -v total_mem="$total_mem_kb" '
    NR==1 {
        # 表头
        printf "%-12s %-8s %-6s %-6s %-12s %-12s %-6s %-8s %-10s %-s\n",
               $1,$2,$3,"%MEM","RSS(MB)","VSZ(MB)",$6,$7,$8,"CMD";
        next
    }
    {
        # 字段索引: $3=%CPU, $4=RSS(KiB), $5=VSZ(KiB), $6=NLWP, ...

        # 手动计算 %MEM
        mem_perc = ($4 / total_mem) * 100;
        
        rss_mb=$4/1024; 
        vsz_mb=$5/1024;
        
        cmd=$9; for(i=10;i<=NF;i++) cmd=cmd" "$i;
        if(length(cmd)>50) cmd=substr(cmd,1,47)"...";
        
        # 打印格式化输出, %MEM 使用 %.2f (保留两位小数)
        printf "%-12s %-8s %-6.1f %-6.2f %-12.1f %-12.1f %-6s %-8s %-10s %-s\n",
               $1,$2,$3,mem_perc,rss_mb,vsz_mb,$6,$7,$8,cmd
    }'
}
# 按进程名统计内存占用 (从高到低排序)
psmem_group() {
    local lines=${1:-20} # 如果没有提供参数，默认显示前 20 行
    printf "\n%-15s | %-5s | %s\n" "MEMORY (MB)" "COUNT" "PROCESS"
    printf "%-15s-|-%-5s-|-%s\n" "---------------" "-----" "-------------------------"
    ps -e -c -o rss=,command= | awk '{
        rss=$1; $1=""; sub(/^[ \t]+/, ""); 
        sum[$0]+=rss; count[$0]++
    } END {
        for (cmd in sum) 
            printf "%12.2f MB | %5d | %s\n", sum[cmd]/1024, count[cmd], cmd
    }' | sort -nr | head -n "$lines"
    echo ""
}
# 登出(结束当前用户所有进程)
logout_killall() {
    sudo killall -u "$(whoami)"
}
# 快速注销当前用户
logout_soft() {
    echo "正在注销当前用户并清理进程..."
    # 优先尝试 AppleScript 强制注销
    osascript -e 'tell application "System Events" to  «event aevtlout»'

    # 如果 5 秒后还没登出（可能有程序卡死），则执行强制清理
    sleep 5 && launchctl bootout "user/$(id -u)"
}
# 按照资源占用从高到低的顺序列出进程(可选内存和cpu占用,其中内存使用合适的精度和单位显示)
psm() {
    # 1. 帮助
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat << EOF
用法: psm [排序字段] [行数]

功能:
  显示当前系统进程状态, 提供高精度内存百分比计算。

参数:
  [排序字段]   (可选) 排序字段, 需带符号:
               '-' 降序, '+' 升序
               常用: -%cpu(默认) | -rss | -vsz | +pid
               别名: -mem / -%mem 自动转换为 -rss
  [行数]       (可选) 显示行数 (不含表头), 默认 20

选项:
  -h, --help   显示帮助并退出

示例:
  psm               # 按 CPU 降序显示前 20 个进程
  psm -rss 10       # 按内存降序显示前 10 个进程
  psm +pid 50       # 按 PID 升序显示前 50 个进程
EOF
        return 0
    fi

    # 2. 参数处理
    local sort_field="${1:--%cpu}"
    local lines="${2:-20}"

    # 3. 内存排序别名
    if [[ "$sort_field" == "-%mem" || "$sort_field" == "-mem" ]]; then
        sort_field="-rss"
    fi

    # 4. 平台判断
    local os_type
    if [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macos"
    else
        os_type="linux"
    fi

    # 5. 获取总内存 (KiB)
    local total_mem_kb
    if [[ "$os_type" == "macos" ]]; then
        total_mem_kb=$(($(sysctl -n hw.memsize) / 1024))
    else
        total_mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    fi

    if [[ -z "$total_mem_kb" || "$total_mem_kb" -eq 0 ]]; then
        echo "错误: 无法获取系统总内存。" >&2
        return 1
    fi

    # 6. 构造 ps 命令并输出
    if [[ "$os_type" == "macos" ]]; then
        _psm_macos "$sort_field" "$lines" "$total_mem_kb"
    else
        _psm_linux "$sort_field" "$lines" "$total_mem_kb"
    fi
}

# ── Linux 分支 ──────────────────────────────────────────────
_psm_linux() {
    local sort_field="$1" lines="$2" total_mem_kb="$3"

    ps -eo user,pid,%cpu,rss,vsz,nlwp,stat,start_time,cmd \
        --sort="$sort_field" |
        head -n $((lines + 1)) |
        awk -v total_mem="$total_mem_kb" '
        NR==1 {
            printf "%-12s %-8s %-6s %-7s %-10s %-10s %-6s %-8s %-10s %s\n",
                   "USER","PID","%CPU","%MEM","RSS(MB)","VSZ(MB)",
                   "NLWP","STAT","STARTED","CMD"
            next
        }
        {
            mem_perc = ($4 / total_mem) * 100
            rss_mb   = $4 / 1024
            vsz_mb   = $5 / 1024
            cmd = $9; for(i=10;i<=NF;i++) cmd=cmd" "$i
            if(length(cmd)>45) cmd=substr(cmd,1,42)"..."
            printf "%-12s %-8s %-6.1f %-7.2f %-10.1f %-10.1f %-6s %-8s %-10s %s\n",
                   $1,$2,$3,mem_perc,rss_mb,vsz_mb,$6,$7,$8,cmd
        }
    '
}

# ── macOS 分支 ──────────────────────────────────────────────
_psm_macos() {
    local sort_field="$1" lines="$2" total_mem_kb="$3"

    local field_name order
    if [[ "$sort_field" == -* ]]; then
        field_name="${sort_field#-}"
        order="desc"
    else
        field_name="${sort_field#+}"
        order="asc"
    fi

    ps -eo user,pid,%cpu,rss,vsz,stat,start,command |
        awk -v total_mem="$total_mem_kb" \
            -v field="$field_name" \
            -v order="$order" \
            -v maxlines="$lines" '
        BEGIN {
            col["user"]=1; col["pid"]=2; col["cpu"]=3; col["%cpu"]=3
            col["rss"]=4;  col["vsz"]=5; col["stat"]=6
            col["start"]=7; col["command"]=8; col["cmd"]=8
        }

        NR==1 { next }

        {
            cmd = $8
            for (i=9; i<=NF; i++) cmd = cmd " " $i

            # ✅ 用 (row, col) 复合键模拟二维数组
            rows[NR, 1] = $1
            rows[NR, 2] = $2
            rows[NR, 3] = $3
            rows[NR, 4] = $4
            rows[NR, 5] = $5
            rows[NR, 6] = $6
            rows[NR, 7] = $7
            rows[NR, 8] = cmd
            row_ids[NR] = NR
            total_rows++
        }

        END {
            printf "%-12s %-8s %-6s %-7s %-10s %-10s %-6s %-10s %s\n", \
                   "USER","PID","%CPU","%MEM","RSS(MB)","VSZ(MB)", \
                   "STAT","STARTED","CMD"

            sort_col = (field in col) ? col[field] : 3

            # 冒泡排序 row_ids 数组
            n = total_rows
            for (i = 1; i <= n; i++) {
                for (j = 1; j <= n - i; j++) {
                    ri = row_ids[j]
                    rj = row_ids[j+1]

                    # 判断是否为字符串列
                    if (sort_col==1 || sort_col==6 || sort_col==7 || sort_col==8) {
                        a = rows[ri, sort_col]
                        b = rows[rj, sort_col]
                        need_swap = (order=="desc") ? (a < b) : (a > b)
                    } else {
                        a = rows[ri, sort_col] + 0
                        b = rows[rj, sort_col] + 0
                        need_swap = (order=="desc") ? (a < b) : (a > b)
                    }

                    if (need_swap) {
                        tmp = row_ids[j]
                        row_ids[j] = row_ids[j+1]
                        row_ids[j+1] = tmp
                    }
                }
            }

            # 输出前 maxlines 行
            printed = 0
            for (i = 1; i <= n && printed < maxlines; i++) {
                ri = row_ids[i]
                mem_perc = (rows[ri, 4] / total_mem) * 100
                rss_mb   =  rows[ri, 4] / 1024
                vsz_mb   =  rows[ri, 5] / 1024
                cmd      =  rows[ri, 8]
                if (length(cmd) > 45) cmd = substr(cmd, 1, 42) "..."
                printf "%-12s %-8s %-6.1f %-7.2f %-10.1f %-10.1f %-6s %-10s %s\n", \
                       rows[ri,1], rows[ri,2], rows[ri,3], mem_perc, \
                       rss_mb, vsz_mb, rows[ri,6], rows[ri,7], cmd
                printed++
            }
        }
    '
}
# 为常用情况创建别名
alias pscpu='psm -%cpu'
alias psmem='psm -%mem'
alias pstop='psm -%cpu 10' # 只显示前10个
