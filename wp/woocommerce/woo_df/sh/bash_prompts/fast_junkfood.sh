#!/bin/bash
# fast-junkfood: faithful junkfood port for bash

# ============================================================
# Git 信息获取（prompt 中 $() 不一定调用）
# ============================================================

__git_prompt_info() {
    # 纯 bash 向上查找 .git，零 fork
    local dir="$PWD"
    while [[ -n "$dir" ]]; do
        [[ -d "$dir/.git" || -f "$dir/.git" ]] && break
        dir="${dir%/*}"
    done
    [[ -z "$dir" && ! -d "/.git" ]] && return

    # 直接读 .git/HEAD 获取分支名，零 fork
    local git_dir="$dir/.git"
    if [[ -f "$git_dir" ]]; then
        local line
        read -r line < "$git_dir"
        git_dir="${line#gitdir: }"
        [[ "$git_dir" != /* ]] && git_dir="$dir/$git_dir"
    fi

    local head_file="$git_dir/HEAD"
    [[ -f "$head_file" ]] || return

    local head
    read -r head < "$head_file"
    local branch
    if [[ "$head" == ref:\ * ]]; then
        branch="${head#ref: refs/heads/}"
    else
        branch="${head:0:7}"
    fi

    echo -n "@${branch}"
}

__git_prompt_dirty() {
    # 这是唯一需要 fork git 的地方
    local dir="$PWD"
    while [[ -n "$dir" ]]; do
        [[ -d "$dir/.git" || -f "$dir/.git" ]] && break
        dir="${dir%/*}"
    done
    [[ -z "$dir" && ! -d "/.git" ]] && return

    # 一次 git status 搞定
    local porcelain
    porcelain=$(git -C "$dir" status --porcelain=v1 2> /dev/null | head -1)

    if [[ -n "$porcelain" ]]; then
        echo -n "✗✗✗"
    else
        echo -n "✔"
    fi
}
__fast_junkfood_prompt() {

    # ============================================================
    #  静态 PS1 定义（和 junkfood 一样，一次性组装）
    # ============================================================
    # 颜色
    __C_RED='\[\e[1;31m\]'
    __C_WHITE='\[\e[1;37m\]'
    __C_YELLOW='\[\e[1;33m\]'
    __C_BLUE='\[\e[1;34m\]'
    __C_GREEN='\[\e[1;32m\]'
    __C_CYAN='\[\e[0;36m\]'
    __C_RESET='\[\e[0m\]'

    # 对应 junkfood 的各段
    # #( 日期@时间 )( user@machine ): 路径@分支 dirty/clean
    # prefix="${__C_RED}# [$(get_os_name)][$(current_shell)]"
    JUNKFOOD_TIME_="${__C_WHITE}( ${__C_YELLOW}\D{%m/%d/%Y}${__C_RESET}@${__C_WHITE}\t ${__C_WHITE})( ${__C_RESET}"
    JUNKFOOD_CURRENT_USER_="${__C_GREEN}\u${__C_RESET}"
    JUNKFOOD_MACHINE_="${__C_BLUE}\h${__C_WHITE} ):${__C_RESET}"
    # # \$(__git_prompt_info) 和 \$(__git_prompt_dirty) 在 PS1 中延迟求值
    # JUNKFOOD_LOCA_="${__C_CYAN}\w${__C_WHITE}\$(__git_prompt_info)${__C_WHITE}\$(__git_prompt_dirty)${__C_RESET}"
    JUNKFOOD_LOCA_="${__C_CYAN}\w${__C_WHITE}"

    # 组装(定义字段顺序)
    __PS1__="${JUNKFOOD_TIME_}${JUNKFOOD_CURRENT_USER_}@${JUNKFOOD_MACHINE_}${JUNKFOOD_LOCA_}
\$ "

    # history 实时写入
    history -a
    # PROMPT_COMMAND="history -a"
}
export __PS1__
