# 设置 Conda 在安装包或搜索包时显示使用的具体镜像源（channel）URL,如果实现不存在配置文件.condarc,还会创建配置文件.condarc
conda config --set show_channel_urls yes

# 查看配置前的内容
Get-Content $home/.condarc
# 将国内源(比如清华源)写入到配置文件中
@'
channels:
  - nodefaults
custom_channels:
  conda-forge: https://mirrors.ustc.edu.cn/anaconda/cloud
  bioconda: https://mirrors.ustc.edu.cn/anaconda/cloud
show_channel_urls: true
'@ >$home/.condarc

# 检查写入结果
Get-Content $home/.condarc
# 清理conda缓存
conda clean -i

