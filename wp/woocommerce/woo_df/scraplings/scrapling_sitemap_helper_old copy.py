#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Scrapling Cloudflare Sitemap Helper
一个可重用的模块，用于方便地抓取受 Cloudflare 保护的 XML 站点地图。

1. 支持 StealthySession 会话模式，自动管理 Cookie
2. 支持 user_data_dir 参数持久化保存 Cookie 到指定目录
3. 多次启动脚本时可直接复用已保存的 Cookie，避免重复验证

使用建议：
- 多次请求同一网站：启用会话模式（use_session=True）,并且启用user_data_dir参数保存 Cookie等数据
- 需要跨脚本重启保持登录：指定 session_dir 参数持久化 Cookie

references:
https://scrapling.readthedocs.io/en/latest
https://scrapling.readthedocs.io/en/latest/fetching/static.html#session-management

"""

from urllib.parse import urlparse
from scrapling import StealthyFetcher, Fetcher, StealthySession
from typing import Union

import logging

if __name__ == "__main__":
    datefmt1 = "%H:%M:%S"  # 仅打印时分秒
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(funcName)s - %(name)s - %(message)s",
        datefmt=datefmt1,
    )
logger = logging.getLogger(__name__)
print = logger.info # 临时测试
debug = logger.debug

# 示例:
SITEMAP_URL = "https://www.lavoroamaglia.it/product-sitemap1.xml"
SESSION_DIR = r"C:/temp/my_scrapling_profile" #user_data_dir 默认路径

def get_base_url(url: str) -> str:
    """从给定的 URL 中提取根域名（首页 URL）"""
    parsed = urlparse(url)
    return f"{parsed.scheme}://{parsed.netloc}/"


def fetch_sitemap_urls(
    sitemap_url: str,
    homepage_url=None,
    proxy=None,
    parse_urls: bool = True,
    verbose: bool = True,
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
    if not homepage_url:
        homepage_url = get_base_url(sitemap_url)

    if verbose:
        print("[*] 启动 Cloudflare 站点地图抓取器...")
        print(f"[*] 站点地图: {sitemap_url}")
        print(f"[*] 辅助首页: {homepage_url}")
        if proxy:
            print(f"[*] 使用代理: {proxy}")

    # 阶段 1：通过 HTML 首页进行 Cloudflare Stealth 验证
    if verbose:
        print("\n[阶段 1/3] 正在加载 HTML 首页以绕过 Cloudflare Turnstile 验证...")

    try:
        page = StealthyFetcher.fetch(
            homepage_url, solve_cloudflare=True, headless=True, proxy=proxy
        )

        if page.status != 200:
            if verbose:
                print(f"[错误] 阶段 1 失败，首页 HTTP 状态码: {page.status}")
            return [] if parse_urls else ""

        if verbose:
            print("[成功] Cloudflare 验证通过！")

        # 提取 cookies 并转换为 dict
        cookies_list = page.cookies
        cookie_dict = {c["name"]: c["value"] for c in cookies_list}

        # 提取请求头
        headers = page.request_headers

    except Exception as e:
        if verbose:
            print(f"[错误] 阶段 1 发生异常: {e}")
        return [] if parse_urls else ""

    # 阶段 2：使用 Fetcher 配合提取的凭证直接抓取 XML
    if verbose:
        print("\n[阶段 2/3] 正在携带绕过凭证直接请求 XML 站点地图...")

    try:
        sitemap_res = Fetcher.get(
            sitemap_url, headers=headers, cookies=cookie_dict, proxy=proxy
        )

        if sitemap_res.status != 200:
            if verbose:
                print(f"[错误] 阶段 2 失败，站点地图 HTTP 状态码: {sitemap_res.status}")
            return [] if parse_urls else ""

        if verbose:
            print(f"[成功] 站点地图内容下载完成，大小: {len(sitemap_res.body)} 字节")

    except Exception as e:
        if verbose:
            print(f"[错误] 阶段 2 发生异常: {e}")
        return [] if parse_urls else ""

    # 阶段 3：处理并返回数据
    if not parse_urls:
        if verbose:
            print("\n[阶段 3/3] 跳过 URL 解析，直接返回 XML 源码字符串。")
        return sitemap_res.body.decode("utf-8", errors="ignore")

    if verbose:
        print("\n[阶段 3/3] 正在解析站点地图 XML 数据...")

    try:
        # 使用 xpath 表达式提取所有的 loc 节点内容
        urls = sitemap_res.xpath("//*[local-name()='loc']/text()").getall()

        if verbose:
            print(f"[成功] 解析完成！共提取到 {len(urls)} 个 URL。")

        return urls

    except Exception as e:
        if verbose:
            print(f"[错误] 阶段 3 解析异常: {e}")
        return []
