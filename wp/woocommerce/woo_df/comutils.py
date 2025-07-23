"""
共用函数或工具库
"""

# %%
import csv
import os
import queue
import re
import threading
from datetime import datetime
from logging import debug, error, info
from typing import List, Optional, Union
from urllib.parse import unquote, urlparse
from pandas import Series
import pandas as pd
import requests
from bs4 import BeautifulSoup

SUPPORT_IMAGE_FORMATS_NAME = (
    "jpg",
    "jpeg",
    "png",
    "webp",
    "tif",
    "heic",
    "tiff",
    "bmp",
    "gif",
)
SUPPORT_IMAGE_FORMATS = ("." + f for f in SUPPORT_IMAGE_FORMATS_NAME)
csv.field_size_limit(int(1e7))  # 允许csv文件最大为10MB
# 有些图片的url中可能包含空格!
COMMON_SEPARATORS = [
    ",",
    ";",
    #  , r"\s+"
]
URL_SEPARATORS = [
    # r"\s+",
    ">",
    # ";",
    # ",",
]
URL_MAIN_DOMAIN_PATTERN = r"(?:https?://)?(?:[\w-]+\.)*([^/]+[.][^/]+)/?"
# (https?://)?([\w-]+\.)*([^/]+[.][^/]+)/?
URL_MAIN_DOMAIN_NAME_PATTERN = (
    r"(https?://)?([\w-]+\.)*(?P<main_domain>[^/]+[.][^/]+)/?"
)
URL_SEP_PATTERN = "|".join(URL_SEPARATORS)
COMMON_SEP_PATTERN = "|".join(COMMON_SEPARATORS)
EMAIL_PATTERN = r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"
# 提取网址的正则表达式(部分情况下url中包含空白字符(比如空格)),对于采集多个图片url的时候有关
# HTTP_S_URL_CONS_PATTERN = r'https?://[^\s"<>]+'
HTTP_S_URL_CONS_PATTERN = r'https?://[^"<>]+'
URL_SEP_REGEXP = re.compile(URL_SEP_PATTERN)
COMMON_SEP_REGEXP = re.compile(COMMON_SEP_PATTERN)


def get_paths(input_dir: str, recurse: bool = False):
    """
    获取指定目录下的所有路径(绝对路径)
    其中包括了文件和子目录

    Args:
        input_dir (str): 要遍历的目录路径。
        recurse (bool): 是否递归遍历子目录，默认为 False。

    Returns:
        List[str]: 所有文件的完整路径列表。
    """
    files = []

    if recurse:
        for root, _, fs in os.walk(input_dir):
            files.extend([os.path.join(root, filename) for filename in fs])
    else:
        files = [
            os.path.join(input_dir, filename) for filename in os.listdir(input_dir)
        ]

    return files


def walk_with_depth(root_dir, depth=None):
    """
    递归遍历目录，支持指定递归深度和过滤目录/文件。

    Args:
        root_dir (str): 根目录路径。
        depth (int, optional): 遍历的最大深度，默认为 None（无限制）。

    Example:
        >>> test_dir=r"C:/ShareTemp/imgs_demo"
        >>> walk_with_depth(test_dir,depth=1 )
    """

    dirs = []
    files = []

    def walker(path, current_depth):
        if depth is not None and current_depth > depth:
            return

        try:
            entries = os.listdir(path)
        except PermissionError:
            # 忽略无法访问的目录
            return

        for entry in entries:
            full_path = os.path.join(path, entry)

            if os.path.isdir(full_path):
                dirs.append(full_path)
                walker(full_path, current_depth + 1)
            else:
                files.append(full_path)

    walker(root_dir, 1)
    return dirs, files


def merge_csv_files(
    directory: str, out_file="", remove_old_files=False, encoding: str = "utf-8"
) -> pd.DataFrame:
    """
    读取指定目录下的所有 CSV 文件并合并为一个结构统一的 DataFrame。

    Args:
        directory (str): 存放 CSV 文件的目录路径。
        out_file (str, optional): 合并后的 CSV 文件的输出路径，留空则不输出。
        remove_old_files (bool, optional): 是否删除原有 CSV 文件，默认为 True。
        encoding (str, optional): CSV 文件的编码格式，默认为 'utf-8'。

    Returns:
        pd.DataFrame: 合并后的 DataFrame。如果目录中没有 CSV 文件，则返回一个空的 DataFrame。

    Examples:
        >>> merged_df = merge_csv_files(r'./csv_demo')
        >>> print(merged_df)
    """
    os.makedirs(directory, exist_ok=True)
    # 获取所有 .csv 文件的绝对路径
    csv_files = [
        os.path.join(directory, file)
        for file in os.listdir(directory)
        if file.endswith(".csv")
    ]

    if not csv_files:
        return pd.DataFrame()

    # 读取所有 CSV 文件到 DataFrame 列表
    dfs = [pd.read_csv(file, encoding=encoding) for file in csv_files]

    if remove_old_files:
        for file in csv_files:
            os.remove(file)
    # 合并所有的 DataFrame
    merged_df = pd.concat(dfs, ignore_index=True)
    if out_file:
        merged_df.to_csv(out_file, index=False, encoding=encoding)

    return merged_df


def remove_duplicate_rows(file, subset=None, inplace=True):
    """移除csv文件中的重复行,默认直接修改原文件
    例如sku重复的行，只保留一条

    Args:
        csv_file (str): 待处理的 CSV 文件路径。
        inplace (bool, optional): 是否直接修改原文件，默认为 True。

    """
    print(f"remove duplicate rows in subset [{subset}] from {file}")
    df = pd.DataFrame()
    if os.path.exists(file):
        df = pd.read_csv(file)
        df.drop_duplicates(subset=subset, inplace=inplace)
        df.to_csv(file, index=False)
    else:
        print(f"{file} not exists")
    return df


def merge_csv_naive(csv_dir, out_file="", remove_old_files=False):
    """读取指定目录下的所有csv文件，并合并成一个csv文件
    注意,如果csv的格式不同(比如具有不同的列名,无法使用此函数合并)

    Args:
        csv_dir (str): csv文件所在目录
        out_file  : 是否将合并的数据输出成新的csv文件,参数为非空文件名时输出到文件,否则不输出到文件
        remove_old_files: 是否删除原有csv文件,默认删除

    Returns:
        tuple: 合并后的csv文件的标头行和数据行构成的元组

    """
    lines = []
    fieldnames = []
    csv_files = [
        os.path.join(csv_dir, f) for f in os.listdir(csv_dir) if f.endswith(".csv")
    ]
    for csv_file in csv_files:
        with open(csv_file, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            fieldnames = reader.fieldnames
            for row in reader:
                lines.append(row)
    if remove_old_files:
        for csv_file in csv_files:
            os.remove(csv_file)
    if out_file:
        with open(
            os.path.join(csv_dir, out_file), "w", encoding="utf-8", newline=""
        ) as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames or [])
            writer.writeheader()
            for row in lines:
                writer.writerow(row)
        # return os.path.join(csv_dir, )

    return fieldnames, lines


def remove_empty_html_tags(html: str, tags=None) -> str:
    """
    移除 HTML 中无内容的标签（如 <span></span> 或仅包含空白字符的标签对）。
    可指定要处理的标签类型，默认处理所有标签。

    Args:
        html (str): 输入的 HTML 字符串。
        tags (list, optional): 需要处理的标签名列表（如 ['span', 'div']），
            若为 None，则处理所有标签。

    Returns:
        str: 处理后的 HTML 字符串。
    """
    if not html:
        return html

    # 如果没有指定标签，则创建一个通用模式匹配所有标签
    if tags is None:
        # 匹配所有空标签或只包含空白字符的标签
        pattern = r"<([a-zA-Z][a-zA-Z0-9]*)[^>]*>\s*</\1>"
    else:
        # 匹配指定标签列表中的空标签
        tag_pattern = "|".join(tags)
        pattern = rf"<({tag_pattern})[^>]*>\s*</\1>"

    # 持续替换直到没有更多匹配项
    prev_html = ""
    current_html = html

    while prev_html != current_html:
        prev_html = current_html
        current_html = re.sub(pattern, "", current_html)

    return current_html


def remove_empty_html_tags_bybs(html: str, tags=None) -> str:
    """
    移除 HTML 中无内容的标签（如 <span></span> 或仅包含空白字符的标签对）。
    可指定要处理的标签类型，默认处理所有标签。

    依赖于 BeautifulSoup 库

    Args:
        html (str): 输入的 HTML 字符串。
        tags (list, optional): 需要处理的标签名列表（如 ['span', 'div']），
            若为 None，则处理所有标签。

    Returns:
        str: 处理后的 HTML 字符串。

    Examples:
    >>> test_html = '<li><span class="x">   </span>   <div> <div>Detail</div> <div> <span> </span> <span> </span> </div> </div> <div><div> <p>No buckle</li> <li>Adjustable from 30 to 52</li> </ul> <p><b>FABRIC TECH:</b></p> <p>100% nylon</p> <p>ITEM #: PG-13736</p> </div></div> </li> <li> <div> <br>
    '
    >>> remove_empty_html_tags_bybs(test_html)

    """

    if not html:
        return html

    # 使用 BeautifulSoup 解析 HTML
    soup = BeautifulSoup(html, "html.parser")

    # 持续查找并移除空标签，直到没有更多可移除的标签
    changed = True
    while changed:
        changed = False

        # 确定要处理的标签
        elements = soup.find_all(tags) if tags else soup.find_all()

        for element in elements:
            # 检查元素是否为空（只包含空白字符）
            if (
                element.name
                and (not element.get_text(strip=True))
                and not element.find_all()
            ):
                element.extract()  # 移除空元素
                changed = True

    return str(soup)


def get_user_choice_csv_fields(selected_ids, reader_headers):
    """询问用户选择csv文件中的要选择csv中的哪些列
    读取并打印csv的表头,列出供用户选择,并返回列号列表

    :param selected_ids: 已经记住的列号列表
    :param reader_headers: csv文件中的表头
    :return: 选择的列号列表

    """
    for idx, header in enumerate(reader_headers):
        print(f"{idx}. {header}")

    ipt = input(
        "请输入需要下载的图片的列号,如果只有一列,则视为图片url列,"
        "如果指定两列,则第一列视为指定的下载的文件保存的名字,第二列为需要下载的URL,输入的列号间用空格/逗号隔开: "
    )
    selectedx = re.split(COMMON_SEP_PATTERN, ipt.strip())
    if isinstance(selected_ids, list):
        selected_ids += selectedx
    info("You selected: %s", selectedx)
    return selected_ids


def split_multi(
    s: str,
    seps: Optional[Union[str, List[str]]] = None,
    ignore_empty: bool = True,
    strip_items: bool = True,
    case_sensitive: bool = True,
) -> List[str]:
    """
    根据多个分隔符分割字符串，支持灵活参数控制。

    Args:
        s (str): 待分割的字符串。
        seps (str | List[str] | None): 分隔符字符串或分隔符列表。
            - None: 默认使用逗号、分号、冒号和任意空白符。
            - str: 单个分隔符或正则表达式。
            - List[str]: 多个分隔符，将自动组合为正则表达式。
        ignore_empty (bool): 是否忽略分割后得到的空字符串，默认True。
        strip_items (bool): 是否去除每个分割项的首尾空白，默认True。
        case_sensitive (bool): 分隔符是否区分大小写，默认True。

    Returns:
        List[str]: 分割后的字符串列表。

    Examples:
        >>> split_multi("a, b; c :d   e")
        ['a', 'b', 'c', 'd', 'e']

        >>> split_multi("a|b|c", seps="|")
        ['a', 'b', 'c']


        >>> split_multi("a, b; c :d   e", seps=[",", ";", ":"," "], ignore_empty=True)
        ['a', 'b', 'c', 'd', 'e']

        >>> split_multi("a, b; c :d   e", seps=[",", ";", ":"," "], ignore_empty=False)
        ['a', '', 'b', '', 'c', '', 'd', '', '', 'e']

        >>> split_multi("a,,b", seps=",", ignore_empty=False)
        ['a', '', 'b']

        >>> split_multi("A,B,a", seps="a", case_sensitive=False)
        ['','B,','']

    """
    if seps is None:
        # 默认分隔符：逗号、分号、冒号、任意空白符
        pattern = r"[,\s;:]+"
    elif isinstance(seps, str):
        pattern = seps if len(seps) > 1 and seps.startswith("[") else re.escape(seps)
    elif isinstance(seps, list):
        pattern = "|".join(re.escape(sep) for sep in seps)
    else:
        raise ValueError("seps 参数必须为 None、str 或 List[str]")

    flags = 0 if case_sensitive else re.IGNORECASE
    items = re.split(pattern, s, flags=flags)
    if strip_items:
        items = [item.strip() for item in items]
    if ignore_empty:
        items = [item for item in items if item]
    return items


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


def set_image_extension(
    series: Series,
    default_image_format=".webp",
    supported_image_formats=SUPPORT_IMAGE_FORMATS_NAME,
):
    """
    批量设置图片字段列的图片格式
    如果image字段列中的文件名字符串以常见的图片格式结尾,则丢弃后缀仅保留文件名,否则认为这个字符串不带格式扩展名,保留原样

    此函数针对于文件名中包含`.`但是后面跟随的并不是文件格式(尤其是图片的判断)的情况
    例如某个图片的文件名是`123.fieldskeepit`,这时候如果直接用`os.path.splitext`这种方法会将`fieldskeepit`作为文件格式,然而这不是一个格式名字(扩展名)
    针对图片文件,许多图片没有给出文件格式,这时候使用此函数可以将大部分情况做正确的处理得到不带格式的图片名(这依赖于supported_image_formats的配置的完善程度)

    通过指定默认格式,可以为图片文件指定一个默认格式(现在的图片软件和浏览器基本都能够自动识别图片真实格式并渲染,因此后缀名和图片实际编码格式对不上往往不影响显示),这对于某些业务是很有用的,简单有效

    :param series: 图片字段列
    :param default_image_format: 默认图片格式(例如'.webp',注意`.`号)
    :param supported_image_formats: 支持的图片格式列表
    :return: 处理后的图片字段列series对象

    """

    res = (
        series.astype(str).apply(get_image_filebasename(supported_image_formats))
        + f"{default_image_format}"
    )

    return res


def get_image_filebasename(supported_image_formats=SUPPORT_IMAGE_FORMATS_NAME):
    """得到不带格式的图片名
    这依赖于supported_image_formats的配置的完善程度

    :param supported_image_formats: 支持的图片格式列表
    :return: 用来计算不带格式扩展名图片名的lambda函数,其参数必须是字符串,否则抛出异常(比如x是个浮点数,就会因为没有split方法报错)

    Examples:
        >>> get_image_filebasename()('abc.jpg')
        'abc'
        >>> get_image_filebasename()('abc.xxx')
        'abc.xxx'
        >>> get_image_filebasename(['png', 'jpg'])('abc.png')
        'abc'
        >>> get_image_filebasename(['png', 'jpg'])('abc.png.jpg')
        'abc.png'
    """

    return lambda x: (
        x.rsplit(".", 1)[0] if x.split(".")[-1] in supported_image_formats else x
    )


def get_filebasename_from_url(url):
    """从URL中提取文件名(basename with extension)
    Args:
        url: 要被解析的URL或文件路径
    例如: https://www.example.com/file.txt -> file.txt

    http://shopunitedgoods.com/ddcks%252000013__22568.1681078784.386.513.webp

    """
    parsed_url = urlparse(url)
    path = unquote(parsed_url.path)
    filename = os.path.basename(path)
    return filename


def complete_image_file_extension(
    file,
    default_extension="",
    supported_image_formats_name=SUPPORT_IMAGE_FORMATS_NAME,
    force_default_fmt=False,
):
    """补全文件名字符串的图片格式扩展名
    如果文件本身有扩展名,则不做处理
    如果文件本身没有扩展名,且指定了默认扩展名,否则为其配置指定的扩展名

    Args:
        file: 文件名字符串
        default_extension: 默认扩展名
        supported_image_formats: 支持的图片格式列表

    Examples:
        >>> complete_image_file_extension("abc")
        'abc'
        >>> complete_image_file_extension("abc.png")
        'abc.png'
        >>> complete_image_file_extension("abc.jpg",default_extension=".webp")
        'abc.jpg'
        >>> complete_image_file_extension("abc.jpg",default_extension=".webp",force_fmt=True)
        'abc.webp'
        >>> complete_image_file_extension("abcjpg",default_extension=".webp")
        'abcjpg.webp'

    """
    supported_image_formats = tuple(("." + f for f in supported_image_formats_name))
    if file.endswith(supported_image_formats) and not force_default_fmt:
        return file
    else:
        return (
            get_image_filebasename(supported_image_formats_name)(file)
            + default_extension
        )


def extract_secondary_domain(url):
    """
    根据提供的url,或者域名,提取二级域名

    Args:
        url (str): 待处理的URL或域名

    Returns:
        str: 提取的二级域名，如果提取失败则返回空字符串

    Raises:
        None

    Example:
        >>> extract_secondary_domain('https://www.example.com/path/to/page.html')
        'example.com'
        >>> extract_secondary_domain('https://www.example.co.uk/')
        'co.uk'
        >>> extract_secondary_domain('https://www.example.com')
        'example.com'
    """
    url = str(url).strip().lower()
    if not url:
        return ""
    if not url.startswith(("http://", "https://")):
        url = "https://" + url
    try:
        parsed = urlparse(url)
        domain = parsed.netloc
    except Exception:
        return ""
    parts = [p for p in domain.split(".") if p]
    if len(parts) >= 2:
        return ".".join(parts[-2:])
    return domain


def find_existing_x_directory(dir_roots, dir_base):
    """
    返回第一个存在的目录
    """

    for root in dir_roots:
        path = f"{root }/{dir_base}"
        if os.path.exists(path):
            return path
    return None


# 日志消息队列
log_queue = queue.Queue()
# 分类缓存锁categories_cache_lock
cat_lock = threading.Lock()
# 使用时间会影响日志输出的性能(比没有时间或者直接print要慢得多,在大量打印的情况下会拖累速度)

LOG_HEADER = ["SKU", "Name", "id", "Status", "message", "datetime"]


# 统计处理后的各个csv文件分别有多少条数据
def count_lines_csv(csv_dir):
    """统计csv的数据行数"""
    total = 0
    for file in os.listdir(csv_dir):
        if not file.endswith(".csv"):
            continue
        file = os.path.join(csv_dir, file)
        df = pd.read_csv(file)
        total += len(df)
        print(file, len(df))

    return total


def get_data_from_csv(args, lines, reader, url_field, name_field):
    """
    读取的csv文件中的图片名字和图片链接

    Args:
        args: 命令行参数
        lines: 图片数据列表,存储解析出来的结果(url或name+url)
        reader: csv文件读取器
        url_field: 图片链接所在的列名
        name_field: 图片名字所在的列名
    """
    for line in reader:
        debug("Processing line: %s", line)
        img_names = line.get(name_field, "")
        img_urls = line.get(url_field, "")
        # 将处理结果保存到img_names和img_urls中
        get_data_line_name_url_from_csv(
            args=args, lines=lines, img_names=img_names, img_urls=img_urls
        )


def get_data_line_name_url_from_csv(args, lines, img_names, img_urls):
    """
    将读取的csv文件中的图片名字和图片链接,处理单行

    Args:
        args: 命令行参数
        lines: 图片数据列表,存储解析出来的结果(name,url)
        img_names: 图片名字
        img_urls: 图片链接
    """
    # 为了兼容旧的表格规范,这里要计算一下img_urls字段取值
    # img_urls = img_urls or img_names
    line_info = f"[[{img_names}] and [{img_urls}]]"
    if not img_urls:
        if img_names:
            img_urls = img_names
            img_names = ""
        else:
            error(f"img_urls and img_names are both empty, skip this line: {lines}")

    debug(f"Get data: {line_info}")

    if img_urls:
        # img_names = img_names.split(",")
        # img_urls = img_urls.split(",")

        # img_names = COMMON_SEP_REGEXP.split(img_names)
        img_names = URL_SEP_REGEXP.split(img_names)
        img_urls = split_urls(img_urls)
    if args.name_url_pairs:
        for img_name, img_url in zip(img_names, img_urls):
            img_name = img_name.strip()
            img_url = img_url.strip()
            lines.append(
                # {
                #     "img_name": img_name,
                #     "img_url": img_url,
                # }
                (img_name, img_url)
            )
    else:
        info("url only:[%s]", img_urls)
        lines.extend(img_urls)


def split_urls(urls):
    """将url构成的字符串解析成一个个url字符串构成的列表

    编写合适的正则表达式来提取url
    1. 匹配以http://或https://开头的URL
    2. 考虑url间的分隔串,如',','>',空白字符等
    :param urls: 要被解析的URL字符串
    例如输入
    :return: 解析后的URL列表

    多个url构成的长串处理例子

    """
    matches = re.findall(HTTP_S_URL_CONS_PATTERN, urls)
    return matches


def parse_dbs_from_str(dbs_str):
    """解析数据库文件路径字符串,返回一个列表

    :param dbs_str: 数据库文件路径字符串(一般建议使用r-string),支持逗号分隔,换行分隔,分号分隔
    例如输入
    :return: 数据库文件路径列表
    返回内容示例
    ['C:\\火车采集器V10.27\\Data\\a\\SpiderResult.db3',
    'C:\\火车采集器V10.27\\Data\\b\\SpiderResult.db3',
    'C:\\火车采集器V10.27\\Data\\c\\SpiderResult.db3',
    '...',
    'C:\\火车采集器V10.27\\Data\\z\\SpiderResult.db3']
    """
    dbs = dbs_str.replace("\n", ",").replace(";", ",").split(",")
    dbs = [db for db in dbs if db.strip() != ""]
    return dbs


def remove_sensitive_info(text, try_remove_phone=False):
    """移除文本中的敏感信息，如邮箱地址、网址
    (电话号码容易误伤,默认不过滤)

    可以使用regex101 (for python)进行在线测试

    1. 在HTTP和HTTPS URL中，允许出现的字符包括但不限于字母（a-z, A-Z）、数字（0-9）、特殊字符（如-, _, ., ~）、以及URL编码后的一些字符（如%20表示空格）。
    为了保守地过滤掉一段文本中的HTTPS链接，可以使用正则表达式来匹配URL的结构，但尽量减少误伤其他文本。


    """
    # 移除邮箱地址
    text = re.sub(EMAIL_PATTERN, "", text)

    # [保守]地移除HTTP(S)链接
    text = re.sub(HTTP_S_URL_CONS_PATTERN, "", text)

    # 移除纯域名
    text = re.sub(r"\b(?:www\.)?[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:/[^\s]*)?", "", text)

    # 移除欧美电话号码(容易误杀,不建议用,电话号码留着问题也不大)
    if try_remove_phone:
        text = re.sub(
            r"\b(?:\+?\d{1,3}[-.\s]?)?(?:\(?\d{2,4}\)?[-.\s]?)?\d{3,4}[-.\s]?\d{4}\b",
            "",
            text,
        )

    return text


def check_iterable(it):
    """逐行打印可迭代对象
    检查参数it是否为可迭代对象,如果是,则逐行打印每个元素
    否则,打印it本身,并报告其类型是不可迭代的
    例如一行一个字典
    """
    if hasattr(it, "__iter__"):
        print(f"total {len(it)} items.")
        if len(it):
            for i, item in enumerate(it, 1):
                # 将这些不规范的产品带序号地列出来
                print(f"row {i}: {item}")
    else:
        error(f"[{it}] is not iterable.(or empty result)")


def download_img_to_local(img_url, product_sku):
    """
    下载远程图片并保存到本地
    :param url: 图片的URL
    :param product_sku: 产品的SKU，用于命名本地图片
    :return: 本地图片路径
    """
    local_filename = f"{product_sku}.jpg"
    with requests.get(img_url, stream=True, timeout=10) as r:
        r.raise_for_status()
        with open(local_filename, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)
    return local_filename


def split_list(lst, n):
    """将可迭代容器(例如列表)平均分为n份,返回分割后的列表
    尽可能的平均分配比较好,如果前n-1份数量相同,且
    将余数元素都放到最后一份可能会导致最后一份元素过多(最坏情况下是平均份的近两倍)
    方案1:推荐
    设你要均分为n份,每份的基本大小为size=len(lst)//n,余数为r=len(lst)%n,且一定有(r<n)
    那么前r份每份含有size+1个元素，后n-r份每份含有size个元素
    此方案可以保证,任意两份所分得的元素数量差不会超过1
    如果n大于lst的元素数量,那么前len(lst)份每份含有1个元素,后n-len(lst)份每份含有0个元素(空列表)

    方案2:不推荐
    如果容器中元素长度为L=len(lst),k为L/n的余数,则将最后k个元素归入最后一份

    Parameters
    ----------
    lst : list
        需要被分割的容器列表
    n : int
        需要被分割的份数(平均)

    Returns
    -------
    list
        分割后的列表的列表
    Examples
    --------
    split_list(list(range(1,11)), 4)


    """
    result = []
    size, r = divmod(len(lst), n)
    info(f"size: {size}, r: {r}")

    size_r = size + 1
    for i in range(r):
        start = i * size_r
        end = (i + 1) * size_r
        result.append(lst[start:end])
    start = (size + 1) * r

    for i in range(r, n):
        end = start + size
        result.append(lst[start:end])
        start = end

    return result


def log_worker(log_file="./"):
    """后台日志记录线程
    利用循环不断尝试从全局日志队列中获取日志条目,然后写入到日志文件中
    log_header 参考:["Timestamp", "RecordID", "Status", "Details", "ProcessingTime"]

    """
    info(f"Log worker started.logs will be written to: {log_file}🎈")
    while True:
        log_entry = log_queue.get()
        debug(f"Log worker got log entry: {log_entry}")
        if log_entry is None:  # 终止信号
            break
        try:
            # 检查路径(目录)存在,若不存在则创建
            log_dir = os.path.dirname(log_file)
            if not os.path.exists(log_dir):
                os.makedirs(log_dir)
            # 写入日志文件
            with open(log_file, "a", newline="", encoding="utf-8") as f:

                writer = csv.writer(f)
                # 如果文件为空，写入标题行
                if f.tell() == 0:
                    writer.writerow(LOG_HEADER)
                writer.writerow(log_entry)
        except Exception as e:
            error(f"Error:Log write failed: {e}")
        finally:
            log_queue.task_done()


def log_upload(sku, name, product_id, status, msg=""):
    """将日志加入到日志消息队列中
    表头结构由常量LOG_HEADER定义,元素顺序与LOG_HEADER一致,或者使用关键字参数传参
    """
    log_entry = [
        sku,
        name,
        product_id,
        status,
        msg,
        datetime.now().isoformat(),
    ]
    log_queue.put(log_entry)
    debug(f"Log preview:{log_entry}")
    return log_entry


def cleanup_log_thread(q_thread):
    """清理函数，等待队列处理完成并停止工作线程"""
    log_queue.join()  # 等待所有日志项处理完成
    log_queue.put(None)  # 发送终止信号
    q_thread.join()  # 等待线程结束
    info("log_thread(daemon) end.")


##
