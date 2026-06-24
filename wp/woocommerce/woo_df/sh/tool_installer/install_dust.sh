#!/bin/bash
set -e # 遇到错误立即退出

# 函数：获取dust最新版本号
get_latest_dust_version() {
    # 使用GitHub API获取最新release的tag_name (格式如 "v1.2.1")
    local version
    version=$(curl -sL "https://api.github.com/repos/bootandy/dust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo "$version"
}

# 函数：安装dust
install_dust() {
    local version="$1"
    local deb_filename="du-dust_${version#v}-1_amd64.deb" # 处理版本号前缀"v"
    local download_url="https://github.com/bootandy/dust/releases/download/${version}/${deb_filename}"

    echo "🔍 正在下载 dust 最新版 (${version})..."
    wget -q --show-progress -O dust.deb "$download_url" || {
        echo "❌ 下载失败，请检查网络或版本号格式。"
        echo "   尝试的URL: $download_url"
        exit 1
    }

    echo "📦 正在安装..."
    sudo dpkg -i dust.deb

    echo "🧹 正在清理安装包..."
    rm -v dust.deb

    echo "✅ 安装完成！"
    dust --version
}

# 主流程
echo "🚀 开始安装 dust 最新版..."
latest_version=$(get_latest_dust_version)

if [ -z "$latest_version" ]; then
    echo "⚠️  无法从GitHub API获取最新版本信息，尝试使用已知版本..."
    # 作为备用，可以定义一个已知最新版本，例如从搜索结果中得知的 v1.2.4
    latest_version="v1.2.4"
    echo "   使用备用版本: $latest_version"
fi

install_dust "$latest_version"

# 示例用法
echo -e "\n📊 示例用法:"
echo "  dust .    # 查看当前目录磁盘使用情况"
echo "  dust --help    # 查看更多选项"
