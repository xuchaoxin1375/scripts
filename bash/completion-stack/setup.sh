#!/usr/bin/env bash
# 一键组合部署 bash 参数补全：argc-completions 补 carapace 缺失的命令，
# carapace 负责两者重叠的命令（git、docker 等）。
# 只做编排：二进制安装与 rc 标记块仍由同仓库两个 setup.sh 完成。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARGC_SETUP="$BASH_DIR/argc-completions/setup.sh"
CARAPACE_SETUP="$BASH_DIR/carapace/setup.sh"

DRY_RUN=0
UNINSTALL=0
CHECK_ONLY=0
INSTALL_CARAPACE=0
SKIP_ARGC=0
SKIP_CARAPACE=0
USE_LOGIN_RC=0
RC_FILE=''
RC_FILE_EXPLICIT=0
ARGC_DIR=''

BEGIN_MARK="# >>> argc-completions >>>"
CARAPACE_MARK="# >>> carapace >>>"

usage() {
	cat <<'EOF'
用法: setup.sh [选项]

组合顺序固定为 argc 在前、carapace 在后：重叠命令由 carapace 接管，
只有 argc 有的命令（如 nginx）保留 argc 的补全。

选项:
  -n, --dry-run          只打印两个 setup.sh 将执行的动作
  -c, --check            只读检查：carapace 状态 + argc 片段与加载状态
  -d, --disable          停用：移除两个 rc 标记块，保留二进制与克隆目录
  -u, --uninstall        同 --disable，历史名称
  -l, --login            写入登录 shell 实际读取的 rc
  -r, --rc <file>        指定 rc 文件（默认 ~/.bashrc，与 --login 互斥）
      --argc-dir <dir>   argc-completions 克隆目录（默认 $ARGC_COMPLETIONS_DIR
                         或自动探测 ~/argc-completions 等）
      --install-carapace 顺带调用 carapace/setup.sh --install 安装二进制
      --skip-argc        不接入 argc（只用 carapace）
      --skip-carapace    不接入 carapace（只用 argc）
  -h, --help             显示本帮助

退出码: 0 正常；1 需要处理；2 参数错误。
EOF
}

if ((BASH_VERSINFO[0] < 4)); then
	echo '错误: 需要 bash 4 及以上（carapace 同样要求）' >&2
	exit 1
fi

while [ $# -gt 0 ]; do
	case "$1" in
	-n | --dry-run) DRY_RUN=1 ;;
	-c | --check | --status) CHECK_ONLY=1 ;;
	-d | --disable | -u | --uninstall) UNINSTALL=1 ;;
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
	--argc-dir)
		shift
		if [ $# -eq 0 ]; then
			echo "错误: --argc-dir 缺少参数" >&2
			exit 2
		fi
		ARGC_DIR="$1"
		;;
	--install-carapace) INSTALL_CARAPACE=1 ;;
	--skip-argc) SKIP_ARGC=1 ;;
	--skip-carapace) SKIP_CARAPACE=1 ;;
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

if [ "$USE_LOGIN_RC" -eq 1 ] && [ "$RC_FILE_EXPLICIT" -eq 1 ]; then
	echo "错误: --login 与 --rc 不能同时使用" >&2
	exit 2
fi
if [ "$SKIP_ARGC" -eq 1 ] && [ "$SKIP_CARAPACE" -eq 1 ]; then
	echo "错误: --skip-argc 与 --skip-carapace 不能同时使用" >&2
	exit 2
fi
if [ "$CHECK_ONLY" -eq 1 ] && { [ "$UNINSTALL" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; }; then
	echo "错误: --check 不能与 --disable/--uninstall、--dry-run 同时使用" >&2
	exit 2
fi
for script in "$ARGC_SETUP" "$CARAPACE_SETUP"; do
	if [ ! -f "$script" ]; then
		echo "错误: 找不到 $script" >&2
		exit 1
	fi
done

login_rc_file() {
	for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
		if [ -f "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	printf '%s\n' "$HOME/.bash_profile"
}

target_rc() {
	if [ -n "$RC_FILE" ]; then
		printf '%s\n' "$RC_FILE"
	elif [ "$USE_LOGIN_RC" -eq 1 ]; then
		login_rc_file
	else
		printf '%s\n' "$HOME/.bashrc"
	fi
}

resolve_argc_dir() {
	if [ -n "$ARGC_DIR" ]; then
		printf '%s\n' "$ARGC_DIR"
		return 0
	fi
	if [ -n "${ARGC_COMPLETIONS_DIR:-}" ]; then
		printf '%s\n' "$ARGC_COMPLETIONS_DIR"
		return 0
	fi
	for candidate in "$HOME/argc-completions" /c/repos/argc-completions /mnt/c/repos/argc-completions; do
		if [ -d "$candidate/completions" ] && [ -d "$candidate/bin" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

probe_loaded() {
	local flag="$1" out
	out="$(bash "$flag" 'type _argc_completer >/dev/null 2>&1 && echo loaded=1 || echo loaded=0' 2>/dev/null || true)"
	case "$out" in
	*loaded=1*) return 0 ;;
	*) return 1 ;;
	esac
}

run_check() {
	local rc failures=0
	rc="$(target_rc)"
	echo '组合检查（只读）'
	if [ "$SKIP_CARAPACE" -eq 0 ]; then
		if bash "$CARAPACE_SETUP" --check; then
			echo '  carapace : 已接入'
		else
			echo '  carapace : 需要处理'
			failures=$((failures + 1))
		fi
	fi
	if [ "$SKIP_ARGC" -eq 0 ]; then
		if [ -f "$rc" ] && grep -qxF "$BEGIN_MARK" "$rc"; then
			echo "  argc     : rc 中已有片段（$rc）"
		else
			echo "  argc     : rc 中未安装（$rc）"
			failures=$((failures + 1))
		fi
		if probe_loaded -ic || probe_loaded -lc; then
			echo '  argc     : 实际已加载'
		else
			echo '  argc     : 两种 shell 均未加载'
			failures=$((failures + 1))
		fi
	fi
	if [ "$failures" -gt 0 ]; then
		echo '结论: 需要处理（见上面各项）'
		return 1
	fi
	echo '结论: 组合补全已可用'
	return 0
}

if [ "$CHECK_ONLY" -eq 1 ]; then
	run_check
	exit $?
fi

rc_opts=()
if [ -n "$RC_FILE" ]; then
	rc_opts=(--rc "$RC_FILE")
elif [ "$USE_LOGIN_RC" -eq 1 ]; then
	rc_opts=(--login)
fi

dry_opts=()
if [ "$DRY_RUN" -eq 1 ]; then
	dry_opts=(--dry-run)
fi

if [ "$UNINSTALL" -eq 1 ]; then
	if [ "$SKIP_CARAPACE" -eq 0 ]; then
		bash "$CARAPACE_SETUP" --disable "${rc_opts[@]}" "${dry_opts[@]}"
	fi
	if [ "$SKIP_ARGC" -eq 0 ]; then
		bash "$ARGC_SETUP" --disable "${rc_opts[@]}" "${dry_opts[@]}"
	fi
	exit 0
fi

if [ "$SKIP_ARGC" -eq 0 ]; then
	if ! ARGC_DIR="$(resolve_argc_dir)"; then
		echo "错误: 未找到 argc-completions 克隆目录；用 --argc-dir 指定，或先克隆：" >&2
		echo "  git clone https://github.com/sigoden/argc-completions.git ~/argc-completions" >&2
		echo "  或加 --skip-argc 只用 carapace" >&2
		exit 1
	fi
	echo "argc-completions 目录: $ARGC_DIR"
fi

if [ "$SKIP_ARGC" -eq 0 ]; then
	echo ''
	echo '== argc-completions（先加载，补 carapace 缺失的命令） =='
	bash "$ARGC_SETUP" --argc-dir "$ARGC_DIR" "${rc_opts[@]}" "${dry_opts[@]}"
fi

if [ "$SKIP_CARAPACE" -eq 0 ]; then
	rc="$(target_rc)"
	install_opts=()
	if [ "$INSTALL_CARAPACE" -eq 1 ]; then
		install_opts=(--install)
	fi
	if [ -f "$rc" ] && grep -qxF "$CARAPACE_MARK" "$rc" && [ "$INSTALL_CARAPACE" -eq 0 ]; then
		echo ''
		echo "== carapace（rc 中已有片段，跳过：$rc） =="
	else
		echo ''
		echo '== carapace（后加载，接管重叠命令） =='
		bash "$CARAPACE_SETUP" "${install_opts[@]}" "${rc_opts[@]}" "${dry_opts[@]}"
	fi
fi

echo ''
echo '完成。验证：'
echo "  bash -ic 'complete -p git; complete -p nginx'"
echo '  bash -ic "bind -p | grep C-i"'
echo '新开终端，或 source 对应 rc 后生效。'
