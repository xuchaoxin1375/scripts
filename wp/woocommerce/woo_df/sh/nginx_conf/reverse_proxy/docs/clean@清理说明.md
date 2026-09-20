[toc]

## 关于清理脚本的设计说明

`base.sh / multi.sh / tenants.sh` 是互斥的“一机一模式”，但三者都不做全量清理，交叉运行会留下对立方文件，导致 `nginx -t` 失败或流量错乱。

`../scripts/clean.sh` 是统一收口：先备份再删，默认只删被 `include` 的 `D` 侧冲突源，保留用户 `map` 数据；彻底下线才加 `--purge-data` 等扩展项。

路径记号：`C=$NGINX_CONF_HOME`（标准 `/etc/nginx`，宝塔 `/www/server/nginx/conf`），`D=$NGINX_CONFD`（标准 `$C/conf.d`，宝塔 `/www/server/panel/vhost/nginx`），`L=$NGINX_LOG_DIR`（标准 `/var/log/nginx/`，宝塔 `/www/logs/`）。

---

## 1. 各脚本产物清单

| 脚本 | 落盘文件（`D` 侧：会直接被 nginx 加载，残留即冲突） | 落盘数据（`C` 侧：无 `D` 侧引用时惰性，不直接冲突） |
| --- | --- | --- |
| `base.sh -G simple` | `D/reverse_to_a.conf` | — |
| `base.sh -G hostmap` | `D/gateway.conf` | `C/gateway/snippets/proxy-common.conf`、`C/gateway/maps/routes.map.conf`（已存在不覆盖）、`C/gateway/proxy-pass-mode`（默认 `url`） |
| `multi.sh` | `D/reverse_multi_ip.conf`（`--conf-name` 可改名；启动即无条件 `rm D/reverse_to_a.conf`，连 `--dry-run` 也会删） | — |
| `tenants.sh` | `D/tenant-common.conf`、`D/tenant-hostmap.conf`、`D/tenant-server.conf`；旧版 `D/10-common-map.conf`、`D/20-tenant-maps.conf`、`D/30-tenant-gateways.conf`（自动删）；`--clean` 才删 `D/reverse_to_a.conf`，`D/reverse_multi_ip.conf` 只告警不删 | `C/tenants/<id>/routes.map`（默认不覆盖）、`C/tenants/proxy-pass-mode`（默认 `hostport`）；`C/nginx.conf` 中 `tenants.sh` 插入的 `map_hash` 块（带 `# managed by tenants.sh` 标记） |
| 三者公共副作用 | `D/cf-realip.conf`、`D/cf-ips-v4.txt`、`D/cf-ips-v6.txt` | `C/update_cf_ip_configs.sh`（拷贝）、`C/log -> L` 软链接、`L/` 下各模式日志 |

---

## 2. 残留为什么会冲突

1. `listen 80 default_server` 抢口：`reverse_to_a.conf / gateway.conf / reverse_multi_ip.conf / tenant-server.conf` 都有，残留即 `duplicate listen` 或请求进错 `server`。
2. `map $http_upgrade / $http_x_forwarded_proto / log_format` 重复定义：多套 `D` 侧文件共存即 `nginx -t` 报 `duplicate`。
3. `proxy-pass-mode` 静默沿用：`C/gateway/proxy-pass-mode`（默认 `url`，`map` 写 `http://ip:port`）与 `C/tenants/proxy-pass-mode`（默认 `hostport`，`map` 写 `ip:port`）互不相通，切模式不改 `map` 格式即 `500`。
4. 缩容不删旧租户：`tenants.sh` 默认保留已有 `routes.map`，`-t` 名单缩小后旧 `tenants/<old-id>/` 仍在；`gateway/maps` 切走后也仍在。
5. `C/nginx.conf` 被改：`tenants.sh` 可能在 `http{` 头插入或抬高 `map_hash_*`，卸载时只有带标记的插入块能自动回退，原地改值的情况只能靠备份恢复。

---

## 3. `clean.sh` 用法

```bash
bash ../scripts/clean.sh --help
bash ../scripts/clean.sh --status
bash ../scripts/clean.sh --dry-run
```

| 选项 | 含义 |
| --- | --- |
| `-c/-d/-l/--tenants-dir` | 指定 `C/D/L/tenants` 根，与三个部署脚本同义 |
| `-m/--mode simple\|hostmap\|multi\|tenants\|all` | 清理范围，可重复或逗号分隔，默认 `all` |
| `--conf-name <name>` | `multi` 自定义文件名，可重复，默认 `reverse_multi_ip.conf` |
| `--tenant <id>` | 仅裁剪该租户数据目录，可重复；单租户模式不碰 `D` 侧共享 `conf` 与 `nginx.conf` |
| `--purge-data` | 连用户 `map` 数据一起删（`C/gateway`、`C/tenants`）；默认只删 `D` 侧，保留数据 |
| `--with-cf/--with-helper/--with-symlink/--with-logs` | 扩展到 `CF` 文件、`C/update_cf_ip_configs.sh`、`C/log` 软链（仅指向 `-l` 才删）、`L` 下 `b_to_a*/b*_to_a*/tenant-*` 日志；默认全保留 |
| `--no-nginx-conf` | 跳过 `nginx.conf` 回退 |
| `--status/--dry-run/--force/--no-backup/--backup-dir` | 巡检 / 预览 / 跳过确认 / 跳过备份 / 指定备份目录（默认 `/root/nginx-reverse-backup/<时间>`，无权限落 `/tmp`） |
| `--no-test/--reload` | 跳过 `nginx -t` / 测过后再 `reload`（默认测而不 `reload`） |

常用命令：

```bash
# 不知道之前跑过哪个部署脚本？不用查：不传 --mode 即按 all 处理，
# 一条命令清空全部四种方案的 D 侧残留（保留 map 数据/CF，适合“回到干净状态再重部署”）
bash ../scripts/clean.sh --force
# 宝塔路径同理
bash ../scripts/clean.sh -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ --force

# 巡检与预览（不删）
bash ../scripts/clean.sh --status
bash ../scripts/clean.sh -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ --status

# 切换模式前：清所有 D 侧冲突，保留 map 数据（推荐）
bash ../scripts/clean.sh --mode all --force
bash ../scripts/clean.sh -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ --mode all --force

# 彻底下线（含用户 map 数据与 CF 文件，按需 reload）
bash ../scripts/clean.sh --mode all --purge-data --with-cf --force --reload

# 只看/只清某一模式
bash ../scripts/clean.sh --mode tenants --dry-run
bash ../scripts/clean.sh --mode multi --conf-name my-multi.conf --force

# 单租户裁剪（只删 tenants/a 数据，不碰共享 conf；后续必须重跑 tenants.sh 或手工摘引用，见第 5 节）
bash ../scripts/clean.sh --mode tenants --tenant a --force

# 在线执行
bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/nginx_conf/reverse_proxy/scripts/clean.sh) --status
```

---

## 4. 标准流程（切换/下线）

```text
--status 巡检 -> 备份 nginx.conf/nginx -T -> clean.sh 清理 -> nginx -t ->
部署新模式（base/multi/tenants 其中之一） -> nginx -t && nginx -s reload ->
curl /__b_health、/__gateway_health、/__tenant_health 与真实 Host 验证
```

切换示例（`hostmap -> tenants`，宝塔）：

```bash
cp -a /www/server/nginx/conf/nginx.conf /root/nginx.conf.bak.$(date +%F)
bash ../scripts/clean.sh -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ --status
bash ../scripts/clean.sh -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ --mode all --force
bash ../scripts/tenants.sh -c /www/server/nginx/conf -d /www/server/panel/vhost/nginx -l /www/logs/ \
  -t 'a=P_IP_A' -t 'b=P_IP_B'
nginx -t && nginx -s reload
```

---

## 5. 注意事项

* 默认保留 `map` 数据是故意的：`C/gateway`、`C/tenants` 无 `D` 侧引用时不影响 `nginx`，误删反而丢路由；要连数据一起清必须显式 `--purge-data`。
* `--tenant` 单删后 `D/tenant-hostmap.conf` 仍 `include` 已删租户的 `routes.map`，`nginx -t` 会失败；正确收尾是用剩余租户重跑 `tenants.sh` 重生三件套，或手工删掉该租户段落。
* `CF` 三件套是三脚本共用，切模式时不要加 `--with-cf`；彻底不用反代才删。
* `multi --conf-name` 改过名的文件，清理时必须用同样的 `--conf-name` 指出来，否则扫不到。
* `multi.sh` 预览也会删 `D/reverse_to_a.conf`，跑 `--dev/--dry-run` 前建议先 `--status` 或先备份。
* `nginx.conf` 回退只认 `# managed by tenants.sh` 标记块；被原地改值的旧块不会自动还原，以备份为准。

---

## 6. 手工兜底（`clean.sh` 不可用时）

```bash
C=/etc/nginx; D=$C/conf.d  # 宝塔：C=/www/server/nginx/conf D=/www/server/panel/vhost/nginx
cp -a $C/nginx.conf /root/nginx.conf.bak.$(date +%F)
rm -fv $D/reverse_to_a.conf $D/gateway.conf $D/reverse_multi_ip.conf \
  $D/tenant-common.conf $D/tenant-hostmap.conf $D/tenant-server.conf \
  $D/10-common-map.conf $D/20-tenant-maps.conf $D/30-tenant-gateways.conf
rm -rfv $C/gateway $C/tenants  # 只想切模式、保留路由时别执行这行
nginx -t && nginx -s reload
```

## 7. 文件索引

* 清理脚本：`../scripts/clean.sh`
* 部署脚本：`../scripts/base.sh`、`../scripts/multi.sh`、`../scripts/tenants.sh`
* 结构参考：`不同反代模式下(hostmap)nginx目录结构参考.md`
