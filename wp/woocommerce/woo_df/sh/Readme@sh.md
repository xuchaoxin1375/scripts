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


# 让指定目录下所有脚本文件(.sh)可执行🎈
find /repos/scripts/wp/woocommerce/woo_df/sh/ -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;
# 更新符号链接
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /deploy.sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /www/wwwroot/deploy_wp_full.sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/wwwroot/sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/nginx_conf/update_nginx_vhosts_conf.sh /update_nginx_vhosts_conf.sh -f
```

## 定时自动任务crontab

使用`crontab -e`选择编辑器编辑自动任务,添加以下内容(可以自定义执行时间)

```bash
0 * * * * /www/wwwroot/sh/deploy_wp_schd.sh
```

注意脚本`deploy_wp_schd.sh`这个脚本的可执行权限(每次更新代码,上面的代码会尝试自动修改这些文件的可执行权限)

## nginx公共配置文件com.conf

对于宝塔用户,可以在`/www/server/nginx/conf`目录下创建一个`com.conf`的配置文件

> 在相关配套脚本的作用下,会在创建站点的时候一并往站点的vhost目录(`/www/server/panel/vhost/nginx/`目录下的`<domain.xxx>.conf`)下配置文件插入一行引用此`com.conf`的指令

下面是基本`com.conf`的基本指令内容,可以根据需要统一在这个配置文件中修改;

每次有需求修改完成后需要重载nginx配置才能逐渐生效`nginx -t && nginx -s reload` (如果语法有误,会报错,如果通过检测,就会重载配置)

```bash
# --- 拦截 xmlrpc.php ---
# location = /xmlrpc.php {
#     deny all;
#     # 返回 444 断开连接（比 403 更隐蔽）
#     # return 444;
# }
location = /xmlrpc.php {
    deny all;
    return 403;
}

# 精确匹配：/wp-admin
location = /wp-admin {
    return 403;
}
# 粗暴禁止访问或跳转到/wp-login.php,部分情况会拦住自己人,如有特殊需要,可以临时开放
# 通常,配合wps-hide-login通常都可以完美让自己人使用专门的后台入口顺利登录(如果被拦截,可能是该插件没启用或者目录名称被改动导致插件失效)
location = /wp-login.php{
    return 403;
}



# --- 保护 wp-cron.php（可选）---
# 正常应由内部触发，不建议公开访问
location = /wp-cron.php {
    # deny all;  # 如果你用系统 cron 替代
    allow 127.0.0.1;  # 只允许本地或 Cloudflare（谨慎）
    # allow 172.68.0.0/16;  # Cloudflare IP 段（可选）
    deny all;
}

# --- 可选：拦截高频 bot 请求 ---
# location / {
#     limit_req zone=bots nodelay;
#     # 正常流量继续
#     try_files $uri $uri/ /index.php?$args;
# }

  
```

### 为指定目录重命名

例如,为`wps-hide-login.bak`(临时被禁用的插件)重命名为`wps-hide-login`的命令行:

```powershell
Get-ChildItem . -Recurse -Depth 5 -filter 'wps-hide-login.bak' -Directory|%{Rename-Item $_ -NewName ($_ -replace '\.bak$','' ) -Verbose}
```

