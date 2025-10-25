    ssh root@$env:df_server3 @"
    bash /update_nginx_vhosts_conf.sh;/update_nginx_vhosts_conf.sh -d /www/server/panel/vhost/nginx --days 1 
    bash /www/sh/nginx_conf/update_nginx_vhosts_log_format.sh -d /www/server/panel/vhost/nginx 
"@