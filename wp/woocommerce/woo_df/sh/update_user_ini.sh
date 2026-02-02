#!/bin/bash
#######################################
# 检查并确保指定的 .user.ini 包含 $VALUE 共享目录。
# 逻辑：
#   1. 解锁文件 i 属性。
#   2. 检查 open_basedir 是否已包含 $VALUE。
#   3. 如果不包含，则在末尾追加；如果包含，则跳过。
#   4. 重新锁定 i 属性。
# Arguments:
#   1 - .user.ini 文件的绝对路径 (string)
# Outputs:
#   执行过程的状态信息写入 STDOUT。

#######################################

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]

选项:
  -p <file_path>          指定具体的 .user.ini 文件路径进行修改。
  -t <open_dir_value>     指定需要检查和添加到 open_basedir 的值。
  -d <dir_path>           指定搜索目录，扫描该目录下的所有 .user.ini。
  -m <max_depth>          指定搜索目录的深度 (配合 -d 使用，默认为 2)。
  -h                      显示帮助信息。

示例:
  $(basename "$0") -p /www/wwwroot/example.com/.user.ini
  $(basename "$0") -p archives/.user.tpl.ini -t /www/wp_plugins
  $(basename "$0") -d /www/wwwroot -m 4
EOF
  exit 1
}
FILE=""
# TODO 支持多个工作目录.
WORK_DIR="/www/wwwroot/"
MAX_DEPTH=4
VALUE='/www/'
# 解析命令行参数
while getopts "p:t:d:m:h" opt; do
  case "$opt" in
  p) FILE="$OPTARG" ;;
  t) VALUE="$OPTARG" ;;
  d) WORK_DIR="$OPTARG" ;;
  m) MAX_DEPTH="$OPTARG" ;;
  h) usage ;;
  *) usage ;;
  esac
done
update_open_basedir() {
  local file_path="$1"

  if [[ ! -f "$file_path" ]]; then
    echo "错误: 文件 $file_path 不存在。" >&2
    return 1
  fi

  # 1. 解锁 (宝塔环境特有属性)
  chattr -i "$file_path" 2>/dev/null || true

  # 2. 判断并修改
  if ! grep -qE "$VALUE$|$VALUE:" "$file_path"; then
    echo "更新中: $file_path"
    # 在 open_basedir 行尾追加 :$VALUE
    # sed -i '/^open_basedir/ s|$|:/www/\n|' "$file_path"
    sed -i '/^open_basedir/ s|$|:'"$VALUE\n|" "$file_path"
    # 清理可能产生的双冒号
    sed -i 's|::|:|g' "$file_path"
  else
    echo "跳过: $file_path (已包含路径 $VALUE)"
  fi

  # 3. 重新锁定
  chattr +i "$file_path" 2>/dev/null || true
}

#######################################
# 脚本主逻辑入口
#######################################
main() {

  # 逻辑判断
  if [[ -n "$FILE" ]]; then
    # 模式 1: 处理单个文件
    update_open_basedir "$FILE"
  elif [[ -n "$WORK_DIR" ]]; then
    # 模式 2: 扫描目录
    if [[ ! -d "$WORK_DIR" ]]; then
      echo "错误: 目录 $WORK_DIR 不存在。" >&2
      exit 1
    fi
    echo "开始扫描目录: $WORK_DIR (深度: $MAX_DEPTH)"

    # 使用 find 查找所有 .user.ini 文件
    # -maxdepth 控制深度，避免扫描过深导致性能问题
    find "$WORK_DIR" -maxdepth "$MAX_DEPTH" -name ".user.ini" | while read -r ini_file; do
      update_open_basedir "$ini_file"
    done
  else
    usage
  fi

  echo "任务完成。"
}

# 启动脚本
main "$@"
