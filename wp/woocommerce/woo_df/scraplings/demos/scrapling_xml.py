#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
使用 Scrapling 库爬取带有 Cloudflare 验证的 XML 站点地图 (Sitemap)

由于 Playwright/Patchright 在直接访问 XML 页面时，可能会因为浏览器对待 XML 的默认行为
（例如触发下载或触发多次导航）而导致 "Unable to retrieve content because the page is navigating" 错误，
本脚本采用了一种极其优雅且稳定的双阶段（Hybrid）绕过策略：

1. **第一阶段 (Stealth 验证绕过)**:
   使用 `StealthyFetcher` 访问目标网站的 HTML 首页 (https://www.lavoroamaglia.it/)。
   由于首页是 HTML 格式，浏览器会非常稳定地加载并自动通过 Cloudflare Turnstile 验证。
   随后，我们从中提取出已解密的 Cloudflare Clearance Cookie (`cf_clearance`) 以及浏览器指纹 Headers (包含 User-Agent)。

2. **第二阶段 (高速 curl-cffi 请求)**:
   利用 Scrapling 内置的 `Fetcher` (底层基于高效的 `curl-cffi` 模拟请求)，
   携带第一阶段获取到的 `cf_clearance` 凭证与相同的 User-Agent/Headers，
   直接对 XML 站点地图 (`https://www.lavoroamaglia.it/product-sitemap1.xml`) 发起 GET 请求。
   这样既完美避开了 Playwright 的 XML 导航异常，又实现了高速度与高成功率的解析。

3. **第三阶段 (XML 数据解析)**:
   使用 Scrapling 强大的 CSS/XPath 引擎，提取站点地图中的所有商品 URL，并保存至本地文件。
"""

import sys
import os
import socket
from scrapling import StealthyFetcher, Fetcher

# ==================== 配置区域 ====================
# 目标 URL
TARGET_HOMEPAGE = "https://www.lavoroamaglia.it/"
TARGET_SITEMAP = "https://www.lavoroamaglia.it/product-sitemap1.xml"

# 输出文件名
OUTPUT_FILE = "product_urls.txt"

# 自动检测本地代理 
PROXY_HOST = "127.0.0.1"
PROXY_PORT = 7897
PROXY_URL = f"http://{PROXY_HOST}:{PROXY_PORT}"
# =================================================

def check_local_proxy() -> str:
    """
    检查本地代理是否可用，如果可用则返回代理 URL，否则返回 None。
    """
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(1.0)
            if sock.connect_ex((PROXY_HOST, PROXY_PORT)) == 0:
                print(f"[INFO] 检测到本地代理可用: {PROXY_URL}")
                return PROXY_URL
    except Exception:
        pass
    print("[INFO] 未检测到本地代理，将尝试直接连接。")
    return None

def main():
    print("=" * 60)
    print(" 开始执行：使用 Scrapling 爬取带有 Cloudflare 验证的站点地图 ")
    print("=" * 60)

    # 1. 代理检测
    proxy = check_local_proxy()

    # 2. 第一阶段：通过首页绕过 Cloudflare 并提取凭证
    print(f"\n[1/3] 正在加载首页进行 Cloudflare 验证: {TARGET_HOMEPAGE}")
    try:
        # 使用 solve_cloudflare=True，并推荐 headless=True
        # 如果在无头模式下有困难，也可以尝试 headless=False
        page = StealthyFetcher.fetch(
            TARGET_HOMEPAGE,
            solve_cloudflare=True,
            headless=True,
            proxy=proxy
        )
        
        if page.status != 200:
            print(f"[ERROR] 首页加载失败，HTTP 状态码: {page.status}")
            sys.exit(1)
            
        print("[SUCCESS] Cloudflare 验证通过！成功获取首页页面。")
        
        # 提取 cookies
        cookies_list = page.cookies
        cookie_dict = {c['name']: c['value'] for c in cookies_list}
        
        # 确保 cf_clearance 存在
        if 'cf_clearance' not in cookie_dict:
            print("[WARNING] 未在返回的 Cookies 中发现 cf_clearance，可能无需验证或绕过有偏差。")
        else:
            print(f"[INFO] 成功提取 cf_clearance 凭证: {cookie_dict['cf_clearance'][:30]}...")

        # 提取请求头 (特别是 User-Agent)
        headers = page.request_headers
        print(f"[INFO] 成功锁定匹配的 User-Agent: {headers.get('user-agent')}")

    except Exception as e:
        print(f"[FATAL] 第一阶段 Cloudflare 验证发生异常: {e}")
        sys.exit(1)

    # 3. 第二阶段：使用高速 Fetcher 请求 XML 站点地图
    print(f"\n[2/3] 正在携带 clearance 凭证请求站点地图: {TARGET_SITEMAP}")
    try:
        sitemap_res = Fetcher.get(
            TARGET_SITEMAP,
            headers=headers,
            cookies=cookie_dict,
            proxy=proxy
        )

        if sitemap_res.status != 200:
            print(f"[ERROR] 站点地图请求失败，HTTP 状态码: {sitemap_res.status}")
            print(f"响应内容片段: {sitemap_res.text[:500]}")
            sys.exit(1)

        print(f"[SUCCESS] 站点地图获取成功！状态码: 200, 响应大小: {len(sitemap_res.body)} 字节")

    except Exception as e:
        print(f"[FATAL] 第二阶段请求站点地图发生异常: {e}")
        sys.exit(1)

    # 4. 第三阶段：XML 节点解析
    print("\n[3/3] 正在解析 XML 站点地图数据...")
    try:
        # 使用 xpath 表达式提取所有的 <loc> 节点
        # 使用 local-name() 可以完美绕过 XML 命名空间(xmlns)导致的匹配失败问题
        urls = sitemap_res.xpath("//*[local-name()='loc']/text()").getall()
        total_urls = len(urls)
        
        if total_urls == 0:
            print("[WARNING] 未能在站点地图中提取到任何 URL，请检查 XML 结构。")
            print("XML 内容片段如下：")
            print(sitemap_res.text[:500])
            sys.exit(1)

        print(f"[SUCCESS] 成功提取到 {total_urls} 个 URL！")
        print("\n前 5 个商品 URL 示例:")
        for idx, url in enumerate(urls[:5], 1):
            print(f"  {idx}. {url}")

        # 5. 保存结果到本地文件
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            for url in urls:
                f.write(f"{url}\n")
        
        print(f"\n[FINISH] 所有 {total_urls} 个 URL 已成功写入到本地文件: {os.path.abspath(OUTPUT_FILE)}")
        print("=" * 60)

    except Exception as e:
        print(f"[FATAL] 解析或保存站点地图时发生异常: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
