#!/usr/bin/env bash
echo "创建符号链接,让所有网站根目录在标准wwwroot下可以访问"

shopt -s nullglob

DEBUG=0 # 正式运行时改为0

echo "将人员目录内的网站根目录套一层wordpress目录名,使得所有网站根目录名为wordpress"
# 将/www/下的网站创建对应的符号链接到/www/wwwroot/下
for site in /{www,data}/{wyr,xch,xmm,xqq,zjh,zy,wcr}/*; do
    echo "处理域名: [$site]" # /www/wyr/domain

    user_dir="$(dirname "$site")" # /www/wyr
    user_name="$(basename "$user_dir")" # wyr
    # ln -snfv "$site" /www/wwwroot/"$(basename "$site")"

    site_name="$(basename "$site")" # domain
    # 移除旧目录
    new_site_name_dir="/www/wwwroot/$user_name/$site_name" # /www/wwwroot/wyr/domain

    echo "尝试清理旧目录: $new_site_name_dir"
    if [[ $DEBUG == 0 ]]; then

        if [ -d "$new_site_name_dir" ];then

            if rm -rfv "$new_site_name_dir";then
                echo "清理旧目录成功: $new_site_name_dir"
            else
                echo "清理旧目录失败: $new_site_name_dir"
                exit 1
            fi
        else
            echo "目录不存在,无需清理"
            # exit 1
        fi
    fi

    # 更新:补充对应的域名后缀:(少数个别非.com域名自行手动修改)
    site_name="${site_name}.com" # domain.com
    new_site_name_dir="/www/wwwroot/$user_name/$site_name" # /www/wwwroot/wyr/domain.com
    # 符号链接名最终是wordpress
    site_root="$new_site_name_dir/wordpress" # /www/wwwroot/wyr/domain/wordpress
    echo "[Debug]: [user_name]:$user_name [site_name]: $site_name;[site_root]:$site ->[new_site_root]: $site_root"

    if [[ $DEBUG == 1 ]]; then
        continue
    else
        mkdir -pv "$new_site_name_dir"
        ln -snfv "$site" "$site_root"
    fi
done