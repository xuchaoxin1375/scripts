#!/bin/bash

# 跨平台原地编辑：GNU sed 用 -i；BSD/macOS sed 的 -i 必须带备份后缀（空串表示不留备份）；
# BusyBox sed 用无后缀 -i。识别失败或 -i 不可用时回退到临时文件替换。
_sed_in_place_compat() {
    local expr="$1"
    local file="$2"
    local version
    local tmp
    version="$(sed --version 2>/dev/null || true)"

    if [[ "$version" == *"GNU sed"* ]]; then
        sed -i "$expr" "$file" && return 0
    elif [[ "$version" == *"BusyBox"* || "$version" == *"busybox"* ]]; then
        sed -i "$expr" "$file" && return 0
    else
        # BSD/macOS sed：-i 后必须跟扩展名参数，空字符串表示不保留备份。
        sed -i '' "$expr" "$file" 2>/dev/null && return 0
    fi

    # 回退：不依赖 sed -i，先复制权限，再写入临时文件，最后原子替换。
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    if cp -p "$file" "$tmp" 2>/dev/null && sed "$expr" "$file" >"$tmp"; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        return 1
    fi
}

# 检查bashrc末尾是否为指定内容（定义需要最后执行的代码片段）
update_last_part_bashrc() {
    local mark_last_start='# >>>last_part>>>'
    local mark_last_end='# <<<last_part<<<'
    # shellcheck disable=SC2016
    # local prompt_prefix_broadcast='_PS1_PRE="${PS1%"$_PS1_RAW"}"'
    local code_segment="source \$sh/shell_env_mgr.sh"
    config_last_part=$(
        cat <<-EOF
$mark_last_start
$code_segment
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
        if ! _sed_in_place_compat "\|${mark_last_start}|,\|${mark_last_end}|d" "$BASHRC_FILE"; then
            echo "删除旧 last_part 块失败，未修改 $BASHRC_FILE" >&2
            return 1
        fi

        # 4. 将新内容插入到文件末尾
        echo -e "\n$config_last_part" >>"$BASHRC_FILE"

        echo "The last part of ~/.bashrc was updated successfully. run 'source ~/.bashrc' to take effect"
    fi
}
