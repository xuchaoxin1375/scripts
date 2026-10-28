# update_wp_functions.sh 使用说明

## 脚本简介

`update_wp_functions.sh` 是一个用于批量覆盖或补充 WordPress 站点主题目录下 `functions.php` 文件的 Bash 脚本。适用于多站点环境下统一更新、修复或补充主题功能代码。脚本支持 dry-run 预览、黑白名单过滤、日志记录、指定用户、自定义目标文件名等多种实用功能，适合自动化运维和批量管理场景。

## 目录结构假设

- 网站根目录结构为：`/www/wwwroot/<username>/<domain.com>/wordpress`
- 目标文件路径为：`/www/wwwroot/<username>/<domain.com>/wordpress/wp-content/themes/<themename>/<目标文件名>`，目标文件名默认为 `functions.php`，可用 `--dest-name` 指定
- 源文件（默认）：`/www/functions.php`，可用 `--src` 指定

## 功能特性

- 批量将指定 `functions.php` 文件覆盖到所有（或指定）WordPress 站点的所有主题目录下。
- 目标文件名（或符号链接名）可与源文件名不同，例如源文件为 `functions-a.php` 时仍可写入 `functions.php`。
- 支持 `copy`（复制）与 `symlink`（软链接）两种写入方式。
- 支持 dry-run 预览操作，不实际写入，便于安全检查。
- 支持黑名单和白名单过滤，灵活控制操作目标。
- 支持仅处理指定用户名下的网站。
- 支持操作日志记录。
- 兼容多主题目录，自动跳过不存在的目录。

## 参数说明

| 参数             | 说明                                                         |
|------------------|--------------------------------------------------------------|
| `-s, --src` <源文件>   | 要覆盖/补充的源文件，默认为 `/www/functions.php` |
| `-n, --dest-name` <文件名> | 写入主题目录时使用的文件名或符号链接名，默认为 `functions.php`；仅接受纯文件名，不含目录部分 |
| `-w, --workdir` <目录> | 网站根目录，多个目录用逗号分隔，默认为 `/www/wwwroot,/wwwdata/wwwroot` |
| `-u, --user` <用户名>  | 仅处理指定用户名下的网站                                      |
| `-m, --install-mode` <模式> | 安装模式：`copy`（复制，默认）或 `symlink`（软链接） |
| `-d, --dry-run`        | 预览操作，不实际执行                                         |
| `--blacklist` <文件> | 黑名单文件（每行一个域名）                                 |
| `--whitelist` <文件> | 白名单文件（每行一个域名，只操作这些域名）                 |
| `--log` <日志文件> | 日志文件                                                     |
| `-h, --help`           | 显示帮助并退出                                               |

> 注意：黑名单和白名单不能同时使用；`--dest-name` 只接受纯文件名，不能包含目录部分。

## 使用示例

- **默认批量覆盖所有站点所有主题 functions.php**

  ```bash
  bash update_wp_functions.sh
  ```

- **指定源文件和工作目录**

  ```bash
  bash update_wp_functions.sh --src /tmp/new_functions.php --workdir /data/wwwroot
  ```

- **源文件名与目标文件名不同（复制到各主题的 functions.php）**

  ```bash
  # 源文件为 /www/functions-a.php，写入目标仍为各主题目录下的 functions.php
  bash update_wp_functions.sh --src /www/functions-a.php --dest-name functions.php
  ```

- **以软链接方式写入，并指定链接名**

  ```bash
  bash update_wp_functions.sh --src /www/functions-a.php --dest-name functions.php --install-mode symlink
  ```

- **仅 dry-run 预览，不实际写入**

  ```bash
  bash update_wp_functions.sh --dry-run
  ```

- **仅处理指定用户名下的网站**

  ```bash
  bash update_wp_functions.sh --user zsh
  ```

- **使用白名单，仅操作指定域名**

  ```bash
  bash update_wp_functions.sh --whitelist whitelist.txt
  # whitelist.txt 内容示例：
  # domain1.com
  # domain2.com
  ```

- **使用黑名单，跳过指定域名**

  ```bash
  bash update_wp_functions.sh --blacklist blacklist.txt
  # blacklist.txt 内容示例：
  # domain3.com
  # domain4.com
  ```

- **记录操作日志**

  ```bash
  bash update_wp_functions.sh --log update.log
  ```

## 日志与错误处理

- 日志文件会记录所有操作和跳过的目标，便于后续追踪。
- 若目标主题目录不存在，脚本会自动跳过并记录。
- 若源文件不存在，脚本会直接报错并退出。
- 若黑白名单文件不存在，脚本会直接报错并退出。
- 若选项缺少取值、`--dest-name` 含目录部分或 `--install-mode` 取值非法，脚本会直接报错并退出。

## 典型输出示例

```
[主机名] 已覆盖 /www/functions.php 到 /www/wwwroot/zsh/example.com/wordpress/wp-content/themes/astra/functions.php
[主机名] 已强制创建软链接 /www/functions.php 到 /www/wwwroot/zsh/example.com/wordpress/wp-content/themes/astra/functions.php
[主机名] 覆盖失败: /www/wwwroot/zsh/example.com/wordpress/wp-content/themes/astra/functions.php
[主机名] 跳过未在白名单中的域名: not-in-list.com
[主机名] 主题目录不存在: /www/wwwroot/zsh/example.com/wordpress/wp-content/themes
[主机名] [DRY RUN] 将写入 /www/functions.php 到 /www/wwwroot/zsh/example.com/wordpress/wp-content/themes/astra/functions.php(copy)
[主机名] Dry run 完成，未做任何更改。
[主机名] 操作已完成。
```

## 注意事项

- 请确保脚本有足够的文件读写权限。
- `--dest-name` 决定站点实际加载的文件名，写入 WordPress 主题时通常应保持 `functions.php`，除非主题显式加载其它文件。
- 建议先用 `--dry-run` 检查目标列表，确认无误后再执行正式操作。
- 建议定期备份目标文件，防止误操作导致数据丢失。

---

如有问题请联系脚本维护者。
