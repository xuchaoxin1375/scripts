"""

更新spaceship中域名的域名服务器(nameservers)
读取配置文件spaceship_config.json中的信息,获取API_KEY和API_SECRET,并创建APIClient对象,完成配置

方便起见,下面用SS表示SpaceShip
---
# powershell命令行:
    python $pys/spaceship_api/update_nameservers.py -h

# 执行nameservers更新操作
    python $pys/spaceship_api/update_nameservers.py -c $Desktop/deploy_configs/spaceship_config.json -f $Desktop/domains_nameservers.csv -v

配置文件(json)内容示例
{
    "api_key": "your_short_api_key",
    "api_secret": "your_secret_long_string",
    "accounts": [
        {
            "account1": {
                "api_key": "your_short_api_key1",
                "api_secret": "your_secret_long_string1"
            }
        },
        {
            "account2": {
                "api_key": "your_short_api_key2",
                "api_secret": "your_secret_long_string2"
            }
        }
    ],
    "nameserver1": "your_ns1",
    "nameserver2": "your_ns2",
    "take": 100,
    "skip": 0,
    "order_by": "expirationDate"
}
"""

import argparse

# import json
# import os
# import sys
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

import pandas as pd

from spaceship_api import APIClient, get_auth

DESKTOP = r"C:/Users/Administrator/Desktop"
# 默认的鉴权信息配置文件(json格式)
DESKTOP = r"C:/Users/Administrator/Desktop"
DEPLOY_CONFIGS = f"{DESKTOP}/deploy_configs"
# 默认配置文件路径
SS_CONFIG_PATH = rf"{DEPLOY_CONFIGS}/spaceship_config.json"

# 域名和名称服务器配置表(二选一)
# 格式1:简化格式的配置文件(只关注域名所在列,其他列数据被忽略,默认设置的NS1和NS2从配置文件中读取)
SS_DOMAINS_TABLE_CONF = f"{DESKTOP}/table.conf"
# 格式2:完整格式的专用配置文件(准确)
SS_DOMAIN_NS_PATH = rf"{DESKTOP}/domains_nameservers.csv"
# 选择其中一个🎈
SS_DOMAINS_FILE = SS_DOMAIN_NS_PATH


URL_MAIN_DOMAIN_PATTERN = r"(?:https?://)?(?:[\w-]+\.)*([^/]+[.][^/]+)/?"


# 核心任务:将一批域名(已经购买)的域名服务器(nameservers)替换为指定值
# 域名配置在一个excel或者csv文件中,包含两列,第一列是域名,第二列是要自定义的域名服务器(nameservers)
# 代码如下:


def get_main_domain_name_from_str(url):
    """
    从字符串中提取域名,结构形如 "二级域名.顶级域名",即SLD.TLD;

    仅提取一个域名,适合于对于一个字符串中仅包含一个确定的域名的情况
    例如,对于更长的结构,"子域名.二级域名.顶级域名"则会丢弃子域名,
    前缀带有http(s)的部分也会被移除

    Examples:
    # 测试URL列表
    urls = ['www.domain.com', 'https://www.dom-ain.com',
    'https://sports.whh.cn.com', 'domain-test.com',
    'http://domain.com', 'https://domain.com/','# https://domain.com']
    """
    # 使用正则表达式提取域名
    match = re.search(URL_MAIN_DOMAIN_PATTERN, url)
    if match:
        return match.group(1) or ""
    return ""


# 读取表格数据(从excel 或 csv 文件文件读取数据)
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
                parts = re.split(r"\s+", line.strip())
                domain = parts[0].strip()
                if not re.match(r"\s*\w+", domain):
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
        "-f",
        "-t",
        "-d",
        "--domains-file",
        type=str,
        default=SS_DOMAINS_TABLE_CONF,
        help="域名和nameserver配置文件路径 (csv/xlsx/conf);几个短选项效果和长选项相同",
    )
    parser.add_argument(
        "-c",
        "--config",
        type=str,
        default=SS_CONFIG_PATH,
        help=f"SpaceShip API配置文件路径 (json),默认值:f{SS_CONFIG_PATH}",
    )
    parser.add_argument(
        "-w", "--threads", type=int, default=4, help="最大并发线程数 (默认: 4)"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="仅预览将要修改的内容,不实际提交API"
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="显示详细日志")
    parser.add_argument(
        "-a",
        "--account",
        type=str,
        default="",
        help="指定SpaceShip账号(用户名),默认置空时则读取默认密钥组",
    )
    parser.add_argument(
        "--list-accounts",
        action="store_true",
        help="列出配置文件中的账号,并退出",
    )
    return parser.parse_args()


def update_nameservers(df, api: APIClient, dry_run=False, verbose=False, threads=4):
    """使用线程池批量更新域名的域名服务器
    调用api.update_nameservers方法,更新域名的域名服务器
    """

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
                # 更新nameservers🎈
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
    auth = get_auth(args.config, args)
    api = APIClient(auth=auth)
    df = get_data(args.domains_file, auth)
    print(df)
    update_nameservers(
        df, api, dry_run=args.dry_run, verbose=args.verbose, threads=args.threads
    )


if __name__ == "__main__":
    main()
