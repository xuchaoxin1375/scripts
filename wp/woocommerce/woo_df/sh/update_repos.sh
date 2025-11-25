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

# CLI flags
FORCE=0

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -f, --force    强制执行（用于覆盖 nginx.conf 并跳过交互或保护性检查）
  -h, --help     显示本帮助信息并退出

This script will clone or update the git repository at $TARGET_DIR and
update several symlinks and nginx configuration files. Use --force to
allow the script to backup and overwrite /www/server/nginx/conf/nginx.conf
when applicable.
EOF
}

# Parse args (simple POSIX-compatible loop)
while [ "$#" -gt 0 ]; do
    case "$1" in
        -f|--force)
            FORCE=1
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        --) # end of options
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1"
            print_usage
            exit 2
            ;;
        *)
            # positional arg (not used) – ignore for now
            shift
            ;;
    esac
done

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

rm -rfv /www/pys

ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/sh -fv
ln -s /repos/scripts/wp/woocommerce/woo_df/pys /www/pys -fv
# 文件的符号链接
ln -s /www/sh/deploy_wp_full.sh /deploy.sh -fv
ln -s /www/sh/update_repos.sh /update_repos.sh -fv
ln -s /www/sh/nginx_conf/update_nginx_vhosts_conf.sh /update_nginx_vhosts_conf.sh -fv
# nginx配置文件软链接(这里如果用二级软连接和宝塔的一些操作(比如api)可能冲突,建议使用文件覆盖或则手动覆盖)
# ln -s /www/sh/nginx_conf/com.conf /www/server/nginx/conf/com.conf -fv
# ln -s /www/sh/nginx_conf/nginx.conf /www/server/nginx/conf/nginx.conf -fv

if [ -f /www/server/nginx/conf/com.conf ]; then
    rm  /www/server/nginx/conf/com.conf -fv
fi
cp /www/sh/nginx_conf/com.conf /www/server/nginx/conf/com.conf -fv
# cp /www/sh/nginx_conf/limit_rate.conf /www/server/nginx/conf/limit_rate.conf -fv
cp /www/sh/nginx_conf/nginx.conf /www/server/nginx/conf/nginx.repos.conf -fv
# todo
# 如果启用了 --force 选项,则备份宝塔的 nginx.conf 文件 (/www/server/nginx/conf/nginx.conf)
# 并使用 /www/sh/nginx_conf/nginx.conf 覆盖宝塔的 nginx.conf 文件
if [ "$FORCE" -eq 1 ]; then
    NGINX_CONF_DIR="/www/server/nginx/conf"
    NGINX_CONF_FILE="$NGINX_CONF_DIR/nginx.conf"
    BACKUP_TS=$(date +%Y%m%d) # %H%M%S
    if [ -f "$NGINX_CONF_FILE" ]; then
        echo "🔒 Force enabled: backing up existing nginx.conf to ${NGINX_CONF_FILE}.bak.${BACKUP_TS}"
        cp -fv "$NGINX_CONF_FILE" "${NGINX_CONF_FILE}.bak.${BACKUP_TS}"
    else
        echo "ℹ️ No existing nginx.conf to backup at $NGINX_CONF_FILE"
    fi

    echo "🔁 Overwriting $NGINX_CONF_FILE with /www/sh/nginx_conf/nginx.conf"
    cp -fv /www/sh/nginx_conf/nginx.conf "$NGINX_CONF_FILE"
# else
#     echo "ℹ️ --force not set: skipping overwrite of /www/server/nginx/conf/nginx.conf"
fi

# 让nginx重新加载配置🎈
nginx -t && nginx -s reload

# fail2ban配置文件
# 如果/etc/fail2ban/fai2ban.repos事先存在则先删除
f2b_repos='/etc/fail2ban/fai2ban.repos'
if [ -d $f2b_repos ]; then
    echo "🗑️  删除已存在的符号链接或目录: $f2b_repos"
    rm -rfv "$f2b_repos"
fi
# 仓库中的fail2ban配置目录软链接到/etc/fail2ban/下(便于编辑器内编辑时参考)
ln -s /www/sh/fail2ban/ $f2b_repos -fv
# 为常用的nginx配置文件软链接
ln -s /www/sh/fail2ban/filter.d/nginx-warn.conf /etc/fail2ban/filter.d/nginx-warn.conf -fv
ln -s /www/sh/fail2ban/jail.d/nginx-cf-warn.conf /etc/fail2ban/jail.d/nginx-cf-warn.local -fv
# 如果cloudflare.local不存在,则创建此文件的软链接,否则跳过此步(避免将已有配置覆盖,尤其是cf的账号和密钥信息)
# 不同服务器使用的cf账号通常不同,并且有的服务器可能用到多个cf账号,这就需要服务器管理员基于此文件(或者fail2ban自带的action.d克隆几个名称相似但不同的cloduflare*.conf和cloudflare*.local文件组合,不过更改只需要更改.local即可,克隆的.conf文件不需要更改,只是文件名不同了)
# 多余多账号cf,还需考虑对应jail中的action引用的变化(名称跟着变化),也是使用个类似定义的jail section
# 配置结果:通过fail2ban-client reload一下,相关jail的最终配置会被打印,如果和预期不同,考虑配置文件间的覆盖关系
if [ ! -f /etc/fail2ban/action.d/cloudflare.local ]; then
    ln -s /www/sh/fail2ban/action.d/cloudflare.conf /etc/fail2ban/action.d/cloudflare.local -fv
fi