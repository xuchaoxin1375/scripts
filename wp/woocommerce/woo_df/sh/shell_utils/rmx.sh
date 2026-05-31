#! /usr/bin/env bash
# 强力删除:能够将标志位是i的文件(目录)更改为可删除,然后删除掉指定目标
# 这是一个简化版本(使用rm1或rm2更可靠)
# 用法: rmx <目标文件或目录>
rmx() {
    if [ $# -eq 0 ]; then
        echo "用法: rmx <目标文件或目录>"
        return 1
    fi
    for target in "$@"; do
        if [ -e "$target" ]; then
            echo "[INFO] 尝试去除 $target 的 i 标志..."
            sudo chattr -R -ia "$target"
            echo "[INFO] 强力删除 $target ..."
            sudo rm -rf "$target"
        else
            echo "[WARN] 目标不存在: $target"
        fi
    done
    return 0
}
#######################################
# 强力删除指定的文件或目录。
# 该函数会尝试移除文件的不可修改属性 (immutable) 和权限限制，
# 然后执行强制递归删除。
# Arguments:
#   待删除的文件或目录路径（支持多个参数）。
# Returns:
#   0 如果所有目标都被成功删除。
#   1 如果未提供参数或删除失败。
#######################################
rm1() {
    # 检查是否输入了参数
    if [[ $# -eq 0 ]]; then
        echo "Error: No arguments provided." >&2
        echo "Usage: rm1 <path> [path...]" >&2
        return 1
    fi

    local exit_code=0
    # 为了支持同时处理多个文件/目录,使用循环遍历此函数的所有参数
    for target in "$@"; do
        # 删除前判断目标是否存在(文件/目录/符号链接等)
        if [[ -e "$target" ]]; then
            echo "Force removing: $target"

            # 1. 移除特殊属性 (-i 不可修改, -a 仅追加)
            # 使用 sudo 确保有权修改属性
            sudo chattr -R -ia "$target" 2> /dev/null

            # 2. 修改权限，确保 root 拥有完全控制权
            sudo chmod -R 777 "$target" 2> /dev/null

            # 3. 递归强制删除
            sudo rm -rf "$target"

            # 检查结果
            if [[ -e "$target" ]]; then
                echo "FAILED: $target still exists." >&2
                exit_code=1
            else
                echo "SUCCESS: $target has been removed."
            fi
        else
            echo "Skip: $target does not exist."
        fi
    done

    return $exit_code
}

rm2() {
    # 强力删除文件或目录（移除 immutable 属性后删除）
    # 用法: rm2 [-f] <目标文件或目录>...
    #   -f: 跳过确认提示

    local force=false
    local errors=0

    # 解析选项
    if [[ "$1" == "-f" ]]; then
        force=true
        shift
    fi

    if [[ $# -eq 0 ]]; then
        echo "用法: rmx [-f] <目标文件或目录>..." >&2
        return 1
    fi

    for target in "$@"; do
        # 检查存在性（包括断开的符号链接）
        if [[ ! -e "$target" && ! -L "$target" ]]; then
            echo "[WARN] 目标不存在: $target" >&2
            ((errors++))
            continue
        fi

        # 安全确认（除非 -f）
        if [[ "$force" != true ]]; then
            read -r -p "[WARN] 确定要强制删除 '$target'? [y/N] " confirm
            [[ "$confirm" != [yY] ]] && continue
        fi

        echo "[INFO] 处理: $target"

        # 移除 immutable 属性（根据类型选择是否递归）
        if [[ -d "$target" ]]; then
            sudo chattr -R -i -- "$target" 2> /dev/null
        else
            sudo chattr -i -- "$target" 2> /dev/null
        fi
        # 注意: 非 ext 文件系统会失败，忽略错误

        # 执行删除
        if sudo rm -rf -- "$target"; then
            echo "[OK] 已删除: $target"
        else
            echo "[ERROR] 删除失败: $target" >&2
            ((errors++))
        fi
    done

    return $((errors > 0 ? 1 : 0))
}
