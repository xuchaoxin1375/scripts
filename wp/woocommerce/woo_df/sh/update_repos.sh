#!/bin/bash
#初次下载代码
#git clone --depth 1 https://gitee.com/xuchaoxin1375/scripts.git /repos/scripts

# 强制更新代码(放弃已有更改)
#git fetch origin
#git reset --hard origin/main
#git pull

version=20260321
REPO_SOURCE='gitee' # gitee或github (gitee可能对国外ip服务器用户限流或要求注册账号)
echo "当前脚本版本: $version;clone repository source: $REPO_SOURCE"
NGINX_CONF_DIR="/www/server/nginx/conf"
NGINX_CONF_FILE="$NGINX_CONF_DIR/nginx.conf"
# nginx主配置文件源(用于覆盖服务器上的旧版本)
NGINX_CONF_TPL_DIR="/www/sh/nginx_conf"
NGINX_CONF_TPL_STD="$NGINX_CONF_TPL_DIR/nginx_nginx.conf"
NGINX_CONF_TPL_OPENRESTY="$NGINX_CONF_TPL_DIR/nginx_openresty.conf"
# 配置变量
REPO_URL="https://$REPO_SOURCE/xuchaoxin1375/scripts.git"
TARGET_DIR="/repos/scripts"
BRANCH="main" # 或 "master"，根据实际情况调整

# CLI flags
FORCE=0
UPDATE_CODE=0
UPDATE_CONFIG=0

print_usage() {
    cat << EOF
Usage: $(basename "$0") [options]

echo "script version: $version"

Options:
    -c, --update-code    更新仓库代码（clone / reset /pull）
    -g, --update-config  更新配置文件和符号链接等（覆盖/创建/重载 nginx, fail2ban 等）
    -f, --force          强制执行,需要和-g配合使用才生效（用于覆盖 nginx.conf 并跳过交互或保护性检查）
    -h, --help           显示本帮助信息并退出

If neither --update-code nor --update-config is specified, the script
will default to updating code only (equivalent to $(--update-code)).

This script will clone or update the git repository at $TARGET_DIR and
optionally update several symlinks and nginx/fail2ban configuration files.
EOF
}

# Copies $source to $dest only if $dest does not already exist.
# If $dest does exist, this function does nothing.
# This is useful for avoiding unnecessary overwrite of existing files.
# Example: copy_if_need /path/to/template /path/to/destination
copy_if_need() {
    local source="$1"
    local dest="$2"
    [[ -f "$dest" ]] || cp -v "$source" "$dest"
}
# 解析脚本命令行参数
while [ "$#" -gt 0 ]; do
    case "$1" in
        -f | --force)
            FORCE=1
            shift
            ;;
        -c | --update-code)
            UPDATE_CODE=1
            shift
            ;;
        -g | --update-config)
            UPDATE_CONFIG=1
            shift
            ;;
        -r | --repo-source)
            REPO_SOURCE="$2"
            shift 2
            ;;
        -h | --help)
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

# 默认行为: 如果没有指定 -c/--update-code 或 -g/--update-config, 则默认启用更新代码
if [ "$UPDATE_CODE" -eq 0 ] && [ "$UPDATE_CONFIG" -eq 0 ]; then
    UPDATE_CODE=1
fi

# ===更新代码===
if [ "$UPDATE_CODE" -eq 1 ]; then
    # 确保父目录存在
    mkdir -p "$(dirname "$TARGET_DIR")"

    echo "🚀 正在同步仓库到最新版本: $TARGET_DIR"

    # 判断目录是否存在，决定是克隆还是更新
    if [ ! -d "$TARGET_DIR/.git" ]; then
        # 目录不存在或不是 Git 仓库：执行浅克隆
        echo "📁 未检测到 Git 仓库，正在执行浅克隆..."
        rm -rf "$TARGET_DIR" # 防止存在非 Git 目录（如普通文件夹）
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
            cd "$TARGET_DIR" || {
                echo "❌ 无法进入目录: $TARGET_DIR"
                exit 1
            }

            # 获取最新提交信息前先 fetch
            git fetch origin "$BRANCH"

            if [ $? -ne 0 ]; then
                echo "❌ 获取远程更新失败"
                exit 1
            fi

            # 重置到远程分支最新提交
            git reset --hard origin/"$BRANCH"

            echo "✅ 仓库已强制更新到 origin/$BRANCH 最新版本"
        )
    fi

    echo "🎉 代码同步完成：$TARGET_DIR"
fi

# ===更新配置文件或模板===
if [ "$UPDATE_CONFIG" -eq 1 ]; then

    bash /www/sh/nginx_conf/update_cf_ip_configs.sh
    # 更新符号链接
    # 目录的符号链接(需要小心处理避免出现循环符号链接).可以先移除再创建防止嵌套
    # [ -L "/www/sh" ] && rm -f "/www/sh"
    if [ -L "/www/sh" ]; then
        echo "Removing existing symbolic link /www/sh"
        rm -rfv "/www/sh"

    else
        echo "/www/sh does not exist or is not a symbolic link"
    fi

    # 兼容wsl (脚本测试开发)
    [[ -d /mnt/c/repos/scripts/ ]] && ln -s -T /mnt/c/repos/scripts/ /repos/scripts

    ln -s -T /repos/scripts/wp/woocommerce/woo_df /www/woo_df -fv
    ln -s -T /www/woo_df/sh /www/sh -fv # 使用-T选项防止嵌套,而-f选项配合-T是会将重复运行符号创建语句效果覆盖而不报错
    ln -s -T /www/woo_df/pys /www/pys -fv
    # 脚本文件的符号链接
    ln -s /www/sh/deploy_wp_full.sh /deploy.sh -fv
    ln -s /www/sh/update_repos.sh /update_repos.sh -fv
    ln -s /www/sh/nginx_conf/update_nginx_vhosts_conf.sh /update_nginx_vhosts_conf.sh -fv
    # vim配置
    nvim_conf_dir="$HOME/.config/nvim"
    [[ -d $nvim_conf_dir ]] || mkdir -p "$nvim_conf_dir"
    ln -s /www/sh/vimrc.vim ~/.vimrc -fv
    ln -s /www/sh/vimrc.vim ~/.config/nvim/init.vim -fv

    # ==nginx配置文件软链接(这里如果用二级软连接和宝塔的一些操作(比如api)可能冲突,建议使用文件覆盖或则手动覆盖)
    # ln -s /www/sh/nginx_conf/com.conf /www/server/nginx/conf/com.conf -fv
    # ln -s /www/sh/nginx_conf/nginx.conf /www/server/nginx/conf/nginx.conf -fv

    # if [ -f /www/server/nginx/conf/com.conf ]; then
    #     rm  /www/server/nginx/conf/com.conf -fv
    # fi
    # cp /www/sh/nginx_conf/com.conf /www/server/nginx/conf/com.conf -fv
    # cp /www/sh/nginx_conf/com_limit_rate.conf /www/server/nginx/conf/com_limit_rate.conf -fv
    # cp /www/sh/nginx_conf/com_basic.conf /www/server/nginx/conf/com_basic.conf -fv
    cp /www/sh/nginx_conf/{com_*.conf,*.html} /www/server/nginx/conf/ -fv
    # 判断nginx是否可用
    openresty=false
    if type nginx &> /dev/null; then
        nginx_version=$(nginx -v 2>&1)
        echo "当前 nginx 已安装"
        if echo "$nginx_version" | grep 'openresty' &> /dev/null; then
            echo "当前 nginx 为 openresty: ( $nginx_version )"
            openresty=true
        else
            echo "当前 nginx 非 openresty"
        fi
    else
        echo "nginx 未安装，跳过 nginx 配置更新"
        nginx_version=""
    fi

    # cp /www/sh/nginx_conf/nginx_nginx.conf /www/server/nginx/conf/nginx.repos.conf -fv
    # cp /www/sh/nginx_conf/nginx_openresty.conf /www/server/nginx/conf/nginx_openresty.conf -fv

    # 如果启用了 --force 选项,则备份宝塔的 nginx.conf 文件 (/www/server/nginx/conf/nginx.conf)
    # 并使用 /www/sh/nginx_conf/nginx.conf 覆盖宝塔的 nginx.conf 文件
    if [ "$FORCE" -eq 1 ]; then
        # 备份当前nginx.conf
        BACKUP_TS=$(date +%Y%m%d) # %H%M%S
        if [ -f "$NGINX_CONF_FILE" ]; then
            echo "🔒 Force enabled: backing up existing nginx.conf to ${NGINX_CONF_FILE}.bak.${BACKUP_TS}"
            cp -fv "$NGINX_CONF_FILE" "${NGINX_CONF_FILE}.bak.${BACKUP_TS}"
        else
            echo "ℹ️ No existing nginx.conf to backup at $NGINX_CONF_FILE"
        fi

        echo "🔁 Overwriting $NGINX_CONF_FILE with /www/sh/nginx_conf/nginx.conf"
        # cp -fv /www/sh/nginx_conf/nginx_nginx.conf "$NGINX_CONF_FILE"
        # 执行覆盖
        if [[ $openresty = true ]]; then
            echo "检测到 openresty, 使用 openresty 配置文件"
            cp $NGINX_CONF_TPL_OPENRESTY $NGINX_CONF_FILE -fv
            # 修改com_basic.conf中的# include /www/server/nginx/conf/com_js_signed.conf
            sed -i.bak -E 's/#[[:space:]]*(.*com_js_signed.conf.*)/\1/g' $NGINX_CONF_DIR/com_basic.conf
        elif [[ $nginx_version = *"nginx"* ]]; then
            echo "使用标准 nginx 配置文件"
            cp $NGINX_CONF_TPL_STD $NGINX_CONF_FILE -fv
        fi
    fi

    # 让nginx重新加载配置🎈
    nginx -t && nginx -s reload

    # ==fail2ban配置文件
    # 检查是否安装fail2ban,如果没有则跳过下面操作
    if [[ -d /etc/fail2ban ]]; then
        # 如果/etc/fail2ban/fai2ban.repos事先存在则先删除
        f2b_repos='/etc/fail2ban/fail2ban.repos'
        if [ -d $f2b_repos ]; then
            echo "🗑️  删除已存在的符号链接或目录: $f2b_repos"
            rm -rfv "$f2b_repos"
        fi
        # 仓库中的fail2ban配置目录软链接到/etc/fail2ban/下(便于编辑器内编辑时参考)
        ln -s /www/sh/fail2ban/ $f2b_repos -fv
        # 自定义过滤器
        cp /www/sh/fail2ban/filter.d/* /etc/fail2ban/filter.d/ -fv

        # fail2ban源配置文件(.conf)
        cf_basic_tpl='/www/sh/fail2ban/action.d/cloudflare-tpl.conf'

        cf_mode_tpl='/www/sh/fail2ban/action.d/cloudflare-mode-tpl.conf'
        nginx_cf_jail_tpl='/www/sh/fail2ban/jail.d/nginx-cf-warn.conf'
        # 目标位置(.local)
        cf_action1='/etc/fail2ban/action.d/cloudflare1.local'
        cf_action2='/etc/fail2ban/action.d/cloudflare2.local'

        cf_mode='/etc/fail2ban/action.d/cloudflare-mode.local'
        nginx_cf_jail='/etc/fail2ban/jail.d/nginx-cf-warn.local'
        # 根据需要复制对应数量文件(注意编号)
        # 由于cp的-n参数在将来可能发生变化,且--update=none老版本cp可能不支持,所以这里使用判断语句
        # 直接cp默认不覆盖,但是会打印报错信息,观感不好,尽管可以重定向错误信息输出到空,但这不是很好
        # cp -nv "$cf_mode" /etc/fail2ban/action.d/cloudflare-mode.local
        # cp -nv "$cf_basic" /etc/fail2ban/action.d/cloudflare1.local
        # cp -nv "$cf_basic" /etc/fail2ban/action.d/cloudflare2.local

        copy_if_need "$cf_basic_tpl" "$cf_action2"
        copy_if_need "$cf_basic_tpl" "$cf_action1"
        copy_if_need "$cf_mode_tpl" "$cf_mode"
        copy_if_need "$nginx_cf_jail_tpl" "$nginx_cf_jail"
    else
        echo "fail2ban 未安装，跳过 fail2ban 配置更新"
    fi

fi

# 让指定目录下所有脚本文件(.sh)可执行🎈
find /repos/scripts/wp/woocommerce/woo_df/sh/ -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;
