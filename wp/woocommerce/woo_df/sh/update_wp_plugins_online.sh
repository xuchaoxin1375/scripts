#!/bin/bash

# =============================================
# WordPress 批量插件更新脚本 (支持并行)
# 适用路径结构: /www/wwwroot/<user_abber>/<domain>/wordpress/
# WP-CLI 调用方式: sudo -u www wp

# 功能和需求:
# 编写bash脚本,调用wp-cli将一批wordpress站点中的指定插件更新到最新版本(我一般使用sudo -u www wp代替wp)
# 这些网站的根目录结构:/www/wwwroot/<user_abber>/<domain>/wordpress/
# 代码功能完备,执行过程中适当输出信息和进度反馈
# 最好是能够并行执行提高效率
# 支持命令行方式调用,通过参数指定工作目录(默认为/www/wwwroot/);允许指定1个或多个插件名字
# =============================================

set -euo pipefail  # 严格模式

# 默认参数
ROOT_DIR="/www/wwwroot"
WP_USER="www"
MAX_JOBS=8  # 并行任务数，根据 CPU 调整

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 帮助函数
show_help() {
    echo "用法: $0 [选项] 插件1 [插件2 ...]"
    echo
    echo "选项:"
    echo "  -d DIR     指定 WordPress 根目录 (默认: $ROOT_DIR)"
    echo "  -j N       并行任务数 (默认: $MAX_JOBS)"
    echo "  -h         显示此帮助"
    echo
    echo "示例:"
    echo "  $0 woocommerce"
    echo "  $0 -d /my/sites woocommerce elementor"
    echo "  $0 -j 4 woocommerce"
    exit 0
}

# 解析命令行参数
while getopts "d:j:h" opt; do
    case $opt in
        d) ROOT_DIR="$OPTARG" ;;
        j) MAX_JOBS="$OPTARG" ;;
        h) show_help ;;
        *) show_help ;;
    esac
done
shift $((OPTIND-1))

# 检查是否指定插件
if [ $# -eq 0 ]; then
    echo -e "${RED}错误: 请至少指定一个插件名称${NC}"
    show_help
fi

PLUGINS=("$@")
PLUGIN_ARGS=$(printf " %s" "${PLUGINS[@]}")
PLUGIN_LIST=$(IFS=,; echo "${PLUGINS[*]}")

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}WordPress 批量插件更新工具${NC}"
echo -e "${BLUE}根目录: $ROOT_DIR${NC}"
echo -e "${BLUE}目标插件: $PLUGIN_LIST${NC}"
echo -e "${BLUE}并行任务数: $MAX_JOBS${NC}"
echo -e "${BLUE}============================================${NC}"

# 检查 parallel 是否安装
if ! command -v parallel >/dev/null 2>&1; then
    echo -e "${YELLOW}警告: GNU parallel 未安装，将串行执行（速度较慢）${NC}"
    echo "建议安装: apt install parallel 或 yum install parallel"
    USE_PARALLEL=false
else
    USE_PARALLEL=true
fi

# 查找所有 WordPress 站点
echo -e "${YELLOW}🔍 正在扫描站点...${NC}"
SITES=()
while IFS= read -r -d '' site; do
    SITES+=("$site")
done < <(find "$ROOT_DIR" -path "*/wordpress/wp-config.php" -print0 2>/dev/null | sed -z 's|/wp-config.php$||')

if [ ${#SITES[@]} -eq 0 ]; then
    echo -e "${RED}未找到任何 WordPress 站点。请检查路径结构。${NC}"
    exit 1
fi

TOTAL_SITES=${#SITES[@]}
echo -e "${GREEN}✅ 找到 $TOTAL_SITES 个站点${NC}"
echo

# 更新单个站点的函数（供 parallel 调用）
update_site() {
    local site_path="$1"
    local plugins=("$2") # 传递插件字符串，内部再分割
    local start_time=$(date +%s)

    # 提取域名用于显示
    domain=$(basename "$(dirname "$site_path")")

    {
        cd "$site_path"

        # 检查插件是否已安装
        for plugin in $plugins; do
            if ! sudo -u "$WP_USER" wp plugin is-installed "$plugin" 2>/dev/null; then
                echo "❌ [$domain] 插件 '$plugin' 未安装，跳过"
                return 1
            fi
        done

        # 检查是否有更新
        needs_update=false
        for plugin in $plugins; do
            if sudo -u "$WP_USER" wp plugin list --name="$plugin" --field=update --format=csv 2>/dev/null | grep -q "available"; then
                needs_update=true
                break
            fi
        done

        if [ "$needs_update" = false ]; then
            echo "ℹ️  [$domain] 所有插件已是最新版"
            return 0
        fi

        # 执行更新
        if sudo -u "$WP_USER" wp plugin update $plugins --quiet 2>/dev/null; then
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            echo "✅ [$domain] 更新成功 (耗时 ${duration}s)"
        else
            echo "❌ [$domain] 更新失败"
            return 1
        fi

    } 2>&1
}

export -f update_site
export WP_USER

# 执行更新
echo -e "${BLUE}🚀 开始批量更新...${NC}"

if [ "$USE_PARALLEL" = true ]; then
    # 使用 parallel 并行执行
    printf '%s\n' "${SITES[@]}" | parallel -j "$MAX_JOBS" --line-buffer --tagstring "{#}" "update_site {} \"$PLUGIN_ARGS\""
else
    # 串行执行
    for site in "${SITES[@]}"; do
        update_site "$site" "$PLUGIN_ARGS"
    done
fi

echo
echo -e "${GREEN}🎉 批量更新完成！${NC}"
echo -e "${BLUE}共处理 ${TOTAL_SITES} 个站点${NC}"