# WordPress 插件批量覆盖脚本说明

## 需求说明

本脚本用于批量覆盖或移除一批 WordPress 网站的插件目录。(大多数功能经过验证,执行速度较快)
支持如下功能：

- 支持指定插件源目录，将其覆盖到所有目标站点的插件目录下。
- 支持通过命令行参数指定网站工作目录（默认为 `/www/wwwroot`）。
- 支持指定用户名，仅操作该用户下的所有站点；未指定则处理所有用户下的站点。
- 支持黑名单和白名单模式，灵活控制操作的站点范围。
- 支持移除指定插件（可批量，逗号分隔），可与覆盖操作独立或同时使用。
- 支持 `--dry-run` 预览模式，仅显示将要执行的操作，不实际更改文件。
- 支持 `--log` 参数，将所有操作日志保存到指定文件。
- 黑名单和白名单只能二选一，不能同时指定。

## 目录结构

```
update_wp_plugin.sh      # 主脚本
README.md              # 使用说明
blacklist.conf         # 黑名单示例文件（可选）
whitelist.conf         # 白名单示例文件（可选）
```

## 使用方法
### 赋予脚本文件可执行权限
```bash
chmod +x update_wp_plugin.sh  #注意真实的脚本具体路径
```

### 覆盖插件（批量分发插件到所有站点）

```bash
bash update_wp_plugin.sh --source <插件目录>
```

### 移除插件（批量删除指定插件名的目录）

```bash
bash update_wp_plugin.sh --remove mallpay
bash update_wp_plugin.sh --remove mallpay,otherplugin
```

### 同时覆盖和移除插件

```bash
bash update_wp_plugin.sh --source <插件目录> --remove mallpay,otherplugin
```

### 指定用户名

```bash
bash update_wp_plugin.sh --source <插件目录> --user <用户名>
```

### 指定工作目录

```bash
bash update_wp_plugin.sh --source <插件目录> --workdir /your/path
```

### 使用黑名单

```bash
bash update_wp_plugin.sh --source <插件目录> --blacklist blacklist.conf
bash update_wp_plugin.sh --remove mallpay --blacklist blacklist.conf
```

### 使用白名单

```bash
bash update_wp_plugin.sh --source <插件目录> --whitelist whitelist.conf
bash update_wp_plugin.sh --remove mallpay --whitelist whitelist.conf
```

### 预览模式（不实际执行）

```bash
bash update_wp_plugin.sh --source <插件目录> --dry-run
bash update_wp_plugin.sh --remove mallpay --dry-run
```

### 保存操作日志

```bash
bash update_wp_plugin.sh --source <插件目录> --log 操作日志.txt
bash update_wp_plugin.sh --remove mallpay --log 删除日志.txt
```

## 黑名单/白名单文件格式

每行一个域名，例如：

```
example.com
testsite.org
```
## 使用示例

```bash
# root @ wnx0020303 in /www/wwwroot/wp-plugin-update [13:05:24] C:130
$ ./update_wp_plugin.sh --source /www/wwwroot/mallpay --blacklist ./blacklist.conf --dry-run  
[DRY RUN] 将覆盖 /www/wwwroot/mallpay 到 /www/wwwroot/Bsite/goodpayway.shop/wordpress/wp-content/plugins/mallpay
[DRY RUN] 将覆盖 /www/wwwroot/mallpay 到 /www/wwwroot/cjq/americangoods24.com/wordpress/wp-content/plugins/mallpay
[DRY RUN] 将覆盖 /www/wwwroot/mallpay 到 /www/wwwroot/cjq/everythingshop24.com/wordpress/wp-content/plugins/mallpay
...
[DRY RUN] 将覆盖 /www/wwwroot/mallpay 到 /www/wwwroot/zsh/allshoppingzone.com/wordpress/wp-content/plugins/mallpay
跳过黑名单域名: armedtechgear.com
[DRY RUN] 将覆盖 /www/wwwroot/mallpay 到 /www/wwwroot/zsh/autobuildershop.com/wordpress/wp-content/plugins/mallpay
[DRY RUN] 将覆盖 /www/wwwroot/mallpay 到 /www/wwwroot/zsh/autoracinggearshop.com/wordpress/wp-content/plugins/mallpay
...
[DRY RUN] 将覆盖 /www/wwwroot/mallpay 到 /www/wwwroot/zsh/babymarktzone.com/wordpress/wp-content/plugins/mallpay
[DRY RUN] 将覆盖 /www/wwwroot/mallpay 到 /www/wwwroot/zsh/bargainhubstore.com/wordpress/wp-content/plugins/mallpay
跳过黑名单域名: beautytherapiesplus.com
[DRY RUN] 将覆盖 /www/wwwroot/mallpay 到 ..
```

## 注意事项

- 黑名单和白名单不能同时使用。
- 未指定 `--user` 时，脚本会遍历所有用户目录。
- 建议先用 `--dry-run` 预览操作，确认无误后再正式执行。
- 脚本会删除目标插件目录后再覆盖，请确保数据安全。
- 移除插件时，指定的插件名可以为多个，逗号分隔。
- 日志文件会记录所有操作和跳过信息，便于后续审查。

## 需求细节
### 基础需求
编写一个bash脚本,其功能是为一批wordpress网站的插件目录覆盖式添加指定目录(一般是个插件目录);
这些wordpress站的根目录的路径规律是形如/www/wwwroot/<user_name>/<domain>/wordpress (一个具体的例子是 /www/wwwroot/zsh/allgoodsmarkets.com/wordpress)
脚本支持完善的命令行和参数


1. 允许我命令行参数配置网站所在的工作目录(默认为/www/wwwroot)
2. 当我没有指定--user时,使用通配的方式尝试处理所有指定工作目录(比如/www/wwwroot///wordpress)
3. 改用中文编写完善的readme文件,包含详细的需求和功能实现以及使用说明
4. 支持指定黑名单文件(blacklist.conf),黑名单文件中指定一系列域名(形如domian.com),一行一个,被配置的域名对应的网站根目录不执行目录更新(添加)操作,即跳过处理,并且给于提示;
还应该支持--dry模式,让我可以在正式执行前判断一下操作是否满足需要
5. 支持白名单的模式,允许我只操作指定域名对应的网站根目录而不是全部
但是当我没有指定黑/白名单时,默认对所有网站根目录执行操作
注释使用中文表述详细

### 补充和完善
1. 允许我移除插件(指定插件名(一个或多个),比如mallpay)然后如果有指定白名单则仅移除白名单站点目录下的插件(目录),否则移除工作目录中全部wp网站下的对应名称插件(目录),仍然支持--dry-run操作预览
2. 还允许我启用log参数指定保存日志到日志log文件
