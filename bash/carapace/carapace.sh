#!/usr/bin/env bash
# carapace 运行时初始化：Git Bash(MSYS)/Cygwin 与 Linux/WSL 共用。
# 由同目录 setup.sh 写入 ~/.bashrc，也可手工 source；可重复 source。
# shellcheck shell=bash

_carapace_main() {
	if [ "${_CARAPACE_SHELL_LOADED:-0}" = "1" ]; then
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
		printf '[carapace] 未找到 carapace，跳过补全初始化；安装见 PS/docs/Deploy-Guide.md（Windows 可用 scoop install carapace-bin）\n' >&2
		return 0
	fi
	if ! carapace --version >/dev/null 2>&1; then
		printf '[carapace] carapace --version 执行失败，跳过补全初始化\n' >&2
		return 0
	fi
	if ! command -v xargs >/dev/null 2>&1; then
		printf '[carapace] 未找到 xargs，bash 补全需要 coreutils；跳过补全初始化\n' >&2
		return 0
	fi

	# shellcheck disable=SC1090
	source <(carapace _carapace bash)

	# Git Bash/MSYS 的 PATH 用 ':' 分隔；carapace 会追加 Windows 风格目录
	# （C:/...;...），';' 会把后面的第一个目录粘进同一项。仅兼容层需要修正。
	case "${OSTYPE:-}" in
	msys* | cygwin*)
		case "$PATH" in
		*';'*) PATH="${PATH#*;}" ;;
		esac
		;;
	esac

	_CARAPACE_SHELL_LOADED=1
}

_carapace_main
unset -f _carapace_main
