## abstract

* [base.sh](../scripts/base.sh) 是单个服务器(vps)仅有单个ip的情况下,为一个或多个后端服务器做反代(有两种工作模式),`-G hostmap` 对应后者
* [tenants.sh](../scripts.sh) 是单个服务器(vps)具有多个ip对情况下,为多个用户(后端服务器管理员)各分配一个ip,也是走 `hostmap`的方式为多个后端服务器反代.

## 目录结构参考

### base.sh

```
.
├── conf.d
│   ├── cf-ips-v4.txt
│   ├── cf-ips-v6.txt
│   ├── cf-realip.conf
│   ├── default.conf
│   └── gateway.conf
├── fastcgi_params
├── gateway
│   ├── maps
│   │   └── routes.map.conf
│   └── snippets
│       └── proxy-common.conf
├── log -> /var/log/nginx/
├── mime.types
├── modules -> /usr/lib/nginx/modules
├── nginx.conf
├── scgi_params
├── update_cf_ip_configs.sh
└── uwsgi_params
```

### tenants.sh

```
.
├── conf.d
│   ├── cf-ips-v4.txt
│   ├── cf-ips-v6.txt
│   ├── cf-realip.conf
│   ├── default.conf
│   ├── tenant-common.conf
│   ├── tenant-hostmap.conf
│   └── tenant-server.conf
├── fastcgi_params
├── log -> /var/log/nginx/
├── mime.types
├── modules -> /usr/lib/nginx/modules
├── nginx.conf
├── scgi_params
├── tenants
│   ├── xcx
│   │   └── routes.map
│   └── yyd
│       └── routes.map
├── update_cf_ip_configs.sh
└── uwsgi_params
```

## notes

对于服务器管理员,主要关注每次新站点添加到vps时,对hostmap(routes.map)文件的增量修改操作.

