#!/bin/bash
# 脚本也兼容zsh
# 部署方式: bash /www/sh/shellrc_addition.sh
# 引入外部shell脚本使用source命令,这里防止shellcheck误报,禁用此类检查
# shellcheck disable=SC1091
# compatible_shells=("bash" "zsh")
# 引入预定义的别名
source /www/sh/shell_vars.sh
source /www/sh/shell_alias.sh
source /www/sh/shell_utils.sh
# 使用windows环境下的编辑器时,例如vscode,注意换行符改为LF,避免多行命令被错误解释🎈
mark='# Load additional shell configs'
# 检查~/.zshrc文件中是否存在:$mark 字符串,如果不存在,则向~/.zshrc添加以下内容,否则跳过插入并报告相关配置已存在
config_lines=$(
  cat << EOF

$mark
# shellcheck source=/www/sh/shell_utils.sh
source /www/sh/shellrc_addition.sh

EOF
)
# 检查极简系统中的~/.bash_profile文件
if ! [ -f ~/.bash_profile ]; then
  echo "Creating .bash_profile..."
  cat << 'EOF' > ~/.bash_profile
# if .bashrc，exist, load it first
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF

fi
# 检查bashrc,zshrc文件,如果配置不存在则插入
rcfiles=(~/.bashrc)
if ! [[ -f ~/.bash_profile ]]; then
  touch ~/.bashrc
fi
if [[ -f ~/.zshrc ]]; then
  rcfiles+=(~/.zshrc)
fi
for rcfile in "${rcfiles[@]}"; do
  if grep -q "$mark" "$rcfile"; then
    echo "Configs shell configs already exists in $rcfile, skipping insertion..."
  else
    echo "Inserting configs shell configs into $rcfile..."
    echo "$config_lines" >> "$rcfile"
  fi
done

# 允许root用户运行常用命令(主要针对zsh)
echo "Loading additional shell config and functions..."

# 目录快速切换
if is_shell bash || check_dependency -q shopt; then
  shopt -s autocd   # 直接输入目录名即可进入，无需 cd
  shopt -s cdspell  # 拼写检查：自动修正 cd 时的小错误
  shopt -s globstar # 递归通配符：允许使用 ls **/*.js 这种写法

  # This allows you to bookmark your favorite places across the file system
  # Define a variable containing a path and you will be able to cd into it regardless of the directory you're in
  shopt -s cdable_vars

  # Update window size after every command
  shopt -s checkwinsize

  # Enable history expansion with space
  # E.g. typing !!<space> will replace the !! with your last command
  bind Space:magic-space
  # Turn on recursive globbing (enables ** to recurse all directories)
  shopt -s globstar 2> /dev/null

  ## SANE HISTORY DEFAULTS ##

  # Append to the history file, don't overwrite it
  shopt -s histappend

  # Save multi-line commands as one command
  shopt -s cmdhist

  # Record each line as it gets issued
  PROMPT_COMMAND='history -a'

  # Huge history. Doesn't appear to slow things down, so why not?
  HISTSIZE=500000
  HISTFILESIZE=100000

  # Avoid duplicate entries
  HISTCONTROL="erasedups:ignoreboth"

  # Don't record some commands
  export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"

  # Use standard ISO 8601 timestamp
  # %F equivalent to %Y-%m-%d
  # %T equivalent to %H:%M:%S (24-hours format)
  HISTTIMEFORMAT='%F %T '
fi
# shellcheck disable=SC2154
export INPUTRC="$sh/.inputrc.tpl.conf"
echo "update inputrc [$INPUTRC]..."

[[ -f "$HOME/.inputrc" ]] && echo "warning: ~/.inputrc exists, $INPUTRC will be used instead!"
# cp "$INPUTRC" "$HOME/.inputrc" -fv
[[ -f "$INPUTRC" ]] && check_dependency -q bind 2> /dev/null && {

  if [[ $- == *i* ]]; then
    # 默认会从 $INPUTRC 文件中读取配置readline配置
    # bind -f "$INPUTRC"
    echo "check readline config (case ignore)..."
    bind -v | grep ignore
    # 检查 Readline 是否识search-ignore-case变量从而决定是否自动启用忽略大小写的历史搜索
    if bind -V 2> /dev/null | grep -q "search-ignore-case"; then
      bind 'set search-ignore-case on'
      # bind 'set completion-ignore-case on'
    fi
  else
    echo "Interactive shell environment is not prepared,jump readline binding."
  fi

}
# ===============自定义函数请添加到shell_utils.sh中=================
