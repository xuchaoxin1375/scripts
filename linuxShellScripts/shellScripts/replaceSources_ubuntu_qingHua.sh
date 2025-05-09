#  以kali-linux 更换国内镜像源(阿里源为例)
# 备份:backup the origin source.list(or just rename(use move command))
# 注意sources.list 不要拼错(带s)
cd /etc/apt
sudo mv sources.list sources.list.bak_bySh
# 切换到家目录,写入国内镜像源到一个文件中(文件名为sources.list),采用多行输入的方式写入
#这里以阿里源为例
cd ~
# 多行输入
cat >sources.list <<EOF
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ impish main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ impish main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ impish-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ impish-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ impish-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ impish-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ impish-security main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ impish-security main restricted universe multiverse

# 预发布软件源，不建议启用
# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ impish-proposed main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ impish-proposed main restricted universe multiverse


EOF

#上面的EOF间的内容不要写入其他与源无关的内容(除了注释和源,其他命令不要写在里头)
# 检查写入的内容:
echo "check the conetent of the file 'source.list'"
## 将家目录下的sources.list 转移到/etc/apt目录下(sodu可以作用与mv/cp等命令,
## 但好像不可以直接作用与cat,所以没有直接在/etc/apt目录下创建新文件)
sudo mv sources.list /etc/apt
cat /etc/apt/sources.list
# 更新并使得apt配置文件生效
echo "updating the apt..."
sudo apt update
