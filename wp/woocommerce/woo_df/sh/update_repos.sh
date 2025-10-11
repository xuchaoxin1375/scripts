#!/bin/bash
#初次下载代码
#git clone --depth 1 https://gitee.com/xuchaoxin1375/scripts.git /repos/scripts

# 强制更新代码(放弃已有更改)
#git fetch origin
#git reset --hard origin/main
#git pull


# === 配置变量 ===
REPO_URL="https://gitee.com/xuchaoxin1375/scripts.git"
TARGET_DIR="/repos/scripts"
BRANCH="main"  # 或 "master"，根据实际情况调整

# === 确保父目录存在 ===
mkdir -p "$(dirname "$TARGET_DIR")"

echo "🚀 正在同步仓库到最新版本: $TARGET_DIR"

# === 判断目录是否存在，决定是克隆还是更新 ===
if [ ! -d "$TARGET_DIR/.git" ]; then
    # 目录不存在或不是 Git 仓库：执行浅克隆
    echo "📁 未检测到 Git 仓库，正在执行浅克隆..."
    rm -rf "$TARGET_DIR"  # 防止存在非 Git 目录（如普通文件夹）
    git clone --depth 1 "$REPO_URL" "$TARGET_DIR"
    if [ $? -ne 0 ]; then
        echo "❌ 克隆失败，请检查网络或仓库地址"
        exit 1
    fi
    echo "✅ 克隆成功"
else
    # 已存在 Git 仓库：进入目录并强制更新
    echo "🔁 检测到现有仓库，正在强制更新到最新版本..."

    (
        cd "$TARGET_DIR" || { echo "❌ 无法进入目录: $TARGET_DIR"; exit 1; }

        # 确保是预期的仓库（可选安全检查）
        # CURRENT_URL=$(git config --get remote.origin.url)
        # if [ "$CURRENT_URL" != "$REPO_URL" ]; then
        #     echo "⚠️ 仓库地址不匹配，预期: $REPO_URL，实际: $CURRENT_URL"
        #     exit 1
        # fi

        # 获取最新提交信息前先 fetch
        git fetch origin "$BRANCH"

        if [ $? -ne 0 ]; then
            echo "❌ 获取远程更新失败"
            exit 1
        fi

        # 重置到远程分支最新提交
        git reset --hard origin/"$BRANCH"

        # 可选：再次 pull 以确保（虽然 reset --hard 后 pull 不必要，但可刷新）
        # git pull --depth 1 origin "$BRANCH"

        echo "✅ 仓库已强制更新到 origin/$BRANCH 最新版本"
    )
fi

echo "🎉 代码同步完成：$TARGET_DIR"

# 创建或更新nginx配置的必要的文件
bash /www/sh/nginx_conf/update_cf_ip_configs.sh

# 让指定目录下所有脚本文件(.sh)可执行🎈
find /repos/scripts/wp/woocommerce/woo_df/sh/ -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;
# 更新符号链接
# 目录的符号链接(需要小心处理避免出现循环符号链接).可以先移除再创建防止嵌套
# [ -L "/www/sh" ] && rm -f "/www/sh"
if [ -L "/www/sh" ]; then
    echo "Removing existing symbolic link /www/sh"
    rm -rfv "/www/sh"
else
    echo "/www/sh does not exist or is not a symbolic link"
fi

ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/sh -fv
# 文件的符号链接
ln -s /www/sh/deploy_wp_full.sh /deploy.sh -fv
ln -s /www/sh/update_repos.sh /update_repos.sh -fv
ln -s /www/sh/nginx_conf/update_nginx_vhosts_conf.sh /update_nginx_vhosts_conf.sh -fv
# nginx配置文件软链接(这里如果用二级软连接和宝塔的一些操作(比如api)可能冲突,建议使用文件覆盖或则手动覆盖)
# ln -s /www/sh/nginx_conf/com.conf /www/server/nginx/conf/com.conf -fv
# ln -s /www/sh/nginx_conf/nginx.conf /www/server/nginx/conf/nginx.conf -fv

cp /www/sh/nginx_conf/com.conf /www/server/nginx/conf/com.conf -fv
# cp /www/sh/nginx_conf/limit_rate.conf /www/server/nginx/conf/limit_rate.conf -fv
cp /www/sh/nginx_conf/nginx.conf /www/server/nginx/conf/nginx.repos.conf -fv

# 让nginx重新加载配置🎈
nginx -t && nginx -s reload