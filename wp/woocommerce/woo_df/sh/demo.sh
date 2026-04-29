# 判断系统平台,找到正确的brew路径并执行shellenv命令生成环境变量设置语句;在通过eval注入到当前环境中;
if [[ $OSTYPE == linux* ]]; then
    test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
    test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ $OSTYPE == darwin* ]]; then
    # 针对 Apple Silicon Mac
    test -d /opt/homebrew && eval "$(/opt/homebrew/bin/brew shellenv)"
    # 针对 Intel Mac
    test -d /usr/local/bin/brew && eval "$(/usr/local/bin/brew shellenv)"
fi
# 插入到shell配置文件中以便持久化
echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bashrc
echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.zshrc
