#! /bin/bash
__fine_bash_prompt() {
    local exit_code=$?
    echo "$exit_code" > /dev/null
    # 颜色定义
    local gray='\[\e[38;5;244m\]'
    local cyan='\[\e[1;36m\]'
    local yellow='\[\e[1;33m\]'
    local red='\[\e[1;31m\]'
    local blue='\[\e[1;34m\]'
    local reset='\[\e[0m\]'

    # 时间
    local time
    time=$(date +"%H:%M:%S")

    # Git 信息
    local git_info=""
    if git rev-parse --git-dir &> /dev/null; then
        local branch
        branch=$(git symbolic-ref --short HEAD 2> /dev/null || git rev-parse --short HEAD 2> /dev/null)
        local git_status=""

        # 检查是否有未提交更改
        if ! git diff --quiet 2> /dev/null || ! git diff --cached --quiet 2> /dev/null; then
            git_status="${red}x${reset}"
        fi

        # 检查是否有未跟踪文件
        if [[ -n $(git ls-files --others --exclude-standard 2> /dev/null) ]]; then
            git_status="${git_status}${yellow}?${reset}"
        fi

        git_info=" ${yellow}on${reset} ${red}git:${branch}${reset}"
        [[ -n $git_status ]] && git_info+=" ${git_status}"
    fi

    # 组装 prompt
    PS1="\n${gray}# [bash]${reset} ${cyan}\u${reset} ${gray}@${reset} ${yellow}\h${reset}"
    PS1+=" ${gray}in${reset} ${blue}\w${reset}"
    PS1+="${git_info}"
    PS1+=" ${gray}[${time}]${reset} \n${gray}\$${reset} "
    #   PS1+=""
    # 额外绑定的动作(可选)
    history -a
}
# 静态 PS1 的刷新局限性,我们使用PROMPT_COMMAND
# PROMPT_COMMAND=__fine_bash_prompt # PROMPT_COMMAND放到~/.bashrc中执行
export PROMPT_COMMAND=__fine_bash_prompt
