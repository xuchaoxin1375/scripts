#! /bin/bash
PS1="" #清空原始的prompt值
# _PS1_RAW="[${PS1}]"
# _PS1_PRE="${PS1%"$_PS1_RAW"}"
# log "===debug: PS1: ${PS1}->[${PS1@P}]"
# echo "===debug: _PS1_RAW: $_PS1_RAW"
# log "===debug: _PS1_RRE: $_PS1_PRE"
# 修改后的 prompt_switcher
prompt_switcher() {
    local prompt_file="$sh/bash_prompts/${BASH_PROMPT}.sh"
    local gray='\[\e[38;5;244m\]'
    local reset='\[\e[0m\]'
    if [[ -f "$prompt_file" ]]; then
        # 仅加载当前需要的那个脚本
        # shellcheck source=/dev/null
        source "$prompt_file"

        # 调用对应的函数(引入__PS1__这部分自定义的prompt片段)
        case "$BASH_PROMPT" in
            "fast_ys") __fast_ys_prompt ;;
            "fast_junkfood") __fast_junkfood_prompt ;;
            "ys") __ys_prompt ;;
            *) echo "warning: function mapping missing for $BASH_PROMPT" >&2 ;;
        esac
        # 配置conda等可能更改prompt的环境变量的部分(可以对比oh my zsh中prompt的效果再按需修改)
        # wsl环境
        grep 'wsl' -iq /proc/version && _IS_WSL=1
        # python venv环境
        _PY_VENV_NAME="${VIRTUAL_ENV##*/}"
        [[ $_PY_VENV_NAME ]] && _PY_VENV_NAME="(${_PY_VENV_NAME})"
        # nodejs环境
        NODE_VERSION=$(check_dependency -q node && node -v 2> /dev/null)
        [[ $NODE_VERSION ]] && NODE_VERSION="(node:${NODE_VERSION})"
        # 环境提示符合并
        _ENV_PROMPT="${CONDA_PROMPT_MODIFIER}${_PY_VENV_NAME}${NODE_VERSION}${KUBECONFIG}"
        # 定义共同前缀
        _COMMOM_PROMPT_PREFIX="${gray}${_ENV_PROMPT}[${_IS_WSL:+wsl}][$(get_os_name -o)][$(current_shell)]${reset}"
        # _PS1_PRE 会在conda等对PS1进行修改后将增加的前缀(例如base)传播回来
        PS1="# ${_PS1_PRE}${_COMMOM_PROMPT_PREFIX}${__PS1__}"
        # echo  "===debug on PROMPT_COMMAND: PS1: <<${PS1}->[${PS1@P}]>>"
    else
        echo "warning: unknown prompt configuration [$BASH_PROMPT]" >&2
    fi
}
# 设置每次返回shell提示符时要执行的逻辑(比如更改prompt,或者其他动作)
PROMPT_COMMAND=prompt_switcher
# 注意,PROMPT_COMMAND不会再被赋值的时候立即执行!和直接调用被赋值函数不同!
# prompt_switcher
# echo "<<${PS1@P}>>"
