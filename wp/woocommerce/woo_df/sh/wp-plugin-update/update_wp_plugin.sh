#!/bin/bash
# 更新重点日志:251204为参数WORKDIR提供接收单个或多个路径的支持,即允许指定1个或多个工作目录
# 如果使用symlink,需要注意和建站工具网站目录中默认设置的"防跨站攻击"功能冲突
# 合理设置防跨站攻击(open_basedir)，防止黑客通过其他网站目录进行入侵攻击

usage() {
    cat << EOF
用法：$0 [--source <插件目录>] [--remove <插件名 1，插件名 2,...>] [--user <用户名>] [--workdir <工作目录 1，工作目录 2,...>] [--dry-run] [--blacklist <黑名单文件>] [--whitelist <白名单文件>] [--log <日志文件>]

参数说明：
  --src,--source,--plugin-source <插件目录>         要被安装/更新的插件源目录
  --remove <插件名列表>       要移除的插件名，多个用逗号分隔
  --user <用户名>             WordPress 站点所属用户名（可选，不指定则处理所有用户）
  --workdir <工作目录列表>    网站根工作目录，多个目录用逗号分隔。默认为 /www/wwwroot,/wwwdata/wwwroot
  -m,--install-mode <安装模式>   安装模式 (copy:复制到指定目录;symlink:软链接到指定目录),默认为 symlink
  -M,--list-mode <列表模式> 获取待处理站点列表的模式 (auto:自动扫描已安装插件的站点;manual:手动指定黑/白名单;full:所有网站都要安装;),默认为 auto
  --plugin-type               插件类型 (如果是 must 类型，则将被处理的插件视为强制执行插件),放到 wp-content 目录下;默认为 common 类型，普通插件，放到 wp-content/plugins 目录下
  --dry-run                   预览操作，不实际执行
  --blacklist <文件>          指定黑名单文件（每行一个域名）;指定了黑名单文件,自动设置LIST_MODE为manual模式
  --whitelist <文件>          指定白名单文件（每行一个域名，只操作这些域名）;指定了白名单文件,自动设置LIST_MODE为manual模式
  --log <日志文件>            指定日志文件保存操作日志
EOF
    exit 1
}

# 解析命令行参数
SOURCE_DIR=""
REMOVE_PLUGINS=""
USER_NAME=""
# 修改默认值，支持多个路径，用逗号分隔
WORKDIR="/www/wwwroot,/wwwdata/wwwroot"
DRY_RUN=false
COMMON_PLUGINS_HOME="wp-content/plugins"
MUST_PLUGINS_HOME="wp-content"
# 安装/更新插件时采用的安装模式(copy/symlink)
INSTALL_MODE="symlink"
# 获取待处理网站列表的模式(自动扫描适用于普通的按需插件更新,未安装过目标插件的网站将自动跳过处理)
LIST_MODE="auto" # auto,manual
# 手动指定黑白名单模式下(manual),可以指定黑/白名单中的一个
BLACKLIST_FILE=""
WHITELIST_FILE=""

LOG_FILE=""
PLUGIN_TYPE="common"
# 命令行参数解析
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --src | --source | --plugin-source)
                SOURCE_DIR="$2"
                shift
                ;;
            --remove)
                REMOVE_PLUGINS="$2"
                shift
                ;;
            --user)
                USER_NAME="$2"
                shift
                ;;
            --workdir)
                WORKDIR="$2"
                shift
                ;; # 接受逗号分隔的多个路径
            --dry-run) DRY_RUN=true ;;
            --blacklist)
                BLACKLIST_FILE="$2"
                echo "指定了黑名单文件,自动设置LIST_MODE为manual模式"
                LIST_MODE="manual"
                shift
                ;;
            --whitelist)
                WHITELIST_FILE="$2"
                echo "指定了白名单文件,自动设置LIST_MODE为manual模式"
                LIST_MODE="manual"
                shift
                ;;
            --plugin-type)
                if [[ "$2" == "must" ]]; then
                    PLUGIN_TYPE="must"
                else
                    PLUGIN_TYPE="common"
                fi
                shift
                ;;
            -m | --install-mode)
                if [[ "$2" == "copy" ]]; then
                    INSTALL_MODE="copy"
                elif [[ "$2" == symlink* ]]; then
                    INSTALL_MODE="symlink"
                fi
                shift
                ;;
            -M | --list-mode)
                if [[ "$2" == "auto" ]]; then
                    echo "仅更新已经安装了指定插件的网站,未安装的网站将跳过！"
                    LIST_MODE="auto"
                else
                    # 手动指定(白名单或黑名单的方式)
                    LIST_MODE="manual"
                fi
                shift
                ;;
            --log)
                LOG_FILE="$2"
                shift
                ;;
            *) usage ;;
        esac
        shift
    done
}
parse_args "$@"
if [[ -z "$SOURCE_DIR" && -z "$REMOVE_PLUGINS" ]]; then
    usage
fi

# 读取黑名单或白名单文件到数组
BLACKLIST=()
WHITELIST=()
if [[ -n "$WHITELIST_FILE" && -n "$BLACKLIST_FILE" ]]; then
    echo "不能同时指定白名单和黑名单！"
    exit 1
fi
if [[ -n "$BLACKLIST_FILE" ]]; then
    if [[ ! -f "$BLACKLIST_FILE" ]]; then
        echo "黑名单文件不存在: $BLACKLIST_FILE"
        exit 1
    fi
    # mapfile -t BLACKLIST < "$BLACKLIST_FILE"
    # mapfile -t BLACKLIST < <(tr -d '\r' < "$BLACKLIST_FILE")

    # 去除域名边缘的空格,兼容CRLF换行的文件
    # s/^[[:space:]]*//：删除行首空格。
    # s/[[:space:]]*$//：删除行尾空格。
    # s/\r$//：删除 Windows 换行符。
    mapfile -t BLACKLIST < <(sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/\r$//' < "$BLACKLIST_FILE")
fi
if [[ -n "$WHITELIST_FILE" ]]; then
    if [[ ! -f "$WHITELIST_FILE" ]]; then
        echo "白名单文件不存在: $WHITELIST_FILE"
        exit 1
    fi
    # mapfile -t WHITELIST < "$WHITELIST_FILE"
    mapfile -t WHITELIST < <(sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/\r$//' < "$WHITELIST_FILE")
fi

# 判断域名是否在黑名单
is_blacklisted() {
    local domain="$1"
    for blacklisted in "${BLACKLIST[@]}"; do
        if [[ "$domain" == "${blacklisted,,}" ]]; then
            return 0
        fi
    done
    return 1
}

# 判断域名是否在白名单
is_whitelisted() {
    local domain="$1"
    # log "检查域名[$domain]是否在白名单中..."
    for whitelisted in "${WHITELIST[@]}"; do
        if [[ "${domain,,}" == "${whitelisted,,}" ]]; then
            return 0
        fi
    done
    return 1
}

# 记录日志函数
log() {
    local msg="$1"
    echo "$msg"
    if [[ -n "$LOG_FILE" ]]; then
        echo "$msg" >> "$LOG_FILE"
    fi
}

# --- 开始修改的重点区域 ---

# 遍历所有工作目录
IFS=',' read -ra WORKDIR_ARRAY <<< "$WORKDIR"
for workdir_path in "${WORKDIR_ARRAY[@]}"; do
    workdir_path=$(echo "$workdir_path" | xargs) # 清除可能的空格

    if [[ ! -d "$workdir_path" ]]; then
        log "工作目录不存在，跳过: $workdir_path"
        continue
    fi

    log "--- 正在处理工作目录: $workdir_path ---"

    # 查找所有 WordPress 站点目录 (SITE_PATHS现在是相对于workdir_path的模式)
    ## 计算合适的搜索模式串,用以匹配网站根目录
    if [[ -n "$USER_NAME" ]]; then
        # 针对指定用户，路径模式为 /www/wwwroot/{user}/{domain}/wordpress
        SEARCH_PATTERN="$workdir_path/$USER_NAME/*/wordpress"
    else
        # 针对所有用户，路径模式为 /www/wwwroot/*/{domain}/wordpress
        SEARCH_PATTERN="$workdir_path/*/*/wordpress"
    fi
    # 计算待处理的各个具体的网站根目录
    ######################################
    # 预览安装提示
    # Global:
    #   DRY_RUN
    #   INSTALL_MODE
    #   SOURCE_DIR
    # Arguments:
    #   $1 - description
    # Returns:
    #   0 on success, non-zero on error
    ######################################
    install_to_target() {
        local TARGET_DIR="$1"
        local TYPE_DESC="$2"
        if $DRY_RUN; then
            log "  [DRY RUN] 将覆盖 $SOURCE_DIR 到 [$TARGET_DIR] [$TYPE_DESC]"
        else
            # 安装插件前,尤其是symbolic方式,建议检查并调整用户ini
            user_ini="$site/.user.ini"
            if [[ -f "$user_ini" ]]; then
                log "调整[$site]的.user.ini..."
                bash /www/sh/update_user_ini.sh -p "$user_ini" || return 1
            fi
            # 正式安装前移除站点中的原插件目录
            if [[ -e "$TARGET_DIR" ]]; then
                log "  删除已存在: $TARGET_DIR"
                rm -rf "$TARGET_DIR" || return 1
            fi
            log "  [$INSTALL_MODE]覆盖 $SOURCE_DIR 到 $TARGET_DIR $TYPE_DESC"
            # 根据安装模式正式执行安装操作
            if [[ "$INSTALL_MODE" == "copy" ]]; then
                cp -r "$SOURCE_DIR" "$TARGET_DIR" || return 1
            elif [[ "$INSTALL_MODE" == "symlink" ]]; then
                ln -sT "$SOURCE_DIR" "$TARGET_DIR" || return 1
            fi
        fi
    }
    ## 黑/白名单模式
    if [[ $LIST_MODE == "manual" || $LIST_MODE == "full" ]]; then
        count=0
        for site in $SEARCH_PATTERN; do
            # 检查目录是否存在,不存在跳过该站处理
            # if [[ ! -d "$site" ]]; then
            #     continue
            # fi

            # 获取域名（父目录名）
            DOMAIN=$(basename "$(dirname "$site")")

            log "处理站点: $DOMAIN @ $site"

            # 如果不符合指定名单,跳过该站处理(continue)
            # 如果是全局安装(full),则不跳过任何站点
            # 白名单优先，只处理白名单中的域名
            if [[ -n "$WHITELIST_FILE" ]]; then
                if ! is_whitelisted "$DOMAIN"; then
                    log "  跳过未在白名单中的域名: $DOMAIN"
                    continue
                else
                    log "  域名[$DOMAIN]在白名单中,需要处理"
                    ((count++))
                fi
            # 黑名单模式，跳过黑名单中的域名
            elif [[ -n "$BLACKLIST_FILE" ]]; then
                if is_blacklisted "$DOMAIN"; then
                    log "  跳过黑名单域名: $DOMAIN"
                    continue
                else
                    log "  域名[$DOMAIN]不在黑名单中,需要处理"
                    ((count++))
                fi
            fi

            # 覆盖式安装插件
            if [[ -n "$SOURCE_DIR" ]]; then
                # 计算插件名称
                PLUGIN_BASENAME="$(basename "$SOURCE_DIR")"
                # 根据不同的插件类型执行不同的安装方式(计算最终的安装目录)
                if [[ "$PLUGIN_TYPE" == "must" ]]; then
                    # 强制执行插件的安装(must-plugin)
                    TARGET_DIR="$site/$MUST_PLUGINS_HOME/$PLUGIN_BASENAME"
                    # 确保 mu-plugins 目录存在
                    if ! $DRY_RUN; then
                        mkdir -p "$site/$MUST_PLUGINS_HOME"
                    fi
                    TYPE_DESC="(must-use plugin)"
                else
                    # 普通wp插件安装
                    TARGET_DIR="$site/$COMMON_PLUGINS_HOME/$PLUGIN_BASENAME"
                    TYPE_DESC="(common plugin)"
                fi

                install_to_target "$TARGET_DIR" "$TYPE_DESC" || return 1
            fi

            # 移除插件(针对普通插件)
            if [[ -n "$REMOVE_PLUGINS" ]]; then
                IFS=',' read -ra PLUGIN_LIST <<< "$REMOVE_PLUGINS"
                for plugin in "${PLUGIN_LIST[@]}"; do
                    REMOVE_DIR="$site/$COMMON_PLUGINS_HOME/$plugin"
                    if [[ -e "$REMOVE_DIR" ]]; then
                        if $DRY_RUN; then
                            log "  [DRY RUN] 将移除插件: $REMOVE_DIR"
                        else
                            log "  移除插件: $REMOVE_DIR"
                            rm -rf "$REMOVE_DIR"
                        fi
                    else
                        log "  插件不存在，无需移除: $REMOVE_DIR"
                    fi
                done
            fi
        done
        log "共处理 $count 个站点。"
    else
        ## 自动模式下更新插件
        PLUGIN_BASENAME="$(basename "$SOURCE_DIR")"
        # find搜索(指定层级提高搜索效率,比递归通配符快速)
        # 写法1:直接mapfile不会实时打印找到的目录
        # mapfile -d '' -t site_plugin_dirs < <(find "$workdir_path" -mindepth 5 -maxdepth 6 -type d -name "$PLUGIN_BASENAME" -print0)

        # 写法2:考虑使用tee来及时输出find找到的路径
        # mapfile -d '' -t site_plugin_dirs < <(
        #     find "$workdir_path" \
        #         -mindepth 5 -maxdepth 6 \
        #         -type d -name "$PLUGIN_BASENAME" \
        #         -print0 | tee /dev/stderr
        # )
        # 写法3:使用兼容性最好的while read循环来处理find的输出(性能会比mapfile差一些)
        site_plugin_dirs=()
        while IFS= read -r -d '' dir; do
            echo "找到目录: $dir"
            site_plugin_dirs+=("$dir")
        done < <(find "$workdir_path" -mindepth 5 -maxdepth 6 \( -type d -o -type l \) -name "$PLUGIN_BASENAME" -print0)

        # 遍历处理找到的站点
        for d in "${site_plugin_dirs[@]}"; do
            log "处理站点: $d"
            # 插件更新(仅针对普通插件,must-plugin类型请使用manual更新)
            install_to_target "$d" "(common plugin)" || return 1
        done
        log "共找到 ${#site_plugin_dirs[@]} 个安装了 $PLUGIN_BASENAME 插件的站点。"
    fi
done

# --- 结束修改的重点区域 ---

if $DRY_RUN; then
    log "Dry run 完成，未做任何更改。"
else
    log "操作已完成。"
fi
