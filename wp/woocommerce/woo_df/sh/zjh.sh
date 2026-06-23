#!/usr/bin/env bash
echo "创建符号链接,让所有网站根目录在标准wwwroot下可以访问"


echo "将人员目录内的网站根目录套一层wordpress目录名,使得所有网站根目录名为wordpress"
# 将/www/下的网站创建对应的符号链接到/www/wwwroot/下
for site in /{www,data}/{wyr,xch,xmm,xqq,zjh,zy,wcr}/*; do
    echo "处理域名: [$site]" # /www/wyr/domain
    user_dir="$(dirname "$site")" # /www/wyr
    user_name="$(basename "$user_dir")" # wyr
    # ln -snfv "$site" /www/wwwroot/"$(basename "$site")"
    site_name="$(basename "$site")" # domain
    new_site_name_dir="/www/wwwroot/$user_name/$site_name" # /www/wwwroot/wyr/domain
    site_root="$new_site_name_dir/wordpress" # /www/wwwroot/wyr/domain/wordpress
    echo "[Debug]: [user_name]:$user_name [site_name]: $site_name;[site_root]:$site ->[new_site_root]: $site_root"

    mkdir -pv "$new_site_name_dir"
    ln -snfv "$site" "$site_root"
done

