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
ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/sh -f
 

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

为了方便期间,将脚本组织成一个脚本文件`update_repos.sh`,下面有两段代码

较长的王政代码第一次运行后,就可以用简化版本

### 简化版本

!第一次运行需要完整版本

```bash
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/update_repos.sh /update_repos.sh -f
```

### 完整版本

```bash
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


# 让指定目录下所有脚本文件(.sh)可执行🎈
find /repos/scripts/wp/woocommerce/woo_df/sh/ -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;

# 更新符号链接
ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /deploy.sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /www/wwwroot/deploy_wp_full.sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/update_repos.sh /update_repos.sh -f
 

```

## 定时自动任务crontab🎈

使用`crontab -e`选择编辑器编辑自动任务,添加以下内容(可以自定义执行时间)

```bash
0 * * * * bash /www/sh/deploy_wp_schd.sh #定时部署解压wp站(每个小时0分的时候执行一次)
*/5 * * * * bash /www/sh/run-all-wp-cron.sh #定时执行wp-cron(每5分钟执行1次)
```

注意脚本`deploy_wp_schd.sh`这个脚本的可执行权限(每次更新代码,上面的代码会尝试自动修改这些文件的可执行权限)

利用系统的crontab定时执行wp-cron,这里的脚本利用了`wp-cli`命令行工具来触发,而不需要通过http链接触发,执行后有日志文件



## nginx配置

### 总配置nginx.conf

放在`http{}`块中

```nginx
# 可选：针对可疑 User-Agent 或空 User-Agent 限流
map $http_user_agent $allow_access {
    default 0;

    # 允许常见浏览器
    "~*chrome"     1;
    "~*firefox"    1;
    "~*safari"     1;
    "~*edge"       1;
    "~*opera"      1;

    # 允许 Google / Bing
    "~*googlebot"  1;
    "~*bingbot"    1;
    # 允许 wp定时任务请求
    "~*wordpress"   1;
}
```



### 公共配置文件com.conf

对于宝塔用户,可以在`/www/server/nginx/conf`目录下创建一个`com.conf`的配置文件

> 在相关配套脚本的作用下,会在创建站点的时候一并往站点的vhost目录(`/www/server/panel/vhost/nginx/`目录下的`<domain.xxx>.conf`)下配置文件插入一行引用此`com.conf`的指令

下面是基本`com.conf`的基本指令内容,可以根据需要统一在这个配置文件中修改;

每次有需求修改完成后需要重载nginx配置才能逐渐生效`nginx -t && nginx -s reload` (如果语法有误,会报错,如果通过检测,就会重载配置)

```bash



# --- 拦截 xmlrpc.php ---
location = /xmlrpc.php {
    deny all;
    # 返回 444 断开连接（比 403 更隐蔽）
    return 444;
    # return 403;
}

# 精确匹配：/wp-admin
location = /wp-admin {
    return 403;
}
# 粗暴禁止访问或跳转到/wp-login.php,配置不当的话部分情况会拦住自己人,如有特殊需要,可以临时开放
# (通常正确安装并激活wps-hide-login后不会被此规则拦截,自己人使用约定的入口url可以登录后台)
location = /wp-login.php{
    return 403;
}
# 拒绝非 Google/Bing 爬虫
if ($allow_access = 0) {
    return 444; # 直接断开连接
}
# if ($allowed_bot = 0) {
#     return 403;
# }
# --- 保护 wp-login.php ---
# location = /wp-login.php {
#     limit_req zone=wplogin burst=1 nodelay;

#     # 可选：仅允许特定 IP 登录（推荐！）
#     # allow 192.168.1.100;   # 你的办公 IP
#     # deny all;

#     # 允许 POST（登录提交），但限制频率
#     # try_files $uri =404;
#     # include /etc/nginx/fastcgi_params;
#     # fastcgi_pass php_backend;
#     # fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
# }



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

## 有用的指令

使用powershell(跨平台的pwsh)方案执行以下任务,记录备用

### 批量重命名wps-hide-login目录

例如,为`wps-hide-login.bak`(临时被禁用的插件)重命名为`wps-hide-login`的命令行:

```powershell
Get-ChildItem . -Recurse -Depth 5 -filter 'wps-hide-login.bak' -Directory|%{Rename-Item $_ -NewName ($_ -replace '\.bak$','' ) -Verbose}
```

### 批量激活wp网站插件

首先扫描出所有wordpress站的根目录

#### 本地windows端

批量激活插件(比如`wps-hide-login`)

首先`cd`到所有网站所在的总目录,然后扫描各个站点根目录(根据情况修改管道符前面的命令)

```powershell
#⚡️[Administrator@CXXUDESK][C:\sites\wp_sites][14:41:03][UP:6.97Days]
PS> ls *.* -Directory|%{cd $_;wp plugin activate wps-hide-login ;cd -}

```

详细步骤:

- 为了获取插件名以便设置(启用/禁用/更新),可以使用`wp plugin list`命令行列出所有插件的标准名字

```bash
$ sudo -u www wp plugin list
+---------------------------------------+----------+-----------+-----------------+----------------+-------------+
| name                                  | status   | update    | version         | update_version | auto_update |
+---------------------------------------+----------+-----------+-----------------+----------------+-------------+
| astra-addon                           | active   | available | 4.8.14          | 4.11.6         | off         |
| clowns-discount                       | active   | none      | Current Version |                | off         |
| mallpay                               | active   | none      | 2.0             |                | off         |
| elementor                             | active   | available | 3.27.7          | 3.31.1         | off         |
| elementor-pro                         | active   | available | 3.27.4          | 3.30.0         | off         |
| paypal-online-payment-for-woocommerce | active   | none      | 1.1.0           |                | off         |
| astra-pro-sites                       | inactive | available | 4.4.11          | 4.4.34         | off         |
| wp-card-tpay                          | active   | none      | 1.2             |                | off         |
| woocommerce                           | active   | available | 9.6.2           | 10.0.4         | off         |
| wps-hide-login                        | inactive | available | 1.9.17.1        | 1.9.17.2       | off         |
| wordpress-seo                         | active   | available | 25.2            | 25.6           | off         |
| yunzipaycc-for-woocommerce            | active   | none      | 1.0.0           |                | off         |
| custom-shortcodes                     | must-use |           |                 |                | off         |
+---------------------------------------+----------+-----------+-----------------+----------------+-------------+
```



- 扫描所有网站根目录

  ```powershell
  $dirs=Get-ChildItem -Recurse -Directory -Depth 2 -Path */wordpress |select -ExpandProperty FullName;$dirs
  
  ```

- 并行激活

  ```bash
  $dirs|% -Parallel {cd $_;sudo -u www wp plugin activate wps-hide-login } -ThrottleLimit 10
  ```

### 禁用wp定时任务wp-cron

powershell批量修改本地wp站点的`wp-config.php`（也可以考虑尝试wp-cli配置）

```bash

using namespace System.Collections.Generic
$configs = Get-ChildItem $wp_sites/*.* -Depth 2 -File -Filter wp-config.php | Select-Object -ExpandProperty FullName 

$configs | ForEach-Object {
    
    #修改单个wp-config.php内容(不立刻回写)
    # $Path = ".\wp-config.php"
    $Path = $_
    $strList = [System.Collections.Generic.List[string]]::new()
    Get-Content $Path | ForEach-Object { 
        if( $_ -match '.*Add any custom.*')
        {
            $t = $_ + @"

define('DISABLE_WP_CRON', true);#禁用wp-cron任务,使用系统定时任务代替

"@
        }
        else { $t = $_ } 
        $strList.Add($t)

    } 
    $strList | Set-Content -Path $Path -Encoding UTF8 -Force 
}
```

