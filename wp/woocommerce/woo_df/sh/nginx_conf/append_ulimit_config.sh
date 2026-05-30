#!/bin/bash
# usage: bash $sh/nginx_conf/append_ulimit_config.sh
limits_conf="/etc/security/limits.conf"
if [[ -f $limits_conf ]]; then
    echo "
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
nginx soft nofile 65536
nginx hard nofile 65536
" >> /etc/security/limits.conf
    # 查看文件的末尾行是否已经是所插入内容
    tail $limits_conf
    # 替换当前进程为新的bash进程
    # 临时让当前会话生效,配置文件中的如果配置正确,则永久生效,需要新建立一个ssh链接检查ulimit -n 的数值
    ulimit -n 65536
else
    echo "conf file [$limits_conf] does not exit!"
fi
