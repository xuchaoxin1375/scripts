# OpenResty JS 挑战（签名 Cookie）— 部署与运维指南

本文档描述一个基于 **OpenResty（nginx + lua-nginx-module）** 实现的 **必须执行 JavaScript 的反爬挑战**。

目标：

- 阻止简单脚本工具（如 `curl`、基础 Python 请求）直接访问受保护页面。
- 允许正常浏览器自动通过。
- 允许指定搜索引擎/爬虫（非中国、可配置）直接放行。
- 适配 CDN / 反向代理场景（不强绑定 IP）。

---

## 1. 功能特性

- **两段式（必须 JS 执行）流程**
  - 挑战页下发一个短期 **票据 Cookie** `sct`（非 HttpOnly）
  - 浏览器 JS 读取 `sct`，计算 `proof`，请求 `/__sc_verify`
  - 服务器校验票据 + proof，通过后才签发 **HttpOnly** 的 `sc2`
  - 不执行 JS 的情况下，无法通过单次 HTTP 请求直接获得有效 `sc2`

- **签名 Cookie：`sc2`（30 分钟）**
  - 格式：`sc2=<ts>_<nonce>_<mac>`
  - `mac = md5(secret|ts|nonce|ua)`
  - TTL：1800 秒（允许少量时钟误差）
  - 绑定 User-Agent（UA），降低 Cookie 被盗用后的复用价值

- **票据 Cookie：`sct`（2 分钟）**
  - 格式：`sct=<ts>_<nonce>_<sig>`
  - `sig = md5(secret|ticket|ts|nonce|ua)`
  - TTL：120 秒
  - 仅用于换取 `sc2`

- **跨子域 Cookie（避免 `www` <-> 裸域反复挑战）**
  - 当请求 Host 为子域名时，Cookie 会带 `Domain=.example.com`

- **挑战生成限速**
  - 使用 `lua_shared_dict sc_token_store` 对同一 IP 的挑战频率进行限制

- **爬虫白名单**
  - 可配置 UA allowlist（主流搜索引擎、社交爬虫等）

---

## 2. 工作原理（请求流程）

### 2.1 访问受保护页面

1. 客户端访问受保护路径，例如：`/product/...`
2. Nginx Lua 判断该请求是否需要挑战（`$need_challenge`）
3. 若需要挑战，则校验 `sc2`：

- 解析 `sc2 = ts_nonce_mac`
- 检查时间戳是否在有效期内
- 计算期望值 `md5(secret|ts|nonce|ua)`
- 与 `mac` 比对

4. 若无效/缺失：内部跳转到 `@challenge`

### 2.2 挑战页（`@challenge`）

- 生成一次性票据：
  - `ts = ngx.time()`
  - `nonce = 类随机 md5 子串`
  - `sig = md5(secret|ticket|ts|nonce|ua)`
- 下发 Cookie：
  - `Set-Cookie: sct=ts_nonce_sig; Max-Age=120; SameSite=Lax;（https 时带 Secure）`
- 返回 `js_challenge_openresty.html`

### 2.3 换票接口（`/__sc_verify`）

浏览器 JS 请求：

```
GET /__sc_verify?ts=...&nonce=...&proof=...
```

其中：

- `proof = md5(ts|nonce|ua)`

服务器校验：

- `sct` Cookie 存在且其 `ts/nonce` 与参数一致
- 票据签名 `sig = md5(secret|ticket|ts|nonce|ua)` 匹配
- `proof` 等于 `md5(ts|nonce|ua)`

成功后：

- 签发 `sc2`（HttpOnly）
- 清理 `sct`
- 返回 `200 ok`

---

## 3. 文件与路径

### 3.1 核心配置

- **挑战配置**：`/www/server/nginx/conf/com_js_signed.conf`
- **共享密钥 include**：`/www/server/nginx/conf/com_secret.conf`
- **挑战页面模板**：`/www/server/nginx/conf/js_challenge_openresty.html`

### 3.2 Nginx 主配置

- 运行中的 master 启动命令应类似：
  - `nginx -c /www/server/nginx/conf/nginx.conf`

---

## 4. 安装/启用

### 4.1 全局 nginx.conf（必需）

在 `/www/server/nginx/conf/nginx.conf` 的 `http {}` 内，确保：

- 已设置 `lua_package_path`（多数 OpenResty 已内置）
- 存在共享字典：

```
lua_shared_dict sc_token_store 10m;
```

然后 reload：

```
nginx -c /www/server/nginx/conf/nginx.conf -t
nginx -c /www/server/nginx/conf/nginx.conf -s reload
```

### 4.2 共享密钥（必需）

编辑：

- `/www/server/nginx/conf/com_secret.conf`

示例：

```
set $sc_secret "LONG_RANDOM_SECRET_32+";
```

要求：

- **务必保密**。
- 长度 **>= 16**（建议 32+）。
- 轮换密钥会使旧的 `sc2` 全部失效（用户会重新触发挑战）。

### 4.3 启用到站点（server 块）

在目标 vhost（例如：`/www/server/panel/vhost/nginx/drapeq.com.conf`）内：

```
include /www/server/nginx/conf/com_js_signed.conf;
```

放在该站点的 `server {}` 内。

然后 reload nginx。

---

## 5. 默认保护范围（以及如何调整）

在 `com_js_signed.conf` 中，目前受保护的 location 是：

- `location ~ ^/(product|shop|category|cart|checkout|account)/ { ... }`

如需保护更多路径，可扩展该正则。

如果你希望“除静态资源外几乎全站保护”，可参考：

- 使用更广的 `location / { ... }`，并显式添加 `location ~* \.(css|js|...)$ { set $need_challenge 0; }`

（务必谨慎，避免影响后台、API、健康检查等路径。）

---

## 6. 测试方法

### 6.1 浏览器测试

- 使用无痕窗口打开受保护页面。
- 应短暂显示挑战页，然后自动跳转/刷新进入真实页面。

在 DevTools > Application > Cookies 中应看到：

- `sct`（短暂存在）
- 随后出现 `sc2`（HttpOnly）

### 6.2 curl 测试（不执行 JS 应无法通过）

请求受保护页面：

```
curl -i https://www.example.com/product/...
```

预期：

- 返回 **挑战页 HTML**，并可能包含 `Set-Cookie: sct=...`
- 首次响应 **不会**直接给出有效 `sc2`
- 不执行 JS 的情况下，重复请求仍会持续返回挑战页

### 6.3 命令行完整模拟（用于调试）

如果你想模拟浏览器行为：

1) Request protected page to get `sct`
2) Compute `proof = md5(ts|nonce|ua)`
3) Call `/__sc_verify` with cookie `sct` and the computed proof
4) Use returned `sc2` to request the page again

---

## 7. 故障排查

### 7.1 挑战页反复循环

常见原因：

- **`/__sc_verify` 没有签发 `sc2`**
  - 表现：`/__sc_verify` 有响应，但没有 `Set-Cookie: sc2=...`
  - 修复：确保 `location = /__sc_verify` 在 `content_by_lua_block` 中执行 Lua（不要被 `return ...;` 短路）。

- **Host 在 `www` 与裸域之间跳转导致 cookie 丢失**
  - 修复：确保 cookie 带 `Domain=.example.com`。

- **密钥缺失或过短**
  - 检查 `com_secret.conf` 是否被 include 且内容正确。

- **系统时间不正确**
  - 服务器时间偏差会导致 `ts` 时间窗校验失败。

### 7.2 `__/sc_verify` 返回 403

可能原因：

- 票据过期（超出约 60 秒时间窗）
- `sct` 缺失（浏览器禁止 cookie）
- UA 不一致（隐私插件/浏览器策略导致请求前后 UA 变化）

### 7.3 Nginx reload 相关问题

务必使用与 master 进程相同的配置文件 reload：

```
nginx -c /www/server/nginx/conf/nginx.conf -s reload
```

确认 master 进程：

- `ps -ef | grep "nginx: master"`

---

## 8. 搜索引擎放行策略（防 UA 伪装）

本方案默认不会仅凭 `User-Agent` 放行 Google/Bing 等搜索引擎。

原因：

- `User-Agent` 很容易被伪造，如果仅靠 UA 放行，会导致“伪装成爬虫”直接绕过挑战。

实现方式（与 Cloudflare Verified Bots 思路类似）：

- 当请求 UA 命中疑似搜索引擎（如 `Googlebot`/`Bingbot`）时，使用 **反向 DNS（PTR）+ 正向 DNS（A/AAAA）回查确认** 该 IP 是否确实属于对应搜索引擎。
- 验证通过才放行（`need_challenge=0`），否则继续走挑战（方案 A）。
- 使用 `lua_shared_dict sc_bot_cache` 对验证结果按 IP 缓存：
  - 通过：缓存较长时间（例如 6 小时）
  - 不通过：缓存较短时间（例如 10 分钟）

注意：

- 需要服务器能够正常解析 DNS。
- 如果你的服务器 DNS 环境受限，可以把 nameserver 替换为你可用的递归解析器。

与 Cloudflare 类似的行为（推荐）：

- 当请求 UA 像 `Googlebot`/`Bingbot` 但验证失败时，直接返回 **403**（不返回挑战页）。
- 目的：避免“伪装爬虫”拿到挑战页 HTML 后把它当作正文抓取结果。
- 响应头会带 `X-SC-Block`，用于定位阻断原因（如 `unverified_bot`、`unverified_bot_no_ptr` 等）。

---

## 9. AI 爬虫策略（弱校验 + 严格限速）

由于多数 AI 爬虫缺少类似 Google/Bing 的稳定“可验证来源”（PTR 域名/固定 IP 段），本方案对 AI 爬虫采用 **弱校验**：主要基于 `User-Agent` 识别。

风险提示：

- `User-Agent` 容易被伪造，因此必须配合更严格的限速与敏感路径隔离。

当前实现策略：

- **常见 AI UA 命中**时，会设置 `is_ai_bot=1`。
- 对 AI bot 的弱放行开关为 `ai_allow`，满足以下条件时才会让 `need_challenge=0`：
  - 仅允许 `GET/HEAD`（非只读方法不弱放行）
  - 不属于敏感路径（账户/结算/后台等）

常见 AI UA 列表示例（可按需增删）：

- `GPTBot`
- `ChatGPT-User`
- `OAI-SearchBot`
- `OpenAI`
- `PerplexityBot`
- `ClaudeBot`
- `Anthropic`
- `cohere-ai`
- `Bytespider`
- `DuckAssistBot`

敏感路径（即使是 AI bot 也不弱放行）：

- `/wp-admin/`
- `/wp-login.php`
- `/xmlrpc.php`
- `/account/`、`/my-account/`
- `/cart/`、`/checkout/`

严格限速建议：

- 若你希望 AI bot 可抓取“几乎全站”，建议在全局启用专用限速区，例如：
  - `limit_req_zone $binary_remote_addr zone=ai_limit:10m rate=30r/m;`
- 并仅对 AI bot 生效（例如只对其访问的主要页面类型/路径开启）。

附加限制（可选）：

- 若你担心伪装 UA 刷挑战，可对 `@challenge` 内对 `is_ai_bot=1` 施加更严的每 IP 频率限制（本方案已加入）。

---

## 10. 安全说明 / 局限性

- 这不是 CAPTCHA。
- 高级攻击者仍可通过无头浏览器/真实浏览器自动化绕过。
- 本方案主要用于：
  - 提高低成本爬虫的攻击门槛
  - 阻止基础 `curl` / 脚本直接访问
  - 通过短 TTL + UA 绑定降低 cookie 重放价值

---

## 11. 快速检查清单

- [ ] `http {}` 内已设置 `lua_shared_dict sc_token_store 10m;`
- [ ] `http {}` 内已设置 `lua_shared_dict sc_bot_cache 10m;`
- [ ] `com_secret.conf` 内已设置 `set $sc_secret "...";`
- [ ] 站点 vhost 已 include `com_js_signed.conf`
- [ ] 挑战页模板存在：`/www/server/nginx/conf/js_challenge_openresty.html`
- [ ] `nginx -t` 通过
- [ ] reload 使用：`-c /www/server/nginx/conf/nginx.conf`
