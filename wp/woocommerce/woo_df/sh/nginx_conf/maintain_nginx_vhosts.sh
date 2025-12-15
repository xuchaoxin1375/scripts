#! /bin/bash
# /usr/bin/python3 
python3 /www/sh/nginx_conf/maintain_nginx_vhosts.py update -m old >> /var/log/maintain_nginx_vhosts.log 2>&1
nginx -t && nginx -s reload
