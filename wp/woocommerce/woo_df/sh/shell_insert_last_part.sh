#!/bin/bash
update_last_part_bashrc() {
    local mark_last_start='# >>>last_part>>>'
    local mark_last_end='# <<<last_part<<<'
    # shellcheck disable=SC2016
    # local prompt_prefix_broadcast='_PS1_PRE="${PS1%"$_PS1_RAW"}"'
    local prompt_prefix_broadcast='source /www/sh/shell_env_mgr.sh'
    config_last_part=$(
        cat <<- EOF
$mark_last_start
# 回传(广播)prompt前缀到前面的PROMPT_COMMAND
$prompt_prefix_broadcast
$mark_last_end
EOF

    )
    # 判断 $mark_last_end 是否为.bashrc的最后一行非空行,如果是则不处理,否则删除$mark_last_start到$mark_last_end之间的内容,然后config_last_part插入到.bashrc的末尾
    # 1. 获取文件最后一行非空行的内容
    # 使用 sed计算删除所有空白行后取最后一行(但这里sed不会实际修改源文件,仅在内存中计算),就得到原配置文件中的最后一行非空行
    last_non_empty_line=$(sed '/^[[:space:]]*$/d' "$BASHRC_FILE" | tail -n 1)

    # 2. 判断逻辑
    if [ "$last_non_empty_line" == "$mark_last_end" ]; then
        echo "[$mark_last_end] already exists in .bashrc, skipping insertion..."
    else
        echo "Updating the last part of ~/.bashrc ..."

        # 3. 删除从 $mark_last_start 到 $mark_last_end 的所有行
        # 使用 \ 来转义变量中可能存在的特殊字符（如果变量包含 /，建议改用 | 作为定界符）
        sed -i "\|${mark_last_start}|,\|${mark_last_end}|d" "$BASHRC_FILE"

        # 4. 将新内容插入到文件末尾
        echo -e "\n$config_last_part" >> "$BASHRC_FILE"

        echo "The last part of ~./bashrc was updated successfully. run 'source ~/.bashrc' to take effect"
    fi
}
