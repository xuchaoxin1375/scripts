# OpenResty 签名 Cookie 浏览器挑战（JS Challenge）说明

## 1. 目标 / 解决的问题

该方案用于对站点的关键路径（如 `/product/*`、`/shop/*` 等）进行“浏览器验证”，实现：

- 允许真实浏览器正常访问（会出现一次检查页，随后自动回到目标页面）。
- 阻挡常见脚本请求（curl、python requests、简单爬虫），因为它们通常不执行 JS、也无法自动完成“挑战页 -> 重新访问”的流程。
- 允许非中国主流搜索引擎爬虫抓取（通过 UA 白名单直接放行）。
- 代理/VPN 用户也能通过（不绑定 IP，避免换 IP 误伤）。

> 备注：此方案是“应用层挑战”，并非万能。高级对手可通过无头浏览器或复刻逻辑绕过，但它对大部分低成本脚本爬虫非常有效。

---

## 2. 核心原理（简述）

### 2.1 签名 Cookie（`sc2`）

当请求命中保护路径时：

1. 若请求携带有效 `sc2` Cookie（且未过期、且签名校验通过），直接放行进入真实页面。
2. 若无有效 Cookie，则内部跳转到挑战页 `@challenge`：
   - 服务端生成短期 token 并设置 `HttpOnly` Cookie `sc2`。
   - 返回一个美观的 HTML 检查页面（英文提示），页面通过 JS 自动 `reload` 回原 URL。
3. 浏览器第二次请求会自动携带 Cookie，此时通过校验并放行。

Cookie 结构：

- `sc2 = ts_nonce_mac`
- `ts`：Unix 时间戳（秒）
- `nonce`：随机值
- `mac`：签名

当前签名算法：

- `mac = md5(secret|ts|nonce|ua)`
- `ua` 为请求 `User-Agent`

校验逻辑：

- `now - ts <= 1800`（30 分钟）
- `ts - now <= 300`（允许 5 分钟时钟漂移）
- `md5(secret|ts|nonce|ua) == mac`

> 安全性说明：
> - 该 Cookie 为 `HttpOnly`，JS 不能读取，可降低前端脚本窃取风险。
> - 绑定 UA + 短时效，使“复制 Cookie 复用”的收益降低。
> - 不绑定 IP，以避免代理用户的 IP 变化导致频繁挑战。

### 2.2 为什么挑战页必须是 200 而非 503

早期用 `error_page 503` 触发挑战会导致：

- 浏览器可能提示“页面有问题/已移动/服务不可用”。

当前实现使用 `access_by_lua_block` 内部：

- `ngx.exec("@challenge")`

这是一次“内部跳转”，最终对用户返回的是挑战页的 HTTP 200，因此体验更自然。

---

## 3. 相关文件与作用

### 3.1 `/www/server/nginx/conf/com_js_signed.conf`

- 主配置文件（被 `server {}` include）。
- 定义：
  - 是否需要挑战：`set $need_challenge 1;` + 各类 UA 白名单逻辑。
  - 受保护路径 `location`。
  - `@challenge`：签发 cookie 并输出挑战页面。
- 注意：目前密钥已写在该文件的 `set $sc_secret "...";`。

### 3.2 `/www/server/nginx/conf/js_challenge_openresty.html`

- 挑战页面模板（美观 UI + 英文化提示）。
- 该页面**不负责写 Cookie**，Cookie 由服务端在 `@challenge` 中写入。
- JS 逻辑：
  - 显示进度条
  - 约 1s 后 `location.reload()` 回原 URL
  - sessionStorage 防循环（超过一定次数提示用户检查 cookies/js/插件）

### 3.3 `/www/server/panel/vhost/nginx/drapeq.com.conf`

- 站点 vhost 配置。
- 当前启用：
  - `include /www/server/nginx/conf/com_js_signed.conf;`

---

## 4. 关键配置点（必须项）

### 4.1 `lua_shared_dict`

在 `nginx.conf` 的 `http {}` 中需要：

- `lua_shared_dict sc_token_store 10m;`

用途：

- 挑战接口的简单频率限制（同一 IP 60 次/分钟）存储计数。

### 4.2 `sc_secret` 密钥

必须提供**足够强的密钥**（建议 32+ 随机字符串）。

当前实现方式（多站点推荐）：

- 通过独立文件集中管理密钥：`/www/server/nginx/conf/com_secret.conf`
- `com_js_signed.conf` 会 `include /www/server/nginx/conf/com_secret.conf;` 来获取 `$sc_secret`

这样你只需要定期替换 `com_secret.conf` 里的一行密钥即可完成“全站统一轮换”。

注意：

- 该文件应限制权限（不要对外暴露），避免泄露。
- 轮换密钥后，所有访客会重新触发一次挑战（旧 cookie 会失效）。

---

## 5. 放行策略（重要细节）

### 5.1 搜索引擎白名单

`com_js_signed.conf` 里对 UA 进行白名单放行（示例）：

- Google: `Googlebot` 等
- Bing: `bingbot`、`msnbot` 等
- Yandex / DuckDuck / Applebot / Slurp

这确保非中国主流搜索引擎可以抓取。

> 注意：UA 白名单只能防“误伤”，无法防“伪装 UA”。更严谨的做法是反向 DNS 验证，但实现成本更高。

### 5.2 代理/VPN 用户

- 本方案不绑定 IP，只绑定 UA。
- 代理用户 IP 变化不影响 cookie 通过。

---

## 6. HTTPS / Cloudflare 注意事项

- `@challenge` 中写 cookie 时会自动判断 `X-Forwarded-Proto=https` 或 `scheme=https` 追加 `Secure`。
- 若你在 Cloudflare 后面，通常 `scheme` 可能是 `http`，而真实外部是 `https`，因此更依赖 `X-Forwarded-Proto`。

---

## 7. 测试方法

### 7.1 使用 curl 验证挑战流程（命令行）

```bash
# 第一次：返回挑战页（HTTP 200），同时 Set-Cookie: sc2=...
curl -I -A 'Mozilla/5.0 ... Chrome/120 Safari/537.36' -c /tmp/scjar.txt \
  https://www.drapeq.com/product/xxx/

# 第二次：携带 cookie，应该返回真实页面（HTTP 200）
curl -I -A 'Mozilla/5.0 ... Chrome/120 Safari/537.36' -b /tmp/scjar.txt \
  https://www.drapeq.com/product/xxx/
```

### 7.2 语法检查与重载

```bash
nginx -t && nginx -s reload
```

---

## 8. 常见问题排查

### 8.1 一直停留在挑战页（循环刷新）

可能原因：

- `sc_secret` 不一致（挑战签发与验证使用的密钥不同）。
- 浏览器禁用 Cookie（或隐私插件阻止）。
- UA 被改变（某些隐私插件会随机 UA）。

### 8.2 500 Internal Server Error

历史踩坑：

- 使用了 `ngx.hmac_sha256` 但当前 OpenResty/ngx_lua 没有该函数。

当前实现已改为 `ngx.md5`，避免缺函数导致 500。

### 8.3 浏览器提示“页面有问题 / 服务不可用”

通常是对外返回了 `503` 状态。

当前实现通过 `ngx.exec("@challenge")` 内部跳转，最终返回 200，已规避该体验问题。

---

## 9. 可选增强（后续迭代方向）

- **更强签名算法**：升级为 HMAC-SHA256（需要确认可用 API 或引入 lua-resty 库）。
- **更严格的 bot 放行**：对 Google/Bing 做反向 DNS 校验（代价：实现复杂 + 误伤风险）。
- **更细粒度策略**：按路径/频率/行为进行分级挑战与封禁。

---

## 10. 变更记录（简要）

- 由 `com_js_plus.conf`（静态 HTML + 简单 cookie）升级为 `com_js_signed.conf`（OpenResty Lua 签名 cookie）。
- 挑战页改为复用 `/www/server/nginx/conf/js_challenge_openresty.html` 的美观模板，并改为英文提示。
- 挑战触发改为内部 `ngx.exec`，对外返回 200。
