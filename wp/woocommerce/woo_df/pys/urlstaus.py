import requests
import threading
from queue import Queue
import pandas as pd
from urllib.parse import urlparse

# 读取URL文件
def read_urls(filename):
    with open(filename, 'r') as f:
        urls = [line.strip() for line in f if line.strip()]
    return urls

# 检查单个URL的状态
def check_url(url, result_queue):
    try:
        # 确保URL有协议头
        if not url.startswith(('http://', 'https://')):
            url = 'http://' + url
        
        response = requests.get(url, timeout=10, allow_redirects=True)
        status = response.status_code
        
    except requests.exceptions.RequestException as e:
        status = str(e)

    print(url+"-> 状态吗："+str(status))
    
    result_queue.put((url, status))

# 多线程检查URL状态
def check_urls(urls, thread_count=10):
    result_queue = Queue()
    threads = []
    
    for url in urls:
        t = threading.Thread(target=check_url, args=(url, result_queue))
        t.start()
        threads.append(t)
        
        # 控制线程数量
        while len(threads) >= thread_count:
            for t in threads:
                if not t.is_alive():
                    threads.remove(t)
                    break
    
    # 等待所有线程完成
    for t in threads:
        t.join()
    
    # 收集结果
    results = []
    while not result_queue.empty():
        results.append(result_queue.get())
    
    # 按原始URL顺序排序结果
    url_order = {url: idx for idx, url in enumerate(urls)}
    results.sort(key=lambda x: url_order[x[0]])
    
    return results

# 主函数
def main():
    # 读取URL
    urls = read_urls('checkurl.txt')
    
    # 检查URL状态
    results = check_urls(urls)
    
    # 准备数据
    data = []
    for url, status in results:
        if status == 200:
            data.append({'URL': url, '状态': '正常 (200)'})
        else:
            data.append({'URL': url, '状态': f'异常 ({status})'})
    
    # 导出到Excel
    df = pd.DataFrame(data)
    output_file = 'url_status.xlsx'
    df.to_excel(output_file, index=False)
    
    print(f"检查完成，结果已保存到 {output_file}")

if __name__ == '__main__':
    main()