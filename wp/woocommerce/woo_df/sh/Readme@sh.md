[toc]



## abstract

运行在linux上的脚本以及相关配置

相关命令行以ubuntu/debian系为例

### 获取或更新脚本代码

```bash
git clone --depth 1 https://gitee.com/xuchaoxin1375/scripts.git /repos/scripts
```

如果仅更新脚本仓库,则可以

```bash
git fetch origin
git reset --hard origin/main
git pull
```



### 配置系统时间为北京时间



```bash
sudo timedatectl set-timezone Asia/Shanghai
```

### 配置可执行权限

```bash
# 这里配置脚本文件(.sh)的可执行属性
chmod +x /repos/scripts/wp/woocommerce/woo_df/sh/*
# 让指定目录下所有脚本文件(.sh)可执行
find /repos/scripts/wp/woocommerce/woo_df/sh/ -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;

# 配置单个脚本可执行属性
#chmod +x /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh

```



### 配置符号链接

```bash
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /deploy.sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /www/wwwroot/deploy_wp_full.sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/wwwroot/sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/nginx_conf/update_nginx_vhosts_conf.sh /update_nginx_vhosts_conf.sh -f
```



### 部署wp网站

```bash
$ /deploy.sh --help
用法: /deploy.sh [选项]
选项:
  --pack-root DIR   设置压缩包根目录 (默认: /srv/uploads/uploader/files)
  --db-user USER    设置数据库用户名 (默认: root)
  --db-pass PASS    设置数据库密码
  --user-dir DIR    仅处理指定用户目录
  --help            显示此帮助信息

```

## 综合脚本

```bash
#初次下载代码
#git clone --depth 1 https://gitee.com/xuchaoxin1375/scripts.git /repos/scripts

# 强制更新代码(放弃已有更改)
#git fetch origin
#git reset --hard origin/main
#git pull

#!/bin/bash

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


# 让指定目录下所有脚本文件(.sh)可执行
find /repos/scripts/wp/woocommerce/woo_df/sh/ -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;
# 更新符号链接
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /deploy.sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /www/wwwroot/deploy_wp_full.sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/wwwroot/sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/nginx_conf/update_nginx_vhosts_conf.sh /update_nginx_vhosts_conf.sh -f
```

