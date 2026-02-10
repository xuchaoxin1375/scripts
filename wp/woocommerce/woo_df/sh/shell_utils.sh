#!/bin/bash
# 提供一些常用的bash/zsh兼容的函数.

 
#######################################
# 检查系统中是否存在指定的依赖命令。
# Arguments:
#   1 - 待检查的命令名称 (string)。
# Outputs:
#   如果命令不存在，则向 STDERR 输出一条错误消息。
# Returns:
#   0 如果命令已找到。
#   1 如果命令不存在。
#######################################
check_dependency() {
  local cmd="$1"
  # command -v "$cmd" &>/dev/null
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "错误: 缺少必要的依赖命令 '$cmd'，请先安装。" >&2
    return 1
  fi
  return 0
}
# 判断当前shell
# 要在脚本内部准确判断当前运行环境，最健壮的方法是利用各 Shell 的内置变量
current_shell() {

  if [ -n "$ZSH_VERSION" ]; then
    CURRENT_SHELL="zsh"
  elif [ -n "$BASH_VERSION" ]; then
    CURRENT_SHELL="bash"
  else
    CURRENT_SHELL="unknow"
  fi

  echo "$CURRENT_SHELL"
}
# 获取bash内置命令的帮助
help_bash() {
  cmd="$1"
  bash -c "help $cmd"
}
# 在非bash(zsh)或bash中可以通用的查询bash内置命令的函数
help() {
  cmd="$1"
  # 黄色的提示:当前help输出来自于bash
  YELLOW='\e[31m'
  END='\e[0m'
  shell=$(current_shell)
  tip="${YELLOW}[START]当前shell为$shell,而help输出来自于bash ${END}"
  if ! [[ "$shell" =~ .*bash ]]; then
    echo -e "$tip"
    help_bash "$cmd" | nl
    echo -e "$tip"
  else
    help_bash "$cmd" | nl
  fi

}

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
  cd "$ORIG_DIR" 2> /dev/null || echo "[WARN] Could not return to original directory: $ORIG_DIR"
  return $EXIT_CODE
}
# 强力删除:能够将标志位是i的文件(目录)更改为可删除,然后删除掉指定目标
# 这是一个简化版本(使用rm1或rm2更可靠)
# 用法: rmx <目标文件或目录>
rmx() {
  if [ $# -eq 0 ]; then
    echo "用法: rmx <目标文件或目录>"
    return 1
  fi
  for target in "$@"; do
    if [ -e "$target" ]; then
      echo "[INFO] 尝试去除 $target 的 i 标志..."
      sudo chattr -R -ia "$target"
      echo "[INFO] 强力删除 $target ..."
      sudo rm -rf "$target"
    else
      echo "[WARN] 目标不存在: $target"
    fi
  done
  return 0
}
#######################################
# 强力删除指定的文件或目录。
# 该函数会尝试移除文件的不可修改属性 (immutable) 和权限限制，
# 然后执行强制递归删除。
# Arguments:
#   待删除的文件或目录路径（支持多个参数）。
# Returns:
#   0 如果所有目标都被成功删除。
#   1 如果未提供参数或删除失败。
#######################################
rm1() {
  # 检查是否输入了参数
  if [[ $# -eq 0 ]]; then
    echo "Error: No arguments provided." >&2
    echo "Usage: rm1 <path> [path...]" >&2
    return 1
  fi

  local exit_code=0
  # 为了支持同时处理多个文件/目录,使用循环遍历此函数的所有参数
  for target in "$@"; do
    # 删除前判断目标是否存在(文件/目录/符号链接等)
    if [[ -e "$target" ]]; then
      echo "Force removing: $target"

      # 1. 移除特殊属性 (-i 不可修改, -a 仅追加)
      # 使用 sudo 确保有权修改属性
      sudo chattr -R -ia "$target" 2> /dev/null

      # 2. 修改权限，确保 root 拥有完全控制权
      sudo chmod -R 777 "$target" 2> /dev/null

      # 3. 递归强制删除
      sudo rm -rf "$target"

      # 检查结果
      if [[ -e "$target" ]]; then
        echo "FAILED: $target still exists." >&2
        exit_code=1
      else
        echo "SUCCESS: $target has been removed."
      fi
    else
      echo "Skip: $target does not exist."
    fi
  done

  return $exit_code
}

rm2() {
  # 强力删除文件或目录（移除 immutable 属性后删除）
  # 用法: rm2 [-f] <目标文件或目录>...
  #   -f: 跳过确认提示

  local force=false
  local errors=0

  # 解析选项
  if [[ "$1" == "-f" ]]; then
    force=true
    shift
  fi

  if [[ $# -eq 0 ]]; then
    echo "用法: rmx [-f] <目标文件或目录>..." >&2
    return 1
  fi

  for target in "$@"; do
    # 检查存在性（包括断开的符号链接）
    if [[ ! -e "$target" && ! -L "$target" ]]; then
      echo "[WARN] 目标不存在: $target" >&2
      ((errors++))
      continue
    fi

    # 安全确认（除非 -f）
    if [[ "$force" != true ]]; then
      read -r -p "[WARN] 确定要强制删除 '$target'? [y/N] " confirm
      [[ "$confirm" != [yY] ]] && continue
    fi

    echo "[INFO] 处理: $target"

    # 移除 immutable 属性（根据类型选择是否递归）
    if [[ -d "$target" ]]; then
      sudo chattr -R -i -- "$target" 2> /dev/null
    else
      sudo chattr -i -- "$target" 2> /dev/null
    fi
    # 注意: 非 ext 文件系统会失败，忽略错误

    # 执行删除
    if sudo rm -rf -- "$target"; then
      echo "[OK] 已删除: $target"
    else
      echo "[ERROR] 删除失败: $target" >&2
      ((errors++))
    fi
  done

  return $((errors > 0 ? 1 : 0))
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
  local total_mem_kb
  total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')

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
# 为常用情况创建别名
alias pscpu='psm -%cpu'
alias psmem='psm -%mem'
alias pstop='psm -%cpu 10' # 只显示前10个
