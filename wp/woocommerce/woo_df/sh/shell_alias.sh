#!/bin/bash

echo "Loading pre-defined aliases..."
# 重新加载别名配置(从外部引入sh环境变量)
# shellcheck disable=SC2154
# shellcheck disable=SC2139
alias update_alias="source '$sh/shell_alias.sh'"
# 常用内置命令缩写
alias bashrc='source ~/.bashrc'
alias zshrc='source ~/.zshrc'
alias cls=clear
alias ls='\ls --color=auto' #macos 上可能默认没有启用颜色
alias lsdir='ls -d */'      #列出所有目录(不含文件)
# man手册(macos bsd版本的命令)
# 例如,使用 bman ln 即可查看bsd版本的ln的原生帮助
alias bman='man -M /usr/share/man'
# 第三方程序缩写(尽可能用neovim(nvim)代替vim)
command -v nvim &> /dev/null && alias vim=nvim
command -v neovim &> /dev/null && alias vim=neovim
command -v vim &> /dev/null && alias vi=vim
# fail2ban系列命令缩写f2b或fb
alias fbc='fail2ban-client'
alias sfbc='sudo fail2ban-client' #非root用户使用,也兼容root用户使用
# brew 已经安装的情况下(执行此命令位置有讲究,或者放到shellrc_addition中)
[[ $OSTYPE != 'darwin'* && $(id -u) -eq 0 ]] && command -v 'brew' >&/dev/null && alias brew=brewr

alias curl='curl --proto-default https'
alias fbcs='fail2ban-client status'
alias fbregex='fail2ban-regex'
alias fbt='fail2ban-testcases'
# windows端wsl的shell脚本目录快速跳转
# python
alias python=python3
alias py=python3
alias pip=pip3
# nix
if command -v nix &> /dev/null; then
    # echo "[nix]:loading nix alias..." # debug
    # alias nia='nix profile add'

    alias nixup='nix profile upgrade --all'
    alias nixupgrade='nix upgrade-nix'
    alias nixls='nix profile list'
    alias nixsearch='nix search nixpkgs'
    alias nixshow='nix search nixpkgs --exclude-details' # 只显示包名
    alias nixrun='nix run nixpkgs#'
    ni() {
        # 支持多包，智能添加 nixpkgs# 前缀
        local packages=()
        for pkg in "$@"; do
            if [[ "$pkg" == *"#"* ]]; then
                packages+=("$pkg")
            else
                packages+=("nixpkgs#$pkg")
            fi
        done
        nix profile add "${packages[@]}"
    }
    show_nix_configs_core() {
        # 查看镜像源/缓存源（类似 conda channels）
        nix config show | grep substituters
        # 查看实验特性
        nix config show | grep experimental-features

        # 查看是否受信任（类似查看 conda 的 allow_conda_downgrades）
        nix config show | grep trusted-users

        # 查看并发构建数
        nix config show | grep cores

        # 查看最大作业数
        nix config show | grep max-jobs

        # 查看超时设置
        # nix config show | grep timeout

        # 访问令牌（类似 conda 的 tokens）
        # nix config show | grep access-tokens
    }
    # 额外的别名 nix profile add
    alias nia=ni
    # alias restart-nix-daemon='sudo systemctl restart nix-daemon'
    restart-nix-daemon() {
        # 适用于有systemd的系统(大部分linux)
        if command -v systemctl &> /dev/null; then
            echo "重启 nix-daemon 服务 (systemd)..."
            sudo systemctl restart nix-daemon 2> /dev/null || true
        # 适用于macos(darwin)系统
        elif command -v launchctl &> /dev/null; then
            echo "重启 nix-daemon 服务 (launchd)..."
            sudo launchctl kickstart -k system/org.nixos.nix-daemon 2> /dev/null || true
        fi
    }
    # 软件包移除和空间回收
    alias nixrm='nix profile remove'
    alias nixgc='nix store gc'
    alias nixgcd='nix-collect-garbage -d'
    alias nixgc-deep='nix profile wipe-history --older-than 7d && nix store gc'
fi
