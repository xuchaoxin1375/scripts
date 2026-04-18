#!/bin/bash
# 适用于服务器(带有root权限),不建议用于个人电脑,个人电脑使用专用版本的更新脚本(或命令行)
# 在代码已经clone的情况下,使用此脚本进行配置服务器环境
# 此脚本也可以直接使用,如果仓库不存在,就会全新clone,否则执行仓库更新;
# 然后可以按照需要,统一执行服务器配置文件修改;

# mkdir -p -v $HOME/repos && git clone --depth 1 https://gitee.com/xuchaoxin1375/scripts.git $HOME/repos/scripts

# 强制更新代码(放弃已有更改)
#git fetch origin
#git reset --hard origin/main
#git pull

version=20260418.2208
echo "当前脚本版本: $version;"
REPO_SOURCE='github' # gitee或github或gitlab (gitee可能对国外ip服务器用户限流或要求注册账号,优先使用github或gitlab)
BRANCH="main" # 或 "master"，根据实际情况调整
NGINX_CONF_DIR="/www/server/nginx/conf"
NGINX_CONF_FILE="$NGINX_CONF_DIR/nginx.conf"

# 配置变量
# SCRIPT_ROOT_SERVER=/repos/scripts
SH_SYM="$HOME/sh"
SH_WWW="/www/sh" #末尾不要加斜杠/

# sh="$SH_SYM" # 简写或者直接用SH_SYM
_REPO_BASE="repos/scripts"
_SH_RELATIVE="wp/woocommerce/woo_df/sh"
SCRIPT_ROOT_DEFAULT="$HOME/$_REPO_BASE"
SCRIPT_ROOT="${SCRIPT_ROOT:-"$SCRIPT_ROOT_DEFAULT"}" # /root/repos/scripts 或 /home/user/repos/scripts
# shell脚本目录(sh)
SH_SCRIPT_DIR="$SCRIPT_ROOT/$_SH_RELATIVE"
ln -snfv "$SH_SCRIPT_DIR" "$SH_SYM"
# 移除可能的就链接,重新创建链接
# unlink $SH_SYM # 可以使用unlink命令安全删除符号链接(不会误删目标目录内的文件)
rm -fv "${SH_WWW%/}" && ln -snfv "$SH_SYM" "$SH_WWW" 

# CLI flags
FORCE=0
UPDATE_CODE=0
UPDATE_CONFIG=0

print_usage() {
    cat << EOF
Usage: $(basename "$0") [options]

echo "script version: $version"

Options:
    -r, --repo-source    指定仓库源，可以是 gitee 或 github 或 gitlab
    -c, --update-code    更新仓库代码（clone / reset /pull）
    -g, --update-config  更新配置文件和符号链接等（覆盖/创建/重载 nginx, fail2ban 等）
    -f, --force          强制执行,需要和-g配合使用才生效（用于覆盖 nginx.conf 并跳过交互或保护性检查）
    --remove-old         删除仓库,完全重新clone(务必谨慎使用,考虑手动备份或者将原来可能自定义的文件备份出来)
    -b, --branch         指定分支名称，默认为 main
    -h, --help           显示本帮助信息并退出

If neither --update-code nor --update-config is specified, the script
will default to updating code only (equivalent to \$(--update-code)).

This script will clone or update the git repository at $SCRIPT_ROOT and
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
parse_args() {

    # 解析脚本命令行参数
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -f | --force)
                FORCE=1
                shift
                ;;
            --remove-old)
                REMOVE_OLD=1
                shift
                ;;
            -b | --branch)
                BRANCH="$2"
                shift 2
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
            -t|--repo-path)
                SCRIPT_ROOT="$2"
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

}
parse_args "$@"
# nginx主配置文件源(用于覆盖服务器上的旧版本)
NGINX_CONF_TPL_DIR="$SH_SYM/nginx_conf"
NGINX_CONF_TPL_STD="$NGINX_CONF_TPL_DIR/nginx_nginx.conf"
NGINX_CONF_TPL_OPENRESTY="$NGINX_CONF_TPL_DIR/nginx_openresty.conf"

# 代码仓库来源
REPO_URL="https://$REPO_SOURCE.com/xuchaoxin1375/scripts.git"
URL_GITEE="https://gitee.com/xuchaoxin1375/scripts.git"
URL_GITHUB="https://github.com/xuchaoxin1375/scripts.git"
URL_GITLAB="https://gitlab.com/xuchaoxin1375/scripts.git"
echo "clone repository source: $REPO_SOURCE;from git: $REPO_URL"

# 默认行为: 如果没有指定 -c/--update-code 或 -g/--update-config, 则默认启用更新代码
if [ "$UPDATE_CODE" -eq 0 ] && [ "$UPDATE_CONFIG" -eq 0 ]; then
    UPDATE_CODE=1
fi

# ===更新代码===
if [ "$UPDATE_CODE" -eq 1 ]; then
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
        # echo "📁 未检测到 Git 仓库，正在执行浅克隆..."
        # rm -rf "$SCRIPT_ROOT" # 防止存在非 Git 目录（如普通文件夹）

        # if git clone --depth 1 "$REPO_URL_GITEE" "$SCRIPT_ROOT"; then
        #     echo "✅ 克隆成功($REPO_SOURCE)"
        # elif git clone --depth 1 "$REPO_URL_GITEE" "$SCRIPT_ROOT"; then
        #     echo "✅ 克隆成功(gitee)"
        # elif git clone --depth 1 "$REPO_URL_GITHUB" "$SCRIPT_ROOT"; then
        #     echo "✅ 克隆成功(github)"
        # else
        #     echo "❌ 克隆失败，请检查网络或仓库地址"
        #     exit 1
        # fi

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
fi

# ===更新配置文件或模板===
if [ "$UPDATE_CONFIG" -eq 1 ]; then

    bash $SH_SYM/nginx_conf/update_cf_ip_configs.sh
    # 更新符号链接
    # 目录的符号链接(需要小心处理避免出现循环符号链接).可以先移除再创建防止嵌套
    # [ -L "$SH_SYM" ] && rm -f "$SH_SYM"
    if [ -L "$SH_SYM" ]; then
        echo "Removing existing symbolic link $SH_SYM"
        rm -rfv "$SH_SYM"

    else
        echo "$SH_SYM does not exist or is not a symbolic link."
    fi

    # 兼容wsl (脚本测试开发)
    # [[ -d /mnt/c/ ]] && ln -s -T $SCRIPT_ROOT /repos/scripts

    # ln -s -T /repos/scripts/wp/woocommerce/woo_df /www/woo_df -fv
    # ln -s -T /www/woo_df/sh $SH_SYM -fv # 使用-T选项防止嵌套,而-f选项配合-T是会将重复运行符号创建语句效果覆盖而不报错
    # ln -s -T /www/woo_df/pys /www/pys -fv
    # 脚本文件的符号链接
    ln -sfv $SH_SCRIPT_DIR $SH_SYM 
    ln -sfv $SH_SYM/deploy_wp_full.sh /deploy.sh 
    ln -sfv $SH_SYM/update_repos.sh /update_repos.sh 
    ln -sfv $SH_SYM/nginx_conf/update_nginx_vhosts_conf.sh /update_nginx_vhosts_conf.sh 
    # vim配置
    nvim_conf_dir="$HOME/.config/nvim"
    [[ -d $nvim_conf_dir ]] || mkdir -p "$nvim_conf_dir"
    ln -s $SH_SYM/vimrc.vim ~/.vimrc -fv
    ln -s $SH_SYM/vimrc.vim ~/.config/nvim/init.vim -fv

    # ==nginx配置文件软链接(这里如果用二级软连接和宝塔的一些操作(比如api)可能冲突,建议使用文件覆盖或则手动覆盖)
    # ln -s $SH_SYM/nginx_conf/com.conf /www/server/nginx/conf/com.conf -fv
    # ln -s $SH_SYM/nginx_conf/nginx.conf /www/server/nginx/conf/nginx.conf -fv

    # if [ -f /www/server/nginx/conf/com.conf ]; then
    #     rm  /www/server/nginx/conf/com.conf -fv
    # fi
    # cp $SH_SYM/nginx_conf/com.conf /www/server/nginx/conf/com.conf -fv
    # cp $SH_SYM/nginx_conf/com_limit_rate.conf /www/server/nginx/conf/com_limit_rate.conf -fv
    # cp $SH_SYM/nginx_conf/com_basic.conf /www/server/nginx/conf/com_basic.conf -fv
    cp $SH_SYM/nginx_conf/{com_*.conf,*.html} /www/server/nginx/conf/ -fv
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

    # cp $SH_SYM/nginx_conf/nginx_nginx.conf /www/server/nginx/conf/nginx.repos.conf -fv
    # cp $SH_SYM/nginx_conf/nginx_openresty.conf /www/server/nginx/conf/nginx_openresty.conf -fv

    # 如果启用了 --force 选项,则备份宝塔的 nginx.conf 文件 (/www/server/nginx/conf/nginx.conf)
    # 并使用 $SH_SYM/nginx_conf/nginx.conf 覆盖宝塔的 nginx.conf 文件
    if [ "$FORCE" -eq 1 ]; then
        # 备份当前nginx.conf
        BACKUP_TS=$(date +%Y%m%d) # %H%M%S
        if [ -f "$NGINX_CONF_FILE" ]; then
            echo "🔒 Force enabled: backing up existing nginx.conf to ${NGINX_CONF_FILE}.bak.${BACKUP_TS}"
            cp -fv "$NGINX_CONF_FILE" "${NGINX_CONF_FILE}.bak.${BACKUP_TS}"
        else
            echo "ℹ️ No existing nginx.conf to backup at $NGINX_CONF_FILE"
        fi

        echo "🔁 Overwriting $NGINX_CONF_FILE with $SH_SYM/nginx_conf/nginx.conf"
        # cp -fv $SH_SYM/nginx_conf/nginx_nginx.conf "$NGINX_CONF_FILE"
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
        ln -s $SH_SYM/fail2ban/ $f2b_repos -fv
        # 自定义过滤器
        cp $SH_SYM/fail2ban/filter.d/* /etc/fail2ban/filter.d/ -fv

        # fail2ban源配置文件(.conf)
        cf_basic_tpl='$SH_SYM/fail2ban/action.d/cloudflare-tpl.conf'

        cf_mode_tpl='$SH_SYM/fail2ban/action.d/cloudflare-mode-tpl.conf'
        nginx_cf_jail_tpl='$SH_SYM/fail2ban/jail.d/nginx-cf-warn.conf'
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
# shellcheck disable=SC2154
find "$SH_SYM" -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;
