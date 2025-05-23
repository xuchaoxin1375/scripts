
# === 函数：解压压缩文件 ===
extract_archive() {
    local archive_file="$1"
    local extract_dir="$2"
    
    # 检查目标目录是否已存在
    if [ -d "$extract_dir" ] && [ "$(ls -A "$extract_dir")" ]; then
        echo "⚠️ 警告: 目标目录 $extract_dir 已存在且不为空"
        while true; do
            # read -p "是否覆盖现有目录 $extract_dir? (y/n): " answer
            echo -n "是否覆盖现有目录 $extract_dir? (y/n): "
            read -r answer
            case "$answer" in
                [yY]|[yY][eE][sS])
                    echo "🗑️ 正在清空目录: $extract_dir"
                    rm -rf "${extract_dir}"/*
                    break # 退出循环，继续执行解压
                    ;;
                [nN]|[nN][oO])
                    echo "⏭️ 跳过解压: $archive_file"
                    return 0 # 退出函数，跳过解压
                    ;;
                *)
                    echo "无效输入，请输入 'y' (是) 或 'n' (否)."
                    # 循环将继续，要求用户重新输入
                    ;;
            esac
        done
    fi
    
    # 确保目标目录存在
    mkdir -p "$extract_dir"
    
    if [[ "$archive_file" == *.zip ]]; then
        echo "🔍 正在解压 ZIP 文件: $archive_file"
        # 统一使用7z解压
        if ! 7z x -y "$archive_file" -o"$extract_dir"; then
            echo "❌ 解压 ZIP 文件失败: $archive_file"
            return 1
        fi
    elif [[ "$archive_file" == *.7z ]]; then
        echo "🔍 正在解压 7z 文件: $archive_file"
        # 添加 -bsp1 参数以显示进度
        if ! 7z x -y -bsp1 "$archive_file" -o"$extract_dir"; then
            echo "❌ 解压 7z 文件失败: $archive_file"
            return 1
        fi
    else
        echo "❌ 不支持的压缩文件格式: $archive_file"
        return 1
    fi
    
    return 0
}

# 改进后的交互逻辑
read -p "是否覆盖现有目录? (y/n，默认为n): " answer
answer=${answer:-n}  # 如果用户未输入，默认为 "n"

# 校验用户输入
case "$answer" in
    [yY]|[yY][eE][sS])
        echo "🗑️ 正在清空目录: $extract_dir"
        rm -rf "$extract_dir"/*
        ;;
    [nN]|[nN][oO])
        echo "⏭️ 跳过解压: $archive_file"
        return 0
        ;;
    *)
        echo "❌ 输入无效，请输入 y 或 n。跳过解压: $archive_file"
        return 0
        ;;
esac
