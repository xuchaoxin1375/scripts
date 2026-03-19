#! /bin/bash
__fast_ys_prompt() {
    local gray='\[\e[38;5;244m\]'
    local cyan='\[\e[1;36m\]'
    local yellow='\[\e[1;33m\]'
    local red='\[\e[1;31m\]'
    local blue='\[\e[1;34m\]'
    local reset='\[\e[0m\]'

    printf -v time '%(%H:%M:%S)T' -1

    local git_info=""
    local head_file
    # 直接找 .git/HEAD，找不到就用 git rev-parse
    head_file="$(git rev-parse --git-dir 2> /dev/null)/HEAD"
    if [[ -f "$head_file" ]]; then
        local head_content
        IFS= read -r head_content < "$head_file"
        local branch
        if [[ "$head_content" == ref:\ * ]]; then
            branch="${head_content#ref: refs/heads/}"
        else
            branch="${head_content:0:7}"
        fi
        git_info=" ${yellow}on${reset} ${red}git:${branch}${reset}"
    fi

    PS1="\n${gray}# [$(get_os_name)][$(current_shell)]${reset} ${cyan}\u${reset} ${gray}@${reset} ${yellow}\h${reset}"
    PS1+=" ${gray}in${reset} ${blue}\w${reset}"
    PS1+="${git_info}"
    PS1+=" ${gray}[${time}]${reset}"
    PS1+="\n${gray}\$${reset} "

    history -a
}

# export PROMPT_COMMAND=__fast_ys_prompt
