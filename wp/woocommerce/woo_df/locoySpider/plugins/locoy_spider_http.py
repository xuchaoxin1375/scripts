import importlib  # noqa: F401 (动态导入)
import sys
from urllib import parse
import json
import os

# 使用curl_cffi 清理绕过代理,StealthyFetcher重量级模拟浏览器
from curl_cffi import requests
from curl_cffi.requests.session import ProxySpec

from scrapling.fetchers import StealthyFetcher, StealthySession

# import curl_cffi
import logging

# fetcher模式:auto,curl(curl_cffi),stealthy,None
# 默认使用auto模式,如果curl_cffi无法通过,则使用stealthy
FETCH_MODE = "auto"
# 定义一个本地文件夹路径用于存放浏览器数据,这样即便 Python 程序结束，下次运行依然能读取到之前的验证状态
# session共用效率更高,但是受限于采集器插件形式在,难以实现(每个url采集都是独立启动插件)条件下,复用cookie等信息,以尽量减少人机验证.
# 访问环境变量:
TEMP = os.environ.get("TEMP")
LOG_DIR = "C:/temp/spider"
# 确保日志文件所在目录存在.
os.makedirs(LOG_DIR, exist_ok=True)
BROWSER_PROFILE = os.path.abspath(
    r"C:/temp/my_scrapling_profile"
)  # 如果缺少权限,可以更换文件夹为: TEMP/scrapling_profile

# 设置插件内部的代理(todo:使用ip池轮换器rotator)
PROXIES_DICT = {"http": "http://localhost:8800", "https": "http://localhost:8800"}
PROXIES = ProxySpec(**PROXIES_DICT)
# PROXIES = PROXIES_DICT
PROXY = "http://localhost:8800"

# 代理字典格式
# proxies = {
#     "http": "http://user:pass@host:port",
#     "https": "http://user:pass@host:port"
# }

datefmt1 = "%H:%M:%S"  # 仅打印时分秒
logging.basicConfig(
    level=logging.INFO,
    filename="C:/temp/spider/log.txt",
    filemode="w",  # 默认是a,追加.
    encoding="utf-8",
    format="%(asctime)s - %(levelname)s - %(name)s - %(message)s",
    datefmt=datefmt1,
)
logger = logging.getLogger(__name__)
info = logger.info
# 获取命令行参数列表
args = sys.argv

info(args)

if len(sys.argv) != 5:
    print(len(sys.argv))
    print("The length of the command-line argument is not5")
    sys.exit()
else:
    # 如果调用方式合适,则进一步处理:
    plugin_name = args[0]
    # python插件的命令行调用中的4个参数语义化(赋值给变量)
    LabelCookie = parse.unquote(sys.argv[1])
    LabelUrl = parse.unquote(sys.argv[2])
    # PageType为List,Content,Pages分别代表列表页，内容页，多页http请求处理，Save代表内容处理
    PageType = sys.argv[3]  # 页面类型是简单字符串,不需要parse.unquote处理.
    SerializerStr = parse.unquote(sys.argv[4])
    info(
        json.dumps(
            {
                "plugin_name": plugin_name,
                "LabelCookie": LabelCookie,
                "LabelUrl": LabelUrl,
                "PageType": PageType,
                "SerializerStr": SerializerStr,
            },
            # sort_keys=True,
            indent=4,
        )
    )
    # 由于采集到的网页源码（HTML）可能非常大，超过了命令行参数的长度限制，火车采集器先将数据存入了一个临时文件，然后把文件路径传给 Python。
    # 判断第4个参数(字符串)是"原始 JSON 字符串"还是一个"指向文件的路径"。
    # 如果是路径，则打开并读取文件内容。这通常是为了防止数据量过大，超过命令行参数的长度限制。

    # JSON 数据的标准格式通常是以 {" 开头的对象。程序检查 SerializerStr 的前两个字符。
    if SerializerStr[0:2] != '''{"''':
        # 如果不满足json字符串的特征,则认为其表示一个文件路径,尝试读取文件.
        # 读取文件

        ## 方案1:try-finally 块处理文件
        # file_object = open(SerializerStr,mode='r',encoding="utf-8")
        # try:
        #     SerializerStr = file_object.read()
        #     解码文件内容:
        #     SerializerStr = parse.unquote(SerializerStr)
        # finally:
        #     # 资源释放
        #     file_object.close()
        # END1

        ## 方案2:使用 with 语句自动管理文件关闭
        with open(SerializerStr, mode="r", encoding="utf-8") as file_object:
            SerializerStr = file_object.read()

        # 文件在缩进结束后会自动关闭，然后再进行解码
        SerializerStr = parse.unquote(SerializerStr)
        # END2

    # 将获取到的字符串解析为 Python 的字典（Dictionary）对象 LabelArray，方便后续通过键值对进行操作。
    LabelArray = json.loads(SerializerStr)

    # 查看当前插件被以什么样的方式调用
    # LabelArray['test'] = PageType
    # 以下是用户编写代码区域
    if PageType == "Save":
        if LabelArray["标题"]:
            LabelArray["标题"] = "这是Python插件处理的标题x"
        # if LabelArray["log"]:
        #     LabelArray["log"] = "这是Python插件处理的日志"
        # LabelArray["log"] = "这是Python插件处理的日志"
    else:
        info(f"处理的url:{LabelUrl}")
        # >>>>>>>>
        url = LabelUrl
        # url = "https://www.momox-shop.fr/tad-hills-duck-goose-find-a-pumpkin-pappbilderbuch-M0037585813X.html"
        # url='https://nissan.worldoemparts.com/oem-parts/nissan-2023-2024-nissan-armada-floor-mats-all-season-black-t99e15zw1b'

        # 移除url中https://(不含)之前的内容:
        if not url.startswith("http://ok"):
            msg = f"普通url,跳过特殊处理:{url}"
            info(msg)
            # LabelArray["Html"] = msg
        else:
            url = url[(url.find("https://")) :]

            def curl_request():
                info(f"Attempting curl_request to: {url}")
                try:
                    response = requests.get(
                        url,
                        # proxies=PROXIES,
                        # impersonate="chrome120",
                        timeout=30,
                    )
                    # 检查 HTTP 状态码是否为 200
                    # if response.status_code == 200:
                    #     print("curl_request success (200)")
                    #     return response.text
                    # else:
                    #     print(f"curl_request failed with status: {response.status_code}")
                    #     return None

                    info(f"curl request status_code:{response.status_code}")
                    response.raise_for_status()  # 请求失败时主动抛出异常
                    return response.text

                except Exception as e:
                    info(f"curl_request error: {e},try another schema.")
                    return None

            def stealthy_fetch():
                try:
                    if BROWSER_PROFILE:
                        with StealthySession(
                            solve_cloudflare=True,
                            headless=False,
                            proxy=PROXY,
                            user_data_dir=BROWSER_PROFILE,  # 关键参数：持久化存储路径
                        ) as session:
                            page = session.fetch(url)
                    else:
                        page = StealthyFetcher.fetch(
                            url,
                            proxy=PROXY,
                            # timeout=30,
                            solve_cloudflare=True,
                            # real_chrome=True,
                            headless=False,
                        )
                    # return page
                    return page.body.decode("utf-8")
                except Exception as e:
                    info(f"scrapling stealthy request failed:{e}")
                    return None

            if FETCH_MODE == "auto":
                result = curl_request()
                if result is None:
                    result = stealthy_fetch()

            elif FETCH_MODE == "curl":
                result = curl_request()

            # scrapling 方案:抓取页面:
            # 基础请求(过不了js挑战)
            # page = Fetcher.get(url, proxy=proxy, timeout=30)
            elif FETCH_MODE == "stealthy":
                result = stealthy_fetch()

            LabelArray["Html"] = result

        # ============
        # 非Html标签似乎无法在此分支修改.
        # LabelArray["log"] #不生效

        # 打印字典LabelArray
        # info(LabelArray)
        # info(LabelArray["Html"])
        # LabelArray["Html"] = "debug"

    # 以上是用户编写代码区域
    # 将字典转换为 JSON 字符串，并控制json输出格式打印到控制台(这里不适合用ensure_ascii=False,否则会出现乱码,和火车头不兼容)
    # LabelArray = json.dumps(LabelArray, indent=4, sort_keys=True)
    LabelArray = json.dumps(LabelArray)
    # 采集器通过捕获python插件的标准输出来解析标签,因此内部调试打印信息不能直接print,只有在最后才能print限定的变量LabelArray(或者抛出异常的位置).
    print(LabelArray)
