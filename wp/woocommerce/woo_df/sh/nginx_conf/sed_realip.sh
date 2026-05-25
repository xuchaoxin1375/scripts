#!/bin/bash
# sed  -n '2p' com_com.conf
# sed -n '\|include /www/.*/cf-realip\.conf;|p' com_com.conf

sed -i '\|include /www/.*/cf-realip.conf;| s/^/# /' com_com.conf
sed -i -E 's|#[[:space:]]*(include real_cdn_ip.conf;)|\1|' com_com.conf

# sed -n '\|include /www/.*/cf-realip.conf;| s/^/# /p' com_com.conf
# sed -n -E 's|#[[:space:]]*(include real_cdn_ip.conf;)|\1| p' com_com.conf

sed -i -E '
  \|include /www/.*/cf-realip\.conf;| s/^/# /
  s|#[[:space:]]*(include real_cdn_ip\.conf;)|\1|
' com_com.conf
