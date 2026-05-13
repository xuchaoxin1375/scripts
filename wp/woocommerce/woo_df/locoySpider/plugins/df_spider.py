"""
# -*- encoding: utf-8 -*-
@File    :   df_Spider.py
@Time    :   2026/01/14
@Author  :   cxxu1375
@Version :   2.0
@License :   (C)Copyright df

Returns
-------
None
    直接修改采集器中已有的标签,不需要返回值


"""

import sys
from enum import Enum
from urllib import parse
import json
import re


class LabelEnum(str, Enum):
    """定义标签枚举类

    采集器模板中定义的固定标签组,和其他可能用到的标签

    """

    DESCRIPTION = "产品描述"
    NAME = "产品名称"
    BRAND = "品牌"
    IMAGE = "产品图片"
    BREADCRUMB = "产品面包屑"
    MODEL = "产品型号"
    PRICE = "产品价格"
    ATTRIBUTE_VALUE1 = "属性值1"
    ATTRIBUTE_NAMES = "属性名集合"
    ATTRIBUTE_OPTIONS = "属性选项集合"
    ATTRIBUTE_NAMES_JSON = "属性名集合json排列组合"
    ATTRIBUTE_OPTIONS_JSON = "属性选项集合json排列组合"
    ATTRIBUTE_MODE = "属性值模式"
    # 其他辅助标签
    LOG = "log"
    HTML = "Html"
    SETTING_JSON = "setting_json"
    # shopify相关标签
    SHOPIFY_JSON = "shopify_json"
    SHOPIFY_ATTRIBUTE_NAMES = "shopify_attr_names"
    SHOPIFY_ATTRIBUTE_OPTIONS = "shopify_attr_options"
    SHOPIFY_DESCRIPTION_BASIC = "shopify_description"
    SHOPIFY_USE_DESCRIPTION = "shopify_use_description"
    SHOPIFY_NAME = "shopify_name"
    SHOPIFY_PRICE = "shopify_price"
    SHOPIFY_IMAGE = "shopify_image"
    SHOPIFY_BREADCRUMB = (
        "shopify_product_type"  # "product_type" or "category" or "collection"
    )


# 定义常量以便于维护和理解
## 控制属性值数量,避免过长(每个属性选项的数量不超过20,否则容易造成wordpress数据显示问题)
MAX_SUB_OPTIONS = 20
NAME = (
    LabelEnum.NAME
)  # 此表达式结果是一个枚举类型的对象而不是字符串,使用.name或.value获取对应名字或值字符串
DESCRIPTION = LabelEnum.DESCRIPTION
BRAND = LabelEnum.BRAND
BREADCRUMB = LabelEnum.BREADCRUMB
IMAGE = LabelEnum.IMAGE
MODEL = LabelEnum.MODEL
SETTING_JSON = LabelEnum.SETTING_JSON
PRICE = LabelEnum.PRICE

ATTRIBUTE_VALUE1 = LabelEnum.ATTRIBUTE_VALUE1
ATTRIBUTE_NAMES_JSON = LabelEnum.ATTRIBUTE_NAMES_JSON
ATTRIBUTE_NAMES = LabelEnum.ATTRIBUTE_NAMES
ATTRIBUTE_OPTIONS = LabelEnum.ATTRIBUTE_OPTIONS

ATTRIBUTE_NAMES_JSONMODE = LabelEnum.ATTRIBUTE_NAMES_JSON
ATTRIBUTE_OPTIONS_JSONMODE = LabelEnum.ATTRIBUTE_OPTIONS_JSON

ATTRIBUTE_VALUE = LabelEnum.ATTRIBUTE_VALUE1
ATTRIBUTE_MODE = LabelEnum.ATTRIBUTE_MODE


SHOPIFY_JSON = LabelEnum.SHOPIFY_JSON
SHOPIFY_ATTRIBUTE_NAMES = LabelEnum.SHOPIFY_ATTRIBUTE_NAMES
SHOPIFY_ATTRIBUTE_OPTIONS = LabelEnum.SHOPIFY_ATTRIBUTE_OPTIONS
SHOPIFY_DESCRIPTION_BASIC = LabelEnum.SHOPIFY_DESCRIPTION_BASIC
SHOPIFY_USE_DESCRIPTION = LabelEnum.SHOPIFY_USE_DESCRIPTION
SHOPIFY_BREADCRUMB = LabelEnum.SHOPIFY_BREADCRUMB
SHOPIFY_NAME = LabelEnum.SHOPIFY_NAME
SHOPIFY_PRICE = LabelEnum.SHOPIFY_PRICE
SHOPIFY_IMAGE = LabelEnum.SHOPIFY_IMAGE


LOG = LabelEnum.LOG
LOG_SEPARATOR = "\r\n" * 2  # 日志输出分隔符(windows下换行符为\r\n)
# 定义采集模板中哪些标签是必须的,它们是插件主要针对处理的模板变量
required_labels = [
    NAME,
    PRICE,
    DESCRIPTION,
    IMAGE,
    BREADCRUMB,
    MODEL,
    BRAND,
    ATTRIBUTE_VALUE1,
]



# 定义需要移除货币符号的标签
no_currency_symbols_labels = [
    PRICE,
    ATTRIBUTE_VALUE1,
    DESCRIPTION
]


# 定义需要移除的字符
chars_to_remove = [r"\n", r"\r"]

# 属性值中需要替换或翻译的的符号(尤其是英文逗号,会引起解析问题,需要替换为其他长得像的符号,比如: [ ‚   ])
attri_chars_translate_dict = {",": "‚", ":": " ", ";": "；"}

remove_specified_char_labels = [DESCRIPTION]
remove_css_labels = [DESCRIPTION]
# 属性值json模式中的正则🎈
# &&&k1:v(11),k2,v(12),k3:v(13)&&&,...,&&&k1:v(n1),k2,v(n2),k3:v(n3)...&&& ->set1,set2,set3,...
PATTERN_KEY_VALUE = r'".*?":"(.*?)"'
# pat_value = r"(.*?)"


class StrList(list):
    """字符串偏好的列表,增加一个方法便于添加日志输出
    增加一个开关用来配合判断是否处理日志输出
    也可以考虑用python的猴子补丁直接给list添加方法"""

    def __init__(self, log_switcher=False):
        super().__init__()
        self.log_switcher = log_switcher

    def add_as_str(self, obj):
        """
        将给定的参数转换为字符串并添加到列表中。

        只在需要的时候启用调试功能,避免采集任务时产生额外的开销;通过变量switcher来判断是否启用日志处理

        参数:
        obj: 要添加到列表中的元素，可以是任何类型，将被转换为字符串。

        返回:
        无返回值。此方法直接修改调用它的列表对象。
        """
        # 将输入参数转换为字符串，并通过append方法添加到列表中
        if self.log_switcher:
            self.append(str(obj))


log = StrList(log_switcher=False)


def remove_empty_html_tags(html: str, tags=None) -> str:
    """
    移除 HTML 中无内容的标签（如 <span></span> 或仅包含空白字符的标签对）。
    可指定要处理的标签类型，默认处理所有标签。

    相比于采集器中枚举标签替换,或者C#

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


def parse_json(json_str):
    """
    带异常捕获的解析JSON数据,将其转换为Python字典对象。

    参数:
        json_str (str): 包含Shopify JSON数据的字符串。

    返回:
        dict: 解析后的Python字典对象。
    """
    try:
        return json.loads(json_str)
    except json.JSONDecodeError as e:
        log.add_as_str(f"JSON解析错误:{'='*10} {e} {'='*10}")
        return {}
    except Exception as e:
        log.add_as_str(f"JSON解析错误: {'='*10} {e} {'='*10}")
        return {}


# 模板自带的代码段
def char_process():
    """处理字符

    这里定义了若干段文本字符串处理流程,通过配置相应的标签数组,可以灵活指定哪些标签的数据需要经过对应步骤的处理

    ---
    str.makestrans和translate方法无法将超过一个字符的字符串(key)替换代为另一个串(value)

    ValueError: string keys in translate table must be of length 1

    下面的朴素代码需要提高性能
    label_dict[label] = value.replace("\\n", " ").replace("\\r", " ")
    或
    for chars in chars_to_remove:
        label_dict[label] = label_dict[label].replace(chars, " ")

    使用考虑正则来替换

    """


    for label in remove_specified_char_labels:
        value = label_dict.get(label)
        if value:
            # 使用 str.translate 方法来替换多个字符，性能更好;先构造替换表(字典),然后调用traslate方法替换
            regex = "|".join(map(re.escape, chars_to_remove))  # 构造安全的正则表达式
            log.add_as_str(regex)
            label_dict[label] = re.sub(regex, " ", value)




def is_matrix(lst):
    """判断输入是否为一个矩阵(每行的元素个数相同)"""
    if not lst:  # 检查是否为空
        return False
    if not isinstance(lst, list):  # 确保 lst 是列表
        return False
    row_length = len(lst[0])  # 获取第一行的长度
    return all(isinstance(row, list) and len(row) == row_length for row in lst)


def attri_value_process_json_permutation(pat_json):
    """处理属性值(商品套餐选项)
    启用了Json模式的情况下
    这里处理属性值排列组合(permutation and combination)存在于json中的情况

    其他较简单情况不必用此函数,可以在采集器中直接处理

    """
    options = []
    if label_dict.get(ATTRIBUTE_MODE, 0):
        log.add_as_str("开始处理属性值(json Mode)...")
        # 针对 key-value 形式的json数据进行处理

        p = re.compile(pattern=pat_json)
        items = label_dict.get(ATTRIBUTE_OPTIONS_JSONMODE)
        if items:
            log.add_as_str("属性值(json)不为空,开始处理...")
            items = p.sub(repl=r"\1", string=items)
            options = re.findall("&&&(.*?)&&&", items)
            log.add_as_str(options)

            options = [option.split(",") for option in options]

            log.add_as_str(options)
            if is_matrix(options):
                matrix = options
                unique_columns = [dict.fromkeys(column) for column in zip(*matrix)]
                options = []
                for i, col in enumerate(unique_columns):
                    if log.log_switcher:
                        log.add_as_str(f"第{i+1}组属性选项取值集合:{col}")
                    options.append("|".join(col))
                options = "~>".join(options)

                log.add_as_str(options)

            else:
                log.add_as_str("属性选项长度没有对齐,停止此部分处理!")
    return str(options)


# def contains_tld(product_name: str) -> bool:
#     """
#     判断给定的产品名称中是否包含常见的顶级域名（如 .com, .de, .fr 等）。

#     参数:
#         product_name (str): 产品名称。

#     返回:
#         bool: 如果包含顶级域名则返回 True，否则返回 False。
#     """
#     tld_pattern = r"\.(com|shop|de|fr|es|it|us|uk)\b"
#     return bool(re.search(tld_pattern, product_name, re.IGNORECASE))


# def check_product_name():
#     """检查产品名称中是否包含顶级域名,并提示用户注意处理"""
#     product_name = label_dict.get(NAME, "")
#     if contains_tld(product_name):
#         msg = f"! {product_name}"
#         log.add_as_str(msg)
#         label_dict[NAME] = msg


def process_shopify():
    """处理Shopify json数据,简化shopify采集
    重点采集对象:属性值
    顺带处理产品描述

    """
    sj = label_dict.get(SHOPIFY_JSON)
    if not sj:
        log.add_as_str("shopify_json数据为空,停止此部分处理!!!")
        return "", ""
    # json初步处理
    # #移除Default Title字符串,防止不该出现属性值的情况带上多余的默认标题
    sj = sj.replace("Default Title", "").replace("null", '""')
    sd = parse_json(sj)
    # debug
    log.add_as_str(f"采集器传入的shopify_json数据:\n{sd}")
    # log.add_as_str(f"采集器传入的shopify_json数据: {sd.get('product').get("options")}")
    product = sd.get("product", {})  # .get("options") # type: ignore
    variants = product.get("variants", [{}])
    options = product.get("options", [])
    description: str = product.get("body_html", "")
    # 第一部分
    if label_dict.get(SHOPIFY_USE_DESCRIPTION):
        log.add_as_str("使用shopify_json中的产品描述等字段")
        label_dict[DESCRIPTION] = description
        label_dict[SHOPIFY_DESCRIPTION_BASIC] = "内容被重定向到'产品描述'标签中"
        # 使用shopify_json中的产品名称,价格,品牌等
        label_dict[SHOPIFY_NAME] = product.get("title", "")
        label_dict[SHOPIFY_PRICE] = variants[0].get("price", 0)
        label_dict[SHOPIFY_BREADCRUMB] = product.get("product_type", "")

        label_dict[NAME] = product.get("title", "")
        label_dict[PRICE] = variants[0].get("price", 0)
        label_dict[BRAND] = product.get("vendor", "")
        label_dict[MODEL] = product.get("sku", "")

    # 第二部分

    # 面包屑(分类),在shopify中不一定总是非空值,也可能是空串
    # breadcrumbs = product.get(BREADCRUMB, "")
    shopify_breadcrumbs = product.get("product_type", "")
    log.add_as_str(f"shopify_breadcrumbs:[{shopify_breadcrumbs}]")
    log.add_as_str(f"shopify_description:[{description}]")
    # if not breadcrumbs and shopify_breadcrumbs:
    # if shopify_breadcrumbs:
    #     # shopify中的分类有先(通常比较准确)
    #     label_dict[BREADCRUMB] = shopify_breadcrumbs

    # 属性值
    names = []
    option_values = []
    if options:
        # log.add_as_str(f"采集器传入的shopify_json数据: {options}")
        for option in options:
            # pass
            # 处理属性名集合
            if option.get("name"):
                log.add_as_str(f"处理属性名: {option.get('name')}")
                names.append(option.get("name") + "#>")
            # 处理属性选项集合
            if option.get("values"):
                option_values.append("|".join(option.get("values")[:MAX_SUB_OPTIONS]))
    # label_dict[LabelEnum.SHOPIFY_ATTRIBUTE_NAMES.value]=
    label_dict[SHOPIFY_ATTRIBUTE_NAMES] = "".join(names)
    label_dict[SHOPIFY_ATTRIBUTE_OPTIONS] = "~>".join(option_values)
    # label_dict[SHOPIFY_DESCRIPTION_BASIC] = description

    return (
        label_dict[SHOPIFY_ATTRIBUTE_NAMES],
        label_dict[SHOPIFY_ATTRIBUTE_OPTIONS],
        # label_dict[SHOPIFY_DESCRIPTION_BASIC],
    )


def attri_value_process_tag(attr_names: str, attr_options: str):
    """处理属性值(商品套餐选项)

    针对html标签模式(默认)

    将形如 size#>color# 的值处理为["size#", "color#"]
    将形如 40|41|42~>red|blue|black 处理为['40|41|42', 'red|blue|black']

    最后将属性名和属性值合并为形如 size#40|41|42~>color#red|blue|black 的字符串

    param: attr_names: 属性名称
    param: attr_options: 属性选项
    return: 处理后的属性值



    """
    log.add_as_str("开始处理属性值...")
    log.add_as_str(
        f"attr_names: {type(attr_names)}, attr_options: {type(attr_options)}"
    )
    # 初步处理集合
    attr_options = re.sub(r"\|[\|\s]+", "|", attr_options)
    attr_options = attr_options.replace("|~", "~")
    attr_options = attr_options.replace(">|", ">").strip("|")

    log.add_as_str(f"🎈🎈🎈🎈 attr_options: {attr_options}🎈🎈🎈🎈")

    check_matches = attr_names and attr_options  # 是否继续处理

    if check_matches:
        log.add_as_str(ATTRIBUTE_NAMES + " and " + ATTRIBUTE_OPTIONS + "均不为空")
    else:
        log.add_as_str(
            ATTRIBUTE_NAMES + " and " + ATTRIBUTE_OPTIONS + "至少一个为空,不继续处理!"
        )
        log.add_as_str(f"属性名: {attr_names}\n属性选项: {attr_options}")
        # 停止执行后续处理
        return
    # 处理属性名
    if attr_names:
        attribute_names_lst = attr_names.split(">")
        log.add_as_str(attribute_names_lst)

        log.add_as_str(
            f"attribute_names_lst: {type(attribute_names_lst)};len: {len(attribute_names_lst)}"
        )
    # 处理属性值
    if attr_options:
        attribute_options_lst = attr_options.split("~>")
        processed_options = []
        for sub_options in attribute_options_lst:
            log.add_as_str(f"sub_options: {sub_options}")
            sub_options = sub_options.replace("~", "")

            lst = sub_options.split("|")[:MAX_SUB_OPTIONS]
            unique_lst = list(dict.fromkeys(lst))

            log.add_as_str(lst)
            log.add_as_str(unique_lst)
            processed_options.append("|".join(unique_lst))

        attribute_options_lst = processed_options

        log.add_as_str(attribute_options_lst)
        log.add_as_str(
            f"attribute_options_lst: {type(attribute_options_lst)};\
                len: {len(attribute_options_lst)}"
        )

    matched_length = min(len(attribute_names_lst), len(attribute_options_lst))
    log.add_as_str(f"属性名和属性选项匹配数量: {matched_length}")

    if matched_length:
        attribute_names_lst = attribute_names_lst[:matched_length]
        attribute_options_lst = attribute_options_lst[:matched_length]

        log.add_as_str("去除重复属性名")
        attribute_names_lst = list(dict.fromkeys(attribute_names_lst))

        log.add_as_str(attribute_names_lst)
        log.add_as_str(attribute_options_lst)
        # 合并属性名和属性选项
        merged_list = [
            f"{name}{option}"
            for name, option in zip(attribute_names_lst, attribute_options_lst)
        ]
        value = "~".join(merged_list).rstrip("~")
        value = re.sub(r"\s+", " ", value)
        value = value.replace("~", "~   ").replace("#|", "#")
        value = re.sub(r"~[^~]*?#~", "~", value)
        value = re.sub(r"[#\s]+#", "#", value)
        # 处理属性值中不应该出现的字符
        translation_table = str.maketrans(attri_chars_translate_dict)
        value = value.translate(translation_table)
        log.add_as_str(value)

        label_dict[ATTRIBUTE_VALUE] = value
    else:
        log.add_as_str("属性名和属性选项(数量)匹配失败!")
    # 消息反馈(插件处理好属性值后,将中间过程填写到普通标签中便于观察处理过程)
    label_dict[ATTRIBUTE_NAMES] = f"{attr_names} \t\t-> {str(attribute_names_lst)}"
    label_dict[ATTRIBUTE_OPTIONS] = (
        f"{attr_options} \t\t-> {str(attribute_options_lst)}"
    )


def attri_value_process():
    """处理属性值(商品套餐选项)
    默认采用标签模式
    """
    attr_names = ""
    attr_options = ""
    # description = ""
    log.add_as_str("查看当前相关标签的取值")

    if label_dict.get(ATTRIBUTE_MODE):
        log.add_as_str("启用json模式")

        label_dict[ATTRIBUTE_MODE] += "(JsonMode为非空值,你启用了Json模式)"
        attr_names = label_dict.get(ATTRIBUTE_NAMES_JSONMODE, "")
        attr_options = attri_value_process_json_permutation(pat_json=PATTERN_KEY_VALUE)
    elif label_dict.get(SHOPIFY_JSON):
        log.add_as_str("启用shopify模式")
        # 处理shopify json数据

        attr_names, attr_options = process_shopify()
        # log.add_as_str(f"shopify_description: {description}")

        if not attr_names or not attr_options:
            log.add_as_str("shopify模式下属性名或属性选项为空,不继续处理!")
            # return
    else:
        log.add_as_str("启用标签模式")

        attr_names = label_dict.get(ATTRIBUTE_NAMES, "")
        attr_options = label_dict.get(ATTRIBUTE_OPTIONS, "")

    log.add_as_str(f"attrnames: {type(attr_names)}, attr_options: {type(attr_options)}")
    # if(label_dict.get())
    attri_value_process_tag(attr_names, attr_options)
    # 将shopify_json标签内容清理节约磁盘空间
    label_dict[SHOPIFY_JSON] = "yes"


def flash_log():
    """刷新日志log内容到采集器日志标签中"""
    if log:
        label_dict[LOG] = LOG_SEPARATOR.join(log)


# 采集器python插件的模板内容---------------------------------


if len(sys.argv) != 5:
    print(len(sys.argv))
    print("命令行参数长度不为5")
    sys.exit()
else:
    LabelCookie = parse.unquote(sys.argv[1])
    LabelUrl = parse.unquote(sys.argv[2])
    PageType = sys.argv[3]
    SerializerStr = parse.unquote(sys.argv[4])
    if SerializerStr[0:2] != '''{"''':
        file_object = open(SerializerStr, encoding="utf-8")
        try:
            SerializerStr = file_object.read()
            SerializerStr = parse.unquote(SerializerStr)
        finally:
            file_object.close()
    # 采集器中采集规则定义的各个标签数据字典🎈
    label_dict: dict = json.loads(SerializerStr)
    # 读取配置标签
    setting = label_dict.get(SETTING_JSON, '{"shopify_use_description": 0}')
    # setting = json.loads(setting)
    setting = parse_json(setting)
    # 设置相关的开关值

    label_dict[SHOPIFY_USE_DESCRIPTION] = setting.get(SHOPIFY_USE_DESCRIPTION, 0)
    # label_dict[ATTRIBUTE_MODE] = setting.get(ATTRIBUTE_MODE, 0) #0表示普通模式,1表示json模式提取属性值

    # 用户代码区🎈
    if label_dict.get(LOG) == "":
        log.log_switcher = True
    log.add_as_str(
        "python插件日志:请展开全屏查看完整日志,此仅供调试使用,正式运行规则时,请关闭调试(移除log标签)提高采集效率..."
    )
    log.add_as_str(f"查看采集模板配置: setting_dict: {setting}")
    log.add_as_str(sys.version)
    log.add_as_str(sys.version_info)

    if PageType == "Save":
        # 定义数据处理流程序列
        #check_product_name()
        process_shopify()
        attri_value_process()
        char_process()
        flash_log()
        # pass
    else:
        label_dict[LabelEnum.HTML] = (
            "当前页面的网址为:"
            + LabelUrl
            + "\r\n页面类型为:"
            + PageType
            + "\r\nCookies数据为:"
            + LabelCookie
            + "\r\n接收到的数据是:"
            + label_dict[LabelEnum.HTML]
        )
    # label_dict[LOG]="debug"
    label_dict = json.dumps(label_dict)  # type: ignore
    print(label_dict)
