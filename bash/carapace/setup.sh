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
CHECK_ONLY=0

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
  -c, --check        只读检查依赖、rc 片段与端到端加载状态，不修改文件
      --status       同 --check
  -h, --help         显示本帮助

说明:
  登录 shell 读 ~/.bash_profile、~/.bash_login 或 ~/.profile，不读 ~/.bashrc；
  非登录 shell 读 ~/.bashrc。先在交互式 shell 执行
  shopt -q login_shell && echo login || echo non-login
  再决定是否加 --login。--login 与 --rc 不能同时使用。

  退出码: 0 正常；1 需要处理；2 参数或环境错误。--check 不修改任何文件。
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
	-c | --check | --status) CHECK_ONLY=1 ;;
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

if [ "$CHECK_ONLY" -eq 1 ] && { [ "$UNINSTALL" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; }; then
	echo "错误: --check 不能与 --uninstall 或 --dry-run 同时使用" >&2
	exit 2
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

if [ "$CHECK_ONLY" -eq 0 ]; then
	if [ -d "$RC_FILE" ]; then
		echo "错误: $RC_FILE 是目录，请用 --rc 指定文件" >&2
		exit 1
	fi

	if [ -L "$RC_FILE" ]; then
		echo "错误: $RC_FILE 是符号链接；为避免替换链接本身，请用 --rc 指向真实文件，或手工编辑目标文件" >&2
		exit 1
	fi
fi

if [ ! -f "$INIT_FILE" ] && [ "$CHECK_ONLY" -eq 0 ]; then
	echo "错误: 找不到 $INIT_FILE" >&2
	exit 1
fi

if [ "$CHECK_ONLY" -eq 0 ] && ! command -v carapace >/dev/null 2>&1; then
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

install_hint() {
	case "${OSTYPE:-}" in
	msys* | cygwin*) printf 'Windows 可执行 scoop install carapace-bin（需 spc bucket）或 Deploy-Carapace -Enable' ;;
	darwin*) printf 'macOS 可执行 brew install carapace' ;;
	*) printf 'Linux 可从官方 Release 安装到 ~/.local/bin，或使用发行版仓库' ;;
	esac
}

block_init_path() {
	awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
        {
            line = $0
            sub(/\r$/, "", line)
        }
        line == begin { inside = 1; next }
        line == end   { inside = 0 }
        inside && match(line, /"[^"]*\.sh"/) {
            print substr(line, RSTART + 1, RLENGTH - 2)
            exit
        }
    ' "$1"
}

check_item() {
	printf '  %-12s : %s\n' "$1" "$2"
}

run_check() {
	local failures=0 rc_installed=0 loaded_any=0
	local candidate block_path carapace_path carapace_ver

	printf 'carapace bash 接入检查（只读）\n'

	if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
		check_item bash "${BASH_VERSION:-unknown}（需要 4+）"
	else
		check_item bash "${BASH_VERSION:-unknown}（需要 4+，当前不满足）"
		failures=$((failures + 1))
	fi

	if carapace_path="$(command -v carapace 2>/dev/null)"; then
		if carapace_ver="$(carapace --version 2>/dev/null)"; then
			check_item carapace "$carapace_path（$carapace_ver）"
		else
			check_item carapace "$carapace_path（--version 执行失败）"
			failures=$((failures + 1))
		fi
	else
		check_item carapace "未在 PATH 中；$(install_hint)"
		failures=$((failures + 1))
	fi

	if command -v xargs >/dev/null 2>&1; then
		check_item xargs "$(command -v xargs)"
	else
		check_item xargs '未找到；bash 补全需要 coreutils'
		failures=$((failures + 1))
	fi

	if [ -f "$INIT_FILE" ]; then
		check_item runtime "$INIT_FILE"
	else
		check_item runtime "$INIT_FILE 不存在"
		failures=$((failures + 1))
	fi

	case "${OSTYPE:-}" in
	msys* | cygwin*) check_item platform "${OSTYPE}（PATH 修正由运行时脚本处理）" ;;
	*) check_item platform "${OSTYPE:-unknown}" ;;
	esac

	if [ -d "$RC_FILE" ]; then
		check_item 'rc target' "$RC_FILE 是目录"
		failures=$((failures + 1))
	elif [ -L "$RC_FILE" ]; then
		check_item 'rc target' "$RC_FILE 是符号链接，setup.sh 会拒绝写入"
		failures=$((failures + 1))
	else
		check_item 'rc target' "$RC_FILE"
	fi

	printf '  rc blocks:\n'
	for candidate in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
		if [ ! -f "$candidate" ]; then
			printf '    %s : 不存在\n' "$candidate"
			continue
		fi
		if ! has_marker "$candidate" "$BEGIN_MARK"; then
			printf '    %s : 未安装\n' "$candidate"
			continue
		fi
		if ! has_marker "$candidate" "$END_MARK"; then
			printf '    %s : 标记不完整（缺结束标记）\n' "$candidate"
			failures=$((failures + 1))
			continue
		fi
		rc_installed=1
		block_path="$(block_init_path "$candidate")"
		if [ -z "$block_path" ]; then
			printf '    %s : 已安装，但未解析出块内路径\n' "$candidate"
			failures=$((failures + 1))
		elif [ ! -f "$block_path" ]; then
			printf '    %s : 已安装，块内路径不存在: %s\n' "$candidate" "$block_path"
			failures=$((failures + 1))
		elif [ "$block_path" != "$INIT_FILE" ]; then
			printf '    %s : 已安装，指向另一份副本: %s\n' "$candidate" "$block_path"
		else
			printf '    %s : 已安装\n' "$candidate"
		fi
	done

	printf '  load test:\n'
	if bash -ic 'declare -F _carapace_completer >/dev/null 2>&1' >/dev/null 2>&1; then
		printf '    %s : 已加载\n' '非登录 shell（读取 ~/.bashrc）'
		loaded_any=1
	else
		printf '    %s : 未加载\n' '非登录 shell（读取 ~/.bashrc）'
	fi
	if bash -lic 'declare -F _carapace_completer >/dev/null 2>&1' >/dev/null 2>&1; then
		printf '    %s : 已加载\n' '登录 shell（读取 ~/.bash_profile 等）'
		loaded_any=1
	else
		printf '    %s : 未加载\n' '登录 shell（读取 ~/.bash_profile 等）'
	fi

	if [ "$failures" -gt 0 ]; then
		printf '结论: 需要处理（见上面标出的依赖或 rc 问题）\n'
		return 1
	fi
	if [ "$rc_installed" -eq 0 ]; then
		printf '结论: 尚未接入 bash\n'
		printf '建议:\n  bash %q --dry-run\n  bash %q\n' "$SCRIPT_DIR/setup.sh" "$SCRIPT_DIR/setup.sh"
		printf '  登录 shell 终端改用 --login；先在实际终端执行 shopt -q login_shell 判断\n'
		return 1
	fi
	if [ "$loaded_any" -eq 0 ]; then
		printf '结论: rc 中已有片段，但两种 shell 类型都未加载\n'
		printf '建议: 检查块内路径与 bash 版本，必要时重新运行 bash %q 刷新片段\n' "$SCRIPT_DIR/setup.sh"
		return 1
	fi
	printf '结论: 已接入 carapace，Tab 补全可用\n'
	return 0
}

if [ "$CHECK_ONLY" -eq 1 ]; then
	if run_check; then
		exit 0
	fi
	exit 1
fi

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
