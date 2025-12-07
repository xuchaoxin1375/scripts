# 注意路径中的大小写
# 创建桌面简写路径变量
New-Item -ItemType Junction  -Path C:/desktop -Target $home/desktop -Verbose -Force