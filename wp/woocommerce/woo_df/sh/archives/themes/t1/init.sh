#! /bin/bash
script_root='/repos/scripts'
if [[ -d "$script_root" ]]; then { echo 'The target dir is already exist! remove old dir...' ; sudo rm "$script_root" -rf ; } ; fi
# rm /repos/scripts -rf 
git clone --depth  1 https://gitee.com/xuchaoxin1375/scripts.git "$script_root"

# 配置更新代码的脚本的符号链接
ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/sh -fv
# 使用简短的更新代码仓库的命令
bash /www/sh/update_repos.sh
# 向bash,zsh配置文件导入常用的shell函数,比如wp命令行等
bash /www/sh/shellrc_addition.sh