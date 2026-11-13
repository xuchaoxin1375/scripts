#!/usr/bin/env bash
# 对比 argc-completions 与 carapace 的单次补全耗时。
#
# 不修改 shell 配置，只 source 两个运行时并直接调用补全函数。
# source 运行时可能刷新 argc shim 或补全引擎缓存，不属于本脚本的额外改动。
#
# 依赖：bash 5.0 及以上（EPOCHREALTIME）、sort、awk；按测试模式另需 argc 或 carapace。
# shellcheck shell=bash

set -o pipefail
# 不启用 set -u：argc 生成的补全函数使用未初始化变量，set -u 会中断补全。

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ARGC_RUNTIME="$SCRIPT_DIR/../argc-completions/argc-completions.sh"
CARAPACE_RUNTIME="$SCRIPT_DIR/../carapace/carapace.sh"

ITERATIONS=7
WARMUP=1
MODE=both
FORMAT=table
declare -a CUSTOM_LINES=()
declare -a SCENARIOS=()
declare -a MODES=()
NOW_US=0

usage() {
	cat <<'EOF'
用法: bench-completion.sh [选项] [--line <命令行>]...

对比 argc-completions 与 carapace 的单次补全耗时。默认测试一组常用命令，
每个场景先执行一次冷调用，再做可配置次数的预热调用，最后记录多次稳态耗时。
只测量补全函数本身，不包含 readline 菜单重绘、终端渲染或按键处理。

选项:
  -n, --iterations <次数>  稳态采样次数，默认 7，范围 1-100
      --warmup <次数>      正式采样前的预热次数，默认 1，范围 0-20
  -m, --mode <模式>        both、argc 或 carapace，默认 both
  -f, --format <格式>      table、tsv 或 markdown，默认 table
  -l, --line <命令行>      自定义测试行，可重复；给出后不再使用默认场景
  -h, --help               显示本帮助

输出:
  table     按场景分组的人类可读表格
  tsv       制表符分隔，首行为表头，便于后续处理
  markdown  Markdown 表格，可直接粘贴到文档

示例:
  bash bench-completion.sh
  bash bench-completion.sh --iterations 9 --warmup 2
  bash bench-completion.sh --mode argc --line 'git commit --a'
  bash bench-completion.sh --format markdown --line 'git diff --'

退出码:
  0 成功；1 运行环境或补全运行时不可用；2 参数错误。
EOF
}

die() {
	printf '错误: %s\n' "$*" >&2
	exit 1
}

usage_error() {
	printf '错误: %s\n' "$*" >&2
	printf '用 --help 查看用法。\n' >&2
	exit 2
}

require_bash5() {
	if [[ -z ${EPOCHREALTIME:-} ]]; then
		die '需要 bash 5.0 及以上（EPOCHREALTIME 不可用）'
	fi
	if ! command -v sort >/dev/null 2>&1; then
		die '需要 sort（coreutils）'
	fi
	if ! command -v awk >/dev/null 2>&1; then
		die '需要 awk'
	fi
}

parse_args() {
	while (($#)); do
		case $1 in
		-n | --iterations)
			[[ $# -ge 2 ]] || usage_error "$1 需要参数"
			ITERATIONS=$2
			shift 2
			;;
		--warmup)
			[[ $# -ge 2 ]] || usage_error "$1 需要参数"
			WARMUP=$2
			shift 2
			;;
		-m | --mode)
			[[ $# -ge 2 ]] || usage_error "$1 需要参数"
			MODE=$2
			shift 2
			;;
		-f | --format)
			[[ $# -ge 2 ]] || usage_error "$1 需要参数"
			FORMAT=$2
			shift 2
			;;
		-l | --line)
			[[ $# -ge 2 ]] || usage_error "$1 需要参数"
			[[ -n $2 ]] || usage_error "$1 不能为空"
			CUSTOM_LINES+=("$2")
			shift 2
			;;
		-h | --help)
			usage
			exit 0
			;;
		--)
			shift
			while (($#)); do
				[[ -n $1 ]] || usage_error '--line 不能为空'
				CUSTOM_LINES+=("$1")
				shift
			done
			;;
		-*)
			usage_error "未知选项: $1"
			;;
		*)
			CUSTOM_LINES+=("$1")
			shift
			;;
		esac
	done

	[[ $ITERATIONS =~ ^[0-9]+$ ]] || usage_error '--iterations 必须是整数'
	((ITERATIONS >= 1 && ITERATIONS <= 100)) || usage_error '--iterations 范围是 1-100'

	[[ $WARMUP =~ ^[0-9]+$ ]] || usage_error '--warmup 必须是整数'
	((WARMUP >= 0 && WARMUP <= 20)) || usage_error '--warmup 范围是 0-20'

	case $MODE in
	both | argc | carapace) ;;
	*) usage_error '--mode 只能是 both、argc 或 carapace' ;;
	esac

	case $FORMAT in
	table | tsv | markdown) ;;
	*) usage_error '--format 只能是 table、tsv 或 markdown' ;;
	esac
}

load_runtimes() {
	case $MODE in
	argc | both)
		[[ -f $ARGC_RUNTIME ]] || die "找不到 argc 运行时: $ARGC_RUNTIME"
		# shellcheck source=/dev/null
		source "$ARGC_RUNTIME"
		if ! declare -F _argc_completer >/dev/null 2>&1; then
			die 'argc 补全未注册；检查 ARGC_COMPLETIONS_DIR、argc 安装与 PATH'
		fi
		;;
	esac

	case $MODE in
	carapace | both)
		[[ -f $CARAPACE_RUNTIME ]] || die "找不到 carapace 运行时: $CARAPACE_RUNTIME"
		# shellcheck source=/dev/null
		source "$CARAPACE_RUNTIME"
		if ! declare -F _carapace_completer >/dev/null 2>&1; then
			die 'carapace 补全未注册；检查 carapace 安装、PATH 与 xargs'
		fi
		;;
	esac
}

build_scenarios() {
	if ((${#CUSTOM_LINES[@]})); then
		SCENARIOS=("${CUSTOM_LINES[@]}")
	else
		SCENARIOS=(
			'git commit --a'
			'git diff --'
			'git che'
			'docker '
			'nginx '
		)
		if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			SCENARIOS+=('git checkout ')
		fi
	fi

	case $MODE in
	both) MODES=(argc carapace) ;;
	argc) MODES=(argc) ;;
	carapace) MODES=(carapace) ;;
	esac
}

read_us() {
	NOW_US=${EPOCHREALTIME//[.,]/}
}

us_to_ms() {
	LC_ALL=C awk -v us="$1" 'BEGIN { printf "%.1f", us / 1000 }'
}

median_ms() {
	printf '%s\n' "$@" |
		LC_ALL=C sort -n |
		LC_ALL=C awk '
			{ a[NR] = $1 }
			END {
				if (NR == 0) { print "NA"; exit }
				if (NR % 2 == 1) printf "%.1f\n", a[(NR + 1) / 2] / 1000
				else printf "%.1f\n", (a[NR / 2] + a[NR / 2 + 1]) / 2000
			}'
}

min_ms() {
	printf '%s\n' "$@" |
		LC_ALL=C sort -n |
		LC_ALL=C awk 'NR == 1 { printf "%.1f\n", $1 / 1000; exit }'
}

max_ms() {
	printf '%s\n' "$@" |
		LC_ALL=C sort -n |
		LC_ALL=C awk '{ last = $1 } END { printf "%.1f\n", last / 1000 }'
}

print_environment() {
	local argc_version='未测试'
	local carapace_version='未测试'

	case $MODE in
	argc | both) argc_version=$(argc --argc-version 2>/dev/null | head -n1) ;;
	esac
	case $MODE in
	carapace | both) carapace_version=$(carapace --version 2>/dev/null | head -n1) ;;
	esac

	printf '环境: bash %s, %s\n' "$BASH_VERSION" "${OSTYPE:-unknown}"
	printf 'argc: %s\n' "$argc_version"
	printf 'carapace: %s\n' "$carapace_version"
	printf '采样: 预热 %s 次，稳态 %s 次；每个场景先执行一次冷调用\n' "$WARMUP" "$ITERATIONS"
	printf '说明: 只计补全函数，不含菜单重绘与终端渲染\n'
}

print_header() {
	case $FORMAT in
	tsv)
		printf 'scenario\tmode\tcandidates\tfirst_ms\tmedian_ms\tmin_ms\tmax_ms\n'
		;;
	markdown)
		printf '| 场景 | 模式 | 候选 | 首次 ms | 中位 ms | 最小 ms | 最大 ms |\n'
		printf '| --- | --- | ---: | ---: | ---: | ---: | ---: |\n'
		;;
	esac
}

print_row() {
	local scenario=$1
	local mode=$2
	local candidates=$3
	local first_ms=$4
	local median=$5
	local min=$6
	local max=$7

	case $FORMAT in
	table)
		printf '%-9s %8s %10s %10s %10s %10s\n' "$mode" "$candidates" "$first_ms" "$median" "$min" "$max"
		;;
	tsv)
		scenario=${scenario//$'\t'/ }
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$scenario" "$mode" "$candidates" "$first_ms" "$median" "$min" "$max"
		;;
	markdown)
		scenario=${scenario//|/\\|}
		# shellcheck disable=SC2016 # 反引号是 Markdown 代码标记，不参与 shell 展开
		printf '| `%s` | %s | %s | %s | %s | %s | %s |\n' "$scenario" "$mode" "$candidates" "$first_ms" "$median" "$min" "$max"
		;;
	esac
}

measure_case() {
	local mode=$1
	local scenario=$2
	local fn

	case $mode in
	argc) fn=_argc_completer ;;
	carapace) fn=_carapace_completer ;;
	esac

	COMP_LINE=$scenario
	COMP_POINT=${#scenario}
	COMP_TYPE=9
	COMP_WORDBREAKS=${COMP_WORDBREAKS:-$' \t\n"\'><=;|&(:'}
	read -r -a COMP_WORDS <<<"$scenario"
	if [[ $scenario == *' ' ]]; then
		COMP_WORDS+=("")
	fi
	COMP_CWORD=$((${#COMP_WORDS[@]} - 1))

	local -a samples=()
	local candidates first_us t0 t1 i

	COMPREPLY=()
	read_us
	t0=$NOW_US
	"$fn" >/dev/null 2>&1
	read_us
	t1=$NOW_US
	first_us=$((t1 - t0))
	candidates=${#COMPREPLY[@]}

	for ((i = 0; i < WARMUP; i++)); do
		COMPREPLY=()
		"$fn" >/dev/null 2>&1
		candidates=${#COMPREPLY[@]}
	done

	for ((i = 0; i < ITERATIONS; i++)); do
		COMPREPLY=()
		read_us
		t0=$NOW_US
		"$fn" >/dev/null 2>&1
		read_us
		t1=$NOW_US
		samples+=($((t1 - t0)))
	done

	print_row "$scenario" "$mode" "$candidates" "$(us_to_ms "$first_us")" \
		"$(median_ms "${samples[@]}")" \
		"$(min_ms "${samples[@]}")" \
		"$(max_ms "${samples[@]}")"
}

main() {
	local scenario mode

	parse_args "$@"
	require_bash5
	load_runtimes
	build_scenarios
	if [[ $FORMAT == table ]]; then
		print_environment
	else
		print_environment >&2
	fi
	print_header

	for scenario in "${SCENARIOS[@]}"; do
		if [[ $FORMAT == table ]]; then
			printf '\n场景: %s\n' "$scenario"
			printf '%-9s %8s %10s %10s %10s %10s\n' '模式' '候选' '首次(ms)' '中位(ms)' '最小(ms)' '最大(ms)'
		fi
		for mode in "${MODES[@]}"; do
			measure_case "$mode" "$scenario"
		done
	done
}

main "$@"
