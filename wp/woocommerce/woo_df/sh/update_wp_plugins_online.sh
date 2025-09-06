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

set -euo pipefail

# 默认参数
ROOT_DIR="/www/wwwroot"
WP_USER="www"
MAX_JOBS=8
MAX_DEPTH=4

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_help() {
    echo "用法: $0 [选项] 插件1 [插件2 ...]"
    echo
    echo "选项:"
    echo "  -d DIR        指定 WordPress 根目录 (默认: $ROOT_DIR)"
    echo "  -j N          并行任务数 (默认: $MAX_JOBS)"
    echo "  --maxdepth N  find 命令最大扫描深度 (默认: $MAX_DEPTH)"
    echo "  -h            显示此帮助"
    echo
    echo "示例:"
    echo "  $0 woocommerce"
    echo "  $0 -d /my/sites --maxdepth 3 woocommerce"
    echo "  $0 elementor woocommerce"
    exit 0
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -d)
            ROOT_DIR="$2"
            shift 2
            ;;
        -j)
            MAX_JOBS="$2"
            shift 2
            ;;
        --maxdepth)
            MAX_DEPTH="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        -*)
            echo -e "${RED}未知选项: $1${NC}" >&2
            show_help
            ;;
        *)
            break
            ;;
    esac
done

PLUGINS=("$@")
if [ ${#PLUGINS[@]} -eq 0 ]; then
    echo -e "${RED}错误: 请至少指定一个插件名称${NC}"
    show_help
fi

PLUGIN_ARGS=$(printf " %s" "${PLUGINS[@]}")
PLUGIN_LIST=$(IFS=,; echo "${PLUGINS[*]}")

# 检查是否包含 woocommerce
UPDATE_WC_DB=false
for plugin in "${PLUGINS[@]}"; do
    if [[ "$plugin" == "woocommerce" ]]; then
        UPDATE_WC_DB=true
        break
    fi
done

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}WordPress 批量插件更新工具${NC}"
echo -e "${BLUE}根目录: $ROOT_DIR${NC}"
echo -e "${BLUE}扫描深度: $MAX_DEPTH${NC}"
echo -e "${BLUE}目标插件: $PLUGIN_LIST${NC}"
if [ "$UPDATE_WC_DB" = true ]; then
    echo -e "${BLUE}📦 将在更新后自动执行 WooCommerce 数据库升级${NC}"
fi
echo -e "${BLUE}并行任务数: $MAX_JOBS${NC}"
echo -e "${BLUE}============================================${NC}"

# 检查 parallel
if ! command -v parallel >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  GNU parallel 未安装，将串行执行${NC}"
    USE_PARALLEL=false
else
    USE_PARALLEL=true
fi

# 扫描站点
echo -e "${YELLOW}🔍 正在扫描 WordPress 站点 (最大深度: $MAX_DEPTH)...${NC}"

SITES=()
while IFS= read -r -d '' wp_config; do
    site_dir=$(dirname "$wp_config")
    if [ -d "$site_dir" ] && [ -f "$site_dir/wp-load.php" ]; then
        SITES+=("$site_dir")
        domain=$(basename "$(dirname "$site_dir")")
        echo -e "${CYAN}📁 发现站点: $domain → $site_dir${NC}"
    fi
done < <(find "$ROOT_DIR" -maxdepth "$MAX_DEPTH" -path "*/wordpress/wp-config.php" -print0 2>/dev/null)

if [ ${#SITES[@]} -eq 0 ]; then
    echo -e "${RED}❌ 未找到任何 WordPress 站点。请检查路径或调整 --maxdepth。${NC}"
    exit 1
fi

TOTAL_SITES=${#SITES[@]}
echo -e "${GREEN}✅ 扫描完成，共找到 $TOTAL_SITES 个站点${NC}"
echo

# ==============================
# 函数：更新插件 + 可选更新 WC DB
# ==============================
update_site() {
    local site_path="$1"
    local plugins="$2"
    local start_time=$(date +%s)

    domain=$(basename "$(dirname "$site_path")")

    {
        cd "$site_path" 2>/dev/null || { echo "❌ [$domain] 无法进入目录"; return 1; }

        # 检查插件是否安装
        for plugin in $plugins; do
            if ! sudo -u "$WP_USER" wp plugin is-installed "$plugin" 2>/dev/null; then
                echo "⚠️  [$domain] 插件 '$plugin' 未安装，跳过"
                return 0
            fi
        done

        # 检查是否需要更新插件
        needs_plugin_update=false
        for plugin in $plugins; do
            if sudo -u "$WP_USER" wp plugin list --name="$plugin" --field=update --format=csv 2>/dev/null | grep -q "available"; then
                needs_plugin_update=true
                break
            fi
        done

        plugin_updated=false
        if [ "$needs_plugin_update" = true ]; then
            if sudo -u "$WP_USER" wp plugin update $plugins --quiet 2>/dev/null; then
                plugin_updated=true
                echo "✅ [$domain] 插件更新成功"
            else
                echo "❌ [$domain] 插件更新失败"
                return 1
            fi
        else
            echo "ℹ️  [$domain] 插件已是最新版"
        fi

        # ================ WooCommerce 数据库更新逻辑 ================
        if [ "$UPDATE_WC_DB" = true ]; then
            # 检查 WooCommerce 是否激活
            if ! sudo -u "$WP_USER" wp plugin is-active woocommerce 2>/dev/null; then
                echo "⚠️  [$domain] WooCommerce 未激活，跳过数据库更新"
            else
                # 检查是否需要 DB 更新
                if sudo -u "$WP_USER" wp wc tool list --format=csv 2>/dev/null | grep -q "update_db"; then
                    echo "🔧 [$domain] 检测到 WooCommerce 数据库需要更新，正在执行..."
                    if sudo -u "$WP_USER" wp wc update --quiet 2>/dev/null; then
                        echo "✅ [$domain] WooCommerce 数据库更新成功"
                    else
                        echo "❌ [$domain] WooCommerce 数据库更新失败"
                        return 1
                    fi
                else
                    echo "ℹ️  [$domain] WooCommerce 数据库已是最新"
                fi
            fi
        fi

        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo "⏱️  [$domain] 本站点总耗时: ${duration} 秒"

    } 2>&1
}

export -f update_site
export WP_USER
export UPDATE_WC_DB

# 执行更新
echo -e "${BLUE}🚀 开始批量更新...${NC}"

if [ "$USE_PARALLEL" = true ]; then
    printf '%s\n' "${SITES[@]}" | parallel -j "$MAX_JOBS" --line-buffer "update_site {} \"$PLUGIN_ARGS\""
else
    for site in "${SITES[@]}"; do
        update_site "$site" "$PLUGIN_ARGS"
    done
fi

echo
echo -e "${GREEN}🎉 批量更新完成！共处理 ${TOTAL_SITES} 个站点${NC}"