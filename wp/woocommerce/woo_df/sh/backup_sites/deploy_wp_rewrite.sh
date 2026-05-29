#!/bin/bash

res=(/www/server/panel/vhost/rewrite/*.conf)
# 覆盖所有网站的rewrite规则.
for r in "${res[@]}"; do
    cp /www/sh/nginx_conf/RewriteRules.LF.conf "$r" -fv
done
