#!/bin/bash
# 脚本也兼容zsh
# 引入外部shell脚本使用source命令,这里防止shellcheck误报,禁用此类检查
# shellcheck disable=SC1091

# 引入预定义的别名
source /www/sh/shell_vars.sh
source /www/sh/shell_alias.sh
# 使用windows环境下的编辑器时,例如vscode,注意换行符改为LF,避免多行命令被错误解释🎈
mark='# Load additional shell configs'
# 检查~/.zshrc文件中是否存在:$mark 字符串,如果不存在,则向~/.zshrc添加以下内容,否则跳过插入并报告相关配置已存在
config_lines=$(
  cat << EOF

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

# ===============添加自定义函数到下面=================

# shellcheck source=/www/sh/shell_utils.sh
source /www/sh/shell_utils.sh
[[ -f "$sh/.inputrc" ]] && check_dependency 2> /dev/null bind && {
  bind -f "$sh/.inputrc"
  echo "update inputrc..."
}
