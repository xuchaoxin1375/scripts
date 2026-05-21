#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Scrapling Cloudflare Sitemap Helper

用于抓取受 Cloudflare 保护的 XML 站点地图：
1. 先用 StealthyFetcher 访问 HTML 首页并获取浏览器 Cookie/User-Agent。
2. 再用 Fetcher.get 携带同一套凭证高速请求 XML。
3. 可返回 XML 原文，或解析 sitemap 中的所有 <loc> URL。
"""

from __future__ import annotations

import logging
import xml.etree.ElementTree as ET
from typing import Any, Mapping, Optional, Union
from urllib.parse import urlparse

from scrapling import Fetcher, StealthyFetcher

logger = logging.getLogger(__name__)

SITEMAP_URL = "https://www.lavoroamaglia.it/product-sitemap1.xml"
SESSION_DIR = r"C:/temp/my_scrapling_profile"


def _log(verbose: bool, message: str) -> None:
    if verbose:
        logger.info(message)


def get_base_url(url: str) -> str:
    """从给定 URL 中提取根域名首页 URL。"""
    parsed = urlparse(url)
    if not parsed.scheme or not parsed.netloc:
        raise ValueError(f"Invalid URL: {url!r}")
    return f"{parsed.scheme}://{parsed.netloc}/"


def _cookies_to_dict(cookies: Any) -> dict[str, str]:
    """兼容 Scrapling/Playwright 常见 Cookie 结构。"""
    if not cookies:
        return {}

    if isinstance(cookies, Mapping):
        return {str(key): str(value) for key, value in cookies.items()}

    cookie_dict: dict[str, str] = {}
    for cookie in cookies:
        if isinstance(cookie, Mapping):
            name = cookie.get("name")
            value = cookie.get("value")
            if name is not None and value is not None:
                cookie_dict[str(name)] = str(value)
        elif isinstance(cookie, tuple) and len(cookie) >= 2:
            cookie_dict[str(cookie[0])] = str(cookie[1])
    return cookie_dict


def _normalize_headers(headers: Any) -> dict[str, str]:
    if not headers:
        return {}
    return {str(key): str(value) for key, value in dict(headers).items() if value is not None}


def _response_text(response: Any) -> str:
    body = getattr(response, "body", b"")
    if isinstance(body, bytes) and body:
        return body.decode("utf-8", errors="ignore")
    if isinstance(body, str) and body:
        return body

    html_content = getattr(response, "html_content", None)
    if html_content:
        return str(html_content)

    text = getattr(response, "text", None)
    if text:
        return str(text)
    return ""


def parse_sitemap_urls(xml_source: Union[str, bytes]) -> list[str]:
    """解析 sitemap XML，返回所有 <loc> 节点文本，自动忽略 XML 命名空间。"""
    if isinstance(xml_source, bytes):
        xml_source = xml_source.decode("utf-8", errors="ignore")

    xml_source = xml_source.strip()
    if not xml_source:
        return []

    root = ET.fromstring(xml_source)
    urls: list[str] = []
    for element in root.iter():
        tag = element.tag.rsplit("}", 1)[-1] if isinstance(element.tag, str) else ""
        if tag == "loc" and element.text:
            url = element.text.strip()
            if url:
                urls.append(url)
    return urls


def fetch_sitemap_urls(
    sitemap_url: str,
    homepage_url: Optional[str] = None,
    proxy: Optional[str] = None,
    parse_urls: bool = False,
    verbose: bool = True,
    user_data_dir: Optional[str] = None,
    headless: bool = False,
    timeout: Union[int, float] = 60000,
    solve_cloudflare: bool = True,
) -> Union[list[str], str]:
    """
    抓取受 Cloudflare 保护的 XML 站点地图。

    Args:
        sitemap_url: 目标站点地图 XML 的完整 URL。
        homepage_url: 目标网站首页 URL。若不提供，将自动从 sitemap_url 中提取。
        proxy: 代理服务器 URL，例如 "http://127.0.0.1:7897"。
        parse_urls: True 返回 URL 列表；False 返回 XML 源码字符串。
        verbose: 是否输出步骤日志。
        user_data_dir: Scrapling/浏览器持久化资料目录，用于复用 Cookie。
        headless: 是否以无头浏览器通过 Cloudflare。
        timeout: 请求超时时间，单位毫秒。
        solve_cloudflare: 是否启用 Scrapling 的 Cloudflare 自动处理。

    Returns:
        parse_urls=True 时返回 list[str]；parse_urls=False 时返回 str。
        任一阶段失败时返回 [] 或 ""。
    """
    try:
        homepage_url = homepage_url or get_base_url(sitemap_url)
    except ValueError as exc:
        _log(verbose, f"[错误] {exc}")
        return [] if parse_urls else ""

    _log(verbose, "[*] 启动 Cloudflare 站点地图抓取器...")
    _log(verbose, f"[*] 站点地图: {sitemap_url}")
    _log(verbose, f"[*] 辅助首页: {homepage_url}")
    if proxy:
        _log(verbose, f"[*] 使用代理: {proxy}")
    if user_data_dir:
        _log(verbose, f"[*] 使用持久化浏览器资料目录: {user_data_dir}")

    _log(verbose, "\n[阶段 1/3] 正在加载 HTML 首页以绕过 Cloudflare 验证...")
    try:
        browser_kwargs: dict[str, Any] = {
            "solve_cloudflare": solve_cloudflare,
            "headless": headless,
            "proxy": proxy,
            "timeout": timeout,
        }
        if user_data_dir:
            browser_kwargs["user_data_dir"] = user_data_dir

        page = StealthyFetcher.fetch(homepage_url, **browser_kwargs)
        page_status = getattr(page, "status", None)
        if page_status != 200:
            _log(verbose, f"[错误] 阶段 1 失败，首页 HTTP 状态码: {page_status}")
            return [] if parse_urls else ""

        cookies = _cookies_to_dict(getattr(page, "cookies", None))
        headers = _normalize_headers(getattr(page, "request_headers", None))
        if not headers.get("user-agent") and not headers.get("User-Agent"):
            _log(verbose, "[警告] 未能从浏览器响应中读取 User-Agent，后续请求可能被拦截。")

        _log(verbose, f"[成功] Cloudflare 验证通过，提取到 {len(cookies)} 个 Cookie。")
    except Exception as exc:
        _log(verbose, f"[错误] 阶段 1 发生异常: {exc}")
        return [] if parse_urls else ""

    _log(verbose, "\n[阶段 2/3] 正在携带绕过凭证直接请求 XML 站点地图...")
    try:
        sitemap_res = Fetcher.get(
            sitemap_url,
            headers=headers,
            cookies=cookies,
            proxy=proxy,
            timeout=timeout,
        )
        sitemap_status = getattr(sitemap_res, "status", None)
        if sitemap_status != 200:
            _log(verbose, f"[错误] 阶段 2 失败，站点地图 HTTP 状态码: {sitemap_status}")
            return [] if parse_urls else ""

        xml_source = _response_text(sitemap_res)
        _log(verbose, f"[成功] 站点地图内容下载完成，大小: {len(xml_source.encode('utf-8'))} 字节")
    except Exception as exc:
        _log(verbose, f"[错误] 阶段 2 发生异常: {exc}")
        return [] if parse_urls else ""

    if not parse_urls:
        _log(verbose, "\n[阶段 3/3] 跳过 URL 解析，直接返回 XML 源码字符串。")
        return xml_source

    _log(verbose, "\n[阶段 3/3] 正在解析站点地图 XML 数据...")
    try:
        urls = parse_sitemap_urls(xml_source)
        _log(verbose, f"[成功] 解析完成！共提取到 {len(urls)} 个 URL。")
        return urls
    except ET.ParseError as exc:
        _log(verbose, f"[错误] 阶段 3 XML 解析失败: {exc}")
        return []
    except Exception as exc:
        _log(verbose, f"[错误] 阶段 3 解析异常: {exc}")
        return []


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(funcName)s - %(name)s - %(message)s",
        datefmt="%H:%M:%S",
    )
    xml_source = fetch_sitemap_urls(
        SITEMAP_URL,
        proxy="http://127.0.0.1:7897",
        user_data_dir=SESSION_DIR,
        headless=False,
        parse_urls=False,
    )
    if xml_source:
        print(xml_source)
    else:
        logger.error("Failed to fetch sitemap XML.")
