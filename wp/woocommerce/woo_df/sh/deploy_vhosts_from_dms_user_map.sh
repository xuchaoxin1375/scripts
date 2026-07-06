#!/usr/bin/env bash

default_config=demo.conf.txt
map_file="$HOME/sh/nginx_conf/default_vhost.conf"

while read -r dms username; do
    cp "$default_config" "$dms.conf" -vf
    sed -i "s/domain.com/$dms/g" "$dms.conf"
    sed -i "s/domain/${dms%.com}/g" "$dms.conf"
    sed -i "s/username/$username/g" "$dms.conf"
done < "$map_file"
