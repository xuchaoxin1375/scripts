#!/bin/bash
#!/bin/zsh
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

# 进程监控函数
psm() {
    local sort_field="${1:--%cpu}"
    local lines="${2:-20}"
    
    ps -eo user,pid,%cpu,%mem,rss,vsz,nlwp,stat,start_time,cmd --sort="$sort_field" | head -n "$((lines+1))" | awk '
    NR==1 {
        printf "%-12s %-8s %-6s %-6s %-12s %-12s %-6s %-8s %-10s %-s\n",
               $1,$2,$3,$4,"RSS(MB)","VSZ(MB)",$7,$8,$9,"CMD";
        next
    }
    {
        rss_mb=$5/1024; vsz_mb=$6/1024;
        cmd=$10; for(i=11;i<=NF;i++) cmd=cmd" "$i;
        if(length(cmd)>50) cmd=substr(cmd,1,47)"...";
        printf "%-12s %-8s %-6.1f %-6.1f %-12.1f %-12.1f %-6s %-8s %-10s %-s\n",
               $1,$2,$3,$4,rss_mb,vsz_mb,$7,$8,$9,cmd
    }'
}

# 为常用情况创建别名
alias pscpu='psm -%cpu'
alias psmem='psm -%mem'
alias pstop='psm -%cpu 10'  # 只显示前10个