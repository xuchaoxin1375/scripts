#!/usr/bin/env bash
# 安装 / 卸载 carapace 的 bash 接入片段（Git Bash、Cygwin、Linux/WSL 通用）。
# 只改写 rc 文件中的标记块，不修改 carapace 本体。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_FILE="$SCRIPT_DIR/carapace.sh"
RC_FILE="$HOME/.bashrc"
DRY_RUN=0
UNINSTALL=0

BEGIN_MARK="# >>> carapace >>>"
END_MARK="# <<< carapace <<<"

usage() {
	cat <<'EOF'
用法: setup.sh [选项]

选项:
  -u, --uninstall    从 rc 文件移除已安装的片段
      --rc <file>    指定 rc 文件（默认 ~/.bashrc）
      --dry-run      只打印将要写入或移除的内容
  -h, --help         显示本帮助
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	-u | --uninstall) UNINSTALL=1 ;;
	--rc)
		shift
		if [ $# -eq 0 ]; then
			echo "错误: --rc 缺少参数" >&2
			exit 2
		fi
		RC_FILE="$1"
		;;
	--dry-run) DRY_RUN=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "错误: 未知参数 $1" >&2
		usage >&2
		exit 2
		;;
	esac
	shift
done

if [ ! -f "$INIT_FILE" ]; then
	echo "错误: 找不到 $INIT_FILE" >&2
	exit 1
fi

if ! command -v carapace >/dev/null 2>&1; then
	echo "提示: 当前 shell 未找到 carapace；安装后重新打开终端，片段会自动生效" >&2
fi

remove_block() {
	awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
        $0 == begin { skip = 1; next }
        $0 == end   { skip = 0; next }
        !skip
    ' "$1"
}

show_block() {
	awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
        $0 == begin { show = 1 }
        show        { print }
        $0 == end   { show = 0 }
    ' "$1"
}

write_block() {
	printf '\n%s\n' "$BEGIN_MARK"
	printf '# 由 scripts/bash/carapace/setup.sh 维护，删除本标记块即卸载\n'
	printf 'if [ -f "%s" ]; then source "%s"; fi\n' "$INIT_FILE" "$INIT_FILE"
	printf '%s\n' "$END_MARK"
}

if [ ! -f "$RC_FILE" ]; then
	if [ "$DRY_RUN" -eq 1 ]; then
		echo "将创建 $RC_FILE"
	else
		mkdir -p "$(dirname "$RC_FILE")"
		: >"$RC_FILE"
	fi
fi

if [ -f "$RC_FILE" ] && grep -qxF "$BEGIN_MARK" "$RC_FILE" && ! grep -qxF "$END_MARK" "$RC_FILE"; then
	echo "错误: $RC_FILE 中存在 carapace 起始标记但缺少结束标记；请手工修复后再运行" >&2
	exit 1
fi

if [ "$UNINSTALL" -eq 1 ]; then
	if [ ! -f "$RC_FILE" ] || ! grep -qxF "$BEGIN_MARK" "$RC_FILE"; then
		echo "$RC_FILE 中没有 carapace 片段，无需卸载"
		exit 0
	fi
	if [ "$DRY_RUN" -eq 1 ]; then
		echo "[dry-run] 将从 $RC_FILE 移除以下标记块:"
		show_block "$RC_FILE"
		exit 0
	fi
	tmp="$(mktemp "${RC_FILE}.XXXXXX")"
	remove_block "$RC_FILE" >"$tmp"
	mv "$tmp" "$RC_FILE"
	echo "已从 $RC_FILE 移除 carapace 片段"
	exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
	echo "[dry-run] 目标 rc 文件: $RC_FILE"
	echo "[dry-run] 将写入以下标记块:"
	write_block
	exit 0
fi

tmp="$(mktemp "${RC_FILE}.XXXXXX")"
remove_block "$RC_FILE" >"$tmp"
write_block >>"$tmp"
mv "$tmp" "$RC_FILE"

if bash -n "$RC_FILE" 2>/dev/null; then
	echo "已写入 $RC_FILE"
else
	echo "警告: $RC_FILE 语法检查未通过，请检查" >&2
fi
echo "重新打开终端，或执行 source $RC_FILE 生效"
