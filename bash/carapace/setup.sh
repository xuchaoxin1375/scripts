#!/usr/bin/env bash
# 安装 / 卸载 carapace 的 bash 接入片段（Git Bash、Cygwin、Linux/WSL、macOS bash 通用）。
# 只改写 rc 文件中的标记块，不修改 carapace 本体。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_FILE="$SCRIPT_DIR/carapace.sh"
RC_FILE="$HOME/.bashrc"
RC_FILE_EXPLICIT=0
USE_LOGIN_RC=0
DRY_RUN=0
UNINSTALL=0

BEGIN_MARK="# >>> carapace >>>"
END_MARK="# <<< carapace <<<"

usage() {
	cat <<'EOF'
用法: setup.sh [选项]

选项:
  -n, --dry-run      只打印将要写入或移除的内容，不修改文件
  -l, --login        写入登录 shell 实际读取的 rc 文件
  -r, --rc <file>    指定 rc 文件（默认 ~/.bashrc）
  -u, --uninstall    从 rc 文件移除已安装的片段
  -h, --help         显示本帮助

说明:
  登录 shell 读 ~/.bash_profile、~/.bash_login 或 ~/.profile，不读 ~/.bashrc；
  非登录 shell 读 ~/.bashrc。先在交互式 shell 执行
  shopt -q login_shell && echo login || echo non-login
  再决定是否加 --login。--login 与 --rc 不能同时使用。
EOF
}

login_rc_file() {
	for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
		if [ -f "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	printf '%s\n' "$HOME/.bash_profile"
}

warn_login_shell_rc() {
	[ "$RC_FILE" = "$HOME/.bashrc" ] || return 0
	for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
		[ -f "$candidate" ] || continue
		if grep -Eq '(^|[[:space:]])(source|\.)[[:space:]]+.*\.bashrc' "$candidate"; then
			return 0
		fi
	done
	printf '提示: 登录 shell（macOS Terminal、Git Bash 常见）读取 ~/.bash_profile/~/.bash_login/~/.profile，而不是 ~/.bashrc。\n' >&2
	printf '      如果当前终端是登录 shell，请改用 bash setup.sh --login，或在登录 rc 中加 source ~/.bashrc。\n' >&2
}

while [ $# -gt 0 ]; do
	case "$1" in
	-n | --dry-run) DRY_RUN=1 ;;
	-l | --login) USE_LOGIN_RC=1 ;;
	-r | --rc)
		shift
		if [ $# -eq 0 ]; then
			echo "错误: --rc 缺少参数" >&2
			exit 2
		fi
		RC_FILE="$1"
		RC_FILE_EXPLICIT=1
		;;
	-u | --uninstall) UNINSTALL=1 ;;
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

if [ "$USE_LOGIN_RC" -eq 1 ]; then
	if [ "$RC_FILE_EXPLICIT" -eq 1 ]; then
		echo "错误: --login 与 --rc 不能同时使用" >&2
		exit 2
	fi
	RC_FILE="$(login_rc_file)"
fi

# 允许 --rc '~/.bashrc' 这种带引号、未由 shell 展开的写法
# shellcheck disable=SC2088
case "$RC_FILE" in
"~") RC_FILE="$HOME" ;;
"~/"*) RC_FILE="$HOME/${RC_FILE#\~/}" ;;
esac

if [ -z "$RC_FILE" ]; then
	echo "错误: --rc 不能为空" >&2
	exit 2
fi

if [ -d "$RC_FILE" ]; then
	echo "错误: $RC_FILE 是目录，请用 --rc 指定文件" >&2
	exit 1
fi

if [ -L "$RC_FILE" ]; then
	echo "错误: $RC_FILE 是符号链接；为避免替换链接本身，请用 --rc 指向真实文件，或手工编辑目标文件" >&2
	exit 1
fi

if [ ! -f "$INIT_FILE" ]; then
	echo "错误: 找不到 $INIT_FILE" >&2
	exit 1
fi

if ! command -v carapace >/dev/null 2>&1; then
	echo "提示: 当前 shell 未找到 carapace；安装后重新打开终端，片段会自动生效" >&2
fi

has_marker() {
	awk -v mark="$2" '
        {
            line = $0
            sub(/\r$/, "", line)
        }
        line == mark { found = 1; exit }
        END { exit(found ? 0 : 1) }
    ' "$1"
}

remove_block() {
	awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
        {
            line = $0
            sub(/\r$/, "", line)
        }
        line == begin { skip = 1; next }
        line == end   { skip = 0; next }
        !skip
    ' "$1"
}

show_block() {
	awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
        {
            line = $0
            sub(/\r$/, "", line)
        }
        line == begin { show = 1 }
        show          { print }
        line == end   { show = 0 }
    ' "$1"
}

write_block() {
	printf '\n%s\n' "$BEGIN_MARK"
	printf '# 由 scripts/bash/carapace/setup.sh 维护，删除本标记块即卸载\n'
	# shellcheck disable=SC2016
	printf 'if [ -n "${BASH_VERSION:-}" ] && [ -f "%s" ]; then . "%s"; fi\n' "$INIT_FILE" "$INIT_FILE"
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

if [ -f "$RC_FILE" ] && has_marker "$RC_FILE" "$BEGIN_MARK" && ! has_marker "$RC_FILE" "$END_MARK"; then
	echo "错误: $RC_FILE 中存在 carapace 起始标记但缺少结束标记；请手工修复后再运行" >&2
	exit 1
fi

if [ "$UNINSTALL" -eq 1 ]; then
	if [ ! -f "$RC_FILE" ] || ! has_marker "$RC_FILE" "$BEGIN_MARK"; then
		echo "$RC_FILE 中没有 carapace 片段，无需卸载"
		if [ "$USE_LOGIN_RC" -eq 0 ] && [ "$RC_FILE_EXPLICIT" -eq 0 ]; then
			login_rc="$(login_rc_file)"
			if [ -f "$login_rc" ] && has_marker "$login_rc" "$BEGIN_MARK"; then
				echo "提示: $login_rc 中有 carapace 片段；如果是登录 shell 安装，请加 --login 卸载" >&2
			fi
		fi
		exit 0
	fi
	if [ "$DRY_RUN" -eq 1 ]; then
		echo "[dry-run] 将从 $RC_FILE 移除以下标记块:"
		show_block "$RC_FILE"
		exit 0
	fi
	tmp="$(mktemp "${RC_FILE}.XXXXXX")"
	cp -p "$RC_FILE" "$tmp"
	remove_block "$RC_FILE" >"$tmp"
	mv "$tmp" "$RC_FILE"
	echo "已从 $RC_FILE 移除 carapace 片段"
	exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
	echo "[dry-run] 目标 rc 文件: $RC_FILE"
	echo "[dry-run] 将写入以下标记块:"
	write_block
	warn_login_shell_rc
	exit 0
fi

tmp="$(mktemp "${RC_FILE}.XXXXXX")"
cp -p "$RC_FILE" "$tmp"
remove_block "$RC_FILE" >"$tmp"
write_block >>"$tmp"
mv "$tmp" "$RC_FILE"

if bash -n "$RC_FILE" 2>/dev/null; then
	echo "已写入 $RC_FILE"
else
	echo "警告: $RC_FILE 语法检查未通过，请检查" >&2
fi
warn_login_shell_rc
echo "重新打开终端，或执行 source $RC_FILE 生效"
