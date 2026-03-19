#! /bin/bash
__ys_prompt() {
    local exit_code=$?

    # 颜色定义（静态，不变）
    local gray='\[\e[38;5;244m\]'
    local cyan='\[\e[1;36m\]'
    local yellow='\[\e[1;33m\]'
    local red='\[\e[1;31m\]'
    local blue='\[\e[1;34m\]'
    local reset='\[\e[0m\]'

    # 时间 — 用 bash 内建变量替代 $(date) 子进程
    printf -v time '%(%H:%M:%S)T' -1

    # ── Git 信息（优化：最少子进程） ──
    local git_info=""
    local git_dir
    # 一次调用同时拿到 git-dir 和 分支名
    if git_dir=$(git rev-parse --git-dir 2>/dev/null); then

        # 优先从文件系统直接读取分支名（零子进程）
        local branch=""
        local head_file="${git_dir}/HEAD"
        if [[ -f "$head_file" ]]; then
            local head_content
            IFS= read -r head_content < "$head_file"
            if [[ "$head_content" == ref:\ * ]]; then
                # 正常分支: "ref: refs/heads/main"
                branch="${head_content#ref: refs/heads/}"
            else
                # detached HEAD，取前 7 位
                branch="${head_content:0:7}"
            fi
        fi

        # 用一次 git status --porcelain 同时检测 修改 + 未跟踪
        # --porcelain 输出稳定，适合解析
        # -unormal 比默认模式更快（不递归扫描未跟踪目录内部）
        local git_status=""
        local has_modified="" has_untracked=""
        local status_line
        while IFS= read -r status_line; do
            case "${status_line:0:1}" in
                '?') has_untracked=1 ;;
                *)   has_modified=1 ;;
            esac
            # 两个都找到了就提前退出，不再继续读
            [[ -n $has_modified && -n $has_untracked ]] && break
        done < <(git status --porcelain -unormal 2>/dev/null)

        [[ -n $has_modified ]]  && git_status="${red}x${reset}"
        [[ -n $has_untracked ]] && git_status+="${yellow}?${reset}"

        git_info=" ${yellow}on${reset} ${red}git:${branch}${reset}"
        [[ -n $git_status ]] && git_info+=" ${git_status}"
    fi

    # ── 组装 prompt ──
    PS1="\n${gray}# [$(get_os_name)][$(current_shell)]${reset} ${cyan}\u${reset} ${gray}@${reset} ${yellow}\h${reset}"
    PS1+=" ${gray}in${reset} ${blue}\w${reset}"
    PS1+="${git_info}"
    PS1+=" ${gray}[${time}]${reset}"

    # 退出码非零时显示（可选，ys 风格）
    # (( exit_code != 0 )) && PS1+=" ${red}✘ ${exit_code}${reset}"

    PS1+="\n${gray}\$${reset} "

    history -a
}

# export PROMPT_COMMAND=__ys_prompt