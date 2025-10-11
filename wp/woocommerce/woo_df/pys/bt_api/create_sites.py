"""
批量创建宝塔网站
调用封装好的宝塔api客户端BTApi
注意首先登录宝塔页面配置ip白名单,使用ip查询当前网络所处属的公网ip段,并添加到白名单中,其他ip发送的请求都会失败,即便密钥和宝塔面板地址是正确的也不行

配置宝塔密钥和面板地址,请拷贝server_config_template.json到你私密的目录下,修改其中的内容,
然后可以更改正式的名字,配置此代码中的server_config变量(默认尝试读取Administrator用户桌面上的deploy_configs/server_config.json文件)

注意,宝塔面板地址填写的是面板地址,如:http://192.168.1.1:8888,而不是http://192.168.1.1也不需要端口号后面的私密字符串，写到端口为止

这种情况下,即便代码泄露,其他ip的人也无法通过密钥访问你的宝塔

基本使用
# 向server2添加登记在配置文件 $desktop/table.conf中的站点(域名)
PS>    py $pys/bt_api/create_sites.py -s server2 -r -c $desktop/table.conf


"""

# import pybtpanel


import argparse
import json
import os
import re
import threading
import time

# import concurrent.futures
from concurrent.futures import ThreadPoolExecutor, as_completed

from btapi import BTApi
from comutils import get_main_domain_name_from_str

DESKTOP = "C:/users/Administrator/Desktop"
SERVER_CONFIG = f"{DESKTOP}/deploy_configs/server_config.json"
TEAM_JSON = r"C:/sites/wp_sites/SpiderTeam.json"
# 参数化🎈
TABLE_CONF = f"{DESKTOP}/table.conf"

REWRITE_CONTENT_WP = r"""
location /
{
	 try_files $uri $uri/ /index.php?$args;
}

rewrite /wp-admin$ $scheme://$host$uri/ permanent;

"""


def get_config(conf_path):
    """从配置文件中读取密钥"""
    with open(conf_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data


def parse_args():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description="批量添加宝塔站点")
    parser.add_argument(
        "-c",
        "--config",
        type=str,
        default=SERVER_CONFIG,
        help=f"宝塔配置文件路径,默认读取{SERVER_CONFIG}",
    )
    parser.add_argument(
        "-f",
        "--file",
        type=str,
        default=TABLE_CONF,
        help=f"待添加站点配置文件路径,默认读取桌面{TABLE_CONF}",
    )
    parser.add_argument(
        "-s",
        "--server",
        type=str,
        required=True,
        help="指定要操作的服务器名称,例如server1,server2,可用的名字定义在对应配置文件中的servers块",
    )
    parser.add_argument(
        "-r",
        "--rewrite",
        action="store_true",
        help="为添加的站点设置伪静态规则",
    )
    parser.add_argument(
        "-p",
        "--proxy",
        type=str,
        default="",
        help="可选，设置http或socks5代理;默认情况下,会清空当前环境的代理设置; \
            如果需要走代理请显式指定,但对于配置宝塔而言通常不指定代理;例如：http://127.0.0.1:7890 或 socks5://127.0.0.1:8800",
    )
    parser.add_argument(
        "-w",
        "--sites-home",
        default="/www/wwwroot",
        help="可选，指定所有站点的总目录,宝塔默认为/www/wwwroot",
    )
    return parser.parse_args()


def _parse_site_to_add(file):
    """
    从配置文件中解析出站点信息
    """
    res = []
    with open(file, "r", encoding="utf-8") as f:
        lines = f.readlines()
        # 检查该行是否被注释
        for line in lines:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                print(f"该行被注释，跳过:[{line}]")
            else:
                # 使用正则解析该行,各个字段用空白字符隔开
                parts = re.split(r"\s+", line)
                url = parts[0]
                domain = get_main_domain_name_from_str(url)
                user = parts[1]
                if not domain:
                    print(
                        f"不规范的域名字段:[domain:{domain};line:{line}],跳过此条配置🎈"
                    )
                    continue
                data = {
                    "domain": domain,
                    "user": user,
                }
                res.append(data)
                # print(f"\t解析到字段:[{parts}]")
                print(f"\t解析到站点信息:[{data}]")
    return res


def parse_site_to_add(file):
    """
    从配置文件中解析出站点信息
    (将站点所属人员用拼音首字母编码)
    """
    data = _parse_site_to_add(file)
    for item in data:
        name = item["user"]
        user_pinyin = get_config(TEAM_JSON)[name]
        item["user"] = user_pinyin
    return data


def set_rewrite(bt_api: BTApi, site_name, rewrite_rule=REWRITE_CONTENT_WP):
    """为网站预设伪静态
    宝塔中默认的伪静态模板:

    例如
    wordpress站点的伪静态模板:
    路径如下:/www/server/panel/rewrite/nginx/wordpress.conf

    内容如下:

    location /
    {
            try_files $uri $uri/ /index.php?$args;
    }

    rewrite /wp-admin$ $scheme://$host$uri/ permanent;



    """
    # 构造网站对应的伪静态文件路径
    rewrite_file_path = f"/www/server/panel/vhost/rewrite/{site_name}.conf"
    res = bt_api.set_filebody(rewrite_file_path, rewrite_rule)
    return res


def add_sites(bt_api: BTApi, args):
    """
    并行批量添加站点
    """
    config_file=args.file
    print(f"开始解析配置文件:[{config_file}]")
    set_rewrite_rule = args.rewrite
    sites_home = args.sites_home

    sites = parse_site_to_add(config_file)
    total = len(sites)
    print(f"共解析到{total}个站点，开始并行添加...")
    print(f"站点总家目录:[{sites_home}]")

    lock = threading.Lock()
    create_time = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())

    def _add_single_site(item, idx=0):
        """添加单个站点的内置函数
        (api有专门的单个站点添加接口,这里为了方便供多线程并发调用以及信息统计,专供内部调用)
        Args:
            item: 站点信息
            idx: 索引，用于打印进度

        Returns:
            tuple:站点域名, 是否成功, 错误信息

        """
        # 构造站点域名(domain.com,www.domain.com,*.domain.com)
        domain = item["domain"]
        domain1 = f"www.{domain}"
        domain2 = f"*.{domain}"
        # 域名列表
        domainlist = [domain1, domain2]
        user = item["user"]
        # 控制网站根目录🎈
        path = f"{sites_home}/{user}/{domain}/wordpress"
        msg_prefix = f"[{idx+1}/{total}] {domain}"
        try:
            with lock:
                print(f"{msg_prefix} -> 正在添加站点...")
            bt_api.add_site(
                webname={"domain": domain, "domainlist": domainlist, "count": 0},
                path=path,
                type_id=0,
                site_type="PHP",
                php_version="74",
                port=80,
                ps=f"by api@[{create_time}]",
                ftp=False,
                ftp_username="",
                ftp_password="",
                sql=False,
                codeing="utf8mb4",
                datauser="your_db_user",
                datapassword="your_db_password",
            )
            with lock:
                print(f"{msg_prefix} -> 添加站点成功！")
            if set_rewrite_rule:
                try:
                    set_rewrite(bt_api, domain, rewrite_rule=REWRITE_CONTENT_WP)
                    with lock:
                        print(f"{msg_prefix} -> 配置wp伪静态成功！")
                except Exception as e:
                    with lock:
                        print(f"{msg_prefix} -> 配置wp伪静态失败: {e}")
            return (domain, True, None)
        except Exception as e:
            with lock:
                print(f"{msg_prefix} -> 添加站点失败: {e}")
            return (domain, False, str(e))

    results = []
    start_time = time.time()
    # 使用线程池并发执行任务🎈
    with ThreadPoolExecutor() as executor:
        future_to_idx = {
            executor.submit(_add_single_site, item, idx): idx
            for idx, item in enumerate(sites)
        }
        for future in as_completed(future_to_idx):
            res = future.result()
            results.append(res)
    elapsed = time.time() - start_time

    # 统计结果
    print(f"\n批量添加完成，总耗时: {elapsed:.2f} 秒")
    success = [d for d, ok, _ in results if ok]
    failed = [(d, err) for d, ok, err in results if not ok]
    print(f"成功: {len(success)} 个, 失败: {len(failed)} 个")
    if failed:
        print("失败站点:")
        for d, err in failed:
            print(f"  {d}: {err}")


def main():
    """入口函数"""
    args = parse_args()
    config = get_config(args.config)
    servers = config["servers"]
    server = servers.get(args.server)
    bt = server.get("bt", {})
    bt_key = server.get("bt_key") or bt.get("bt_key")
    bt_url = server.get("bt_panel") or bt.get("bt_panel")

    # 这里以http代理为例，socks5可用requests库的socks支持
    os.environ["HTTP_PROXY"] = args.proxy
    os.environ["HTTPS_PROXY"] = args.proxy

    print("开始尝试链接宝塔并获取面板信息")
    api = BTApi(bt_url, bt_key)
    # check_connection(api)
    add_sites(bt_api=api, args=args)


if __name__ == "__main__":
    # 读取宝塔密钥配置文件
    main()
