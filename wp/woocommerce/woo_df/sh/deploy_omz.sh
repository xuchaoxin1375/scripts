#!/bin/bash
# 配置zsh(oh my zsh)相关插件,让体验向fish靠拢
# 此部署代码尽量实现幂等性(避免反复运行导致配置文件内容混乱.)
echo "version:20260411"
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
! [[ -d $zap ]] && git clone --depth 1 https://gitee.com/zsh-users/zsh-autosuggestions $zap

! [[ -d $zshp ]] && git clone --depth 1 https://gitee.com/zsh-users/zsh-syntax-highlighting.git $zshp

! [[ -d $zhssp ]] && git clone --depth 1 https://gitee.com/mirror-hub/zsh-history-substring-search $zhssp

# zsh-completions这个项目gitee官方可能没有镜像,使用个人用户的自镜像版本(建议有需要的可以自己拉取一份比较安全)
# 另外这个插件比其他zsh插件不同,在配合oh my zsh使用时需要额外注意配置文件的写法;
! [[ -d $zcp ]] && git clone --depth 1 https://gitee.com/duchenpaul/zsh-completions.git $zcp
! [[ -d $zysu ]] && git clone https://gitcode.com/gh_mirrors/zs/zsh-you-should-use.git $zysu
# 将工作目录转移到家目录
# cd ~ || exit 1
zshrc_path="$HOME/.zshrc"
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
# 为每行插件名末尾增加`\`便于在sed中使用(注意最后一个比较特殊,手动补充\\)
plugins_list="${plugins_list//$'\n'/\\$'\n'}\\"
echo "[$plugins_list]"

echo "[$zshrc_path]"
if grep '^plugins=(.*)' "$zshrc_path"; then
    echo "初次覆盖plugins(单行)"
    sed -i 's/^plugins=(.*)/\
plugins=(\
'"$plugins_list"'
)/' -i "$zshrc_path"
elif grep '^plugins=($' "$zshrc_path"; then
    echo "覆盖插件列表(多行plugins更新)"
    sed -i '/^plugins=(/,/)/c\
plugins=(\
'"$plugins_list"'
)' -i "$zshrc_path"

fi
# 在plugins= 行或者source $ZSH/oh-my-zsh.sh行上方插入额外片段行(适用于zsh-completions)
# shellcheck disable=SC2016
# sed -i '/source \$ZSH\/oh-my-zsh\.sh/i\
if ! grep '# >>> zsh-completions' "$zshrc_path"; then
    sed -i '/^plugins=(/i\
# >>> zsh-completions\
fpath+=${ZSH_CUSTOM:-${ZSH:-~\/.oh-my-zsh}\/custom}\/plugins\/zsh-completions\/src\
autoload -U compinit \&\& compinit\
# <<< zsh-completions\
' ~/.zshrc
fi
# 重建补全
rm -f ~/.zcompdump

#检查配置文件是否有相应的行
cat "$zshrc_path" | grep -e zsh-syntax-highlighting -e zsh-autosuggestions -e zsh-history-substring-search -e zsh-completions

# 利用sed并启用扩展正则原地修改,将Zsh主题设置为随机
sed -Ei 's/(^ZSH_THEME=)(.*)/\1"random"/' "$zshrc_path"
#设置随机选择的主题的列表为ys,junkfood,rkj-repos;具体可以改成自己喜欢的主题
sed -Ei.bak 's/(^#*\s*)(ZSH_THEME_RANDOM.*=)(.*)/\2("ys" "junkfood" )/' "$zshrc_path"
#检查修改结果
cat ~/.zshrc | grep -E '^[^#]' | grep -e random -e THEME -e RANDOM | cat -n
#刷新配置结果
# shellcheck disable=SC1090
# source "$zshrc_path"
exec zsh
