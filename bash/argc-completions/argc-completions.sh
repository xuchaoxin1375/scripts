#!/usr/bin/env bash
# argc-completions 运行时初始化，Git Bash(MSYS)、Linux/WSL 与 macOS bash 共用。
# 由同目录 setup.sh 写入 ~/.bashrc，也可手工 source。
# 不修改 argc-completions 仓库本身。
# shellcheck shell=bash

_argc_completions_main() {
	# 已加载则跳过，避免重复注册补全与重复追加 PATH
	if [ "${_ARGC_COMPLETIONS_LOADED:-0}" = "1" ]; then
		return 0
	fi

	local candidate

	# 允许通过环境变量覆盖，默认按平台推断
	: "${ARGC_COMPLETIONS_DIR:=}"
	if [ -z "$ARGC_COMPLETIONS_DIR" ]; then
		if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
			ARGC_COMPLETIONS_DIR=/c/repos/argc-completions
		elif [[ "${OSTYPE:-}" == linux* ]] && [ -d /mnt/c/repos/argc-completions ]; then
			ARGC_COMPLETIONS_DIR=/mnt/c/repos/argc-completions
		else
			for candidate in "$HOME/argc-completions" "$HOME/repos/argc-completions"; do
				if [ -d "$candidate/completions" ]; then
					ARGC_COMPLETIONS_DIR="$candidate"
					break
				fi
			done
			[ -n "$ARGC_COMPLETIONS_DIR" ] || ARGC_COMPLETIONS_DIR="$HOME/argc-completions"
		fi
	fi

	if [ ! -d "$ARGC_COMPLETIONS_DIR/completions" ]; then
		return 0
	fi

	local os_dir=linux is_msys=0
	case "${OSTYPE:-}" in
	msys* | cygwin*)
		is_msys=1
		os_dir=windows
		;;
	darwin*)
		os_dir=macos
		;;
	esac

	if [ "$is_msys" -eq 1 ]; then
		# MSYS 下 bin/argc 是 Linux ELF，会遮蔽 bin/argc.exe；
		# 在上游仓库之外复制一份 argc.exe 作为 bash 内的优先入口。
		local argc_shim="$HOME/.local/bin"
		local argc_exe="$ARGC_COMPLETIONS_DIR/bin/argc.exe"
		if [ -x "$argc_exe" ]; then
			if [ ! -x "$argc_shim/argc.exe" ] || [ "$argc_exe" -nt "$argc_shim/argc.exe" ]; then
				mkdir -p "$argc_shim" && cp -f "$argc_exe" "$argc_shim/argc.exe"
			fi
		fi
		# 仓库 bin 放在末尾：yq.exe 仍可用，同时不会抢在 shim 前面提供 ELF
		export PATH="$argc_shim:$PATH:$ARGC_COMPLETIONS_DIR/bin"

		# Scoop 或非标准 Git for Windows 布局下 argc 猜不到 bash，需要显式指定
		if [ -z "${ARGC_SHELL_PATH:-}" ] && [ -n "${BASH:-}" ]; then
			ARGC_SHELL_PATH="$(cygpath -w "$BASH")"
			export ARGC_SHELL_PATH
		fi

		export ARGC_COMPLETIONS_ROOT="$ARGC_COMPLETIONS_DIR"
		local win_completions
		win_completions="$(cygpath -w "$ARGC_COMPLETIONS_DIR/completions")"
		export ARGC_COMPLETIONS_PATH="${win_completions}\\windows;${win_completions}"
	else
		export ARGC_COMPLETIONS_ROOT="$ARGC_COMPLETIONS_DIR"
		export ARGC_COMPLETIONS_PATH="$ARGC_COMPLETIONS_DIR/completions/$os_dir:$ARGC_COMPLETIONS_DIR/completions"
		# argc 也可以来自 PATH（例如 macOS/Linux 的 Homebrew）；只有仓库内确有 bin/ 时才前置。
		if [ -d "$ARGC_COMPLETIONS_DIR/bin" ]; then
			export PATH="$ARGC_COMPLETIONS_DIR/bin:$PATH"
		fi
	fi

	if ! argc --argc-version >/dev/null 2>&1; then
		echo "[argc-completions] argc 不可用，跳过补全初始化（检查 $ARGC_COMPLETIONS_DIR/bin 或 PATH）" >&2
		return 0
	fi

	# bash 没有独立的描述列，上游默认把“候选 (说明)”拼成同一个字符串。
	# 描述开启后，menu-complete 或 ble.sh 选中候选时会把说明写进命令行，
	# 因此为保证插入内容干净，默认关闭；确认 Tab 仍是普通 complete 且
	# 未加载 ble.sh 时，可显式设为 1。
	export ARGC_COMPGEN_DESCRIPTION="${ARGC_COMPGEN_DESCRIPTION:-0}"

	local file base
	argc_scripts=()
	if [ -n "${ARGC_COMPLETIONS_ONLY:-}" ]; then
		read -ra argc_scripts <<<"$ARGC_COMPLETIONS_ONLY"
	else
		for file in "$ARGC_COMPLETIONS_DIR/completions/$os_dir"/*.sh "$ARGC_COMPLETIONS_DIR/completions"/*.sh; do
			[ -e "$file" ] || continue
			base="${file##*/}"
			argc_scripts+=("${base%.sh}")
		done
	fi
	# shellcheck source=/dev/null
	source <(argc --argc-completions bash "${argc_scripts[@]}")

	_ARGC_COMPLETIONS_LOADED=1
}

_argc_completions_main
unset -f _argc_completions_main
