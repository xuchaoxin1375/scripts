"""
批量创建宝塔网站
调用封装好的宝塔api客户端BTApi
注意首先登录宝塔页面配置ip白名单,使用ip查询当前网络所处属的公网ip段,并添加到白名单中,其他ip发送的请求都会失败,即便密钥和宝塔面板地址是正确的也不行

配置宝塔密钥和面板地址,请拷贝bt_config_template.json到你私密的目录下,修改其中的内容,
然后可以更改正式的名字,配置此代码中的BT_CONFIG变量(默认尝试读取Administrator用户桌面上的bt_config.json文件)

注意,宝塔面板地址填写的是面板地址,如:http://192.168.1.1:8888,而不是http://192.168.1.1也不需要端口号后面的私密字符串，写到端口为止

这种情况下,即便代码泄露,其他ip的人也无法通过密钥访问你的宝塔

"""

# import pybtpanel


import json
import re

from comutils import get_main_domain_name_from_str

from btapi import BTApi

DESKTOP = "C:/users/Administrator/Desktop/"
BT_CONFIG = f"{DESKTOP}/bt_config.json"
TEAM_JSON = r"C:/sites/wp_sites/SpiderTeam.json"
DEFAULT_SERVER_NAME = "cxxu_df1"
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
                if(not domain):
                    print(f"不规范的域名字段:[domain:{domain};line:{line}],跳过此条配置🎈")
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


def add_sites(bt_api: BTApi, config_file, set_rewrite_rule=True):
    """批量添加站点
    从文件中读取并解析站点信息，并批量添加到宝塔面板
    Args：
        file:站点信息文件(table.conf)

    """
    for item in parse_site_to_add(config_file):
        domain = item["domain"]
        domain1 = f"www.{domain}"
        domain2 = f"*.{domain}"
        domainlist = [domain1, domain2]
        user = item["user"]
        path = f"/www/wwwroot/{user}/{domain}/wordpress"
        try:
            bt_api.add_site(
                webname={"domain": domain, "domainlist": domainlist, "count": 0},
                path=path,
                type_id=0,
                site_type="PHP",
                php_version="74",
                port=80,
                ps="by api",
                ftp=False,
                ftp_username="",
                ftp_password="",
                sql=False,
                codeing="utf8mb4",
                datauser="your_db_user",
                datapassword="your_db_password",
            )
            print(f"添加站点成功:[{domain}]")
            # 配置wp伪静态
            if set_rewrite_rule:
                try:
                    set_rewrite(bt_api, domain, rewrite_rule=REWRITE_CONTENT_WP)
                    print(f"配置wp伪静态成功:[{domain}]")
                except Exception as e:
                    print(f"配置wp伪静态失败:[{domain}],error:[{e}]")

        except Exception as e:
            print(f"添加站点失败:[{domain}],error:[{e}]")


if __name__ == "__main__":
    # 读取宝塔密钥配置文件
    config = get_config(BT_CONFIG)
    auth = config["servers"][DEFAULT_SERVER_NAME]
    bt_key = auth["bt_key"]
    bt_url = auth["bt_panel"]
    # print(key,bt_url)

    print("开始获取宝塔面板信息")
    api = BTApi(bt_url, bt_key)
    print(api.get_diskinfo())
    add_sites(api, TABLE_CONF)
