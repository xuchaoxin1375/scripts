#!/bin/bash
#!/bin/zsh


# 引入预定义的别名
source /www/sh/shell_alias.sh
# 使用windows环境下的编辑器时,例如vscode,注意换行符改为LF,避免多行命令被错误解释🎈
mark='# Load additional shell configs'
# 检查~/.zshrc文件中是否存在:$mark 字符串,如果不存在,则向~/.zshrc添加以下内容,否则跳过插入并报告相关配置已存在
config_lines=$(cat <<EOF

$mark
source /www/sh/shellrc_addition.sh

EOF
)
# 检查bashrc,zshrc文件,如果配置不存在则插入
for rcfile in ~/.zshrc ~/.bashrc; do
  if grep -q "$mark" "$rcfile"; then
    echo "Configs shell configs already exists in $rcfile, skipping insertion..."
  else
    echo "Inserting configs shell configs into $rcfile..."
    echo "$config_lines" >> "$rcfile"
  fi
done

# 允许root用户运行常用命令(主要针对zsh)
echo "Loading additional shell config and functions..."
# 运行wp命令(借用www用户权限)
wp() {
  	user='www' #修改为你的系统上存在的一个普通用户的名字,比如宝塔用户可以使用www
    echo "[INFO] Executing as user '$user':wp $*"
    sudo -u $user wp "$@"
    local EXIT_CODE=$?
    return $EXIT_CODE
}
# 运行brew命令(借用linuxbrew用户权限)
brew() {
    user='linuxbrew' #修改为你的系统上存在的一个普通用户的名字
    local ORIG_DIR="$PWD"
    echo "[INFO] Executing as user '$user' in /home/linuxbrew: brew $*"
    cd /home/$user && sudo -u $user /home/linuxbrew/.linuxbrew/bin/brew "$@"
    local EXIT_CODE=$?
    cd "$ORIG_DIR" 2>/dev/null || echo "[WARN] Could not return to original directory: $ORIG_DIR"
    return $EXIT_CODE
}
# 强力删除:能够将标志位是i的文件(目录)更改为可删除,然后删除掉指定目标
rmx(){
  # 用法: rmx <目标文件或目录>
  if [ $# -eq 0 ]; then
    echo "用法: rmx <目标文件或目录>"
    return 1
  fi
  for target in "$@"; do
    if [ -e "$target" ]; then
      echo "[INFO] 尝试去除 $target 的 i 标志..."
      sudo chattr -R -i "$target"
      echo "[INFO] 强力删除 $target ..."
      sudo rm -rf "$target"
    else
      echo "[WARN] 目标不存在: $target"
    fi
  done
  return 0
}

# 进程监控函数psm
psm() {
    # 1. 检查帮助选项
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        # 使用 'cat << EOF' 来格式化多行帮助文本
        cat << EOF
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

    # 4. 获取总内存 (KiB)
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')

    # 4.1. 检查是否成功获取
    if [ -z "$total_mem_kb" ] || [ "$total_mem_kb" -eq 0 ]; then
        echo "错误: 无法从 /proc/meminfo 读取总内存。" >&2
        return 1
    fi

    # 5. 执行 ps 和 awk 命令 (核心逻辑不变)
    ps -eo user,pid,%cpu,rss,vsz,nlwp,stat,start_time,cmd --sort="$sort_field" | \
    head -n "$((lines+1))" | \
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
# 为常用情况创建别名
alias pscpu='psm -%cpu'
alias psmem='psm -%mem'
alias pstop='psm -%cpu 10'  # 只显示前10个