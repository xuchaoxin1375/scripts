#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
检查电商独立站所属平台的脚本

功能：
1. 首先尝试通过robots.txt文件中的标志性标记判断平台
2. 如果robots.txt方法不可用，则使用备用方法判断平台
3. 支持命令行参数输入URL
4. 输出检测结果

支持的平台：
- Shopify
- WooCommerce
- Shopline
- Magento
- BigCommerce
- Ecwid
- PrestaShop
- OpenCart
- Wix
- Squarespace

示例用法：
python check_shopify.py https://example.com
"""

import argparse
import requests
from urllib.parse import urlparse

# 支持的平台及其标志性标记
PLATFORM_MARKERS = {
    "Shopify": ["shopify", "cdn.shopify.com"],
    "WooCommerce": ["woocommerce", "wp-content/plugins/woocommerce"],
    "Shopline": ["shopline", "cdn.shoplineapp.com"],
    "Magento": ["magento", "skin/frontend/"],
    "BigCommerce": ["bigcommerce", "cdn11.bigcommerce.com"],
    "Ecwid": ["ecwid", "app.ecwid.com"],
    "PrestaShop": ["prestashop", "modules/"],
    "OpenCart": ["opencart", "catalog/view/theme/"],
    "Wix": ["wix", "static.wixstatic.com"],
    "Squarespace": ["squarespace", "assets.squarespace.com"],
}


def get_robots_txt(url):
    """获取网站的robots.txt文件内容"""
    parsed_url = urlparse(url)
    robots_url = f"{parsed_url.scheme}://{parsed_url.netloc}/robots.txt"
    try:
        response = requests.get(robots_url, timeout=10)
        response.raise_for_status()
        return response.text
    except requests.RequestException:
        return None


def detect_platform(url):
    """检测电商独立站所属平台"""
    robots_content = get_robots_txt(url)
    if robots_content:
        for platform, markers in PLATFORM_MARKERS.items():
            for marker in markers:
                if marker in robots_content.lower():
                    return platform

    # 如果robots.txt方法不可用，尝试其他备用方法
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        content = response.text.lower()
        for platform, markers in PLATFORM_MARKERS.items():
            for marker in markers:
                if marker in content:
                    return platform
    except requests.RequestException:
        pass

    return "未知平台"


def main():
    parser = argparse.ArgumentParser(description="检查电商独立站所属平台")
    parser.add_argument("url", help="电商独立站的URL")
    args = parser.parse_args()

    platform = detect_platform(args.url)
    print(f"检测到的平台: {platform}")


if __name__ == "__main__":
    main()
