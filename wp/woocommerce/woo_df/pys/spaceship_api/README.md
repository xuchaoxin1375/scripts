# Spaceship API Client 使用说明

本程序用于通过命令行管理 Spaceship 域名、DNS、联系人等。

## 一、准备工作
1. 获取 Spaceship API Key 和 API Secret。
   - 登录 Spaceship 官网，进入 [API 管理页面](https://www.spaceship.com/zh/application/api-manager/)，创建并复制 API Key 和 Secret。
2. 配置 API 信息。
   - 推荐将 API 信息保存到 `spaceship_config.json` 文件，格式参考[spaceship_config_template_readonly.json](./spaceship_config_template_readonly.json)
   - 或者每次命令行加参数 `--api_key` 和 `--api_secret`。

3. 官方api和文档:[Spaceship public API documentation.](https://docs.spaceship.dev/)

## 二、基本用法

所有命令均在命令行运行：
```cmd
python spaceship_api.py [子命令] [参数]
```

### 常用命令一览
| 功能             | 子命令                | 主要参数说明 |
|------------------|----------------------|-------------|
| 列出域名         | list-domains         | --take --skip --order_by --names_only --all |
| 查询域名详情     | get-domain           | --domain |
| 注册域名         | register-domain      | --domain --auto_renew --privacy_level |
| 删除域名         | delete-domain        | --domain |
| 续费域名         | renew-domain         | --domain --years --current_expiration_date |
| 恢复域名         | restore-domain       | --domain |
| 域名转移         | transfer-domain      | --domain --auth_code |
| 设置转移锁       | lock-domain          | --domain --is_locked --no_lock |
| 设置隐私保护     | privacy-domain       | --domain --privacy_level --user_consent |
| 设置邮箱保护     | email-protect        | --domain --contact_form |
| 查询DNS记录      | list-dns             | --domain --take --skip --order_by |
| 添加DNS记录      | add-dns              | --domain --type --name --address --ttl |
| 删除DNS记录      | delete-dns           | --domain --type --name --address |
| 创建联系人       | save-contact         | --first_name --last_name --email --country --phone 等 |
| 查询联系人       | get-contact          | --contact_id |
| 更新联系人       | update-contact       | --contact_id 其它信息 |
| 联系人属性管理   | save-contact-attr    | --type --euAdrLang --is_natural_person |
| 查询联系人属性   | get-contact-attr     | --contact_id |
| 查询异步操作     | get-async            | --operation_id |
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
python C:\repos\scripts\wp\woocommerce\woo_df\pys\spaceship_api\spaceship_api.py list-domains --list_suspended_domains all $desktop/suspend.json --brief
```

#### 查询已购买的域名在哪个账号上

假设我有多个spaceship账号,但是最近购买的域名忘记是哪个账号买的,可以利用这些账号的api配置文件并发查询,快速获取结果

```bash
python C:\repos\scripts\wp\woocommerce\woo_df\pys\spaceship_api\spaceship_api.py get-domain  --from_all_accounts --domain example.com     
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
python spaceship_api.py save-contact --first_name 张 --last_name 三 --email zhangsan@example.com --country CN --phone 13800000000
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

可通过命令行参数 `--api_key` 和 `--api_secret`，或配置文件 `spaceship_config.json` 提供认证信息。
使用指定位置的配置文件,可以使用`--config`参数指定
例如
```bash
python spaceship_api.py --config C:\sites\wp_sites\spaceship_config.json get-domain  --domain stadtmarkt24.com
```
## list-domains 新参数说明

### 只输出域名（每行一个）

```bash
python spaceship_api.py list-domains --names_only
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
python spaceship_api.py list-domains --all --names_only
```
输出所有域名，每行一个。

## 其它示例

注册域名：

```bash
python spaceship_api.py register-domain --domain example.com --auto_renew --privacy_level high
```

查询 DNS 记录：

```bash
python spaceship_api.py list-dns --domain example.com
```

更多命令和参数请使用 `-h` 查看帮助。
- 查询联系人：
  ```bash
  python spaceship_api.py get-contact --contact_id 1ZdMXpapqp9...Azf5
  ```

### 异步操作
- 查询异步操作状态：
  ```bash
  python spaceship_api.py get-async --operation_id <id>
  ```

## 输出
所有命令均以 JSON 格式输出结果。

## 更多命令和参数
请运行：
```bash
python spaceship_api.py --help
```
查看所有支持的命令和参数。
