#!/bin/bash
# 配置zsh(oh my zsh)相关插件,让体验向fish靠拢
# 此部署代码尽量实现幂等性(避免反复运行导致配置文件内容混乱.)
# 补全类插件要求比较严格,尤其是动态自动补全实现比较复杂需要更多的步骤
# 测试补全插件效果时,对于基础工具,注意区分gnu版本和bsd版本,可用选项和风格有所不同
version=20260415
# 默认插件安装选项(仅补全类插件)
install_zsh_completions=true # true|false
install_zsh_autocomplete=omz # omz|std|false
# 定义使用帮助(help)
usage='
version:'"$version"'
usage:
    deploy_omz.sh [options]
options:
    -zc | --install-zsh-completions [true|false]
        install zsh-completions plugin if true
    -zac | --install-zsh-autocomplete [omz|std|false]
        install zsh-autocomplete plugin if true,if use std (standard) mode,this plugin will be installed without oh my zsh plugins list
    -h,--help 
        show this help message.
'
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -zc | --install-zsh-completions)
                install_zsh_completions="$2"
                if ! [[ "${install_zsh_completions,,}" =~ ^(false|true)$ ]]; then
                    echo "Invalide zsh-completions install mode '$install_zsh_completions' !" >&2
                    echo "$usage"
                    exit 1
                fi
                shift
                ;;
            -zac | --install-zsh-autocomplete)
                install_zsh_autocomplete="$2"
                if ! [[ "${install_zsh_autocomplete,,}" =~ ^(omz|std|false)$ ]]; then
                    echo "Invalide zsh-autocomplete install mode '$install_zsh_autocomplete'!" >&2
                    echo "$usage"
                    exit 1
                fi
                shift
                ;;
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            -*)
                echo "unknown option: "
                echo "$usage"
                exit 1
                ;;
        esac
        shift
    done
}
parse_args "$@"
# 以下代码需要gnu sed,如果gsed不可用,请用户安装
if [[ $OSTYPE == darwin* ]]; then
    if command -v gsed &> /dev/null; then
        # 临时设置别名
        alias sed=gsed
    else
        echo "macOS:gnu sed not found, please install gnu sed first!"
        if command -v brew &> /dev/null; then
            brew install gnu-sed
        else
            echo "Please install gnu-sed first!"
            exit 1
        fi
    fi
fi
# 将推荐的插件下载到指定目录下:(git 已经指定好了目录)
zap=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
zshp=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
zhssp=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
zcp=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions
zysu=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/you-should-use
zac=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete
! [[ -d $zap ]] && git clone --depth 1 https://gitee.com/zsh-users/zsh-autosuggestions "$zap"

! [[ -d $zshp ]] && git clone --depth 1 https://gitee.com/zsh-users/zsh-syntax-highlighting.git "$zshp"

! [[ -d $zhssp ]] && git clone --depth 1 https://gitee.com/mirror-hub/zsh-history-substring-search "$zhssp"

# zsh-completions这个项目gitee官方可能没有镜像,使用个人用户的自镜像版本(建议有需要的可以自己拉取一份比较安全)
# 另外这个插件比其他zsh插件不同,在配合oh my zsh使用时需要额外注意配置文件的写法;
! [[ -d $zcp ]] && git clone --depth 1 https://gitee.com/duchenpaul/zsh-completions.git "$zcp"
! [[ -d $zysu ]] && git clone --depth 1 https://gitcode.com/gh_mirrors/zs/zsh-you-should-use.git "$zysu"
# 自动动态的补全预测,属于较复杂插件(代替incr.zsh)
! [[ -d $zac ]] && git clone --depth 1 https://gitee.com/mirrors/zsh-autocomplete.git "$zac"

# 将工作目录转移到家目录
current_wd=$(pwd)
cd ~ || exit 1
zshrc_path="$HOME/.zshrc"

# 构造新的plugins插件列表(字符串),保存到全局变量plugins_list中
get_omz_plugins_list() {

    # 配置插件(不要在下面的列表中添加zsh-completions这个特殊插件)

    # backslash='\\'
    plugins_list=$(
        cat << EOF
git
z
zsh-syntax-highlighting
zsh-autosuggestions
zsh-history-substring-search
you-should-use
EOF
    )
    if [[ $install_zsh_autocomplete == "omz" ]]; then
        front_plugins=$(
            cat << EOF
zsh-autocomplete
EOF
        )
        plugins_list="${front_plugins}"$'\n'"${plugins_list}"

    fi

    # 为每行插件名末尾增加`\`便于在sed中使用(注意最后一个比较特殊,手动补充\\)
    plugins_list="${plugins_list//$'\n'/\\$'\n'}\\"
    echo "[$plugins_list]"
    # exit 1 # debug plugins_list
    echo "[$zshrc_path]"
}
get_omz_plugins_list

# 将.zshrc中的列表更新
update_omz_plugins_rc() {

    if grep '^plugins=(.*)' "$zshrc_path"; then
        echo "初次覆盖plugins(单行)"
        sed -i 's/^plugins=(.*)/\
plugins=(\
'"$plugins_list"'
)/' "$zshrc_path"
    elif grep '^plugins=($' "$zshrc_path"; then
        echo "覆盖插件列表(多行plugins更新)"
        sed -i '/^plugins=(/,/)/c\
plugins=(\
'"$plugins_list"'
)' "$zshrc_path"

    fi
}

update_omz_plugins_rc

# 将补全相关插件的配置写入.zshrc
update_comp_plugins_config_rc() {

    echo "checking and install completion related plugins (zc,zac) ..."
    # 在plugins= 行或者source $ZSH/oh-my-zsh.sh行上方插入额外片段行(适用于zsh-completions)
    # shellcheck disable=SC2016
    # sed -i '/source \$ZSH/oh-my-zsh\.sh/i\
    if [[ "$install_zsh_completions" == "true" ]]; then
        echo "安装zsh-completions ..."
        _switch=''
        if ! grep '# >>> zsh-completions' "$zshrc_path"; then
            if [[ $install_zsh_autocomplete != "false" ]]; then
                #     _switch=''
                # else
                _switch='#'
            fi
            sed -i '/^plugins=(/i\
# >>> zsh-completions\
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src\
'"$_switch"' autoload -U compinit \&\& compinit # 有zsh-autocomplete时这一行注释掉防止冲突\
# <<< zsh-completions\
' ~/.zshrc
            # 重建补全(词库)
            rm -f ~/.zcompdump
        fi
    fi
    # 向.zshrc文件头部插入source命令(根据插件官方知道要让autocomplete插件尽早加载,写在.zshrc文件头部,如果oh my zsh插件管理中的加载时机无法正常生效时,可以考虑下面的方案,代替插件列表中的简单配置)
    if [[ "$install_zsh_autocomplete" == "std" ]]; then
        echo "安装zsh-autocomplete ..."
        if ! grep '# >>> zsh-autocomplete' "$zshrc_path"; then
            # shellcheck disable=SC2016
            sed -i '1i\
# >>> zsh-autocomplete\
# source /path/to/zsh-autocomplete/zsh-autocomplete.plugin.zsh\
source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh\
# <<< zsh-autocomplete\
' ~/.zshrc
        fi
        echo "remove zsh-autocomplete from plugin list(of my zsh)..."
        echo plugins_list |sed -i '/zsh-autocomplete/d' 
        update_omz_plugins_rc
    fi
}
update_comp_plugins_config_rc

# 利用sed并启用扩展正则原地修改,将Zsh主题设置为随机
sed -Ei 's/(^ZSH_THEME=)(.*)/\1"random"/' "$zshrc_path"
#设置随机选择的主题的列表为ys,junkfood,rkj-repos;具体可以改成自己喜欢的主题
sed -Ei.bak 's/(^#*\s*)(ZSH_THEME_RANDOM.*=)(.*)/\2("ys" "junkfood" )/' "$zshrc_path"

#检查修改结果
#检查配置文件是否有相应的行
cat "$zshrc_path" | grep -e zsh-syntax-highlighting -e zsh-autosuggestions \
    -e zsh-history-substring-search -e zsh-autocomplete -e zsh-completions
cat ~/.zshrc | grep -E '^[^#]' | grep -e random -e THEME -e RANDOM | cat -n

#刷新配置结果
# shellcheck disable=SC1090
# source "$zshrc_path"
cd "$current_wd" || exit 1
echo "======END======"
exec zsh
