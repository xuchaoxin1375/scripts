#!/usr/bin/env bash
# 安装 / 停用 argc-completions 的 bash 接入片段（Git Bash、WSL/Linux 与 macOS 通用）。
# 只改写 ~/.bashrc 中的标记块，不修改 argc-completions 仓库。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_FILE="$SCRIPT_DIR/argc-completions.sh"
RC_FILE="$HOME/.bashrc"
RC_FILE_EXPLICIT=0
USE_LOGIN_RC=0
DRY_RUN=0
UNINSTALL=0
ARGC_DIR=''

BEGIN_MARK="# >>> argc-completions >>>"
END_MARK="# <<< argc-completions <<<"
CARAPACE_MARK="# >>> carapace >>>"

usage() {
	cat <<'EOF'
用法: setup.sh [选项]

选项:
  -d, --disable      停用：从 rc 移除标记块，不删除克隆目录（--uninstall 同义）
  -u, --uninstall    同 --disable，历史名称
      --rc <file>    指定 rc 文件（默认 ~/.bashrc）
  -l, --login        写入登录 shell 实际读取的 rc 文件
      --argc-dir <d> 指定 argc-completions 克隆目录，写入 ARGC_COMPLETIONS_DIR
  -n, --dry-run      只打印将要写入或移除的内容
  -h, --help         显示本帮助

说明:
  同一命令由后 source 的补全框架接管。rc 中已有 carapace 块时，本脚本把
  argc 块插到它之前，保证 carapace 继续负责重叠命令（git 等），argc 只补
  carapace 缺失的部分。--login 与 --rc 不能同时使用。
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

while [ $# -gt 0 ]; do
	case "$1" in
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
	-n | --dry-run) DRY_RUN=1 ;;
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
if [ "$USE_LOGIN_RC" -eq 1 ]; then
	RC_FILE="$(login_rc_file)"
fi

# shellcheck disable=SC2088
case "$ARGC_DIR" in
'') ;;
"~") ARGC_DIR="$HOME" ;;
"~/"*) ARGC_DIR="$HOME/${ARGC_DIR#\~/}" ;;
esac
if [ -n "$ARGC_DIR" ] && [ ! -d "$ARGC_DIR/completions" ]; then
	echo "错误: $ARGC_DIR 不是 argc-completions 克隆目录（缺少 completions/）" >&2
	exit 1
fi

if [ ! -f "$INIT_FILE" ]; then
	echo "错误: 找不到 $INIT_FILE" >&2
	exit 1
fi

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
        $0 == begin { show = 1 }
        show        { print }
        $0 == end   { show = 0 }
    ' "$1"
}

write_block() {
	printf '%s\n' "$BEGIN_MARK"
	printf '# 由 scripts/bash/argc-completions/setup.sh 维护，删除本标记块即卸载\n'
	if [ -n "$ARGC_DIR" ]; then
		printf 'export ARGC_COMPLETIONS_DIR="%s"\n' "$ARGC_DIR"
	fi
	printf '[ -f "%s" ] && source "%s"\n' "$INIT_FILE" "$INIT_FILE"
	printf '%s\n' "$END_MARK"
}

insert_block() {
	local base="$1" block="$2" out="$3"
	if grep -qxF "$CARAPACE_MARK" "$base"; then
		awk -v mark="$CARAPACE_MARK" -v bf="$block" '
            $0 == mark && !done {
                while ((getline line < bf) > 0) print line
                close(bf)
                print ""
                done = 1
            }
            { print }
        ' "$base" >"$out"
	else
		cat "$base" >"$out"
		printf '\n' >>"$out"
		cat "$block" >>"$out"
	fi
}

if [ ! -f "$RC_FILE" ]; then
	if [ "$DRY_RUN" -eq 1 ]; then
		echo "将创建 $RC_FILE"
	else
		mkdir -p "$(dirname "$RC_FILE")"
		: >"$RC_FILE"
	fi
fi

if [ "$UNINSTALL" -eq 1 ]; then
	if [ ! -f "$RC_FILE" ] || ! grep -qxF "$BEGIN_MARK" "$RC_FILE"; then
		echo "$RC_FILE 中没有 argc-completions 片段，无需停用"
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
	echo "已从 $RC_FILE 移除 argc-completions 片段（已停用，克隆目录未删除）"
	exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
	echo "[dry-run] 目标 rc 文件: $RC_FILE"
	if [ -f "$RC_FILE" ] && grep -qxF "$CARAPACE_MARK" "$RC_FILE"; then
		echo "[dry-run] 插入位置: carapace 块之前（保证 carapace 后加载）"
	else
		echo "[dry-run] 插入位置: 文件末尾"
	fi
	echo "[dry-run] 将写入以下标记块:"
	write_block
	exit 0
fi

tmp_base="$(mktemp "${RC_FILE}.XXXXXX")"
tmp_block="$(mktemp "${RC_FILE}.block.XXXXXX")"
tmp_out="$(mktemp "${RC_FILE}.out.XXXXXX")"
remove_block "$RC_FILE" >"$tmp_base"
write_block >"$tmp_block"
insert_block "$tmp_base" "$tmp_block" "$tmp_out"
mv "$tmp_out" "$RC_FILE"
rm -f "$tmp_base" "$tmp_block"

if bash -n "$RC_FILE" 2>/dev/null; then
	echo "已写入 $RC_FILE"
else
	echo "警告: $RC_FILE 语法检查未通过，请检查" >&2
fi
echo "重新打开终端，或执行 source $RC_FILE 生效"
