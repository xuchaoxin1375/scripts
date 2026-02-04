    $cmds = @"
#START
bash /update_nginx_vhosts_conf.sh -d /www/server/panel/vhost/nginx --days 1 -M 1 
bash /www/sh/nginx_conf/update_nginx_vhosts_log_format.sh -d /www/server/panel/vhost/nginx 
bash /www/sh/update_user_ini.sh
python3 /www/sh/nginx_conf/maintain_nginx_vhosts.py maintain -d -k first

# END
"@
    # 方案1
    # ssh $User@$HostName ($cmds -replace "`r", "")
    # 方案2
    $cmds | Convert-CRLF -To LF|Get-CRLFChecker -ViewCRLF