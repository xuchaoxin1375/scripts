[toc]



---

# 🔒 Fail2Ban 合并版 `jail.local` 模板

一站式防御 **敏感文件扫描** + **后台登录暴力破解**

**文件路径**（通常是）：
```bash
/etc/fail2ban/jail.local
```

**内容**：
```ini
# ========== 基础配置 ==========
[DEFAULT]
# 封禁时长（秒），24 小时
bantime  = 86400
# 统计时间窗（秒），10 分钟
findtime = 600
# 在统计时间窗内允许错误的次数
maxretry = 5

# 使用 iptables 封禁
banaction = iptables-multiport

# 邮件报警（可选）
# destemail = you@example.com
# sender    = fail2ban@example.com
# mta       = sendmail

# ========== 1) 防止 WordPress 敏感文件扫描 ==========
[nginx-wordpress]
enabled  = true
filter   = nginx-wordpress
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 5
findtime = 600
bantime  = 86400

# ========== 2) 防止 wp-login.php 暴力破解 ==========
[wordpress-login]
enabled   = true
filter    = wordpress-login
port      = http,https
logpath   = /var/log/nginx/access.log
maxretry  = 5
findtime  = 600
bantime   = 86400
```

---

# 🔎 对应的 Filter 文件

## 1. `nginx-wordpress`  
**路径：**
```bash
/etc/fail2ban/filter.d/nginx-wordpress.conf
```
**内容：**
```ini
[Definition]
failregex = ^<HOST> -.* "(GET|POST).*(/xmlrpc\.php|/wp-json/wp/v2/users|/wlwmanifest\.xml|/\?author=).*" (200|301|403|404|444)
ignoreregex =
```

---

## 2. `wordpress-login`  
**路径：**
```bash
/etc/fail2ban/filter.d/wordpress-login.conf
```
**内容：**
```ini
[Definition]
failregex = ^<HOST> -.* "POST /wp-login\.php HTTP.*" (200|401|403)
ignoreregex =
```

---

# 🚀 启用并检查

1. **重启 Fail2Ban**
```bash
sudo systemctl restart fail2ban
sudo systemctl enable fail2ban
```

2. **查看监狱状态**
```bash
sudo fail2ban-client status
```
输出示例：
```
Jail list: nginx-wordpress, wordpress-login
```

3. **查看具体监狱**
```bash
sudo fail2ban-client status wordpress-login
```

---

# ✅ 最终效果

- 🔒 **nginx-wordpress** → 拦截扫描 `xmlrpc.php`、`?author=ID`、REST API 用户暴露、`wlwmanifest.xml` 等常见自动化探测。  
- 🔒 **wordpress-login** → 拦截 `wp-login.php` 暴力破解（默认 5 次失败 → 拉黑 24 小时）。  
- 🔒 **自动化封禁** → Fail2Ban 直接写入 iptables，攻击 IP 被彻底踢出局。  

