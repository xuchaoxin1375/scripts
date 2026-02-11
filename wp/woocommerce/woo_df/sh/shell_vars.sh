#!/bin/bash
# 定义常用变量(路径变量为主)
echo "loading pre-defined variables..."
# wsl 用户: 统一将使用wsl的设备设置桌面的统一别名目录C:/desktop->$desktop,使用符号链接可以在不改动的情况下优雅的实现这一点
# New-Item -ItemType Junction  -Path C:/desktop -Target $home/desktop -Verbose -Force #powershell执行

uploader_files="/srv/uploads/uploader/files"
woo_df="/www/woo_df"
pys="$woo_df/pys"

desktop="/mnt/c/Users/Administrator/Desktop"
wslsh="/mnt/c/repos/scripts/wp/woocommerce/woo_df/sh"
# sh="$wslsh"
# 根据不同的系统环境为变量sh配置不同的取值
if [[ -d /mnt/c/ ]]; then
    # wsl环境
    sh="$wslsh"
else
    # 非wsl环境,如linux服务器等
    sh="/www/sh"
fi
# 配置oh-my-bash主题路径和自定义轻量化主题路径
# cp $omb_copied_duru  $omb_themes -fv
omb_themes="$HOME/.oh-my-bash/themes"
omb_cduru_theme="$omb_themes/cduru"
omb_cduru="$sh/omb-copied-duru.sh"
# 宝塔nginx配置文件路径
# vhost
bt_nginx_vhost_conf_home="/www/server/panel/vhost/nginx"
bt_nginx_conf_home="/www/server/nginx/conf"

# 将定义的变量声明为环境变量
export desktop sh omb_themes omb_cduru_theme omb_cduru \
bt_nginx_vhost_conf_home \
bt_nginx_conf_home uploader_files woo_df pys

# mkdir -p $omb_themes
# ln -s $omb_cduru $omb_cduru_theme/cduru.theme.sh -fv
