#! /bin/bash
version="1.5.7" #指定要安装的版本(源:github)
cd ~ || exit
wget "https://github.com/facebook/zstd/releases/download/v$version/zstd-$version.tar.gz"
tar xvf zstd-*.tar.gz
cd "zstd-$version" || exit
# make -j 16
make -j$(nproc) && make install

# 移除掉系统默认安装的zstd(根据需要执行),系统预装的版本优先级更高
sudo apt remove zstd