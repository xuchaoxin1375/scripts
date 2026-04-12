#!/bin/bash
# 脚本也兼容zsh
# 部署方式: bash "$sh"/shellrc_addition.sh
# wsl中执行部署: sudo mkdir -p /www/ ; sudo ln -sTv /mnt/c/repos/scripts/$SH_RELATIVE/  "$sh"
# 引入外部shell脚本使用source命令,这里防止shellcheck误报,禁用此类检查
# shellcheck disable=SC1091
# shellcheck disable=SC2154
# compatible_shells=("bash" "zsh")

# 计算加载配置的耗时
start_time=$(date +%s%N)
# BASHRC_FILE="$HOME/.bashrc"
_SH_RELATIVE="wp/woocommerce/woo_df/sh"
_REPO_BASE="repos/scripts"
_SHELL_DEBUG=0
# 防止重复导入检查处理
if [ -z "$_SHELLX_LOADED" ]; then
  # 标记为空,则说明此前并未导入,本轮需要导入  # 方便起见,直接修改标记为被导入,然后再继续后面的配置代码
  _SHELLX_LOADED=true
else
  # echo "===debug: custom shell already loaded..."
  # 跳过本次导入
  return 0
fi
# 判断当前系统(平台)类型
echo "Current Os type is [$OSTYPE]"
if [[ $OSTYPE == "darwin"* ]]; then
  SCRIPT_ROOT="$HOME/$_REPO_BASE"
elif [[ $OSTYPE == "linux"* ]]; then
  SCRIPT_ROOT="$HOME/$_REPO_BASE"
  # ! [[ -e $SCRIPT_ROOT ]] && SCRIPT_ROOT="$HOME/$_REPO_BASE"
  # wsl可选:
  [[ -d /mnt/c/ ]] && SCRIPT_ROOT="/mnt/c/$_REPO_BASE"
else
  # msys*(windows上的一些模拟层)
  [[ -d /c/ ]] && SCRIPT_ROOT="/c/$_REPO_BASE"
fi
sh="$SCRIPT_ROOT/$_SH_RELATIVE"

# bash prompt主题配置
export BASH_PROMPT="fast_ys"
export BASHRC_FILE="$HOME/.bashrc"
export BASH_PROMPTS_ROOT="$sh/bash_prompts"
# linuxbrew的基本环境变量
_HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
_HOMEBREW_PATH="$_HOMEBREW_PREFIX/bin/brew"
# macos brew(homebrew) 会自己注册HOMEBREW_PREFIX等环境变量
# HOMEBREW_PREFIX="$(brew --prefix)"

# 引入预定义的别名
source "$sh"/shell_vars.sh
source "$sh"/shell_alias.sh
source "$sh"/shell_utils.sh
# source "$sh"/shell_env_mgr.sh
source "$sh"/shell_insert_last_part.sh
# source "$BASH_PROMPTS_ROOT/prompt_switcher.sh"

if is_shell bash; then
  # 配置调试用途的PS4

  # export PS4='\[\e[35m\]+ [${BASH_SOURCE[0]##*/}:${LINENO}]\[\e[0m\] '
  export PS4='+ [${BASH_SOURCE[0]##*/}:${LINENO}] ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  # export PS4='+ [${SECONDS}s][${BASH_SOURCE}:${LINENO}][${FUNCNAME[0] || main}] '
  # 启用调试模式(按需启用set -x)
  [[ $_SHELL_DEBUG -eq 1 ]] && set -x
fi

# brew包管理器配置(如果可用的话) brew shellenv 是幂等的,如果shell环境执行过一次,那么再次执行输出为空.
if [[ -e "$_HOMEBREW_PATH" && -z $HOMEBREW_PREFIX ]]; then
  # $_HOMEBREW_PATH shellenv # debug print it
  eval "$($_HOMEBREW_PATH shellenv)"
fi
# 移除wsl中ls列出文件夹的背景色
remove_background_color() {
  echo "Remove the background color to improve the reading experience."
  echo "try to remove bgc for the current shell:$SHELL!"
  if command -v dircolors &> /dev/null; then
    eval "$(dircolors -p |
      sed 's/ 4[0-9];/ 01;/; s/;4[0-9];/;01;/g; s/;4[0-9] /;01 /' |
      dircolors /dev/stdin)"
  fi
}

# 使用windows环境下的编辑器时,例如vscode,注意换行符改为LF,避免多行命令被错误解释🎈
# mark='# Load additional shell configs'
mark="custom additional shell"
mark_start="# >>>$mark>>>"
mark_end="# <<<$mark<<<"
# 检查~/.zshrc文件中是否存在:$mark 字符串,如果不存在,则向~/.zshrc添加以下内容,否则跳过插入并报告相关配置已存在
config_lines=$(
  cat << EOF

$mark_start
# Load additional shell configs
# shellcheck source=/dev/null

source "$sh"/shellrc_addition.sh

$mark_end

EOF
)

# START-CBRC:检查极简系统中的~/.bash_profile文件,必要时插入引导~/.bashrc的逻辑
if ! [ -f ~/.bash_profile ]; then
  echo "Creating .bash_profile..."
  cat << 'EOF' > ~/.bash_profile
# if .bashrc，exist, load it first
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

EOF

fi
# END-CBRC

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
    echo "[$mark] already exists in $rcfile, skipping insertion..."
  else
    echo "Inserting configs shell configs into $rcfile..."
    echo "$config_lines" >> "$rcfile"
  fi
done

# 允许root用户运行常用命令(主要针对zsh)
echo "Loading additional shell config and functions..."
# 为macos导入专用配置
if is_darwin; then
  # 导入macos相关定义
  # shellcheck source=/dev/null
  source "$macos_sh"/*.sh
  # 设置gnu工具集优先
  set_gnu_instead_bsd
fi
# 针对bash的配置(依赖于shopt命令和针对bash的prompt)
if is_shell bash || check_dependency -q shopt; then
  if ! [[ $OSTYPE == "darwin"* ]]; then
    # macos does not need remove the folder background colors
    remove_background_color
  fi
  # 插入bashrc的最后部分的配置
  update_last_part_bashrc "$sh"
  # 在合适的位置加载bash prompt(间接修改PS1)
  source "$BASH_PROMPTS_ROOT/prompt_switcher.sh"
  # 检查当前 Shell 是否运行在 POSIX 模式下。
  # POSIX 模式是为了严格遵守 Unix 标准，它会禁用很多 Bash 特有的“花哨”功能（比如高级补全）。
  if ! shopt -oq posix; then
    # echo "bash not running on posix mode ..."
    # for macos bash-completion
    if is_darwin; then
      # set -x
      [[ -r "/opt/homebrew/etc/profile.d/bash_completion.sh" ]] && . "/opt/homebrew/etc/profile.d/bash_completion.sh"
      # set +x
    else
      # 检查PS1环境变量,非空(且尚未导入过)bash-completion采执行导入;
      # declare -p PS1 #debug:检查PS1环境变量取值
      # Use bash-completion, if available, and avoid double-sourcing
      [[ $PS1 &&
        ! ${BASH_COMPLETION_VERSINFO:-} &&
        -f /usr/share/bash-completion/bash_completion ]] &&
        . /usr/share/bash-completion/bash_completion
    fi
    # 注意感叹号!在双引号中可能具有特殊性,尤其是历史功能启用的情况下,建议转义!号
    echo "[bash-completion] (version:${BASH_COMPLETION_VERSINFO:-"None"})..."
  fi

  set_shopt() {

    # 目录快速切换
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
  }
  set_shopt

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
  # 加载bash prompt(注意每次加载prompt附近可能绑定其他一些动作)
  # Record each line as it gets issued
  # 自定义prompt的话一般也会更改PROMPT_COMMAND,考虑把被绑定的语句放到prompt定义中
  # PROMPT_COMMAND='history -a'
  echo "bash prompt:$BASH_PROMPT"
  # 考虑到用户可能使用conda,nvm等环境管理工具,这可能修改prompt,因此这里在覆盖promopt前保留原propmt值供后续拼接
  # 注意本代码在~/.bashrc中插入位置要靠后,否则如果在conda这类导入片段之前可能会被覆盖效果;或者.bashrc(中BASH_COMMAND的设置 )

fi
if is_shell zsh; then
  # ^[[A 和 ^[[B 是大多数终端（如 iTerm2, VS Code 终端, Putty）发送给 Shell 的原始“向上”和“向下”信号。
  # 绑定向上箭头
  bindkey '^[[A' history-substring-search-up
  # 绑定向下箭头
  bindkey '^[[B' history-substring-search-down
  # ${terminfo}[kcuu1] 代表从系统的终端信息数据库中读取“向上箭头”的定义。
  bindkey "${terminfo[kcuu1]}" history-substring-search-up
  bindkey "${terminfo[kcud1]}" history-substring-search-down
  # 如果你使用 Vi 模式，还可以绑定 j 和 k
  # bindkey -M vicmd 'k' history-substring-search-up
  # bindkey -M vicmd 'j' history-substring-search-down
fi
export INPUTRC="$sh/.inputrc.conf"
echo "update inputrc [$INPUTRC]..."

[[ -f "$HOME/.inputrc" ]] && echo "warning: ~/.inputrc exists, $INPUTRC will be used instead!"
# cp "$INPUTRC" "$HOME/.inputrc" -fv
[[ -f "$INPUTRC" ]] && check_dependency -q bind 2> /dev/null && {

  # 默认会从 $INPUTRC 文件中读取配置readline配置
  bind -f "$INPUTRC" 2> /dev/null
  if [[ $- == *i* ]]; then
    echo "check readline config (case ignore)..."
    bind -v | grep ignore
    # 检查 Readline 是否识search-ignore-case变量从而决定是否自动启用忽略大小写的历史搜索
    # if bind -V 2> /dev/null | grep -q "search-ignore-case"; then
    #   bind 'set search-ignore-case on'
    #   # bind 'set completion-ignore-case on'
    # fi
  else
    echo "Interactive shell environment is not prepared. Jump readline binding util next time bash loading."
  fi

}

# end bash-completion importer
end_time=$(date +%s%N)
# 计算差值（纳秒转毫秒）
elapsed=$(((end_time - start_time) / 1000000))
echo "Elapsed(execution) Time: ${elapsed} ms"
# 如果要自定义函数请添加到shell_utils.sh中!
