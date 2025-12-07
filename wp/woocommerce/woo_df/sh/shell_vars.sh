#!/bin/bash
# 定义常用变量(路径变量为主)
echo "loading pre-defined variables..."
# 统一将使用wsl的设备设置桌面的统一别名目录C:/desktop->$desktop,使用符号链接可以在不改动的情况下优雅的实现这一点
# New-Item -ItemType Junction  -Path C:/desktop -Target $home/desktop -Verbose -Force

desktop=/mnt/c/Users/Administrator/Desktop
wslsh=/mnt/c/repos/scripts/wp/woocommerce/woo_df/sh
sh="$wslsh"