#! /usr/bin/env bash
# 参考文档:https://www.lazyvim.org/
# 快捷键:https://www.lazyvim.org/keymaps
# required
test -e ~/.config/nvim &&
    mv ~/.config/nvim{,.bak}

# optional but recommended
{
    mv ~/.local/share/nvim{,.bak}
    mv ~/.local/state/nvim{,.bak}
    mv ~/.cache/nvim{,.bak}
} &> /dev/null
github_mirror="https://gh-proxy.com/"
# 建议使用github镜像加速或国内代码仓库托管平台代替(脚本下载+仓库clone,注意第二阶段的clone加速设置)
git clone "$github_mirror"https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git
nvim
