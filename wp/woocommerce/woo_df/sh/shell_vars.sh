#!/bin/bash
# 定义常用变量(路径变量为主)
echo "loading pre-defined variables..."
# wsl 用户: 统一将使用wsl的设备设置桌面的统一别名目录C:/desktop->$desktop,使用符号链接可以在不改动的情况下优雅的实现这一点
# New-Item -ItemType Junction  -Path C:/desktop -Target $home/desktop -Verbose -Force #powershell执行

desktop=/mnt/c/Users/Administrator/Desktop
wslsh=/mnt/c/repos/scripts/wp/woocommerce/woo_df/sh
sh="$wslsh"

# 配置oh-my-bash主题路径和自定义轻量化主题路径
# cp $omb_copied_duru  $omb_themes -fv
omb_themes=~/.oh-my-bash/themes
omb_cduru_theme=$omb_themes/cduru
omb_cduru=/www/sh/omb-copied-duru.sh
# mkdir -p $omb_themes
# ln -s $omb_cduru $omb_cduru_theme/cduru.theme.sh -fv
