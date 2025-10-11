#sed配置强制使用https

# sed -ri "/\/\*\* Sets up WordPress vars and included files. \*/i \

sed -r "/\/\* That's all, stop editing! Happy publishing. \*/i \
\$_SERVER['HTTPS'] = 'on'; define('FORCE_SSL_LOGIN', true); define('FORCE_SSL_ADMIN', true);\
\n\
" w.php