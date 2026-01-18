#! /bin/bash

sed -i -e '/#CERT-APPLY-CHECK--START/i\
    \
    #CUSTOM-CONFIG-START\
    include /www/server/nginx/conf/com.conf;\
    #CUSTOM-CONFIG-END\
' ./domain1.com.conf