# -*- coding: utf-8 -*-

import time
import hashlib
import json
import requests
import urllib3
import os

urllib3.disable_warnings()
TIME_OUT = 30
DEFAULT_RETRIES = 3
DEFAULT_BACKOFF = 1


class BTApi:
    """
    宝塔api常用接口功能封装
    """

    def __init__(self, bt_panel=None, bt_key=None, retries=None, backoff=None):
        if bt_panel:
            self.__BT_PANEL = bt_panel
            self.__BT_KEY = bt_key
        # 重试配置（可在实例化时覆盖）
        self._retries = DEFAULT_RETRIES if retries is None else retries
        self._backoff = DEFAULT_BACKOFF if backoff is None else backoff
        # 配置完立即检查是否可以连接到服务器
        self.check_connection()

    def __get_md5(self, s):
        """
        计算MD5
        Args:
            s: 字符串
        Returns:
            MD5字符串
        """
        m = hashlib.md5()
        m.update(s.encode("utf-8"))
        return m.hexdigest()

    def __get_key_data(self):
        """
        构造带有签名的关联数组


        """
        now_time = int(time.time())
        requests_data = {
            "request_token": self.__get_md5(
                str(now_time) + "" + self.__get_md5(self.__BT_KEY)
            ),
            "request_time": now_time,
        }
        return requests_data

    def __http_post(self, url, requests_data, timeout=TIME_OUT, retries=None, backoff=None):
        """
        发送POST请求，带简单重试机制，忽略SSL验证(因为自签的原因)

        :param url: 请求的URL
        :param requests_json: 请求的关联数组
        :param timeout: 超时时间
        :param retries: 最大重试次数（可选，默认为实例配置或模块默认）
        :param backoff: 基础退避时间（秒），采用指数退避：backoff * (2**(attempt-1))
        """
        headers = {"Content-Type": "application/x-www-form-urlencoded"}

        if retries is None:
            retries = getattr(self, "_retries", DEFAULT_RETRIES)
        if backoff is None:
            backoff = getattr(self, "_backoff", DEFAULT_BACKOFF)

        attempt = 0
        while True:
            try:
                # 使用requests发送POST请求并禁用SSL验证
                response = requests.post(
                    url, data=requests_data, headers=headers, timeout=timeout, verify=False
                )
                response.raise_for_status()
                return response.text
            except requests.exceptions.RequestException as e:
                # 对于明确的客户端错误(4xx)，通常不应重试
                if isinstance(e, requests.exceptions.HTTPError):
                    status_code = e.response.status_code if e.response is not None else None
                    if status_code and 400 <= status_code < 500:
                        raise

                attempt += 1
                if attempt > retries:
                    # 达到最大重试次数，向上抛出最后一次异常
                    raise

                # 指数退避
                sleep_time = backoff * (2 ** (attempt - 1))
                try:
                    time.sleep(sleep_time)
                except Exception:
                    # 如果sleep被中断，继续下一次尝试或抛出
                    pass

    def check_connection(self):
        """检查和宝塔服务器的链接是否正常 

        如果失败则抛出异常停止后续操作!
        """
        info = self.get_systeminfo()
        # type(res)
        print(info)

        # 如果获取成功,可能没有'status'字段,如果失败,则有status:False
        version = info.get("version")
        if version:
            print(f"获取服务器信息成功,配置正确,宝塔版本:{version}")
        else:

            # status = res.get("status")
            # if getattr(res, "status") and status is False:
            print(
                "获取服务器信息失败,请检查错误,或者ip配置(白名单是否配置了当前ip或者是否使用了多余的代理导致白名单ip失效)"
            )
            print(f"HTTP_PROXY:{os.environ.get('HTTP_PROXY')}")
            print(f"HTTPS_PROXY:{os.environ.get('HTTPS_PROXY')}")
            raise ConnectionError("获取服务器信息失败,请检查错误")

    def get_logs(self):
        """
        获取日志列表

        """

        url = self.__BT_PANEL + "/data?action=getData"
        requests_data = self.__get_key_data()

        requests_data["table"] = "logs"
        requests_data["limit"] = 10
        requests_data["tojs"] = "test"

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_systeminfo(self):
        """
        获取系统基础统计

        """
        url = self.__BT_PANEL + "/system?action=GetSystemTotal"
        requests_data = self.__get_key_data()

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_diskinfo(self):
        """
        获取磁盘分区信息

        """
        url = self.__BT_PANEL + "/system?action=GetDiskInfo"
        requests_data = self.__get_key_data()

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_network(self):
        """
        获取实时状态信息(CPU、内存、网络、负载)

        """
        url = self.__BT_PANEL + "/system?action=GetNetWork"
        requests_data = self.__get_key_data()

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_taskcount(self):
        """
        检查是否有安装任务

        """
        url = self.__BT_PANEL + "/ajax?action=GetTaskCount"
        requests_data = self.__get_key_data()

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_panelup(self):
        """
        检查面板更新
        """
        url = self.__BT_PANEL + "/ajax?action=UpdatePanel"
        requests_data = self.__get_key_data()

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def _get_sites(
        self, limit=10, page=None, site_type=None, order=None, tojs=None, search=None
    ):
        """
        获取网站或列出网站列表,获取单个网站通常利用search参数来指定网站名

        Args:
            limit (int): 取回的数据行数【默认10】
            page (int): 当前分页[可选]
            site_type (int): 分类标识,-1:分部分类0:默认分类[可选
            order (str): 排序规则使用id降序：iddesc使用名称升序：namedesc[可选]
            tojs (str): 分页JS回调,若不传则构造URI分页连接[可选]
            search (str): 搜索内容[可选]
        Returns:
            dict: API响应结果
        """
        url = self.__BT_PANEL + "/data?action=getData&table=sites"
        requests_data = self.__get_key_data()

        requests_data["limit"] = limit
        requests_data["p"] = page
        requests_data["type"] = site_type
        requests_data["order"] = order
        requests_data["tojs"] = tojs
        requests_data["search"] = search

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_sites(self, limit=20, site_type=None, order=None, tojs=None, search=None):
        """
        获取所有网站列表
        每次获取100条数据，分为多次获取，直到全部数据获取完毕
        避免一次性获取过多造成传输异常

        Args:
            limit (int): 取回的数据行数,默认20,设置为0时返回全部
            site_type (int): 分类标识,-1:分部分类0:默认分类[可选]
            order (str): 排序规则使用id降序：iddesc使用名称升序：namedesc[可选]
            tojs (str): 分页JS回调,若不传则构造URI分页连接[可选]
            search (str): 搜索内容[可选]
        Returns:
            list: 网站列表


        """
        sites = []
        page = 1
        page_size_perfetch = 100
        cnt = 0
        while True:
            result = self._get_sites(
                limit=page_size_perfetch,
                page=page,
                site_type=site_type,
                order=order,
                tojs=tojs,
                search=search,
            )
            # 获取其中的data字段(数组)

            # 当data为空时或者数量低于page_size_perfetch，表示已经获取完毕
            result_size = len(result["data"])
            # 将本轮获取的数据添加到总容器
            sites.extend(result["data"])
            if result_size < page_size_perfetch:
                break
            # 当已获取网站数量超过所需要的数量,也退出循环
            if limit and len(sites) >= limit:
                sites = sites[:limit]
                break
            # 下一次获取的位置偏移
            page += 1
            cnt += 1
            print(
                f"第{cnt}轮获取到网站数量：{result_size},累计获取网站数量：{len(sites)}"
            )
        return sites

    def get_sitetypes(self):
        """
        获取网站分类
        """
        url = self.__BT_PANEL + "/site?action=get_site_types"
        requests_data = self.__get_key_data()
        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_phpversion(self):
        """
        获取已安装的PHP版本列表

        """
        url = self.__BT_PANEL + "/site?action=GetPHPVersion"
        requests_data = self.__get_key_data()
        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def add_site(
        self,
        webname: dict,
        path: str,
        type_id: int = 0,
        # api中使用'type'指定参数类型,而python中'type'为保留字,故使用'site_type'代替较好
        site_type: str = "PHP",
        php_version: str = "74",
        port: int = 80,
        ps: str = "by api",
        ftp=False,
        ftp_username="",
        ftp_password="",
        sql=False,
        codeing="utf8mb4",
        datauser="",
        datapassword="",
        time_out=TIME_OUT,
    ):
        """
        创建网站
        注意,宝塔api操作数据库的开关有bug,设置true似乎不生效

        Args:
            webname (dict): 网站主域名和域名列表，格式: {"domain":"domain.com","domainlist":[],"count":0}
            path (str): 网站根目录路径，例如: /www/wwwroot/domain.com
            type_id (int): 分类标识，0表示默认分类
            type (str): 项目类型，例如: "PHP"
            version (str): PHP版本，例如: "74" 表示PHP 7.4
            port (int): 网站端口，例如: 80
            ps (str): 网站备注信息
            ftp (bool): 是否创建FTP，True表示创建，False表示不创建
            ftp_username (str): FTP用户名，当ftp=True时必填
            ftp_password (str): FTP密码，当ftp=True时必填
            sql (bool): 是否创建数据库，True表示创建，False表示不创建
            codeing (str): 数据库字符集，例如: "utf8mb4"
            datauser (str): 数据库用户名及名称，当sql=True时必填
            datapassword (str): 数据库密码，当sql=True时必填

        Returns:
            dict: API响应结果
        """

        url = self.__BT_PANEL + "/site?action=AddSite"
        requests_data = self.__get_key_data()

        requests_data["webname"] = json.dumps(webname)
        requests_data["path"] = path
        requests_data["type_id"] = type_id
        requests_data["type"] = site_type
        requests_data["version"] = php_version
        requests_data["port"] = port
        requests_data["ps"] = ps
        requests_data["ftp"] = ftp
        requests_data["ftp_username"] = ftp_username
        requests_data["ftp_password"] = ftp_password
        requests_data["sql"] = sql
        requests_data["codeing"] = codeing
        requests_data["datauser"] = datauser
        requests_data["datapassword"] = datapassword
        # print(f"数据库开关:{sql}")
        result = self.__http_post(url, requests_data, timeout=time_out)
        print(json.loads(result))

        return json.loads(result)

    def del_site(self, site_id, webname, path, database, ftp):
        """
        删除网站

        Args:
            site_id (int): 网站ID，必传。
            webname (str): 网站名称，必传。
            path (str): 网站根目录路径，若不删除请传空字符串。
            database (bool): 是否删除关联数据库，True表示删除，False表示不删除。
            ftp (bool): 是否删除关联FTP，True表示删除，False表示不删除。
        Returns:
            dict: API响应结果
        """
        url = self.__BT_PANEL + "/site?action=DeleteSite"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id
        requests_data["webname"] = webname
        requests_data["path"] = path
        requests_data["database"] = database
        requests_data["ftp"] = ftp

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def stop_site(self, site_id, webname):
        """
        停用网站

        Args:
            site_id (int): 网站ID。
            webname (str): 网站名称。
        Returns:
            dict: API响应结果
        """
        url = self.__BT_PANEL + "/site?action=SiteStop"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id
        requests_data["name"] = webname

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def start_site(self, site_id, webname):
        """
        启用网站

        Args:
            site_id (int): 网站ID。
            webname (str): 网站名称。
        Returns:
            dict: API响应结果
        """
        url = self.__BT_PANEL + "/site?action=SiteStart"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id
        requests_data["name"] = webname

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_expdate(self, site_id, exp_date):
        """
        网站到期时间

        Args:
            site_id (int): 网站ID，必传。
            exp_date (str): 到期时间，格式如 '0000-00-00' 表示永久。
        Returns:
            dict: API响应结果
        """
        url = self.__BT_PANEL + "/site?action=SetEdate"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id
        requests_data["edate"] = exp_date

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_ps(self, site_id, ps=None):
        """
        修改网站备注

        Args:
            site_id (int): 网站ID。
            ps (str, optional): 备注内容。
        Returns:
            dict: API响应结果
        """
        url = self.__BT_PANEL + "/data?action=setPs&table=sites"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id
        requests_data["ps"] = ps

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_sitebakeups(self, page, limit, tojs, search):
        """
        获取网站备份列表
        :param page:
        :param limit:
        :param tojs:
        :param search:

        """
        url = self.__BT_PANEL + "/data?action=getData&table=backup"
        requests_data = self.__get_key_data()

        requests_data["p"] = page
        requests_data["limit"] = limit
        requests_data["tojs"] = tojs
        requests_data["search"] = search
        requests_data["type"] = 0

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_sitebackup(self, site_id):
        """
        创建网站备份
        :param site_id:

        """
        url = self.__BT_PANEL + "/site?action=ToBackup"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def del_backup(self, backup_id):
        """
        删除网站备份
        Args:
            backup_id (int): 备份ID
        Returns:
            dict: API响应结果
        """

        url = self.__BT_PANEL + "/site?action=DelBackup"
        requests_data = self.__get_key_data()

        requests_data["id"] = backup_id

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_sitedomainlist(self, site_id):
        """
        获取网站的域名列表
        Args:
            site_id (int): 网站ID
        Returns:
            dict: API响应结果
        """
        url = self.__BT_PANEL + "/data?action=getData&table=domain"
        requests_data = self.__get_key_data()

        requests_data["search"] = site_id
        requests_data["list"] = True

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def add_domain(self, site_id, webname, domain):
        """
        添加域名

        Args:
            site_id (int): 网站ID
            webname (str): 网站名称
            domain (str): 域名
        Returns:
            dict: API响应结果
        """
        url = self.__BT_PANEL + "/site?action=AddDomain"
        requests_data = self.__get_key_data()

        requests_data["search"] = site_id
        requests_data["webname"] = webname
        requests_data["domain"] = domain

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def del_domain(self, site_id, webname, domain, port):
        """
        删除域名
        Args:
            site_id (int): 网站ID
            webname (str): 网站名称
            domain (str): 域名
            port (int): 网站端口
        Returns:
            dict: API响应结果
        """

        url = self.__BT_PANEL + "/site?action=DelDomain"
        requests_data = self.__get_key_data()

        requests_data["search"] = site_id
        requests_data["webname"] = webname
        requests_data["domain"] = domain
        requests_data["port"] = port

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_rewritelist(self, siteName="domain.com"):
        """
        获取可选的预定义伪静态列表
        :param siteName:网站名称

        """
        url = self.__BT_PANEL + "/site?action=GetRewriteList"
        requests_data = self.__get_key_data()

        requests_data["siteName"] = siteName

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_filebody(self, path):
        """
        获取指定预定义伪静态规则内容(获取文件内容)
        取网站配置文件内容(获取文件内容)
        """
        url = self.__BT_PANEL + "/files?action=GetFileBody"
        requests_data = self.__get_key_data()

        requests_data["path"] = path

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_filebody(self, path, data):
        """
        保存伪静态规则内容(保存文件内容)
        保存网站配置文件(保存文件内容)

        Args:
            path (str): 文件路径
            data (str): 文件内容
        Returns:
            dict: API响应结果
        """
        url = self.__BT_PANEL + "/files?action=SaveFileBody"
        requests_data = self.__get_key_data()

        requests_data["path"] = path
        requests_data["data"] = data
        requests_data["encoding"] = "utf-8"

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_predefined_rewrite(self, template_name):
        """获取预设的伪静态规则
        可以通过get_rewritelist()获取可选的预定义伪静态列表，比如选取其中的wordpress名字,
        然后通过get_predefined_rewrite('wordpress')获取指定模板的伪静态规则内容。

        参考列表:
            {'rewrite': ['0.当前',
                'EduSoho',
                'EmpireCMS',
                'ShopWind',
                'crmeb',
                'dabr',
                'dbshop',
                'dedecms',
                'default',
                'discuz',
                'discuzx',
                'discuzx2',
                'discuzx3',
                'drupal',
                'ecshop',
                'emlog',
                'laravel5',
                'maccms',
                'mvc',
                'niushop',
                'pbootcms',
                'phpcms',
                'phpwind',
                'sablog',
                'seacms',
                'shopex',
                'thinkphp',
                'typecho',
                'typecho2',
                'wordpress',
                'wp2',
                'zblog'],
            }

        Args:
            template_name (str): 网站模板名称
        Returns:
            {'status': True,
                'only_read': False,
                'size': 107,
                'encoding': 'utf-8',
                'data': 'location /\n{\n\t try_files $uri $uri/ /index.php?$args;\n}\n\nrewrite /wp-admin$ $scheme://$host$uri/ permanent;',
                'historys': [],
                'auto_save': None,
                'st_mtime': '1754223539'
            }

        """
        path = f"/www/server/panel/rewrite/nginx/{template_name}.conf"
        res = self.get_filebody(path)

        return res

    def get_sitepath(self, site_id):
        """
        取回指定网站的根目录
        :param site_id:

        """
        url = self.__BT_PANEL + "/data?action=getKey&table=sites&key=path"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_diruserini(self, site_id, path):
        """
        取回防跨站配置/运行目录/日志开关状态/可设置的运行目录列表/密码访问状态

        """
        url = self.__BT_PANEL + "/site?action=GetDirUserINI"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id
        requests_data["path"] = path

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_diruserini(self, path):
        """
        设置防跨站状态(自动取反)

        """
        url = self.__BT_PANEL + "/site?action=SetDirUserINI"
        requests_data = self.__get_key_data()

        requests_data["path"] = path

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_accesslogs(self, site_id):
        """
        设置写访问日志

        """
        url = self.__BT_PANEL + "/site?action=logsOpen"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_sitepath(self, site_id, path):
        """
        修改网站根目录

        """
        url = self.__BT_PANEL + "/site?action=SetPath"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id
        requests_data["path"] = path

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_siteaccesslogs(self, site_id, path):
        """
        设置是否写网站访问日志

        """
        url = self.__BT_PANEL + "/site?action=SetSiteRunPath"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id
        requests_data["path"] = path

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_accesspwd(self, site_id, username, password):
        """
        设置密码访问

        """
        url = self.__BT_PANEL + "site?action=SetHasPwd"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id
        requests_data["username"] = username
        requests_data["password"] = password

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def close_accesspwd(self, site_id):
        """
        关闭密码访问

        """
        url = self.__BT_PANEL + "/site?action=CloseHasPwd"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_limitnet(self, site_id):
        """
        获取流量限制相关配置（仅支持nginx）

        """
        url = self.__BT_PANEL + "/site?action=GetLimitNet"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_limitnet(self, site_id, perserver, perip, limit_rate):
        """
        开启或保存流量限制配置（仅支持nginx）

        """
        url = self.__BT_PANEL + "/site?action=SetLimitNet"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id
        requests_data["perserver"] = perserver
        requests_data["perip"] = perip
        requests_data["limit_rate"] = limit_rate

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def close_limitnet(self, site_id):
        """
        关闭流量限制（仅支持nginx）

        """
        url = self.__BT_PANEL + "/site?action=CloseLimitNet"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def get_index(self, site_id):
        """
        取默认文档信息

        """
        url = self.__BT_PANEL + "/site?action=GetIndex"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id

        result = self.__http_post(url, requests_data)
        return json.loads(result)

    def set_index(self, site_id, index):
        """
        设置默认文档

        """
        url = self.__BT_PANEL + "/site?action=SetIndex"
        requests_data = self.__get_key_data()

        requests_data["id"] = site_id

        requests_data["Index"] = index

        result = self.__http_post(url, requests_data)
        return json.loads(result)
