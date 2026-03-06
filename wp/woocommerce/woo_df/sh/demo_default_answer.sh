#!/usr/bin/env bash
set -euo pipefail

# ============ 默认值 ============
ASSUME_ANSWER="" # 留空表示交互模式

# ============ 参数解析 ============
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -y, --yes       对所有询问自动回答 yes
  -n, --no        对所有询问自动回答 no
  -h, --help      显示帮助信息
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        # 核心选项
        -y | --yes)
            ASSUME_ANSWER="y"
            shift
            ;;
        -n | --no)
            ASSUME_ANSWER="n"
            shift
            ;;
        # 其他选项
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "未知选项: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# ============ 核心函数：统一询问 ============
# 用法: confirm "提示信息" [默认值y/n]
# 返回: 0=yes, 1=no
confirm() {
    local prompt="$1"
    local default="${2:-}" # 无命令行覆盖时的默认值(空串)

    # 🔑 如果命令行指定了自动回答，直接返回
    if [[ -n "$ASSUME_ANSWER" ]]; then
        echo "${prompt} → 自动回答: ${ASSUME_ANSWER}"
        [[ "$ASSUME_ANSWER" == "y" ]] && return 0 || return 1
    fi
    # 如果命令行没有指定自动回答,则要求用户交互,交互方式可以定义3类(至少要求输入一个回车)
    # 构造提示符的输入选择部分
    # (对于y,Y表示偏好为自动输入yes(return 0),如果是n,N,偏好是自动输入no(return 1))
    local yn
    case "$default" in
        y | Y) yn="[Y/n]" ;;
        n | N) yn="[y/N]" ;;
        *) yn="[y/n]" ;; # 表示要求用户必须输入可用值
    esac

    # 交互式询问（支持重试）
    while true; do
        read -r -p "${prompt} ${yn}: " answer
        answer="${answer:-$default}" # 用户直接回车则取默认值
        case "${answer,,}" in        # ${,,} 转小写 (bash 4+)
            y | yes) return 0 ;;
            n | no) return 1 ;;
            *) echo "请输入 y 或 n" ;;
        esac
    done
}

# ============ 使用示例 ============
echo "=== 部署脚本开始 ==="

if confirm "是否更新系统软件包?" "y"; then
    echo "→ 执行: apt update && apt upgrade"
    # apt update && apt upgrade -y
else
    echo "→ 跳过系统更新"
fi

if confirm "是否安装 Docker?" "n"; then
    echo "→ 执行: 安装 Docker"
else
    echo "→ 跳过 Docker 安装"
fi

if confirm "是否清理临时文件?" "y"; then
    echo "→ 执行: 清理临时文件"
else
    echo "→ 跳过清理"
fi

echo "=== 部署完成 ==="
