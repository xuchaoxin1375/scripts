# deploy_wp_full_parallel.sh 说明文档（GNU parallel 版本）

本文档描述脚本 `/www/sh/deploy_wp_full_parallel.sh` 的用途、设计、参数、并发模型、运行流程、日志格式、故障排查与维护注意事项，便于团队协作与长期维护。

## 1. 脚本用途与范围

该脚本用于批量部署 WordPress 站点（站点文件 + 数据库），数据来源为上传目录 `PACK_ROOT` 下的用户子目录（每个用户一个目录）。

### 1.1 输入约定（目录结构）

- `PACK_ROOT`（默认：`/srv/uploads/uploader/files`）
  - `${PACK_ROOT}/${username}/`：某个建站人员/账号的工作目录
  - 站点包：如 `example.com.zst` / `example.com.zip` / `example.com.7z` / `example.com.tar` / `example.com.lz4`
  - SQL 文件（导入用）：`${PACK_ROOT}/${username}/${domain}.sql`
  - SQL 压缩包（可选）：如 `example.com.sql.zst` / `example.com.sql.zip` 等（该脚本会先解压出 `.sql`）
  - 归档目录：`${PACK_ROOT}/${username}/deployed/`（用于归档已处理的压缩包）

### 1.2 输出（部署结果）

- 站点目录：`${PROJECT_HOME}/${username}/${domain}/wordpress/`
  - 默认 `PROJECT_HOME=/www/wwwroot`
- 数据库：`${username}_${domain}`（域名中的 `.` 保留）

### 1.3 能力边界（脚本不做的事）

- 不负责生成站点压缩包、不负责生成 `.sql`
- 不负责宝塔创建站点/配置 PHP/Nginx（仅写伪静态 rewrite 文件并在批次结束 reload Nginx）
- 不保证并发执行时“外部人工移动压缩包文件”不会造成任务失败（建议运行期间不要手工移动包文件）

---

## 2. 核心设计

### 2.1 并发模型（GNU parallel）

脚本使用 GNU `parallel` 并发执行两类任务：

- SQL 压缩包解压（`__process_sql` worker）
- 站点部署（`__deploy_site` worker）

并发度由 `--jobs` 控制：

- 同一时间最多运行 `JOBS` 个 worker 任务

#### 2.1.1 关键点：zstd 线程数与总 CPU

`.zst` / `.zstd` 解压如果使用 `zstd -T0` 会导致单个任务占满所有 CPU 核心，从而使 `--jobs` 形同虚设。

为确保“并发真的可控”，脚本提供：

- `--zstd-threads N`（默认 `1`）

其含义是：每个任务解压 zstd 时最多使用 `N` 个 CPU 线程。

经验上，总体解压 CPU 上限约为：

- `jobs * zstd_threads`

推荐组合：

- 保守/稳：`--jobs 4 --zstd-threads 1`
- 8 核左右：`--jobs 4 --zstd-threads 2`

> 注意：即使 zstd 很快，后续 `tar -xf`（文件创建/元数据写入）也可能造成 IO 压力，建议不要把 `--jobs` 开太大。

### 2.2 子命令模式（worker 模式）

为了避免 `parallel` 环境下函数导出、引用复杂化，脚本使用“子命令模式”实现并发调用：

- 主进程：负责扫描文件、生成任务列表、调用 `parallel`
- worker 子进程：通过 `bash "$0" __deploy_site ...` / `bash "$0" __process_sql ...` 进入

两个 worker 入口：

- `__process_sql <username> <sql_archive>`
- `__deploy_site <username> <site_archive_abs_path>`

worker 使用主进程 `export` 的环境变量：

- `PACK_ROOT DB_USER DB_PASSWORD DEPLOYED_DIR PROJECT_HOME JOBS ZSTD_THREADS`

### 2.3 文件路径策略（降低“文件找不到”）

站点部署任务传递的是**站点包的绝对路径**（例如 `/srv/uploads/uploader/files/zsh/example.com.zst`），这样 worker 不依赖 `cd`，减少并发与路径变化导致的误差。

同时，在 `deploy_site` 开始阶段会对归档文件存在性做硬检查，不存在立即失败退出。

---

## 3. 参数说明

### 3.1 通用参数

- `-p, --pack-root DIR`
  - 输入包目录根（默认：`DEFAULT_PACK_ROOT`）
- `--db-user USER`
  - 数据库用户（默认：`root`）
- `--db-pass PASS`
  - 数据库密码（默认：脚本内默认值）
- `--user-dir DIR`
  - 只处理某个用户目录（例如 `zsh`）
- `--deployed-dir DIR`
  - 预留字段（当前主要使用 `${PACK_ROOT}/${username}/deployed/`）
- `-j, --jobs N`
  - parallel 并发任务数（默认：`4`）
- `--zstd-threads N`
  - 每个任务解压 `.zst` 时使用的线程数（默认：`1`）
- `-r, --project-home DIR`
  - 部署输出根目录（默认：`/www/wwwroot`）

### 3.2 跳过开关

- `-R, --site-root-skip`
  - 跳过站点包解压（不影响后续步骤；通常仅用于已解压但需重做 DB 的场景）
- `-D, --site-db-skip`
  - 跳过数据库导入（不删除 `.sql`，也不更新 `wp_options`）

---

## 4. 运行流程（主流程）

### 4.1 执行概览

对每个用户目录（`${PACK_ROOT}/${username}`）执行：

1. 生成 `${PACK_ROOT}/${username}/deployed/`（若不存在）
2. 发现并解压所有 `*.sql.*` 压缩包（并发）
3. 发现所有站点压缩包（排除 `*.sql.*`），并发部署每个站点：
   - 解压站点包（如果未跳过）
   - 安装插件/拷贝 `functions.php`
   - 导入 `${domain}.sql`（如果存在且未跳过）
   - 更新 `wp_options.home/siteurl`
   - 写伪静态 rewrite 文件
   - 设置权限
   - 归档站点包到 deployed 目录
4. 用户目录处理完成后，设置 `deployed/` 权限

批次结束：

- `nginx -s reload`

### 4.2 站点部署逻辑要点

- 解压目录适配两种包结构：
  - 原生包：解压后出现 `${site_domain_home}/${domain}`
  - 导出包：解压后出现 `${site_domain_home}/wordpress`

- 解压成功后，会把原生包的 `${domain}` 目录内容移动到 `wordpress/`

---

## 5. 日志与可观测性

### 5.1 parallel 输出标签

并发日志会带前缀，便于区分来源：

- SQL：`[job x/N][progress i/total][SQL username] ...`
- SITE：`[job x/N][progress i/total][SITE domain] ...`

字段含义：

- `job x/N`：GNU parallel 的 slot 编号（第几个 worker），最大为 `--jobs`
- `progress i/total`：当前用户目录下扫描到的任务序号
- `SITE domain`：站点域名

### 5.2 joblog 文件

每个用户目录会生成：

- SQL：`/tmp/deploy_wp_${username}_sql_<timestamp>.joblog`
- SITE：`/tmp/deploy_wp_${username}_site_<timestamp>.joblog`

可用于统计成功/失败任务数与耗时。

---

## 6. 常见问题与排查

### 6.1 CPU 暴增/看似卡住

典型原因：

- `--jobs` 过大导致多个站点同时 `tar -xf`、`chmod -R`、`chown -R`，产生 IO/元数据风暴

排查建议：

- 看 `top` 的 `%wa`（iowait）是否高
- 先用保守参数：`--jobs 2 --zstd-threads 1`

### 6.2 “归档文件不存在”/“文件找不到”

典型原因：

- 运行过程中人工/其它脚本移动了包文件
- 文件命名与脚本扫描规则不一致

建议：

- 运行期间不要在 `PACK_ROOT` 下对包文件手工 `mv`
- 通过日志前缀定位具体 domain，再到目录核对文件是否存在

### 6.3 SQL 导入失败后出现 Unknown database / wp_options 不存在

已修复：

- 现在 SQL 导入失败会立即 return，不继续更新 `wp_options`，也不会删除 `.sql`

如果仍出现：

- 多半是 SQL 本身不完整/格式问题
- 数据库权限/磁盘空间不足

### 6.4 mysql “Using a password on the command line…” 警告

脚本已尽量使用 `MYSQL_PWD` 环境变量以减少该警告输出。

---

## 7. 维护注意事项

- 修改并发相关逻辑时，务必明确区分：
  - 任务并发（`--jobs`）
  - 单任务内部线程（`--zstd-threads`）

- 若需要进一步稳定（尤其是大批量站点/机械盘环境），建议后续迭代：
  - 引入 `--extract-jobs` / `--db-jobs` 分阶段限流
  - `.zst` 改为流式解包：`zstd -dc | tar -x -C ...`，减少中间 tar 文件落盘

---

## 8. 典型运行示例

- 单用户目录，保守并发：

```bash
bash /www/sh/deploy_wp_full_parallel.sh --user-dir zsh --jobs 2 --zstd-threads 1
```

- 全量用户目录，适中并发：

```bash
bash /www/sh/deploy_wp_full_parallel.sh --jobs 4 --zstd-threads 2
```

- 仅部署站点文件（不导入 DB）：

```bash
bash /www/sh/deploy_wp_full_parallel.sh -D
```

- 仅导入 DB（跳过解压）：

```bash
bash /www/sh/deploy_wp_full_parallel.sh -R
```
