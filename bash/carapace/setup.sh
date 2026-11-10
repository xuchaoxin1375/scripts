#!/usr/bin/env bash
# 安装 / 停用 carapace 的 bash 接入片段（Git Bash、Cygwin、Linux/WSL、macOS bash 通用）。
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
INSTALL=0
INSTALL_DEPS=0
INSTALL_VERSION=''
BIN_DIR=''
FORCE_INSTALL=0
MIRROR_MODE='auto'
MIRROR_SET=0
CUSTOM_MIRROR=''
PROXY_URL=''
PROXY_SET=0
BLOCK_CARAPACE_BIN=''

BEGIN_MARK="# >>> carapace >>>"
END_MARK="# <<< carapace <<<"

usage() {
	cat <<'EOF'
用法: setup.sh [选项]

选项:
  -n, --dry-run      只打印将要写入或移除的内容，不修改文件
  -l, --login        写入登录 shell 实际读取的 rc 文件
  -r, --rc <file>    指定 rc 文件（默认 ~/.bashrc）
  -d, --disable      停用：从 rc 移除标记块，不删除二进制（--uninstall 同义）
  -u, --uninstall    同 --disable，历史名称
  -c, --check        只读检查依赖、rc 片段与端到端加载状态，不修改文件
      --status       同 --check
  -i, --install      下载并安装 carapace（官方 Release + SHA-256），然后写入 rc
      --install-deps 安装缺失依赖（Linux 用 sudo 包管理器，macOS 用 brew）
      --version <v>  --install 时固定版本；默认查询最新 release
      --bin-dir <d>  --install 的安装目录（默认 $CARAPACE_BIN；Windows 为
                     ~/.cxxu/bin，其他平台为 ~/.local/bin）
      --mirror <m>   --install 的下载通道: auto（默认，镜像优先）、direct、ghproxy、
                     ghproxynet、ghfast 或 https 前缀
      --proxy <url>  --install 时经 HTTP/HTTPS/SOCKS 代理下载
      --force        --install 时覆盖已存在的 carapace
  -h, --help         显示本帮助

说明:
  登录 shell 读 ~/.bash_profile、~/.bash_login 或 ~/.profile，不读 ~/.bashrc；
  非登录 shell 读 ~/.bashrc。先在交互式 shell 执行
  shopt -q login_shell && echo login || echo non-login
  再决定是否加 --login。--login 与 --rc 不能同时使用。

  --install 支持 Linux/macOS 与 Git Bash/Cygwin：Windows 下载 windows zip，
  解压出 carapace.exe 后装到 ~/.cxxu/bin，其他平台下载 tar.gz 装到
  ~/.local/bin。下载走 curl 或 wget：auto 模式先试 GitHub 文件镜像再回退直连；
  版本查询始终直连（或经 --proxy），不经过文件镜像。未指定 --proxy 时沿用
  HTTPS_PROXY/HTTP_PROXY/ALL_PROXY。

  --install-deps 只在显式给出时执行：缺 curl/wget、coreutils、tar 时调用
  包管理器安装；Linux 需要 sudo（已是 root 时直接执行），macOS 用 brew。
  Git Bash 的这些依赖通常随 Git 提供；缺失时给出手工安装命令，不自动执行。
  不加该选项时只提示命令，不安装任何软件。

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
	-d | --disable | -u | --uninstall) UNINSTALL=1 ;;
	-c | --check | --status) CHECK_ONLY=1 ;;
	-i | --install) INSTALL=1 ;;
	--install-deps) INSTALL_DEPS=1 ;;
	--version)
		shift
		if [ $# -eq 0 ]; then
			echo "错误: --version 缺少参数" >&2
			exit 2
		fi
		INSTALL_VERSION="$1"
		;;
	--bin-dir)
		shift
		if [ $# -eq 0 ]; then
			echo "错误: --bin-dir 缺少参数" >&2
			exit 2
		fi
		BIN_DIR="$1"
		;;
	--mirror)
		shift
		if [ $# -eq 0 ]; then
			echo "错误: --mirror 缺少参数" >&2
			exit 2
		fi
		case "$1" in
		auto | direct | ghproxy | ghproxynet | ghfast) MIRROR_MODE="$1" ;;
		https://*)
			CUSTOM_MIRROR="${1%/}"
			MIRROR_MODE=custom
			;;
		*)
			echo "错误: 无法识别的镜像 $1（可用 auto、direct、ghproxy、ghproxynet、ghfast 或 https 前缀）" >&2
			exit 2
			;;
		esac
		MIRROR_SET=1
		;;
	--proxy)
		shift
		if [ $# -eq 0 ]; then
			echo "错误: --proxy 缺少参数" >&2
			exit 2
		fi
		PROXY_URL="$1"
		PROXY_SET=1
		;;
	--force) FORCE_INSTALL=1 ;;
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
	echo "错误: --check 不能与 --disable/--uninstall 或 --dry-run 同时使用" >&2
	exit 2
fi

if [ "$INSTALL" -eq 1 ] && { [ "$UNINSTALL" -eq 1 ] || [ "$CHECK_ONLY" -eq 1 ]; }; then
	echo "错误: --install 不能与 --disable/--uninstall 或 --check 同时使用" >&2
	exit 2
fi

if [ "$INSTALL" -eq 0 ] && { [ -n "$INSTALL_VERSION" ] || [ -n "$BIN_DIR" ] || [ "$FORCE_INSTALL" -eq 1 ] || [ "$MIRROR_SET" -eq 1 ] || [ "$PROXY_SET" -eq 1 ]; }; then
	echo "错误: --version、--bin-dir、--mirror、--proxy、--force 只能与 --install 一起使用" >&2
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

if [ "$CHECK_ONLY" -eq 0 ] && [ "$INSTALL" -eq 0 ] && ! command -v carapace >/dev/null 2>&1; then
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
        line == begin { skip = 1; pending = 0; next }
        line == end   { skip = 0; next }
        skip          { next }
        line == ""    { pending = 1; next }
        {
            if (pending) { print ""; pending = 0 }
            print line
        }
        END { if (pending) print "" }
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
	if [ -n "$BLOCK_CARAPACE_BIN" ]; then
		printf 'export CARAPACE_BIN="%s"\n' "$BLOCK_CARAPACE_BIN"
	fi
	# shellcheck disable=SC2016
	printf 'if [ -n "${BASH_VERSION:-}" ] && [ -f "%s" ]; then . "%s"; fi\n' "$INIT_FILE" "$INIT_FILE"
	printf '%s\n' "$END_MARK"
}

install_hint() {
	case "${OSTYPE:-}" in
	msys* | cygwin*) printf 'Windows 可执行 bash setup.sh --install（官方 Release + SHA-256），或 scoop install carapace-bin；也可用 Deploy-Carapace -Enable' ;;
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

block_carapace_bin() {
	awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
        {
            line = $0
            sub(/\r$/, "", line)
        }
        line == begin { inside = 1; next }
        line == end   { inside = 0 }
        inside && /CARAPACE_BIN/ && match(line, /"[^"]*"/) {
            print substr(line, RSTART + 1, RLENGTH - 2)
            exit
        }
    ' "$1"
}

probe_shell() {
	bash "$1" -c '
	if declare -F _carapace_completer >/dev/null 2>&1; then echo "carapace-probe:loaded=1"; fi
	' 2>/dev/null || true
}

report_load() {
	local label="$1" out="$2"
	case "$out" in
	*carapace-probe:loaded=1*) printf '    %s : 已加载\n' "$label" ;;
	*) printf '    %s : 未加载\n' "$label" ;;
	esac
}

rc_loads_blesh() {
	local f
	for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
		[ -f "$f" ] || continue
		if grep -Eq 'ble\.sh|BLE_VERSION' "$f"; then
			return 0
		fi
	done
	return 1
}

check_item() {
	printf '  %-12s : %s\n' "$1" "$2"
}

run_check() {
	local failures=0 rc_installed=0 loaded_any=0
	local candidate block_path bin_dir rc_bin carapace_path carapace_ver nonlogin login

	printf 'carapace bash 接入检查（只读）\n'

	if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
		check_item bash "${BASH_VERSION:-unknown}（需要 4+）"
	else
		check_item bash "${BASH_VERSION:-unknown}（需要 4+，当前不满足）"
		failures=$((failures + 1))
	fi

	rc_bin=''
	for candidate in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
		[ -f "$candidate" ] || continue
		bin_dir="$(block_carapace_bin "$candidate")"
		if [ -n "$bin_dir" ] && [ -x "$bin_dir/carapace" ]; then
			rc_bin="$bin_dir"
			break
		fi
	done

	if carapace_path="$(command -v carapace 2>/dev/null)"; then
		if carapace_ver="$(carapace --version 2>/dev/null)"; then
			check_item carapace "${carapace_path}（${carapace_ver}）"
		else
			check_item carapace "${carapace_path}（--version 执行失败）"
			failures=$((failures + 1))
		fi
	elif [ -n "$rc_bin" ]; then
		if carapace_ver="$("$rc_bin/carapace" --version 2>/dev/null)"; then
			check_item carapace "${rc_bin}/carapace（${carapace_ver}，经 rc 片段的 CARAPACE_BIN）"
		else
			check_item carapace "$rc_bin/carapace（--version 执行失败）"
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
		bin_dir="$(block_carapace_bin "$candidate")"
		if [ -n "$bin_dir" ] && [ ! -d "$bin_dir" ]; then
			printf '    %s : CARAPACE_BIN 目录不存在: %s\n' "$candidate" "$bin_dir"
			failures=$((failures + 1))
		fi
	done

	printf '  load test:\n'
	nonlogin="$(probe_shell -i)"
	login="$(probe_shell -l)"
	report_load '非登录 shell（读取 ~/.bashrc）' "$nonlogin"
	report_load '登录 shell（读取 ~/.bash_profile 等）' "$login"
	if rc_loads_blesh; then
		check_item 'ble.sh' 'rc 中已加载；运行时用 bash-ble 适配'
	else
		check_item 'ble.sh' '未检测到；使用普通 bash 补全'
	fi
	case "$nonlogin$login" in
	*carapace-probe:loaded=1*) loaded_any=1 ;;
	esac

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

host_os() {
	case "${OSTYPE:-}" in
	linux*) printf 'linux\n' ;;
	darwin*) printf 'darwin\n' ;;
	msys* | cygwin*) printf 'windows\n' ;;
	*) printf 'unknown\n' ;;
	esac
}

host_arch() {
	case "$(uname -m 2>/dev/null)" in
	x86_64 | amd64) printf 'amd64\n' ;;
	aarch64 | arm64) printf 'arm64\n' ;;
	i386 | i486 | i586 | i686 | x86) printf '386\n' ;;
	*) printf '\n' ;;
	esac
}

download_tool() {
	if command -v curl >/dev/null 2>&1; then
		printf 'curl\n'
	elif command -v wget >/dev/null 2>&1; then
		printf 'wget\n'
	else
		printf '\n'
	fi
}

sha_tool() {
	if command -v sha256sum >/dev/null 2>&1; then
		printf 'sha256sum\n'
	elif command -v shasum >/dev/null 2>&1; then
		printf 'shasum\n'
	else
		printf '\n'
	fi
}

bin_name() {
	if [ "$(host_os)" = "windows" ]; then
		printf 'carapace.exe\n'
	else
		printf 'carapace\n'
	fi
}

archive_ext() {
	if [ "$(host_os)" = "windows" ]; then
		printf 'zip\n'
	else
		printf 'tar.gz\n'
	fi
}

extract_tool() {
	if [ "$(host_os)" = "windows" ]; then
		if command -v unzip >/dev/null 2>&1; then
			printf 'unzip\n'
		elif command -v bsdtar >/dev/null 2>&1; then
			printf 'bsdtar\n'
		elif command -v powershell.exe >/dev/null 2>&1; then
			printf 'powershell\n'
		fi
	elif command -v tar >/dev/null 2>&1; then
		printf 'tar\n'
	fi
}

extract_release() {
	local dir="$1" asset="$2" member="$3"
	case "$asset" in
	*.tar.gz)
		tar -xzf "$dir/$asset" -C "$dir" "$member"
		;;
	*.zip)
		if command -v unzip >/dev/null 2>&1; then
			unzip -o -q "$dir/$asset" "$member" -d "$dir"
		elif command -v bsdtar >/dev/null 2>&1; then
			bsdtar -xf "$dir/$asset" -C "$dir" "$member"
		elif command -v powershell.exe >/dev/null 2>&1; then
			powershell.exe -NoProfile -NonInteractive -Command \
				"Expand-Archive -LiteralPath '$(cygpath -w "$dir/$asset")' -DestinationPath '$(cygpath -w "$dir")' -Force"
		else
			return 1
		fi
		;;
	*)
		return 1
		;;
	esac
}

package_manager() {
	if command -v apt-get >/dev/null 2>&1; then
		printf 'apt-get\n'
	elif command -v dnf >/dev/null 2>&1; then
		printf 'dnf\n'
	elif command -v pacman >/dev/null 2>&1; then
		printf 'pacman\n'
	elif command -v apk >/dev/null 2>&1; then
		printf 'apk\n'
	elif command -v brew >/dev/null 2>&1; then
		printf 'brew\n'
	fi
}

run_privileged() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	elif command -v sudo >/dev/null 2>&1; then
		sudo "$@"
	else
		printf '需要 root 权限；请手工执行: %s\n' "$*" >&2
		return 1
	fi
}

install_packages() {
	local pm="$1"
	shift
	case "$pm" in
	apt-get) run_privileged apt-get install -y "$@" ;;
	dnf) run_privileged dnf install -y "$@" ;;
	pacman) run_privileged pacman -S --needed "$@" ;;
	apk) run_privileged apk add "$@" ;;
	brew) brew install "$@" ;;
	*)
		printf '错误: 不支持的包管理器 %s\n' "$pm" >&2
		return 1
		;;
	esac
}

missing_install_deps() {
	local deps=''
	[ -n "$(download_tool)" ] || deps="$deps curl"
	[ -n "$(sha_tool)" ] || deps="$deps coreutils"
	command -v tar >/dev/null 2>&1 || deps="$deps tar"
	command -v xargs >/dev/null 2>&1 || deps="$deps coreutils"
	printf '%s\n' "$deps" | tr ' ' '\n' | awk 'NF && !seen[$0]++'
}

install_deps() {
	local deps pm
	if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
		printf '提示: 当前 bash %s 低于 4，carapace 会拒绝加载。\n' "$BASH_VERSION" >&2
		if [ "$(host_os)" = "darwin" ]; then
			printf '      macOS 可执行 brew install bash，把新版 bash 加入 /etc/shells 后 chsh 切换。\n' >&2
		else
			printf '      请安装 bash 4 及以上版本。\n' >&2
		fi
	fi

	deps="$(missing_install_deps | tr '\n' ' ' | sed 's/ *$//')"
	if [ -z "$deps" ]; then
		printf '依赖已齐全（下载=%s，解压=%s，校验=%s）\n' \
			"$(download_tool)" "$(extract_tool)" "$(sha_tool)"
		return 0
	fi
	printf '缺少依赖: %s\n' "$deps"

	if [ "$(host_os)" = "windows" ]; then
		printf 'Git Bash 的依赖随 Git for Windows 提供：请在 MSYS2 中用 pacman 安装对应包，或重装 Git for Windows。\n' >&2
		return 1
	fi

	pm="$(package_manager)"
	if [ -z "$pm" ]; then
		printf '未识别到包管理器；请手工安装: %s\n' "$deps" >&2
		return 1
	fi
	if [ "$DRY_RUN" -eq 1 ]; then
		case "$pm" in
		apt-get) printf '[dry-run] 将执行: sudo apt-get install -y %s\n' "$deps" ;;
		dnf) printf '[dry-run] 将执行: sudo dnf install -y %s\n' "$deps" ;;
		pacman) printf '[dry-run] 将执行: sudo pacman -S --needed %s\n' "$deps" ;;
		apk) printf '[dry-run] 将执行: sudo apk add %s\n' "$deps" ;;
		brew) printf '[dry-run] 将执行: brew install %s\n' "$deps" ;;
		esac
		return 0
	fi
	printf '调用 %s 安装: %s\n' "$pm" "$deps"
	# shellcheck disable=SC2086
	install_packages "$pm" $deps || return 1

	if [ -z "$(download_tool)" ] || [ -z "$(sha_tool)" ]; then
		printf '警告: 安装后仍缺 curl/wget 或 sha256sum；请手工处理后重试\n' >&2
		return 1
	fi
	return 0
}

deps_hint() {
	if command -v apt-get >/dev/null 2>&1; then
		printf 'sudo apt-get install -y %s\n' "$1"
	elif command -v dnf >/dev/null 2>&1; then
		printf 'sudo dnf install -y %s\n' "$1"
	elif command -v pacman >/dev/null 2>&1; then
		printf 'sudo pacman -S --needed %s\n' "$1"
	elif command -v apk >/dev/null 2>&1; then
		printf 'sudo apk add %s\n' "$1"
	else
		printf '用发行版包管理器安装 %s\n' "$1"
	fi
}

gh_mirror_prefixes() {
	case "$MIRROR_MODE" in
	auto) printf '%s\n' 'https://gh-proxy.com' 'https://ghproxy.net' '' ;;
	direct) printf '%s\n' '' ;;
	ghproxy) printf '%s\n' 'https://gh-proxy.com' ;;
	ghproxynet) printf '%s\n' 'https://ghproxy.net' ;;
	ghfast) printf '%s\n' 'https://ghfast.top' ;;
	custom) printf '%s\n' "$CUSTOM_MIRROR" ;;
	esac
}

http_get() {
	local url="$1"
	if [ "$(download_tool)" = "curl" ]; then
		if [ -n "$PROXY_URL" ]; then
			curl -fsSL --connect-timeout 10 --max-time 20 -x "$PROXY_URL" "$url"
		else
			curl -fsSL --connect-timeout 10 --max-time 20 "$url"
		fi
	else
		wget -qO- --timeout=20 "$url"
	fi
}

http_head() {
	local url="$1"
	if [ "$(download_tool)" = "curl" ]; then
		if [ -n "$PROXY_URL" ]; then
			curl -fsSI --connect-timeout 10 --max-time 20 -x "$PROXY_URL" "$url"
		else
			curl -fsSI --connect-timeout 10 --max-time 20 "$url"
		fi
	else
		wget -qS --spider --timeout=20 "$url" 2>&1
	fi
}

latest_version() {
	local tag=''
	tag="$(http_head 'https://github.com/carapace-sh/carapace-bin/releases/latest' 2>/dev/null |
		awk 'tolower($1) == "location:" { print $2 }' | tr -d '\r' | sed 's#.*/tag/##' | head -n 1)"
	if [ -z "$tag" ]; then
		tag="$(http_get 'https://api.github.com/repos/carapace-sh/carapace-bin/releases/latest' 2>/dev/null |
			sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
	fi
	printf '%s\n' "${tag#v}"
}

download_file() {
	if [ "$(download_tool)" = "curl" ]; then
		if [ -n "$PROXY_URL" ]; then
			curl -fL --connect-timeout 10 --retry 1 --max-time 300 -x "$PROXY_URL" -o "$2" "$1"
		else
			curl -fL --connect-timeout 10 --retry 1 --max-time 300 -o "$2" "$1"
		fi
	else
		if [ -n "$PROXY_URL" ]; then
			wget -q -e use_proxy=yes -e "https_proxy=$PROXY_URL" -O "$2" "$1"
		else
			wget -q -O "$2" "$1"
		fi
	fi
}

download_release_file() {
	local url="$1" dest="$2" prefix full
	while IFS= read -r prefix; do
		if [ -n "$prefix" ]; then
			full="${prefix%/}/$url"
		else
			full="$url"
		fi
		printf '  尝试 %s\n' "$full"
		if download_file "$full" "$dest"; then
			return 0
		fi
	done < <(gh_mirror_prefixes)
	return 1
}

install_binary() {
	if command -v install >/dev/null 2>&1; then
		install -m 0755 "$1" "$2"
	else
		cp "$1" "$2" && chmod 0755 "$2"
	fi
}

note_install_path() {
	case ":$PATH:" in
	*":$1:"*) ;;
	*)
		printf '提示: %s 不在 PATH 中，rc 片段会写入 CARAPACE_BIN 前置该目录\n' "$1"
		BLOCK_CARAPACE_BIN="$1"
		;;
	esac
}

verify_sha256() {
	local dir="$1" asset="$2" expected actual tool
	expected="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$dir/checksums.txt")"
	if [ -z "$expected" ]; then
		echo "错误: checksums.txt 中没有 $asset 的校验值" >&2
		return 1
	fi
	tool="$(sha_tool)"
	if [ "$tool" = "sha256sum" ]; then
		actual="$(sha256sum "$dir/$asset" | awk '{ print $1 }')"
	else
		actual="$(shasum -a 256 "$dir/$asset" | awk '{ print $1 }')"
	fi
	if [ "$expected" != "$actual" ]; then
		echo "错误: SHA-256 校验失败（期望 ${expected}，实际 ${actual}）" >&2
		return 1
	fi
}

install_dest() {
	local dest
	if [ -n "$BIN_DIR" ]; then
		dest="$BIN_DIR"
	elif [ -n "${CARAPACE_BIN:-}" ]; then
		dest="$CARAPACE_BIN"
	elif [ "$(host_os)" = "windows" ]; then
		dest="$HOME/.cxxu/bin"
	else
		dest="$HOME/.local/bin"
	fi
	# shellcheck disable=SC2088
	case "$dest" in
	"~") dest="$HOME" ;;
	"~/"*) dest="$HOME/${dest#\~/}" ;;
	esac
	printf '%s\n' "$dest"
}

print_install_plan() {
	local os arch dest ver channel
	os="$(host_os)"
	arch="$(host_arch)"
	dest="$(install_dest)"
	ver="${INSTALL_VERSION:-<最新 release>}"
	case "$MIRROR_MODE" in
	auto) channel='auto（gh-proxy → ghproxy.net → 直连）' ;;
	direct) channel='direct（直连）' ;;
	ghproxy) channel='ghproxy（https://gh-proxy.com）' ;;
	ghproxynet) channel='ghproxynet（https://ghproxy.net）' ;;
	ghfast) channel='ghfast（https://ghfast.top）' ;;
	custom) channel="custom（${CUSTOM_MIRROR}）" ;;
	esac
	printf '[dry-run] 平台: %s/%s\n' "$os" "${arch:-未知}"
	printf '[dry-run] 版本: %s\n' "$ver"
	printf '[dry-run] 产物: carapace-bin_<版本>_%s_%s.%s\n' "$os" "${arch:-未知}" "$(archive_ext)"
	printf '[dry-run] 安装目录: %s\n' "$dest"
	printf '[dry-run] 下载通道: %s\n' "$channel"
	if [ -n "$PROXY_URL" ]; then
		printf '[dry-run] 代理: 已设置（不显示地址）\n'
	fi
	printf '[dry-run] 依赖: 下载=%s，解压=%s，校验=%s\n' \
		"$(download_tool || true)" "$(extract_tool || true)" "$(sha_tool || true)"
}

run_install() {
	local os arch dest ver asset base dep bin

	os="$(host_os)"
	if [ "$os" = "unknown" ]; then
		echo "错误: 无法识别的平台 ${OSTYPE:-unknown}；请改用包管理器安装" >&2
		return 1
	fi
	arch="$(host_arch)"
	if [ -z "$arch" ]; then
		echo "错误: 没有 $(uname -m) 对应的官方产物；请改用发行版仓库或包管理器安装" >&2
		return 1
	fi
	dest="$(install_dest)"
	bin="$(bin_name)"

	if command -v carapace >/dev/null 2>&1 && [ "$FORCE_INSTALL" -eq 0 ]; then
		printf '已安装 %s（%s）；如需覆盖，加 --force\n' \
			"$(command -v carapace)" "$(carapace --version 2>/dev/null || printf '版本未知')"
		# 目标目录没有副本时不再写 CARAPACE_BIN，避免 rc 指向不存在的目录
		if [ -x "$dest/$bin" ]; then
			note_install_path "$dest"
		fi
		return 0
	fi
	if [ -x "$dest/$bin" ] && [ "$FORCE_INSTALL" -eq 0 ]; then
		printf '已安装 %s（%s）；如需覆盖，加 --force\n' \
			"$dest/$bin" "$("$dest/$bin" --version 2>/dev/null || printf '版本未知')"
		note_install_path "$dest"
		return 0
	fi

	dep="$(download_tool)"
	if [ -z "$dep" ]; then
		echo "错误: 需要 curl 或 wget；$(deps_hint curl)（也可加 --install-deps 自动安装）" >&2
		return 1
	fi
	if [ "$os" = "windows" ]; then
		if [ -z "$(extract_tool)" ]; then
			echo "错误: 解压 zip 需要 unzip、bsdtar 或 powershell.exe 之一；$(deps_hint unzip)" >&2
			return 1
		fi
	elif ! command -v tar >/dev/null 2>&1; then
		echo "错误: 需要 tar；$(deps_hint tar)（也可加 --install-deps 自动安装）" >&2
		return 1
	fi
	if [ -z "$(sha_tool)" ]; then
		echo "错误: 需要 sha256sum 或 shasum；$(deps_hint coreutils)（也可加 --install-deps 自动安装）" >&2
		return 1
	fi

	if [ -n "$INSTALL_VERSION" ]; then
		ver="${INSTALL_VERSION#v}"
	else
		printf '查询 carapace 最新 release ...\n'
		ver="$(latest_version)"
	fi
	case "$ver" in
	'')
		echo "错误: 无法获取 carapace 版本；可用 --version 指定固定版本，或检查网络/代理" >&2
		return 1
		;;
	*[!0-9.]*)
		echo "错误: 无法识别的版本号 ${ver}（用 1.8.2 这类三段版本）" >&2
		return 1
		;;
	esac

	asset="carapace-bin_${ver}_${os}_${arch}.$(archive_ext)"
	base="https://github.com/carapace-sh/carapace-bin/releases/download/v${ver}"
	INSTALL_TMP="$(mktemp -d)"
	trap 'rm -rf "${INSTALL_TMP:-}"' EXIT

	printf '下载 %s ...\n' "$asset"
	if ! download_release_file "$base/$asset" "$INSTALL_TMP/$asset"; then
		echo "错误: 下载失败: ${base}/${asset}（可加 --mirror 或 --proxy 重试）" >&2
		return 1
	fi
	if ! download_release_file "$base/carapace-bin_${ver}_checksums.txt" "$INSTALL_TMP/checksums.txt"; then
		echo "错误: 下载校验文件失败: $base/carapace-bin_${ver}_checksums.txt（可加 --mirror 或 --proxy 重试）" >&2
		return 1
	fi
	verify_sha256 "$INSTALL_TMP" "$asset" || return 1

	if ! extract_release "$INSTALL_TMP" "$asset" "$bin"; then
		echo "错误: 解压 $asset 失败（Windows 需要 unzip、bsdtar 或 powershell.exe 之一）" >&2
		return 1
	fi
	if ! mkdir -p "$dest"; then
		echo "错误: 无法创建安装目录 $dest" >&2
		return 1
	fi
	if ! install_binary "$INSTALL_TMP/$bin" "$dest/$bin"; then
		echo "错误: 无法写入 $dest/$bin" >&2
		return 1
	fi
	if ! "$dest/$bin" --version >/dev/null 2>&1; then
		echo "错误: 安装后的二进制无法执行：$dest/$bin" >&2
		return 1
	fi
	printf '已安装 %s（%s）\n' "$dest/$bin" "$("$dest/$bin" --version 2>/dev/null)"
	note_install_path "$dest"
	return 0
}

if [ "$INSTALL_DEPS" -eq 1 ]; then
	install_deps || exit 1
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
	if run_check; then
		exit 0
	fi
	exit 1
fi

if [ "$INSTALL" -eq 1 ]; then
	if [ "$DRY_RUN" -eq 1 ]; then
		print_install_plan
	else
		run_install || exit 1
	fi
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
		echo "$RC_FILE 中没有 carapace 片段，无需停用"
		if [ "$USE_LOGIN_RC" -eq 0 ] && [ "$RC_FILE_EXPLICIT" -eq 0 ]; then
			login_rc="$(login_rc_file)"
			if [ -f "$login_rc" ] && has_marker "$login_rc" "$BEGIN_MARK"; then
				echo "提示: $login_rc 中有 carapace 片段；如果是登录 shell 安装，请加 --login 停用" >&2
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
	echo "已从 $RC_FILE 移除 carapace 片段（已停用，二进制未删除）"
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
