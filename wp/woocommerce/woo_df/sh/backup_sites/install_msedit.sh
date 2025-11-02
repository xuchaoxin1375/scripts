# 1 注意edit版本链接的获取方案(1.1,1.2分别为自动和手动)
## 1.1 方案1:自动获取最新版本
# 获取系统架构
arch=$(uname -m)

# 获取最新版本信息
latest_release=$(curl -s https://api.github.com/repos/microsoft/edit/releases/latest)
version=$(echo $latest_release | grep tag_name | cut -d '"' -f 4)

# 根据架构选择正确的下载链接
if [ "$arch" = "x86_64" ]; then
    download_url=$(echo $latest_release | grep browser_download_url | grep x86_64-linux-gnu | cut -d '"' -f 4)
elif [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
    download_url=$(echo $latest_release | grep browser_download_url | grep aarch64-linux-gnu | cut -d '"' -f 4)
else
    echo "不支持的架构: $arch"
    exit 1
fi

echo "检测到系统架构: $arch"
echo "下载链接: $download_url"

# 下载最新版本
curl -L $download_url -o ~/edit.tar.zst

## 1.2 方案2:根据指定链接下载指定版本

# curl -L https://github.com/microsoft/edit/releases/download/v1.2.1/edit-1.2.0-x86_64-linux-gnu.tar.zst -o ~/edit.tar.zst


# 2 解压并安装
zstd -d ~/edit.tar.zst -o ~/edit.tar
# 解压tar获得edit文件(可执行程序)
tar -xvf ~/edit*.tar -C ~

# 重命名edit为msedit #推荐,部分情况在需要,edit名字可能和已有命令冲突!
newname="msedit" # 如果不想要改动edit名字,则把msedit改回edit即可(pacman安装的ms-edit就是通过msedit调用的)
mv ~/edit ~/$newname -fv

# 如果~/.local/bin 不存在，则创建
if [ ! -d ~/.local/bin ]; then
  mkdir -p ~/.local/bin
fi
mv ~/$newname ~/.local/bin/$newname -fv

# 尝试为所有用户创建软链接(可能需要权限)
# 添加权限检查和sudo
if [ -w /usr/local/bin ]; then
    ln -s ~/.local/bin/$newname /usr/local/bin/$newname -fv
else
    echo "需要管理员权限才能创建软链接到 /usr/local/bin/"
    # 或者提示用户手动执行: sudo ln -s ~/.local/bin/$newname /usr/local/bin/$newname
fi

# 检查软件包是否安装成功,版本号打印(使用msedit这个名字(或者你自定义的名字)调用此文本编辑器)
$newname --version
$newname -h 