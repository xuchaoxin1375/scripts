#!/bin/bash
# SITE_LIST_FILE="$HOME/site_to_remove.txt"
SITE_LIST_FILE=""
# verbose开关,注意取名和verbose函数区别,这里使用大小表示变量
VERBOSE=false
DRY_RUN=false

project_roots_default=('/www/wwwroot' '/wwwdata/wwwroot')
parse_args() {
    local project_roots=()
    # mysql 链接参数
    local host="" port="" user="" pass="" verbose=0 args=()
    local usage="
移除宝塔中的站点(wp),包括清理数据库,删除站点根目录,移除配置文件(nginx/apache),伪静态文件
> 宝塔自带的btcli site del命令可以用来删除站点,但是有些批量建站的情况数据库我们是绕过宝塔创建的,这种情况下btcli删除不干净
因此这里站点的配置文件和站点根目录用btcli删除(考虑到有些站点根目录嵌套了目录,可以考虑自行扫描删除);
而删除数据库可以根据白名单,构造要删除的数据库名来遍历删除;
usage:
    $0 [options]    
options:
    -r,--project-root project_root 项目目录,可以多次使用此选项,指定多个项目目录
    -s,--site-list-file 指定要被移除的名单(每行一个域名)
    mysql链接相关部分(不指定的话尝试从mysql配置文件中读取链接参数):

    -H hostname mysql数据库所属服务器,默认为localhost
    -P port mysql数据库链接端口
    -u user mysql用户
    -p pass mysql用户对应的密码
    -v verbose 启用详细信息输出模式

    -h,--help 打印此帮助
"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r | --project-root)
                project_roots+=("$2")
                shift 2
                ;;
            -s | --site-list-file)
                SITE_LIST_FILE="$2"
                shift 2
                ;;
            --dry-run)
                # echo "--- dry run ---"
                DRY_RUN=true
                shift
                ;;
            -H | -P | -u)
                # 这三个选项必须有参数值
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "错误: 选项 $1 需要一个参数值。"
                    return 1
                fi
                case "$1" in
                    -H) host="$2" ;;
                    -P) port="$2" ;;
                    -u) user="$2" ;;
                esac
                shift 2
                ;;

            # -p 单独处理，支持三种形式：-p123 / -p 123 / -p（空密码）
            -p)
                # -p 后面跟空格的情况
                if [[ -n "$2" && "$2" != -* ]]; then
                    pass="$2"
                    shift 2
                else
                    # 没有密码参数，可以交互输入或设为空
                    read -rsp "请输入密码: " pass
                    echo
                    shift
                fi
                ;;
            -p*)
                # -p123 连写形式
                pass="${1#-p}"
                shift
                ;;

            -v)
                VERBOSE=true
                shift
                ;;
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                echo "$usage"
                exit 1
                ;;
        esac
    done

}

parse_args "${@}"
# 定义verbose函数,相当于$VERBOSE的简写
verbose() {
    [[ $VERBOSE == "true" ]] && return 0
    return 1
}
# 强力删除:能够将标志位是i的文件(目录)更改为可删除,然后删除掉指定目标
# 这是一个简化版本(使用rm1或rm2更可靠)
# 用法: rmx <目标文件或目录>
rmx() {
    if [ $# -eq 0 ]; then
        echo "用法: rmx <目标文件或目录>"
        return 1
    fi
    for target in "$@"; do
        if [ -e "$target" ]; then
            echo "[INFO] 尝试去除 $target 的 i 标志..."
            sudo chattr -R -ia "$target"
            echo "[INFO] 强力删除 $target ..."
            sudo rm -rf "$target"
        else
            echo "[WARN] 目标不存在: $target"
        fi
    done
    return 0
}
# 读取白名单
mapfile -t sites < "$SITE_LIST_FILE"

[[ -n "$host" ]] && args+=(-h "$host")
[[ -n "$port" ]] && args+=(-P "$port")
[[ -n "$user" ]] && args+=(-u "$user")
[[ -n "$pass" ]] && args+=(-p"$pass")

if ((verbose)); then
    echo "--- check_mysql ---"
    echo "  host : ${host:-<default>}"
    echo "  port : ${port:-<default>}"
    echo "  user : ${user:-<default>}"
    echo "  pass : ${pass:+****}"
    echo -n "  result: "
fi
# 链接测试
mysql "${args[@]}" -e "
SELECT 
    VERSION()           AS '版本',
    USER()              AS '用户',
    DATABASE()          AS '数据库',
    NOW()               AS '时间',
    @@hostname          AS '主机名',
    @@port              AS '端口',
    @@datadir           AS '数据目录',
    @@character_set_server AS '字符集';
"
# exit 0 # debug
# 如果用户没有指定项目目录,则使用默认值列表
[[ ${#project_roots} -eq 0 ]] && project_roots+=("${project_roots_default[@]}")

cnt=0
removing=0 # 统计被移除的站点数
succeed=0
log() {
    echo -e "[$(date +%F-%T.%3N)] $*"
}
for pr in "${project_roots[@]}"; do
    [[ -e $pr ]] || continue
    echo "processing sites in project:[$pr]"
    for site in "${sites[@]}"; do
        ((cnt++))
        verbose && log "cleaning[$cnt]:$site"
        # 扫描网站根目录(或站点顶级目录),例如/www/wwwroot/user/domain.com/
        # find "$pr" -mindepth 2 -maxdepth 2 -type d -iname "$site" -exec printf "[site dir to be remove (%s)]\n" {} \;
        # mapfile -t -d '' site_dirs < <(find "$pr" -mindepth 2 -maxdepth 2 -type d -iname "$site" -print0)
        # for sp in "${site_dirs[@]}"; do
        # done
        # 安全地保存找到的目录(多个的话仅保存第一个路径)
        read -d '' -r site_path < <(find "$pr" -mindepth 2 -maxdepth 2 -type d -iname "$site" -print0)
        if [[ $site_path ]]; then
            tmp=${site_path#"$pr"}
            tmp=${tmp#/}
            owner=${tmp%%/*}
            log "[remove:$((removing++))] site root [$site_path]..."
            verbose && log "extract user of [${site_path}]-> ($owner)"
            # 精确处理

            db_name="${owner}_${site}"
            # mysql "${args[@]}" -e "SHOW DATABASES LIKE '${db_name}';"
            # 除了删除数据库,还可以选择删除对应的专用用户(如果有的话):DROP USER '数据库用户名'@'localhost';

            # START-DW 删除站点(危险区域)🎈
            log "\t[INFO] 尝试删除网站[$site]:配套数据库${db_name}"
            if [[ $DRY_RUN == "false" ]]; then
                mysql "${args[@]}" -e "DROP DATABASE IF EXISTS \`${db_name}\`" &&
                    yes | btcli site del "$site" &&
                    ((succeed++))
                # 移除可能多余的上层目录
                rm -rf "$site_path" >&/dev/null
            else
                log "\t[DRY-RUN] 模拟删除"
            fi
            # END-DW 结束删除站点(危险区域)🎈

            # rmx "$site_path" && #rmx 强力删除,自带-rf效果
            # 移除nginx配置文件
            # rm -fv /www/server/panel/vhost/nginx/"${site}".conf >&/dev/null
            # rm -fv /www/server/panel/vhost/nginx/"www.${site}".conf >&/dev/null
            # # 移除伪静态文件
            # rm -fv /www/server/panel/vhost/rewrite/"${site}".conf >&/dev/null
            # rm -fv /www/server/panel/vhost/rewrite/"www.${site}".conf >&/dev/null
            # 模糊处理
            # db_name="$site"
            # mysql "${args[@]}" -e "SHOW DATABASES LIKE '%_${db_name}';"
        fi
    done
done
echo "summary:[${succeed}] sites have been removed."
