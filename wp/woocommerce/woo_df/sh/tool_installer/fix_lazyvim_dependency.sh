#!/usr/bin/env bash
if command -v npm &> /dev/null; then
    echo "尝试卸载可能残留的错误 tree-sitter-cli..."
    npm uninstall -g tree-sitter-cli
else
    echo "npm is not available. Skipping npm uninstall step."
fi
sudo apt remove tree-sitter-cli tree-sitter 2> /dev/null

# 检查所有 tree-sitter 相关的命令是否已被卸载
type -a tree-sitter
# 更新apt信息
sudo apt update
# 补齐 Ubuntu 较低版本的 编译依赖

sudo apt install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    clang \
    git \
    curl
# 安装/更新 rust
curl https://sh.rustup.rs -sSf | sh
# shellcheck disable=SC1091
source "$HOME/.cargo/env"

rustup update stable
rustup default stable

rustc --version
cargo --version
# 正式下载并编译安装tree-sitter-cli
cargo install --locked tree-sitter-cli
# 检查结果
which tree-sitter
tree-sitter --version
ldd "$(which tree-sitter)" | grep libc
# 进程替换,确保环境重新加载,防止tree-sitter-cli找不到.
exec bash
