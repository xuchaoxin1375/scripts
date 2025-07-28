"""
从spaceship_config.json文件中读取配置信息
方便起见,下面用SS表示SpaceShip
"""

import argparse
import json
import os
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
import pandas as pd
from spaceship_api import APIClient

DESKTOP = r"C:/Users/Administrator/Desktop"
# 鉴权信息配置文件(json格式)
SS_CONFIG_PATH = r"C:/sites/wp_sites/spaceship_config.json"

# 域名和名称服务器配置表(二选一)
SS_DOMAINS_TABLE_CONF = f"{DESKTOP}/table.conf"  # 简化格式的配置文件(只关注域名所在列,其他列数据被忽略,默认设置的NS1和NS2从配置文件中读取)
SS_DOMAIN_NS_PATH = (
    rf"{DESKTOP}/domains_nameservers.csv"  # 完整格式的专用配置文件(准确)
)
# 选择其中一个🎈
SS_DOMAINS_FILE = SS_DOMAINS_TABLE_CONF


URL_MAIN_DOMAIN_PATTERN = r"(?:https?://)?(?:[\w-]+\.)*([^/]+[.][^/]+)/?"


# 核心任务:将一批域名(已经购买)的域名服务器(nameservers)替换为指定值
# 域名配置在一个excel或者csv文件中,包含两列,第一列是域名,第二列是要自定义的域名服务器(nameservers)
# 代码如下:


def get_main_domain_name_from_str(url):
    """
    从字符串中提取域名,结构形如 "二级域名.顶级域名",即SLD.TLD;

    仅提取一个域名,适合于对于一个字符串中仅包含一个确定的域名的情况
    例如,对于更长的结构,"子域名.二级域名.顶级域名"则会丢弃子域名,前缀带有http(s)的部分也会被移除

    Examples:
    # 测试URL列表
    urls = ['www.domain.com', 'https://www.dom-ain.com','https://sports.whh.cn.com', 'domain-test.com',
    'http://domain.com', 'https://domain.com/','# https://domain.com']
    """
    # 使用正则表达式提取域名
    match = re.search(URL_MAIN_DOMAIN_PATTERN, url)
    if match:
        return match.group(1) or ""
    return ""


# 读取excel 或 csv 文件
def read_data(file_path):
    """读取数据
    根据文件名判断使用pd.csv还是pd.excel亦或是普通的.conf文件等其他普通文本文件

    Args:
        file_path (str): 文件路径
    Returns:
        pd.DataFrame: 数据
    """
    if file_path.endswith(".csv"):
        df = pd.read_csv(file_path)
    elif file_path.endswith(".xlsx") or file_path.endswith(".xls"):
        df = pd.read_excel(file_path)
    else:
        with open(file_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
            domains = []
            for line in lines:
                # line.split(" ")
                # 数量不定的空白作为分隔符
                parts = re.split(r"\s+", line)
                domain = parts[0].strip()
                if not re.match(r"\w+", domain):
                    print(f"忽略行: {line}")
                    continue
                domain = get_main_domain_name_from_str(domain)
                domains.append(domain)
        all_columns = ["domain", "nameserver1", "nameserver2"]
        df = pd.DataFrame({"domain": domains}, columns=all_columns)
        # df.fillna("", inplace=True)

    return df


def get_data(file_path, config):
    """读入的数据,执行必要的处理

    Args:
        file_path (str): 文件路径
        config (dict): 配置参数

    Returns:
        pd.DataFrame: 处理后的数据


    """

    df = read_data(file_path)
    # 如果nameserver1字段为空,则设置默认值为x,nameserver2字段为空,则设置默认值为y
    df_filled = df.fillna(
        {
            "nameserver1": config.get("nameserver1"),
            "nameserver2": config.get("nameserver2"),
        }
    )
    # 移除边缘的空格(试验表明,如果nameserver边缘有多余的空格,会导致api调用失败(422错误))
    df_filled["domain"] = df_filled["domain"].astype(str).str.strip()
    df_filled["nameserver1"] = df_filled["nameserver1"].astype(str).str.strip()
    df_filled["nameserver2"] = df_filled["nameserver2"].astype(str).str.strip()
    return df_filled


def parse_args():
    """命令行参数解析"""
    parser = argparse.ArgumentParser(
        description="批量更新SpaceShip域名的Nameservers\n\n"
        "示例: python update_nameservers.py -d domains.csv -c config.json --threads 8 --dry-run -v\n"
        "参数说明:\n"
        "  -d, --domains-file   域名和nameserver配置文件路径 (csv/xlsx/conf)\n"
        "  -c, --config        SpaceShip API配置文件路径 (json)\n"
        "  --threads           并发线程数 (默认: 4)\n"
        "  --dry-run           仅预览将要修改的内容,不实际提交API\n"
        "  -v, --verbose       显示详细日志\n"
    )
    parser.add_argument(
        "-d",
        "--domains-file",
        type=str,
        default=SS_DOMAINS_TABLE_CONF,
        help="域名和nameserver配置文件路径 (csv/xlsx/conf)",
    )
    parser.add_argument(
        "-c",
        "--config",
        type=str,
        default=SS_CONFIG_PATH,
        help="SpaceShip API配置文件路径 (json)",
    )
    parser.add_argument("--threads", type=int, default=4, help="并发线程数 (默认: 4)")
    parser.add_argument(
        "--dry-run", action="store_true", help="仅预览将要修改的内容,不实际提交API"
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="显示详细日志")
    return parser.parse_args()


def get_auth(config_path):
    """加载配置
    读取配置文件和环境变量中相关值

    Args:
        config_path (str): 配置文件路径
    Returns:
        dict: 配置信息

    key,secret优先级按照以下顺序(高优先级的值会覆盖低优先级的配置中对应的字段值):
    1. 环境变量 - 最高优先级
    2. 配置文件 - 默认值
    3. 程序默认值（如果有）

    """
    # 如果环境变量中配置了SP_KEY和SP_SECRET,则使用环境变量的值,否则使用配置文件中的值
    key = os.environ.get("SP_KEY")
    secret = os.environ.get("SP_SECRET")
    # 从json配置文件中读取鉴权配置
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    if key and secret:
        config["api_key"] = key
        config["api_secret"] = secret

    return config or {}


def update_nameservers(df, api, dry_run=False, verbose=False, threads=4):
    """使用线程池批量更新域名的域名服务器"""

    def task(row):
        domain = row["domain"]
        nameserver1 = row["nameserver1"]
        nameserver2 = row["nameserver2"]
        try:
            before = api.get_nameservers(domain)
            if verbose:
                print(domain, "before", before)
            if dry_run:
                print(
                    f"[DRY-RUN] Would update {domain} to NS: {nameserver1}, {nameserver2}"
                )
            else:
                result = api.update_nameservers(
                    domain, "custom", [nameserver1, nameserver2]
                )
                print(domain, "after", result)
        except Exception as e:
            print(f"[ERROR] {domain}: {e}")

    records = df.to_dict("records")
    with ThreadPoolExecutor(max_workers=threads) as executor:
        futures = [executor.submit(task, row) for row in records]
        for future in as_completed(futures):
            future.result()


def main():
    """主函数"""
    args = parse_args()
    config = get_auth(args.config)
    api = APIClient(config.get("api_key"), config.get("api_secret"))
    df = get_data(args.domains_file, config)
    print(df)
    update_nameservers(
        df, api, dry_run=args.dry_run, verbose=args.verbose, threads=args.threads
    )


if __name__ == "__main__":
    main()
