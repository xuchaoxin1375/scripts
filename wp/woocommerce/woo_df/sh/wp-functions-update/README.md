# update_wp_functions.sh 使用说明

## 脚本简介

`update_wp_functions.sh` 是一个用于批量覆盖或补充 WordPress 站点主题目录下 `functions.php` 文件的 Bash 脚本。适用于多站点环境下统一更新、修复或补充主题功能代码。脚本支持 dry-run 预览、黑白名单过滤、日志记录、指定用户等多种实用功能，适合自动化运维和批量管理场景。

## 目录结构假设

- 网站根目录结构为：`/www/wwwroot/<username>/<domain.com>/wordpress`
- 目标文件路径为：`/www/wwwroot/<username>/<domain.com>/wordpress/wp-content/themes/<themename>/functions.php`
- 源文件（默认）：`/www/wwwroot/functions.php`

## 功能特性

- 批量将指定 `functions.php` 文件覆盖到所有（或指定）WordPress 站点的所有主题目录下。
- 支持 dry-run 预览操作，不实际写入，便于安全检查。
- 支持黑名单和白名单过滤，灵活控制操作目标。
- 支持仅处理指定用户名下的网站。
- 支持操作日志记录。
- 兼容多主题目录，自动跳过不存在的目录。

## 参数说明

| 参数             | 说明                                                         |
|------------------|--------------------------------------------------------------|
| --src <源文件>   | 要覆盖/补充的 functions.php 文件，默认为 /www/wwwroot/functions.php |
| --workdir <目录> | 网站根目录，默认为 /www/wwwroot                              |
| --user <用户名>  | 仅处理指定用户名下的网站                                      |
| --dry-run        | 预览操作，不实际执行                                         |
| --blacklist <文件> | 黑名单文件（每行一个域名）                                 |
| --whitelist <文件> | 白名单文件（每行一个域名，只操作这些域名）                 |
| --log <日志文件> | 日志文件                                                     |

> 注意：黑名单和白名单不能同时使用。

## 使用示例

1. **默认批量覆盖所有站点所有主题 functions.php**

   ```bash
   bash update_wp_functions.sh
   ```

2. **指定源文件和工作目录**

   ```bash
   bash update_wp_functions.sh --src /tmp/new_functions.php --workdir /data/wwwroot
   ```

3. **仅 dry-run 预览，不实际写入**

   ```bash
   bash update_wp_functions.sh --dry-run
   ```

4. **仅处理指定用户名下的网站**

   ```bash
   bash update_wp_functions.sh --user zsh
   ```

5. **使用白名单，仅操作指定域名**

   ```bash
   bash update_wp_functions.sh --whitelist whitelist.txt
   # whitelist.txt 内容示例：
   # domain1.com
   # domain2.com
   ```

6. **使用黑名单，跳过指定域名**

   ```bash
   bash update_wp_functions.sh --blacklist blacklist.txt
   # blacklist.txt 内容示例：
   # domain3.com
   # domain4.com
   ```

7. **记录操作日志**

   ```bash
   bash update_wp_functions.sh --log update.log
   ```

## 日志与错误处理

- 日志文件会记录所有操作和跳过的目标，便于后续追踪。
- 若目标主题目录不存在，脚本会自动跳过并记录。
- 若源文件不存在，脚本会直接报错并退出。
- 若黑白名单文件不存在，脚本会直接报错并退出。

## 典型输出示例

```
已覆盖 /www/wwwroot/functions.php 到 /www/wwwroot/zsh/example.com/wordpress/wp-content/themes/astra/functions.php
覆盖失败: /www/wwwroot/zsh/example.com/wordpress/wp-content/themes/astra/functions.php
跳过未在白名单中的域名: not-in-list.com
主题目录不存在: /www/wwwroot/zsh/example.com/wordpress/wp-content/themes
Dry run 完成，未做任何更改。
操作已完成。
```

## 注意事项

- 请确保脚本有足够的文件读写权限。
- 建议先用 `--dry-run` 检查目标列表，确认无误后再执行正式操作。
- 建议定期备份目标文件，防止误操作导致数据丢失。

---

如有问题请联系脚本维护者。
