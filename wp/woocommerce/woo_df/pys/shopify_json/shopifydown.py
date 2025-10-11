"""
Shopify JSON下载器
功能：批量下载Shopify网站的产品JSON数据
作者：Claude
"""

import argparse
import concurrent.futures
import hashlib
import json
import os
import random
import re
import signal
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from urllib.parse import urlparse

import pandas as pd
import requests
from bs4 import BeautifulSoup
from config import *
from useragents import USER_AGENTS

os.makedirs(STATUS_DIR, exist_ok=True)


# 日志辅助函数
def log(message, level=1, end=None):
    """根据设置的日志级别输出日志

    Args:
        message: 日志消息
        level: 日志级别，0-错误，1-信息，2-详细
        end: 行尾字符，默认为None，即换行
    """
    if level <= LOG_LEVEL:
        print(message, end=end)


class ShopifyDownloader:
    """Shopify产品JSON数据下载工具"""

    def __init__(self, output_dir=None, url_threads=3, download_threads=8):
        """初始化下载器
        
        Args:
            output_dir: 输出目录，默认为当前目录
            url_threads: URL采集线程数
            download_threads: JSON下载线程数
        """
        self.output_dir = output_dir or os.path.dirname(os.path.abspath(__file__))
        self.url_threads = url_threads
        self.download_threads = download_threads
        
        # 初始化统计数据
        self.stats = {
            'start_time': datetime.now(),
            'total_sites': 0,
            'processed_sites': 0,
            'successful_sites': 0,
            'failed_sites': 0,
            'total_products': 0,
            'downloaded_products': 0,
            'failed_products': 0,
            'site_details': []
        }
        
        # 记录每个站点下载的文件名
        self.file_records = {}
        
        # 中断标志
        self.interrupted = False
        
        # 设置中断信号处理
        signal.signal(signal.SIGINT, self.handle_interrupt)
        
        # 站点正则表达式配置
        self.site_regex_config = {}
        self._load_regex_config()

    def _load_regex_config(self):
        """从Excel加载站点正则表达式配置"""
        try:
            if os.path.exists(EXCEL_FILE_PATH):
                df = pd.read_excel(EXCEL_FILE_PATH)
                
                # 检查是否有site列和正则表达式列
                if 'site' in df.columns:
                    has_include_regex = 'include_regex' in df.columns
                    has_exclude_regex = 'exclude_regex' in df.columns
                    
                    if has_include_regex or has_exclude_regex:
                        log("从Excel加载正则表达式配置...", 1)
                        
                        for _, row in df.iterrows():
                            site = str(row['site']).strip()
                            if not site or site.lower() == 'nan':
                                continue
                                
                            config = {}
                            
                            # 加载包含正则表达式
                            if has_include_regex and not pd.isna(row['include_regex']):
                                include_regex = str(row['include_regex']).strip()
                                if include_regex and include_regex.lower() != 'nan':
                                    config['include_regex'] = include_regex
                            
                            # 加载排除正则表达式
                            if has_exclude_regex and not pd.isna(row['exclude_regex']):
                                exclude_regex = str(row['exclude_regex']).strip()
                                if exclude_regex and exclude_regex.lower() != 'nan':
                                    config['exclude_regex'] = exclude_regex
                            
                            if config:
                                self.site_regex_config[site] = config
                        
                        log(f"已加载 {len(self.site_regex_config)} 个站点的正则表达式配置", 1)
                    else:
                        log("Excel中未找到正则表达式列，将使用默认配置", 1)
        except Exception as e:
            log(f"加载正则表达式配置失败: {e}", 0)

    def get_site_regex(self, site_url):
        """获取指定站点的正则表达式配置
        
        Args:
            site_url: 站点URL
            
        Returns:
            包含include_regex和exclude_regex的字典
        """
        # 尝试直接匹配完整URL
        if site_url in self.site_regex_config:
            return self.site_regex_config[site_url]
        
        # 尝试匹配域名部分
        domain = urlparse(site_url).netloc
        if domain in self.site_regex_config:
            return self.site_regex_config[domain]
        
        # 如果没有找到匹配的配置，返回默认配置
        return {
            'include_regex': DEFAULT_INCLUDE_REGEX,
            'exclude_regex': DEFAULT_EXCLUDE_REGEX
        }

    def handle_interrupt(self, sig, frame):
        """处理中断信号"""
        log("\n\n接收到中断信号，正在安全停止...", 0)
        self.interrupted = True
        log("状态已保存，程序将在当前任务完成后退出", 0)
        log("再次按Ctrl+C将强制退出（可能丢失数据）", 0)
        
        # 如果再次按下Ctrl+C，则强制退出
        signal.signal(signal.SIGINT, lambda s, f: sys.exit(1))
    
    def get_random_headers(self):
        """获取随机User-Agent的请求头
        
        Returns:
            包含随机User-Agent的请求头字典
        """
        return {
            'User-Agent': random.choice(USER_AGENTS),
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1',
            'Cache-Control': 'max-age=0'
        }

    def get_sitemap_urls(self, site_url):
        """获取网站的产品sitemap URL列表
        
        Args:
            site_url: Shopify网站URL
            
        Returns:
            包含产品sitemap的URL列表
        """
        # 检查站点状态记录
        site_key = f"site:{site_url}"
        if site_key in self.collection_status and self.collection_status[site_key]['status'] == 1:
            log(f"使用缓存的sitemap数据: {site_url}", 1)
            return self.collection_status[site_key]['sitemaps']
        
        # 确保URL格式正确
        if not site_url.startswith('http'):
            site_url = 'https://' + site_url
        site_url = site_url.rstrip('/')
        
        sitemap_url = f"{site_url}/sitemap.xml"
        log(f"获取网站sitemap: {sitemap_url}", 1)
        
        try:
            # 使用随机User-Agent
            headers = self.get_random_headers()
            response = requests.get(sitemap_url, headers=headers, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'xml')
            
            # 获取站点的正则表达式配置
            regex_config = self.get_site_regex(site_url)
            include_regex = regex_config.get('include_regex', DEFAULT_INCLUDE_REGEX)
            exclude_regex = regex_config.get('exclude_regex', DEFAULT_EXCLUDE_REGEX)
            
            log(f"使用正则表达式 - 包含: {include_regex}, 排除: {exclude_regex}", 2)
            
            # 查找包含产品的sitemap
            product_sitemaps = []
            for loc in soup.find_all('loc'):
                url = loc.text.strip()
                
                # 使用配置的正则表达式进行匹配
                if re.search(include_regex, url) and not re.search(exclude_regex, url):
                    product_sitemaps.append(url)
            
            # 记录站点的sitemap数据
            self.collection_status[site_key] = {
                'status': 1,
                'time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'sitemaps': product_sitemaps
            }
            
            log(f"找到 {len(product_sitemaps)} 个产品sitemap", 1)
            return product_sitemaps
        except Exception as e:
            log(f"获取sitemap失败: {e}", 0)
            
            # 记录失败状态
            self.collection_status[site_key] = {
                'status': 0,
                'time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'error': str(e),
                'sitemaps': []
            }
            
            return []

    def get_product_urls(self, sitemap_url):
        """从sitemap中提取产品URL
        
        Args:
            sitemap_url: 产品sitemap的URL
            
        Returns:
            产品URL列表
        """
        # 检查是否已采集过
        if sitemap_url in self.collection_status and self.collection_status[sitemap_url]['status'] == 1:
            log(f"跳过已采集的sitemap: {sitemap_url}", 1)
            return self.collection_status[sitemap_url]['urls']
        
        # 如果未采集或状态为0，则进行采集
        try:
            log(f"采集sitemap: {sitemap_url}", 1)
            # 使用随机User-Agent
            headers = self.get_random_headers()
            response = requests.get(sitemap_url, headers=headers, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'xml')
            
            urls = []
            total_locs = len(soup.find_all('loc'))
            log(f"发现 {total_locs} 个URL，开始解析...", 1)
            
            for i, loc in enumerate(soup.find_all('loc'), 1):
                url = loc.text.strip()
                if '/products/' in url and not url.startswith('https://cdn.shopify.com'):
                    urls.append(url)
                
                # 显示进度
                if i % 100 == 0 or i == total_locs:
                    log(f"解析进度: {i}/{total_locs} ({i/total_locs*100:.1f}%)", 1, end="\r")
            
            log(f"\n从 {sitemap_url} 中提取了 {len(urls)} 个产品URL", 1)
            
            # 初始化json_status字段
            json_status = {}
            for url in urls:
                m = re.search(r'/products/([^/]+)', url)
                if m:
                    filename = f"{m.group(1)}.json"
                    json_status[filename] = 0
            
            # 记录采集状态
            self.collection_status[sitemap_url] = {
                'status': 1,  # 1表示已采集
                'time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'urls': urls,
                'json_status': json_status
            }
            
            return urls
        except Exception as e:
            log(f"获取产品URL失败 ({sitemap_url}): {e}", 0)
            
            # 记录失败状态
            self.collection_status[sitemap_url] = {
                'status': 0,  # 0表示未成功采集
                'time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'error': str(e),
                'urls': [],
                'json_status': {}
            }
            
            return []

    def download_json(self, product_url, save_dir, site_url=None, max_retries=5):
        """下载单个产品的JSON数据，增加重试和延时"""
        for attempt in range(max_retries):
            try:
                # 随机延迟，防止被限流
                time.sleep(random.uniform(0.5, 2.0))
                json_url = product_url + '.json'
                headers = self.get_random_headers()
                response = requests.get(json_url, headers=headers, timeout=10)
                response.raise_for_status()
                data = response.json()
                handle = re.search(r'/products/([^/]+)', product_url).group(1)
                filename = f"{handle}.json"
                filepath = os.path.join(save_dir, filename)
                with open(filepath, 'w', encoding='utf-8') as f:
                    json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
                # 下载成功，更新json_status
                if site_url:
                    for sitemap_url, info in self.collection_status.items():
                        if isinstance(info, dict) and 'urls' in info and product_url in info['urls']:
                            if 'json_status' in info:
                                info['json_status'][filename] = 1
                            break
                return True, filename
            except requests.exceptions.HTTPError as e:
                # 确保response已定义后再使用
                if 'response' in locals() and response.status_code == 429:
                    wait_time = 5 * (attempt + 1)
                    log(f"429限流，等待{wait_time}秒后重试...（第{attempt+1}次）", 1)
                    time.sleep(wait_time)
                    continue
                else:
                    log(f"下载失败 ({product_url}): {e}", 0)
                    break
            except Exception as e:
                log(f"下载失败 ({product_url}): {e}", 0)
                break
        # 下载失败，更新json_status
        if site_url:
            for sitemap_url, info in self.collection_status.items():
                if isinstance(info, dict) and 'urls' in info and product_url in info['urls']:
                    if 'json_status' in info:
                        handle = re.search(r'/products/([^/]+)', product_url)
                        if handle:
                            info['json_status'][f"{handle.group(1)}.json"] = 0
                    break
        return False, None

    def get_status_file_path(self, site_url):
        """生成唯一的状态文件路径
        
        Args:
            site_url: 站点URL
            
        Returns:
            状态文件的完整路径
        """
        domain = urlparse(site_url).netloc or site_url.split('/')[0]
        # 使用URL的哈希值确保文件名唯一
        url_hash = hashlib.md5(site_url.encode('utf-8')).hexdigest()[:8]
        return os.path.join(STATUS_DIR, f"{domain}_{url_hash}.json")

    def process_site(self, site_url, subfolder=None):
        """处理单个网站
        
        Args:
            site_url: Shopify网站URL
            subfolder: 子文件夹名，如果为None则使用域名
            
        Returns:
            包含下载结果的字典
        """
        # 准备站点统计信息
        site_stats = {
            'url': site_url,
            'start_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'status': 'failed',  # 默认为失败，成功时更新
            'total_products': 0,
            'downloaded_products': 0,
            'save_dir': '',
            'elapsed_time': 0
        }
        
        start_time = time.time()
        
        # 提取域名作为默认子文件夹名
        domain = urlparse(site_url).netloc
        if not domain:
            domain = site_url.split('/')[0]
        
        # 确定保存目录 - 使用指定的子文件夹名或默认使用域名
        folder_name = subfolder if subfolder else domain
        save_dir = os.path.join(self.output_dir, folder_name)
        site_stats['save_dir'] = save_dir
        
        # 创建保存目录
        os.makedirs(save_dir, exist_ok=True)
        
        # 确保文件列表保存目录存在
        os.makedirs(FILES_LIST_PATH, exist_ok=True)
        
        # 初始化该站点的文件名记录
        self.file_records[site_url] = []
        
        log(f"\n开始处理: {site_url}", 1)
        log(f"保存目录: {save_dir}", 1)
        
        # 检查是否中断
        if self.interrupted:
            log(f"检测到中断信号，跳过站点: {site_url}", 1)
            site_stats['status'] = 'skipped'
            site_stats['elapsed_time'] = round(time.time() - start_time, 2)
            return site_stats
        
        # 为每个站点创建独立的collection_status字典
        self.collection_status = {}
        
        # 加载该站点的状态
        status_file = self.get_status_file_path(site_url)
        if os.path.exists(status_file):
            try:
                with open(status_file, 'r', encoding='utf-8') as f:
                    self.collection_status = json.load(f)
                log(f"已加载采集状态: {status_file}", 1)
            except Exception as e:
                log(f"加载状态文件失败: {e}，将创建新的状态文件", 0)
                self.collection_status = {}
        else:
            self.collection_status = {}
        
        # 获取产品sitemap
        log("正在获取产品sitemap...", 1)
        sitemap_urls = self.get_sitemap_urls(site_url)
        if not sitemap_urls:
            log(f"未找到产品sitemap: {site_url}", 1)
            site_stats['elapsed_time'] = round(time.time() - start_time, 2)
            return site_stats
        
        # 检查是否中断
        if self.interrupted:
            log(f"检测到中断信号，跳过站点URL采集: {site_url}", 1)
            site_stats['status'] = 'skipped'
            site_stats['elapsed_time'] = round(time.time() - start_time, 2)
            return site_stats
        
        # 获取所有产品URL
        log(f"开始采集产品URL，共 {len(sitemap_urls)} 个sitemap...", 1)
        all_product_urls = []
        
        # 检查哪些sitemap需要采集
        sitemap_to_collect = []
        for sitemap_url in sitemap_urls:
            if sitemap_url not in self.collection_status or self.collection_status[sitemap_url].get('status', 0) != 1:
                sitemap_to_collect.append(sitemap_url)
            else:
                log(f"跳过已采集的sitemap: {sitemap_url}", 1)
                # 将已采集的URL添加到列表中
                if isinstance(self.collection_status[sitemap_url], dict) and 'urls' in self.collection_status[sitemap_url]:
                    all_product_urls.extend(self.collection_status[sitemap_url]['urls'])
        
        if sitemap_to_collect:
            log(f"需要采集的sitemap: {len(sitemap_to_collect)}/{len(sitemap_urls)}", 1)
            
            # 串行采集需要的sitemap（不再使用多线程）
            for sitemap_url in sitemap_to_collect:
                if self.interrupted:
                    log(f"检测到中断信号，停止URL采集", 1)
                    break
                urls = self.get_product_urls(sitemap_url)
                all_product_urls.extend(urls)
            # 采集完成后保存状态
            self.save_collection_status(status_file)
        else:
            log("所有sitemap已采集，使用缓存数据", 1)
        
        if not all_product_urls:
            log(f"未找到产品URL: {site_url}", 1)
            site_stats['elapsed_time'] = round(time.time() - start_time, 2)
            return site_stats
        
        site_stats['total_products'] = len(all_product_urls)
        self.stats['total_products'] += len(all_product_urls)
        
        log(f"找到 {len(all_product_urls)} 个产品URL", 1)
        log("正在准备下载任务，请稍候...", 1)
        
        # 检查是否中断
        if self.interrupted:
            log(f"检测到中断信号，跳过JSON下载: {site_url}", 1)
            site_stats['status'] = 'skipped'
            site_stats['elapsed_time'] = round(time.time() - start_time, 2)
            return site_stats
        
        # 下载所有产品JSON
        success_count = 0
        downloaded_files = []
        
        # 优化：创建下载任务时使用更高效的方法
        download_tasks = []
        # 创建URL到sitemap的映射，避免重复查找
        url_to_sitemap = {}
        for sitemap_url, info in self.collection_status.items():
            if isinstance(info, dict) and 'urls' in info:
                for url in info['urls']:
                    url_to_sitemap[url] = sitemap_url
        
        # 使用映射快速创建下载任务
        for url in all_product_urls:
            m = re.search(r'/products/([^/]+)', url)
            if m:
                filename = f"{m.group(1)}.json"
                sitemap_url = url_to_sitemap.get(url)
                
                need_download = True
                if sitemap_url:
                    info = self.collection_status.get(sitemap_url, {})
                    if isinstance(info, dict) and 'json_status' in info and info['json_status'].get(filename, 0) == 1:
                        # 已经下载成功，跳过
                        need_download = False
                
                if need_download:
                    download_tasks.append((url, save_dir, site_url))
        
        total_tasks = len(download_tasks)
        log(f"需要下载 {total_tasks} 个文件，已跳过 {len(all_product_urls) - total_tasks} 个已下载文件", 1)
        
        # 如果任务太多，分批处理以减少内存使用
        batch_size = 5000  # 每批处理的任务数
        for batch_start in range(0, len(download_tasks), batch_size):
            batch_end = min(batch_start + batch_size, len(download_tasks))
            current_batch = download_tasks[batch_start:batch_end]
            
            log(f"处理批次 {batch_start//batch_size + 1}/{(len(download_tasks) + batch_size - 1)//batch_size}，" 
                f"任务 {batch_start+1}-{batch_end} (共{len(download_tasks)})", 1)
            
            with ThreadPoolExecutor(max_workers=self.download_threads) as executor:
                # 批量提交任务
                futures = []
                for task in current_batch:
                    futures.append(executor.submit(self.download_json, *task))
                
                completed = 0
                
                # 使用as_completed处理已完成的任务，提高效率
                for future in concurrent.futures.as_completed(futures):
                    completed += 1
                    try:
                        result, filename = future.result(timeout=30)  # 设置30秒超时
                        if result:
                            success_count += 1
                            if filename:
                                # 格式化文件名为 http://wp.test/json/子文件夹名/文件名 的形式
                                formatted_filename = f"http://wp.test/json/{folder_name}/{filename}"
                                downloaded_files.append(formatted_filename)
                    except concurrent.futures.TimeoutError:
                        log(f"下载任务超时", 0)
                    except Exception as e:
                        log(f"下载任务异常: {e}", 0)
                    
                    # 显示进度
                    current_progress = batch_start + completed
                    total_progress = len(download_tasks)
                    log(f"进度: {current_progress}/{total_progress} ({current_progress/total_progress*100:.1f}%)", 1, end="\r")
                    
                    # 每下载50个文件保存一次状态
                    if completed % 50 == 0:
                        self.save_collection_status(status_file)
                    
                    # 检查是否中断
                    if self.interrupted and completed % 5 == 0:  # 每5个任务检查一次
                        log(f"\n检测到中断信号，将在完成当前批次后停止", 0)
                        # 取消剩余任务
                        for f in futures:
                            if not f.done():
                                f.cancel()
                        break
            
            # 每批次结束后保存状态
            self.save_collection_status(status_file)
            
            # 如果被中断，退出批处理循环
            if self.interrupted:
                log("\n处理被中断，停止后续批次", 1)
                break
        
        # 记录下载的文件名
        self.file_records[site_url] = downloaded_files
        
        # 只记录已完成的文件（json_status为1）
        finished_files = []
        for sitemap_url, info in self.collection_status.items():
            if isinstance(info, dict) and 'urls' in info and 'json_status' in info:
                for filename, status in info['json_status'].items():
                    if status == 1:
                        finished_files.append(f"http://wp.test/json/{folder_name}/{filename}")

        # 将文件名保存到TXT文件
        files_txt_path = os.path.join(FILES_LIST_PATH, f"{folder_name}.txt")
        with open(files_txt_path, 'w', encoding='utf-8') as f:
            f.write(f"站点: {site_url}\n")
            f.write(f"保存目录: {save_dir}\n")
            f.write(f"下载时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"成功下载文件数: {len(finished_files)}\n")
            f.write("-" * 60 + "\n")
            for i, formatted_filename in enumerate(finished_files, 1):
                f.write(f"{formatted_filename}\n")
        
        # 统计所有已完成的文件数（json_status为1的总数）
        all_finished = 0
        for sitemap_url, info in self.collection_status.items():
            if isinstance(info, dict) and 'urls' in info and 'json_status' in info:
                for v in info['json_status'].values():
                    if v == 1:
                        all_finished += 1
        
        log(f"\n完成! 已完成 {all_finished}/{len(all_product_urls)} 个JSON文件", 1)
        log(f"文件列表已保存至: {files_txt_path}", 1)
        
        # 更新站点统计信息
        site_stats['downloaded_products'] = success_count
        site_stats['status'] = 'success' if success_count > 0 else 'failed'
        site_stats['elapsed_time'] = round(time.time() - start_time, 2)
        
        # 更新全局统计
        self.stats['downloaded_products'] += success_count
        self.stats['failed_products'] += (len(all_product_urls) - success_count)
        
        if success_count > 0:
            self.stats['successful_sites'] += 1
        else:
            self.stats['failed_sites'] += 1
        
        # 保存站点统计信息
        self.stats['site_details'].append(site_stats)
        
        # 保存该站点的状态
        try:
            self.save_collection_status(status_file)
        except Exception as e:
            log(f"保存采集状态失败: {e}", 0)
        
        return site_stats

    def read_excel(self, excel_file):
        """从Excel文件读取网站URL和子文件夹名
        
        Args:
            excel_file: Excel文件路径
            
        Returns:
            包含(url, subfolder)元组的列表
        """
        try:
            log(f"读取Excel文件: {excel_file}", 1)
            df = pd.read_excel(excel_file)
            
            # 查找URL列
            url_columns = [col for col in df.columns if any(keyword in str(col).lower() 
                          for keyword in ['url', 'site', 'website', '网址', '网站', '域名'])]
            
            url_column = url_columns[0] if url_columns else df.columns[0]
            log(f"使用URL列: {url_column}", 1)
            
            # 查找子文件夹名列
            folder_columns = [col for col in df.columns if any(keyword in str(col).lower() 
                           for keyword in ['folder', 'subfolder', 'directory', '文件夹', '子文件夹', '目录'])]
            
            has_folder = bool(folder_columns)
            folder_column = folder_columns[0] if folder_columns else None
            
            if has_folder:
                log(f"使用子文件夹名列: {folder_column}", 1)
            else:
                log("未找到子文件夹名列，将使用域名作为子文件夹名", 1)
            
            # 检查是否有正则表达式列
            has_include_regex = 'include_regex' in df.columns
            has_exclude_regex = 'exclude_regex' in df.columns
            
            if has_include_regex or has_exclude_regex:
                log("检测到正则表达式配置列", 1)
            
            # 读取数据
            site_data = []
            for _, row in df.iterrows():
                url = str(row[url_column]).strip()
                if not url or url.lower() == 'nan':
                    continue
                
                # 处理子文件夹名
                subfolder = None
                if has_folder and not pd.isna(row[folder_column]):
                    subfolder = str(row[folder_column]).strip()
                    if not subfolder or subfolder.lower() == 'nan':
                        subfolder = None
                
                site_data.append((url, subfolder))
            
            log(f"从Excel读取了 {len(site_data)} 个站点", 1)
            self.stats['total_sites'] = len(site_data)
            return site_data
            
        except Exception as e:
            log(f"读取Excel文件失败: {e}", 0)
            return []

    def generate_report(self):
        """生成下载报告，保存为TXT文件
        
        Returns:
            报告文件的路径
        """
        # 计算总耗时
        end_time = datetime.now()
        duration = end_time - self.stats['start_time']
        duration_seconds = duration.total_seconds()
        
        # 准备报告内容
        report_lines = [
            "=" * 60,
            "Shopify JSON下载报告",
            "=" * 60,
            f"开始时间: {self.stats['start_time'].strftime('%Y-%m-%d %H:%M:%S')}",
            f"结束时间: {end_time.strftime('%Y-%m-%d %H:%M:%S')}",
            f"总耗时: {int(duration_seconds // 3600)}小时 {int((duration_seconds % 3600) // 60)}分钟 {int(duration_seconds % 60)}秒",
            "-" * 60,
            f"处理的站点总数: {self.stats['total_sites']}",
            f"成功的站点数: {self.stats['successful_sites']}",
            f"失败的站点数: {self.stats['failed_sites']}",
            f"发现的产品总数: {self.stats['total_products']}",
            f"成功下载的产品数: {self.stats['downloaded_products']} ({self.stats['downloaded_products']/max(1, self.stats['total_products'])*100:.1f}%)",
            f"下载失败的产品数: {self.stats['failed_products']}",
            "=" * 60,
            "\n站点详情:",
            "-" * 60,
        ]
        
        # 添加每个站点的详细信息
        for site in self.stats['site_details']:
            report_lines.extend([
                f"URL: {site['url']}",
                f"状态: {'成功' if site['status'] == 'success' else '失败'}",
                f"开始时间: {site['start_time']}",
                f"保存目录: {site['save_dir']}",
                f"产品总数: {site['total_products']}",
                f"下载成功: {site['downloaded_products']} ({site['downloaded_products']/max(1, site['total_products'])*100:.1f}%)",
                f"耗时: {site['elapsed_time']}秒",
                "-" * 60,
            ])
        
        # 确保文件列表保存目录存在
        os.makedirs(FILES_LIST_PATH, exist_ok=True)
        
        # 保存报告
        report_path = os.path.join(FILES_LIST_PATH, f"下载报告_{end_time.strftime('%Y%m%d_%H%M%S')}.txt")
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(report_lines))
        
        log(f"\n下载报告已保存至: {report_path}", 1)
        return report_path

    def start(self, urls=None, excel_file=None):
        """开始下载任务
        
        Args:
            urls: 网站URL列表
            excel_file: Excel文件路径
        """
        site_data = []
        
        if excel_file:
            site_data = self.read_excel(excel_file)
        elif urls:
            # 对于命令行提供的URLs，使用域名作为子文件夹名
            site_data = [(url.strip(), None) for url in urls if url.strip()]
            self.stats['total_sites'] = len(site_data)
        
        if not site_data:
            log("错误: 没有提供有效的URL", 0)
            return
        
        # 确保输出目录存在
        if not os.path.exists(self.output_dir):
            os.makedirs(self.output_dir)
        
        # 确保文件列表保存目录存在
        if not os.path.exists(FILES_LIST_PATH):
            os.makedirs(FILES_LIST_PATH)
            
        log(f"开始下载，共 {len(site_data)} 个站点，主目录: {self.output_dir}", 1)
        log(f"文件列表将保存到: {FILES_LIST_PATH}", 1)
        log("按Ctrl+C可以安全中断程序，下次运行将从中断处继续", 1)
        
        try:
            # 处理每个站点
            for i, (url, subfolder) in enumerate(site_data, 1):
                log(f"\n[{i}/{len(site_data)}] 处理站点: {url}", 1)
                
                # 检查是否中断
                if self.interrupted:
                    log(f"检测到中断信号，停止处理剩余站点", 1)
                    break
                
                site_stats = self.process_site(url, subfolder)
                
                # 更新处理的站点数
                self.stats['processed_sites'] += 1
            
            if self.interrupted:
                log("\n程序已安全中断", 1)
            else:
                log("\n所有站点处理完成!", 1)
            
            # 生成下载报告
            self.generate_report()
            
        finally:
            # 确保在任何情况下都保存所有已处理站点的状态
            for i, (url, subfolder) in enumerate(site_data):
                if i < self.stats['processed_sites']:  # 只保存已处理的站点
                    status_file = self.get_status_file_path(url)
                    try:
                        # 需要先加载站点状态，因为每个站点有独立的collection_status
                        if os.path.exists(status_file):
                            with open(status_file, 'r', encoding='utf-8') as f:
                                self.collection_status = json.load(f)
                        self.save_collection_status(status_file)
                    except Exception as e:
                        log(f"保存采集状态失败 ({url}): {e}", 0)

    def save_collection_status(self, status_file):
        """保存采集状态到文件"""
        try:
            with open(status_file, 'w', encoding='utf-8') as f:
                json.dump(self.collection_status, f, ensure_ascii=False, indent=2)
            # 不再显示保存提示
        except Exception as e:
            log(f"保存采集状态失败: {e}", 0)
