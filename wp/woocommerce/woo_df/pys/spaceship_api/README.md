# Spaceship API Client 使用说明

本程序用于通过命令行管理 Spaceship 域名、DNS、联系人等。

## 文档索引

- `README.md`（本文档，总入口）：`spaceship_api.py` 完整用法，覆盖域名/DNS/联系人管理、状态过滤与 CSV 导出。
- [README@update_nameservers.md](./README@update_nameservers.md)：批量更新域名服务器（`update_nameservers.py`）专用说明，含表格文件格式约定。
- [../domain_fix/README.md](../domain_fix/README.md)：spaceship 正常域名与 Cloudflare zone 差集检测/修复（`domain_fix.py`），并在重加域名后补齐 DNS、激活、邮箱转发、SSL 与基础安全/加速。
- [spaceship_config_template_readonly.json](./spaceship_config_template_readonly.json)：鉴权配置文件模板。
- [domains_nameservers_template_readonly.csv](./domains_nameservers_template_readonly.csv)：批量改 NS 的域名表格模板。
- `archived/`：历史版本存档。

> 参数命名规范：命令行选项统一使用连字符（`--order-by`），旧下划线写法（`--order_by`）已不再支持。

## 一、准备工作
1. 获取 Spaceship API Key 和 API Secret。
   - 登录 Spaceship 官网，进入 [API 管理页面](https://www.spaceship.com/zh/application/api-manager/)，创建并复制 API Key 和 Secret。
2. 配置 API 信息。
   - 推荐将 API 信息保存到 `spaceship_config.json` 文件，格式参考[spaceship_config_template_readonly.json](./spaceship_config_template_readonly.json)
   - 或者每次命令行加参数 `--api-key` 和 `--api-secret`。

3. 官方api和文档:[Spaceship public API documentation.](https://docs.spaceship.dev/)

## 二、基本用法

所有命令均在命令行运行：
```cmd
python spaceship_api.py [子命令] [参数]
```

### 常用命令一览
| 功能             | 子命令                | 主要参数说明 |
|------------------|----------------------|-------------|
| 列出域名         | list-domains         | --take --skip --order-by --names-only --all --status --export-csv --csv-fields --all-accounts --output |
| 查询域名详情     | get-domain           | --domain |
| 注册域名         | register-domain      | --domain --auto-renew --privacy-level |
| 删除域名         | delete-domain        | --domain |
| 续费域名         | renew-domain         | --domain --years --current-expiration-date |
| 恢复域名         | restore-domain       | --domain |
| 域名转移         | transfer-domain      | --domain --auth-code |
| 设置转移锁       | lock-domain          | --domain --is-locked --no-lock |
| 设置隐私保护     | privacy-domain       | --domain --privacy-level --user-consent |
| 设置邮箱保护     | email-protect        | --domain --contact-form |
| 查询DNS记录      | list-dns             | --domain --take --skip --order-by |
| 添加DNS记录      | add-dns              | --domain --type --name --address --ttl |
| 删除DNS记录      | delete-dns           | --domain --type --name --address |
| 创建联系人       | save-contact         | --first-name --last-name --email --country --phone 等 |
| 查询联系人       | get-contact          | --contact-id |
| 更新联系人       | update-contact       | --contact-id 其它信息 |
| 联系人属性管理   | save-contact-attr    | --type --euAdrLang --is-natural-person |
| 查询联系人属性   | get-contact-attr     | --contact-id |
| 查询异步操作     | get-async            | --operation-id |
| 查看域名nameservers | get-nameservers   | --domain |
| 更新域名nameservers | update-nameservers | --domain --provider --hosts |

### 批量更新域名服务器(nameservers)🎈

这是重点任务,另见单独的文档介绍

 [README@update_nameservers.md](README@update_nameservers.md) 



## 三、命令示例

### 1. 列出全部域名
```cmd
python spaceship_api.py list-domains --all
```

#### 查询被停用的域名

从所有账号查询

```bash
python C:\repos\scripts\wp\woocommerce\woo_df\pys\spaceship_api\spaceship_api.py list-domains --list-suspended-domains all suspend.json --brief # 将文件输出到suspend.json中(可以自行指定完整路径)
```

#### 查询已购买的域名在哪个账号上

假设我有多个spaceship账号,但是最近购买的域名忘记是哪个账号买的,可以利用这些账号的api配置文件并发查询,快速获取结果

```bash
python C:\repos\scripts\wp\woocommerce\woo_df\pys\spaceship_api\spaceship_api.py get-domain  --from-all-accounts --domain example.com
```



### 2. 查询某域名详情

```cmd
python spaceship_api.py get-domain --domain example.com
```

### 3. 查看域名nameservers
```cmd
python spaceship_api.py get-nameservers --domain example.com
```

### 4. 更新域名nameservers
- 使用基础服务商：
```cmd
python spaceship_api.py update-nameservers --domain example.com --provider basic
```
- 使用自定义nameservers：
```cmd
python spaceship_api.py update-nameservers --domain example.com --provider custom --hosts ns1.example.com ns2.example.com
```

### 5. 添加DNS记录
```cmd
python spaceship_api.py add-dns --domain example.com --type A --name www --address 1.2.3.4 --ttl 3600
```

### 6. 创建联系人
```cmd
python spaceship_api.py save-contact --first-name 张 --last-name 三 --email zhangsan@example.com --country CN --phone 13800000000
```



## 四、常见问题

- API Key/Secret未配置或错误会提示“API Key 和 Secret 必须指定”。
- 命令参数缺失会有详细提示。
- 所有输出均为标准JSON格式，方便查看和保存。

## 五、进阶说明
- 支持批量操作（如列出全部域名）。
- 支持自定义nameservers和DNS记录。
- 联系人、属性、异步操作等均有对应命令。



- get-contact-attr: 查询联系人属性
- get-async: 查询异步操作状态

## 认证

可通过命令行参数 `--api-key` 和 `--api-secret`，或配置文件 `spaceship_config.json` 提供认证信息。
使用指定位置的配置文件,可以使用`--config`参数指定
例如
```bash
python spaceship_api.py --config C:\sites\wp_sites\spaceship_config.json get-domain  --domain stadtmarkt24.com
```
## list-domains 新参数说明

### 只输出域名（每行一个）

```bash
python spaceship_api.py list-domains --names-only
```
输出：
```
example.com
test.com
...
```

### 列出全部域名（忽略 take/skip 参数，自动分页）

```bash
python spaceship_api.py list-domains --all
```
输出所有域名信息（json格式）。

### 结合只输出域名和全部域名

```bash
python spaceship_api.py list-domains --all --names-only
```
输出所有域名，每行一个。

### 按状态过滤并导出 CSV

`--status` 可选 `all`（全部，默认）、`normal`（正常，无 suspensions）、`suspended`（被停用）。
注意：`normal` 只看 `suspensions`，**已过期但未被停用的域名仍会被算作正常**；如需「未过期且正常」，
再加 `--exclude-expired`（按 `expirationDate` <= 当前时间剔除；缺失或无法解析则保留）：

```bash
# 未过期且正常的域名（推荐用于 domain_fix 的源数据核对）
python spaceship_api.py list-domains --all --status normal --exclude-expired --export-csv normal_unexpired.csv
```

```bash
# 当前账号的正常域名导出为 CSV
python spaceship_api.py list-domains --all --status normal --export-csv normal.csv

# 所有账号的正常域名导出为 CSV
python spaceship_api.py list-domains --all --status normal --all-accounts --export-csv all_normal.csv

# 兼容旧写法：--from-all-accounts 直接给出文件名
python spaceship_api.py list-domains --status normal --from-all-accounts all_normal.csv

# 只导出需要的列（逗号分隔，缺省为全部默认列）
python spaceship_api.py list-domains --all --status normal --export-csv mini.csv --csv-fields name,expirationDate,account

# 同时保存一份过滤后的 JSON
python spaceship_api.py list-domains --all --status normal --export-csv normal.csv --output normal.json
```

默认 CSV 列（顺序即列顺序）：`account,name,unicodeName,registrationDate,expirationDate,autoRenew,isPremium,lifecycleStatus,verificationStatus,eppStatuses,suspensions,nsProvider,nameservers,privacyLevel`。CSV 为 `utf-8-sig` 编码，Excel 可直接打开。

注意：`--take` 为过滤前获取数量，要导出全部正常域名请使用 `--all`。

## 其它示例

注册域名：

```bash
python spaceship_api.py register-domain --domain example.com --auto-renew --privacy-level high
```

查询 DNS 记录：

```bash
python spaceship_api.py list-dns --domain example.com
```

更多命令和参数请使用 `-h` 查看帮助。
- 查询联系人：
  ```bash
  python spaceship_api.py get-contact --contact-id 1ZdMXpapqp9...Azf5
  ```

### 异步操作
- 查询异步操作状态：
  ```bash
  python spaceship_api.py get-async --operation-id <id>
  ```

## 输出
默认以 JSON 格式输出到屏幕；`list-domains` 可用 `--output/-o xxx.json` 保存 JSON，用 `--export-csv xxx.csv` 导出 CSV。

## 更多命令和参数
请运行：
```bash
python spaceship_api.py --help
```
查看所有支持的命令和参数。
