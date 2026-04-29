#!/bin/bash
# 针对个人电脑(windows(wsl),macos,linux)的shell配置部署/更新脚本
# 如果没有部署过,则完整克隆,否则执行代码更新
# bash <( curl -sSfL https://gitee.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/update_shell_config.sh)
# 服务器版本的参考deploy_srv.sh,update_repos.sh脚本

version=20260419
REPO_SOURCE='github.com'
BRANCH="main" # 或 "master"，根据实际情况调整

repos="$HOME/repos"
scripts="$repos/scripts"
sh_script_dir="$scripts/wp/woocommerce/woo_df/sh"
SCRIPT_ROOT="$scripts"

SH_SYM="$HOME/sh" # 假设服务器上有root权限,并能够创建/www/sh 目录
show_help() {
    cat << EOF
    针对个人电脑(windows(wsl),macos,linux)的shell配置部署/更新脚本.

    version: $version
    Usage:  
        $0 [options]
    Options:
        -r,--repo-source       指定代码仓库源(github.com,gitee.com)
        -h,--help       显示帮助
EOF
}
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r | --repo-source)
                REPO_SOURCE="$2"
                shift
                ;;
            -b | --branch)
                BRANCH="$2"
                shift
                ;;
            -h | --help)
                show_help
                exit 0
                ;;
            --) # end of options
                shift
                break
                ;;
            -*)
                echo "Unknown option: $1"
                show_help
                exit 2
                ;;
            *)
                # positional arg (not used) – ignore for now
                shift
                ;;
        esac
        shift
    done
}
parse_args "$@"
# 代码仓库来源
REPO_URL="https://${REPO_SOURCE}.com/xuchaoxin1375/scripts.git"
URL_GITEE="https://gitee.com/xuchaoxin1375/scripts.git"
URL_GITHUB="https://github.com/xuchaoxin1375/scripts.git"
URL_GITLAB="https://gitlab.com/xuchaoxin1375/scripts.git"
echo "clone repository source: $REPO_SOURCE;from git: $REPO_URL"

# ===更新代码===

# 确保父目录存在
mkdir -p "$(dirname "$SCRIPT_ROOT")"

echo "🚀 正在同步仓库到最新版本: $SCRIPT_ROOT"

if [[ $REMOVE_OLD -eq 1 ]]; then
    echo "🗑️ 删除旧仓库..."
    rm -rf "$SCRIPT_ROOT"
fi
# 判断目录是否存在，决定是克隆还是更新

# 定义源的优先级(尝试顺序数组)：将指定的 REPO_SOURCE 放在首位，其他作为备份
case "$REPO_SOURCE" in
    "github") SOURCES=("$URL_GITHUB" "$URL_GITEE" "$URL_GITLAB") ;;
    "gitlab") SOURCES=("$URL_GITLAB" "$URL_GITHUB" "$URL_GITEE") ;;
    *) SOURCES=("$URL_GITEE" "$URL_GITHUB" "$URL_GITLAB") ;; # 默认 Gitee 优先
esac

# 目录不存在或不是 Git 仓库：执行浅克隆
if [ ! -d "$SCRIPT_ROOT/.git" ]; then

    # 准备工作：清理可能存在的残留目录
    echo "📁 未检测到有效 Git 仓库，正在准备执行浅克隆..."
    rm -rf "$SCRIPT_ROOT"

    #  循环尝试序列中的仓库源
    CLONE_SUCCESS=false
    for URL in "${SOURCES[@]}"; do
        [ -z "$URL" ] && continue # 跳过空地址

        echo "📡 尝试从 $URL 克隆..."
        # --depth 1 配合 --single-branch
        if git clone --progress --depth 1 --single-branch -b "$BRANCH" "$URL" "$SCRIPT_ROOT"; then
            echo "✅ 克隆成功！(源: $URL)"
            CLONE_SUCCESS=true
            break
        else
            echo "⚠️  该源连接失败，尝试下一个..."
            rm -rf "$SCRIPT_ROOT" # 关键：失败后必须清理目录，否则下次 clone 会报错
        fi
    done

    #  最终检查
    if [ "$CLONE_SUCCESS" = false ]; then
        echo "❌ 所有远程源均克隆失败，请检查网络！"
        exit 1
    fi
else
    # 已存在 Git 仓库：进入目录并强制更新
    echo "🔁 检测到现有仓库，正在强制更新到最新版本..."

    (
        cd "$SCRIPT_ROOT" || {
            echo "❌ 无法进入目录: $SCRIPT_ROOT"
            exit 1
        }
        # 循环尝试序列中的仓库源(自动重试方案)
        UPDATE_SUCCESS=false # 初始化状态开关

        for URL in "${SOURCES[@]}"; do
            [ -z "$URL" ] && continue

            echo "📡 尝试从 $URL 更新..."

            # 1. 动态设置远程地址 (这里建议直接用 $URL 变量，而不是 $REPO_URL)
            if ! git remote set-url origin "$URL"; then
                echo "⚠️  无法设置远程地址，尝试下一个源..."
                continue
            fi

            # 2. 执行 Fetch
            echo "📥 正在拉取分支 $BRANCH..."
            if git fetch origin "$BRANCH"; then
                # --- 如果 fetch 成功，进入重置阶段 ---
                echo "✅ Fetch 成功，正在同步本地代码..."

                if git reset --hard origin/"$BRANCH"; then
                    echo "✨ 仓库已成功更新到源: $URL"
                    UPDATE_SUCCESS=true
                    break # 【关键】跳出 for 循环，不再尝试后续的源
                fi
            else
                echo "⚠️  源 $URL 连接失败或分支不存在，尝试下一个..."
            fi
        done

        # 最后检查是否所有源都失败了
        if [ "$UPDATE_SUCCESS" = false ]; then
            echo "❌ 错误：所有配置的远程源均无法完成更新！"
            exit 1
        fi

        # 单次尝试方案

        #  定义不同源的仓库基础地址 (根据你的实际情况修改)
        # case "$REPO_SOURCE" in
        #     "github")
        #         REPO_URL=$URL_GITHUB
        #         ;;
        #     "gitlab")
        #         REPO_URL=$URL_GITLAB
        #         ;;
        #     "gitee")
        #         REPO_URL=$URL_GITEE
        #         ;;
        #     *)
        #         echo "⚠️ 未知的 REPO_SOURCE: $REPO_SOURCE，将尝试使用当前配置的 origin"
        #         REPO_URL=""
        #         ;;
        # esac

    )

fi

echo "🎉 代码同步完成：$SCRIPT_ROOT"
# 可选的配置shell脚本库（兼容bash，zsh)
# ! [[ -L $sh_sym ]] &&
ln -snfv "$sh_script_dir" "$SH_SYM"
# wsl的ble.sh用户专属配置
if [ -e '/mnt/' ]; then
    blerc="$SH_SYM/env_sh/.blerc"
    [ -e "$blerc" ] && ln -snfv "$blerc" "$HOME/.blerc"
fi
# 部署shell 交互方案(prompt主题和补全方案)
bash "$SH_SYM"/shellrc_addition.sh # 内部不执行进程替换
# 进程替换
# exec bash
