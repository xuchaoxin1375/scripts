#!/bin/bash
#!/bin/zsh

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
