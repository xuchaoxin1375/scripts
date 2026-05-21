# 受 Cloudflare 保护的 XML 站点地图 (Sitemap) 高效抓取指南

本指南详细介绍如何使用 `scrapling` 库，配合一种高度稳定且高效的**双阶段混合（Hybrid）绕过策略**，抓取受 Cloudflare 强力验证保护的 XML 站点地图（Sitemap）。

---

## 🎯 核心技术挑战与解决方案

在面对 Cloudflare (CF) 保护的站点地图（例如 `https://www.lavoroamaglia.it/product-sitemap1.xml`）时，传统的爬虫手段往往会遇到两大难题：

1. **CF 阻拦 (403 Forbidden / Turnstile Captcha)**: 直接发起 HTTP 请求会触发 Cloudflare 质询拦截，导致抓取失败。
2. **Playwright XML 导航崩溃**: 如果直接使用自动化浏览器（如 `StealthyFetcher`）访问 `.xml` 页面，由于浏览器在解析 XML 时的底层行为（如触发多次跳转或启动下载），会抛出以下异常：
   ```text
   patchright._impl._errors.Error: Page.content: Unable to retrieve content because the page is navigating and changing the content.
   ```

### 💡 双阶段混合绕过策略 (Hybrid Bypass Strategy)

为了彻底解决以上问题，本方案将爬取过程分解为以下两个核心阶段：

1. **第一阶段：HTML 首页验证绕过**
   * 使用 `StealthyFetcher` 启动真实的无头浏览器并自动通过 Cloudflare Turnstile 验证首页（首页是标准的 HTML，验证极其稳定安全）。
   * 随后，我们提取出解密后的 **Cloudflare Clearance Cookie (`cf_clearance`)** 以及请求头 **User-Agent**。
   
2. **第二阶段：高速 C 级并发请求直接获取 XML**
   * 携带第一阶段获取的 Clearance 凭证与匹配的 User-Agent，使用 `Fetcher.get`（基于高速 `curl-cffi` 模拟器）直接请求 XML 站点地图文件。
   * 此方法**完美避开了 Playwright 试图加载并渲染 XML 时的崩溃现象**，且由于无浏览器引擎损耗，下载速度极快。

---

## 🛠️ 重用模块：`scrapling_sitemap_helper.py`

在您的项目工作区中已创建了通用的助手模块：`c:\repos\scripts\wp\woocommerce\woo_df\scraplings\scrapling_sitemap_helper.py`。

### 接口定义：`fetch_sitemap_urls`

```python
from typing import Union

def fetch_sitemap_urls(
    sitemap_url: str, 
    homepage_url: str = None, 
    proxy: str = None, 
    parse_urls: bool = True, 
    verbose: bool = True
) -> Union[list, str]:
    """
    抓取受 Cloudflare 保护的 XML 站点地图。可选择直接返回 XML 源码或解析后的 URL 列表。

    参数:
        sitemap_url (str): 目标站点地图 XML 的完整 URL。
        homepage_url (str, 可选): 目标网站首页 URL。若不提供，将自动从 sitemap_url 中提取。
        proxy (str, 可选): 代理服务器 URL，例如 'http://127.0.0.1:7897'。
        parse_urls (bool): 是否解析 XML 并提取其 URL 列表。若为 False，则直接返回 XML 源码字符串。默认值为 True。
        verbose (bool): 是否打印步骤日志。

    返回:
        Union[list, str]: 
            - 若 parse_urls=True，返回包含所有页面 URL 的 list。
            - 若 parse_urls=False，返回 XML 源码的 str。
            - 若抓取失败，返回空列表 [] 或空字符串 ""。
    """
```

---

## 🚀 快速上手示例

您可以直接在外部脚本中引入并调用该模块。在工作区中，本示例已保存在 `c:\repos\scripts\wp\woocommerce\woo_df\scraplings\example_usage.py`：

```python
#!/usr/bin/env python
# -*- coding: utf-8 -*-

from scrapling_sitemap_helper import fetch_sitemap_urls

# 1. 目标站点地图 URL
sitemap_url = "https://www.lavoroamaglia.it/product-sitemap1.xml"
proxy_server = "http://127.0.0.1:7897"

# ------------------ 示例 1: 默认解析 URL 列表 (parse_urls=True) ------------------
print("[*] 正在拉取并解析站点地图商品链接...")
urls = fetch_sitemap_urls(sitemap_url=sitemap_url, proxy=proxy_server, parse_urls=True)

if urls:
    print(f"[SUCCESS] 成功解析了 {len(urls)} 个链接！前三个为：")
    for i, link in enumerate(urls[:3], 1):
        print(f"  {i}. {link}")
    
    with open("my_product_urls.txt", "w", encoding="utf-8") as f:
        for url in urls:
            f.write(f"{url}\n")

# ------------------ 示例 2: 仅获取 XML 源码字符 (parse_urls=False) ------------------
print("\n[*] 正在获取站点地图 XML 原码...")
xml_source = fetch_sitemap_urls(sitemap_url=sitemap_url, proxy=proxy_server, parse_urls=False)

if xml_source:
    print(f"[SUCCESS] 成功获取 XML 原码，长度: {len(xml_source)} 字符")
    print("原码片段演示:")
    print(xml_source.strip()[:200])
```

---

## ⚙️ 进阶配置与最佳实践

* **代理 (Proxy) 的重要性**：
  Cloudflare Turnstile 验证不仅会校验浏览器指纹，还会严厉惩罚低信誉的 IP。如果在公有云/数据中心 IP 下频繁测试，验证通过率会大幅下降。
  * **建议**：配置高速住宅代理（Residential Proxy）或本地开发代理，这可以极大提高验证通过速度（通常在 3-8 秒内完成）。

* **请求头匹配 (User-Agent Match)**：
  Cloudflare 会把通过 Turnstile 验证的 `cf_clearance` 凭证与当时浏览器的 User-Agent 绑定。在第二阶段发起 `Fetcher.get` 请求时，**必须确保 headers 中的 User-Agent 与第一阶段抓取时完全一致**。`scrapling_sitemap_helper` 已在内部自动为您完成了此映射绑定。

---

## 📈 常见排查指南

### 1. 首页加载报错或超时？
* **原因**：网络延迟较大或未配置代理，导致 Playwright 打开浏览器后长时间无法连通目标网站。
* **解决**：在 `fetch_sitemap_urls` 参数中传入有效的本地或线上代理 URL。

### 2. 获取到了页面，但提取的 URL 数量为 0？
* **原因**：部分网站的 XML 节点结构或命名空间特殊。
* **解决**：本助手内部使用 `//*[local-name()='loc']/text()` 的 XPath 语法，它会自动剥离所有的 XML 命名空间限制（`xmlns`），适用于 99% 的标准 sitemap。
