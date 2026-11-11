#!/usr/bin/env bash
# 诊断当前交互式 bash 会话的补全来源与 rc 新鲜度。
# 用法：source <仓库路径>/bash/completion-diagnose.sh
# 只读：不修改 rc、不注册或注销补全、不改变当前选项。
# 必须以 source 运行：执行的子进程看不到当前 shell 内存里的 complete 注册。

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	printf '请用 source 运行：source %s\n' "${BASH_SOURCE[0]}" >&2
	exit 1
fi

_cxdiag_print() { printf '[completion] %s\n' "$*"; }

_cxdiag_registration() { complete -p "$1" 2>/dev/null || true; }

_cxdiag_mtime() {
	if [ -f "$1" ]; then
		stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'
	else
		printf '0'
	fi
}

_cxdiag_main() {
	local now shell_start login_rc user_rc rc_path rc_mtime stale=0 rc_order git_line fn cmd

	now=$(date +%s)
	shell_start=$((now - SECONDS))
	_cxdiag_print "bash ${BASH_VERSION:-unknown}, OSTYPE=${OSTYPE:-unknown}, 已运行 ${SECONDS}s"
	case "${OSTYPE:-}" in
	msys* | cygwin*) _cxdiag_print '宿主: Git Bash / MSYS（mintty 不是控制台，窗口级验证用 bin\bash.exe）' ;;
	esac

	login_rc="$HOME/.bash_profile"
	[ -f "$login_rc" ] || login_rc="$HOME/.bash_login"
	[ -f "$login_rc" ] || login_rc="$HOME/.profile"
	user_rc="$HOME/.bashrc"
	for rc_path in "$user_rc" "$login_rc"; do
		[ -f "$rc_path" ] || continue
		rc_mtime=$(_cxdiag_mtime "$rc_path")
		if [ "$rc_mtime" -gt $((shell_start + 2)) ]; then
			_cxdiag_print "$rc_path 在本次 shell 启动后修改过：当前会话仍是旧注册"
			stale=1
		fi
	done

	if [ -f "$user_rc" ]; then
		rc_order=$(grep -n -e '>>> argc-completions >>>' -e '>>> carapace >>>' "$user_rc" 2>/dev/null | tr '\n' ' ' || true)
		[ -n "$rc_order" ] && _cxdiag_print "用户 rc 块顺序（行号）: $rc_order"
	fi

	for cmd in git gitk nginx; do
		git_line=$(_cxdiag_registration "$cmd")
		if [ -n "$git_line" ]; then
			_cxdiag_print "$cmd -> $git_line"
		else
			_cxdiag_print "$cmd -> 未注册（补全框架没有接管）"
		fi
	done

	for fn in _carapace_completer_ble _carapace_completer _argc_completer; do
		if declare -F "$fn" >/dev/null 2>&1; then
			_cxdiag_print "函数 $fn: 已定义"
		else
			_cxdiag_print "函数 $fn: 未定义"
		fi
	done

	_cxdiag_print "CARAPACE_EXCLUDES=${CARAPACE_EXCLUDES:-<空>} ARGC_COMPLETIONS_ONLY=${ARGC_COMPLETIONS_ONLY:-<空>}"
	case $- in
	*i*)
		_cxdiag_print "Tab: $(bind -q complete 2>/dev/null | head -n 1 || true) / $(bind -q menu-complete 2>/dev/null | head -n 1 || true)"
		;;
	esac

	git_line=$(_cxdiag_registration git)
	case "$git_line" in
	*_argc_completer*) _cxdiag_print '注意: git 归 argc；仓库约定 git/gitk 归 carapace（argc 缺 --cached、--staged 等选项）' ;;
	*_carapace_completer*) _cxdiag_print 'git 归 carapace，符合仓库约定' ;;
	esac

	if [ "$stale" -eq 1 ]; then
		_cxdiag_print "建议: source $user_rc（或新开终端）后重跑本诊断"
	fi
	_cxdiag_print '归属与顺序说明见 bash/README.md；参考可执行命令：complete -p <命令>'
}

_cxdiag_main "$@"
unset -f _cxdiag_main _cxdiag_print _cxdiag_registration _cxdiag_mtime 2>/dev/null || true
