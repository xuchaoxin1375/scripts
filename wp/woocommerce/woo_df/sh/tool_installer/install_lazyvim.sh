#! /usr/bin/env bash
# 安装依赖:https://www.lazyvim.org/
# 1.允许单独执行neovim的安装操作
# 2.允许指定是否使用github镜像
# 建议安装后运行 :LazyHealth 命令。这将加载所有插件并检查一切是否正常运行。
# neovim安装最新版
# 如果有brew可用,则使用brew安装
if command -v brew &> /dev/null; then
    brew install neovim
else
    # 下载并安装到 /usr/local

    # 验证版本
    nvim --version
fi

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
