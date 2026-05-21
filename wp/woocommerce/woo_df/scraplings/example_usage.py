#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
外部使用示例代码：调用 scrapling_sitemap_helper 模块抓取站点地图
"""

import os
from scrapling_sitemap_helper import fetch_sitemap_urls

def main():
    # 目标受 Cloudflare 验证保护的 XML 站点地图
    sitemap_url = "https://www.lavoroamaglia.it/product-sitemap1.xml"
    
    # 代理配置 (如果您的环境需要代理，请配置对应的代理地址，否则设置为 None)
    proxy = "http://127.0.0.1:7897" 
    
    def example_parse_urls():
            # ------------------ 示例 1: 默认行为（解析 URL 列表） ------------------
        print("=" * 60)
        print("【示例 1】默认解析站点地图 URL 列表 (parse_urls=True)")
        print("=" * 60)
        urls = fetch_sitemap_urls(sitemap_url=sitemap_url, proxy=proxy, parse_urls=True, verbose=True)
        
        if urls:
            print(f"\n[INFO] 成功解析！总计获取 URL 数量: {len(urls)}")
            print("前 3 个 URL:")
            for i, url in enumerate(urls[:3], 1):
                print(f"  {i}. {url}")
                
            output_path = "external_product_urls.txt"
            with open(output_path, "w", encoding="utf-8") as f:
                for url in urls:
                    f.write(f"{url}\n")
            print(f"[INFO] 已将 URL 列表保存至: {os.path.abspath(output_path)}")
        else:
            print("\n[ERROR] 示例 1 抓取失败。")
    def example_get_xml():
        # ------------------ 示例 2: 仅获取 XML 原码 ------------------
        print("\n" + "=" * 60)
        print("【示例 2】仅获取站点地图 XML 原码 (parse_urls=False)")
        print("=" * 60)
        xml_content = fetch_sitemap_urls(sitemap_url=sitemap_url, proxy=proxy, parse_urls=False, verbose=True)
        
        if xml_content:
            print(f"\n[INFO] 成功获取 XML 原码！原码字符长度: {len(xml_content)}")
            print("XML 前 300 个字符展示:")
            print("-" * 40)
            print(xml_content.strip()[:300])
            print("-" * 40)
            
            xml_output_path = "external_sitemap_raw.xml"
            with open(xml_output_path, "w", encoding="utf-8") as f:
                f.write(xml_content)
            print(f"[INFO] 已将 XML 原码保存至: {os.path.abspath(xml_output_path)}")
        else:
            print("\n[ERROR] 示例 2 抓取失败。")

if __name__ == "__main__":
    # example_parse_urls()
    example_get_xml()
