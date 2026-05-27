# 站点备份脚本说明

## 功能需求

1. 扫描 /www/wwwroot/<username>/<domain>/wordpress 目录，自动识别所有用户和站点。
2. 备份站点文件：将 wordpress 目录打包为 tar（无后缀），用 zstd 压缩，压缩包存放到 /srv/uploads/uploader/files/<username>/deployed/。
3. 支持 --dry-run 预览模式。
4. 支持只备份指定用户（-u/--user），不指定则备份全部用户。
5. 支持自定义源目录和目标目录（-s/--src, -d/--dest）。
6. 支持帮助信息（-h/--help）。
7. 备份前检查目标 zst 文件是否已存在，已存在则跳过。
8. 自动备份数据库，依次尝试 username_domain、domain、www.domain 三种数据库名，成功导出则跳过后续，并用 zstd 压缩 sql 文件（原始 .sql 文件压缩后自动删除）。
9. 所有辅助说明和打印语句均为中文，便于理解和运维。

## 实现细节

- 脚本参数解析灵活，所有参数均可选，未指定时使用默认值。
- 备份文件和数据库均存放到 /srv/uploads/uploader/files/<username>/deployed/ 目录。
- 数据库检测用 mysqlshow，导出用 mysqldump。
- 备份过程不会修改任何原始网站目录内容。
- dry-run 模式下仅输出将要执行的操作，不实际执行。
- 已存在的 zst 压缩包会被自动跳过，避免重复备份。
- 数据库备份只要有一个候选名成功导出即跳过后续。

## 用法示例

```bash
# 备份所有用户所有站点
bash backup_old_sites.sh

# 仅备份指定用户
bash backup_old_sites.sh -u cjq

# dry-run 预览
bash backup_old_sites.sh --dry-run

# 指定源和目标目录
bash backup_old_sites.sh -s /custom/src -d /custom/dest

# 查看帮助（中文输出）
bash backup_old_sites.sh -h
```

## 依赖
- tar
- zstd
- mysqlshow
- mysqldump

## 注意事项
- 需有数据库访问权限。
- 备份目录需有写权限。
- 脚本不会覆盖已存在的 zst 压缩包和数据库 sql.zst 文件。
- 所有输出均为中文，便于理解和运维。
- 数据库备份文件会自动用 zstd 压缩，原始 .sql 文件压缩后自动删除。
