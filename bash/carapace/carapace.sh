#!/usr/bin/env bash
# carapace 运行时初始化：Git Bash(MSYS)/Cygwin、Linux/WSL 与 macOS bash 共用。
# 由同目录 setup.sh 写入 rc（~/.bashrc 或登录 rc），也可手工 source；可重复 source。
# 需要 bash 4+；bash 3（macOS 自带 /bin/bash 3.2）会被 carapace 拒绝。
# shellcheck shell=bash

_carapace_install_hint() {
	case "${OSTYPE:-}" in
	msys* | cygwin*) printf 'Windows 可在 Git Bash 执行 bash setup.sh --install（官方 Release + SHA-256），或 scoop install carapace-bin；也可用 Deploy-Carapace -Enable' ;;
	darwin*) printf 'macOS 可执行 brew install carapace；系统自带 bash 3.2 需先 brew install bash 并切换登录 shell' ;;
	*) printf 'Linux 可从官方 Release 安装到 ~/.local/bin，或使用发行版仓库' ;;
	esac
}

_carapace_main() {
	if [ "${_CARAPACE_SHELL_LOADED:-0}" = "1" ]; then
		return 0
	fi

	if ((BASH_VERSINFO[0] < 4)); then
		printf '[carapace] 需要 bash 4 及以上（当前 %s）；macOS 自带 /bin/bash 3.2，请用 brew install bash 并切换登录 shell\n' "${BASH_VERSION:-unknown}" >&2
		return 0
	fi

	# 可选：把 carapace 所在目录前置到 PATH（例如 ~/.cxxu/bin）
	if [ -n "${CARAPACE_BIN:-}" ] && [ -d "$CARAPACE_BIN" ]; then
		case ":$PATH:" in
		*":$CARAPACE_BIN:"*) ;;
		*) PATH="$CARAPACE_BIN:$PATH" ;;
		esac
	fi

	if ! command -v carapace >/dev/null 2>&1; then
		printf '[carapace] 未找到 carapace，跳过补全初始化；%s\n' "$(_carapace_install_hint)" >&2
		return 0
	fi
	# 不单独执行 carapace --version：它会多一次进程启动（本机约 40ms）；
	# 生成脚本是否有效由下面的 source 状态和 declare -F 检查。
	if ! command -v xargs >/dev/null 2>&1; then
		printf '[carapace] 未找到 xargs，bash 补全需要 coreutils；跳过补全初始化\n' >&2
		return 0
	fi

	# 用 bash-ble：ble.sh 已加载时走 ble 专用补全（compopt -o ble/no-default、
	# 候选交给 ble 菜单、自动补全时不接管），未加载时同一份脚本回退到普通
	# bash 补全，因此不需要在运行时探测 ble.sh 是否可用。
	# process substitution 不会把生成器的退出码传给 source；没有输出或输出不完整时，
	# 由下面的 declare -F 兜底。
	# shellcheck disable=SC1090
	if ! source <(carapace _carapace bash-ble); then
		printf '[carapace] 生成或加载补全脚本失败，跳过补全初始化；请检查 carapace 版本与 bash 环境\n' >&2
		return 0
	fi
	if ! declare -F _carapace_completer >/dev/null 2>&1; then
		printf '[carapace] 补全函数未注册，跳过初始化；%s\n' "$(_carapace_install_hint)" >&2
		return 0
	fi

	# Git Bash/MSYS 的 PATH 用 ':' 分隔；carapace 会在最前面追加 Windows 风格目录
	# （C:/...;...），';' 会把后面的第一个目录粘进同一项。仅兼容层需要修正，
	# 且只处理以盘符开头的那一项，避免误伤 PATH 中其他含 ';' 的条目。
	case "${OSTYPE:-}" in
	msys* | cygwin*)
		case "$PATH" in
		[A-Za-z]:/*';'*) PATH="${PATH#*;}" ;;
		esac
		;;
	esac

	_CARAPACE_SHELL_LOADED=1

	# Tab 模式需要在补全函数注册之后再决定：读取 ~/sh 点文件的 shellrc_addition.sh
	# 在 rc 顶部调用该助手时还看不到 _carapace_completer，会退回 menu-complete。
	# 这里补一次，把 Tab 切回「列出全部候选」；没有该助手时保持原有绑定。
	if declare -F apply_tab_completion_mode >/dev/null 2>&1; then
		apply_tab_completion_mode
	fi
}

_carapace_main
unset -f _carapace_main _carapace_install_hint
