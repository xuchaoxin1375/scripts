#!/bin/bash
# 配置zsh(oh my zsh)相关插件,让体验向fish靠拢
# 此部署代码尽量实现幂等性(避免反复运行导致配置文件内容混乱.);
# 此脚本配置的不全仅适用于zsh,对于bash没有作用,不过此脚本可以用bash执行部署;
# 软件要求:zsh需要用户实现安装好;对于一些精简的系统,可能要事先安装curl和git来拉去一些插件代码;
# 补全类插件要求比较严格,尤其是动态自动补全实现比较复杂需要更多的步骤
# 测试补全插件效果时,对于基础工具,注意区分gnu版本和bsd版本,可用选项和风格有所不同
# 卸载此套件:本脚本主要下载了oh-my-zsh配置框架(如果是默认选项会尝试为你安装),
# 并且下载了一组zsh插件,并且对于补型插件修改了配置文件(~/.zshrc);
# 若要删除插件,请进入 $ZSH_CUSTOM/plugins目录中,删除不需要的插件(目录),然后修改(~/.zshrc)配置中多余的代码片段
# 此脚本通过sed修改的配置片段都使用了起始和结束标记组合('>>>'和'<<<',模仿conda风格),用户可以清晰的识别出修改的代码片段
# 最后记得检查oh-my-zsh中的插件列表(plugins数组)中的插件是否移除多余内容.

# 一键部署
# bash <(https://gitee.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/deploy_omz.sh)
requirements=(git curl)
meet_req=true
for req in "${requirements[@]}"; do
    if command -v "$req" >&/dev/null; then
        echo "[error]:'$req' is not available! Install $req and retry again."
        meet_req=false
    fi
done

if [[ $meet_req == false ]]; then exit 2; fi
version=20260417
# 默认插件安装选项(仅补全类插件)
install_zsh_completions=true # true|false
install_zsh_autocomplete=omz # omz|std|false
install_omz="default"        # default|github|gitee
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
    -omz|--install-omz) [""|default|gitee|github]
        install oh-my-zsh(omz) if omz is not available.
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
            -o | --install-omz)
                install_omz="$2"
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
omz_installer() {
    if [[ $install_omz ]]; then
        echo "检查oh-my-zsh是否已经安装"
        if [[ -d $HOME/.oh-my-zsh ]]; then
            echo "oh-my-zsh已经安装(如果要重新安装请删除$HOME/.oh-my-zsh目录)"
            return 1
        fi
        echo "将要安装oh-my-zsh [$install_omz]"
    else
        echo "跳过安装oh-my-zsh"
        return 0
    fi
    if [[ $install_omz == default ]]; then
        sh -c "$(curl -fsSL https://install.ohmyz.sh/)"
    elif [[ $install_omz == github ]]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    elif [[ $install_omz == gitee ]]; then
        curl https://gitee.com/mirrors/oh-my-zsh/raw/master/tools/install.sh -o ~/install.sh
        # 由于国内网络问题,可能需要多尝试几次一下source 命令才可以安装成功.(我将其注释掉,采用换源后再执行clone
        #source install.sh
        #本段代码将修改install.sh中的拉取源,以便您能够冲gitee上成功将需要的文件clone下来.

        # 本段代码会再修改前做备份(备份文件名为install.shE)
        # shellcheck disable=SC2016
        sed '/(^remote)|(^repo)/I s/^#*/#/ ;
/^#*remote/I a\
REPO=${REPO:-mirrors/oh-my-zsh}\
REMOTE=${REMOTE:-https://gitee.com/${REPO}.git} ' -r ~/install.sh > ~/gitee_install.sh
        # 执行安装
        # shellcheck source=/dev/null
        source ~/gitee_install.sh

    fi

}
omz_installer
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
    update_zc_config_rc() {
        # 定义zsh-completions片段
        mark_zc_start='# >>> zsh-completions'
        mark_zc_end='# <<< zsh-completions'
        if [[ "$install_zsh_completions" == "true" ]]; then
            echo "安装zsh-completions ..."
            _switch=''
            # 如果zsh-autocomplete启用,则设置注释开关
            if [[ $install_zsh_autocomplete != "false" ]]; then
                _switch='#'
            fi
            # 检查是否曾经配置过zsh-completions片段
            # 如果已有,则原地更新(可以通过删除旧片段),然后统一执行插入

            if grep "$mark_zc_start" "$zshrc_path"; then
                echo "Remove old zsh-completions  snippet..."
                sed -i "/$mark_zc_start/,/$mark_zc_end/d" "$zshrc_path"
            fi
            # 在合适的位置插入zsh_completions配置片段
            sed -i '/^plugins=(/i\
# >>> zsh-completions\
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src\
'"$_switch"'autoload -U compinit \&\& compinit # 有zsh-autocomplete时这一行注释掉防止冲突\
# <<< zsh-completions\
' ~/.zshrc
            # 重建补全(词库)
            rm -f ~/.zcompdump
        else
            # zsh-completions不安装(配置撤销)
            sed -i "/$mark_zc_start/,/$mark_zc_end/d" "$zshrc_path"
        fi
    }
    update_zc_config_rc
    # 安装zsh-autocomplete的方案分2类
    # 标准方式安装zsh-autocomplete(不依赖于oh my zsh等配置框架)
    update_zac_config_rc() {
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
            echo "Try to remove zsh-autocomplete from plugin list(of my zsh)..."
            # 移除可能omz安装模式下,oh my zsh中的plugins残留插件名
            # plugins_list=$(echo "$plugins_list" | sed '/zsh-autocomplete/d')
            # 将 zsh-autocomplete 替换为空字符
            plugins_list="${plugins_list//zsh-autocomplete/}"

        elif [[ $install_zsh_autocomplete == "omz" ]]; then
            # 移除可能在std模式下,在~/.zshrc头部插入的source代码片段;
            echo "Try to remove 'source .../zsh-autocomplete' code snippet..."
            sed -i '/# >>> zsh-autocomplete/,/# <<< zsh-autocomplete/d' "$zshrc_path"
        fi
        # 时候后置的动作(收尾部分)
        if [[ "$install_zsh_autocomplete" == "false" ]]; then
            sed -i '/# >>> zsh-autocomplete/,/# <<< zsh-autocomplete/d' "$zshrc_path"
            plugins_list="${plugins_list//zsh-autocomplete/}"
            sed -i '/# >>> zac bindkey config/,/# <<< zac bindkey config/d' "$zshrc_path"
        else
            # 设置compinit
            # 插入前清空可能的旧片段
            sed -i '/# >>> zac_compinit/,/# <<< zac_compinit/d' "$zshrc_path"
            sed -i '$a\
# >>> zac_compinit\
# 避免zsh compinit: insecure directories and files, run compaudit for list.\
# compaudit | xargs chmod g-w,o-w --verbose # 通常是linuxbrew单独用户的原因(所有者问题),建议忽略这部分的检查\
zstyle '"'*:compinit'"' arguments -i -u \
# <<< zac_compinit\
' "$zshrc_path"
            # 配置快捷键
            # 如果此前配置过,则清空相应区域,以便统一更新相应配置
            sed -i '/# >>> zac bindkey config/,/# <<< zac bindkey config/d' "$zshrc_path"
            # 定义快捷键片段
            # shellcheck disable=SC2016
            # shellcheck disable=SC2125
            zsh_bindkey_config='
# 将 Tab 和 Shift 和 Tab 设置为更改菜单中的选择(menu-select)
# 这样， Tab 和 ShiftTab 分别将菜单中的选择项向右和向左移动，而不是退出菜单：
bindkey              '^I' menu-select
bindkey "$terminfo[kcbt]" menu-select

# 使 Enter 始终提交命令行
# 这样一来，即使您在菜单中， Enter 也始终会提交命令行：
bindkey -M menuselect '^M' .accept-line

# 其他 
# 将 Tab 和 ShiftTab 添加到菜单中(menu-complete)
# 这样，当在命令行中按下 Tab 和 ShiftTab 时，它们将进入菜单而不是插入补全命令：
# bindkey              '^I'         menu-complete
# bindkey "$terminfo[kcbt]" reverse-menu-complete

# 使 ← 和 → 始终在命令行上移动光标
# 这样，即使您在菜单中， ← 和 → 也始终会在命令行上移动光标：
# bindkey -M menuselect  '^[[D' .backward-char  '^[OD' .backward-char
# bindkey -M menuselect  '^[[C'  .forward-char  '^[OC'  .forward-char
'
            echo "$zsh_bindkey_config" > ~/zsh_bindkey_config.sh
            # 快捷键脚本文件插入到.zshrc
            sed -i '$a\
# >>> zac bindkey config\
source ~/zsh_bindkey_config.sh\
# <<< zac bindkey config\
' ~/.zshrc

            # 如果是ubuntu系统,设置.zshenv
            if [[ -f /etc/os-release ]] && grep -q -i 'NAME="Ubuntu' /etc/os-release; then
                echo "ubuntu系统设置.zshenv"
                zshenv=~/.zshenv
                append_zshenv=true
                if [[ -f $zshenv ]]; then
                    grep '^skip_global_compinit=1' $zshenv && append_zshenv=false
                fi
                if [[ $append_zshenv == true ]]; then
                    echo 'skip_global_compinit=1' >> $zshenv
                fi
            fi
            # When using Nix, add to your home.nix file:
            # programs.zsh.enableCompletion = false;
        fi
    }

    update_zac_config_rc
    # 将最终的plugins列表写回到~/.zshrc中
    update_omz_plugins_rc
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

# 移除多余空行(大片空行压缩)
sed -i '/^$/N;/^\n$/D' "$zshrc_path"

#刷新配置结果
# shellcheck disable=SC1090
# source "$zshrc_path"
cd "$current_wd" || exit 1
echo "======END======"
exec zsh
