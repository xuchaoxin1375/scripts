#!/bin/bash
# 20260411
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
git clone --depth 1 https://gitee.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

git clone --depth 1 https://gitee.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

git clone --depth 1 https://gitee.com/mirror-hub/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
# 将工作目录转移到家目录
cd ~ || exit 1
zshrc_path="$HOME/.zshrc"
# 配置插件
plugins_list=$(
    cat << EOF
    git\\
    z\\
    zsh-syntax-highlighting\\
    zsh-autosuggestions\\
    zsh-history-substring-search\\
EOF
)
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

#检查配置文件是否有相应的行
cat "$zshrc_path" | grep -e zsh-syntax-highlighting -e zsh-autosuggestions -e zsh-history-substring-search

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
