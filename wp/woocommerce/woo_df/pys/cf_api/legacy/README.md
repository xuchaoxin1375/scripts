# legacy（封存）

本目录存放被 `cloudflare_dns_tool.py` 取代的旧脚本，仅供追溯，不再维护：

- `cf_config_api.py`：早期单账号 DNS 操作脚本；依赖已不可用的 `cloudflare` Python SDK，其 DNS/邮箱转发/SSL/安全能力已由 `cloudflare_dns_tool.py --provision` 重建。
- `cf_update_dns_ip.py`：早期 IP 批量更新脚本。

新需求请直接使用根目录的 `cloudflare_dns_tool.py`（CLI），用法见根目录 `ReadMe.md`。
