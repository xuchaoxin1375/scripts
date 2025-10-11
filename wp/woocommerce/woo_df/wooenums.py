"""
WooCommerce 脚本用到的枚举类

db3数据库中的重点字段
1. 产品名称
2. 产品价格
3. 产品图片
4. 产品描述
5. 产品面包屑
6. 品牌
7. 产品型号
8. 属性值1
9. PageUrl

"""

# %%
import random
from enum import Enum


class EnumIt(Enum):
    """增加两个方法的Enum子类,方便列出枚举成员名称和值"""

    @classmethod
    def get_all_fields_value(cls, exclude_field="", extend_fields=None):
        """获取所有字段取值列表

        :param extend_fields: 额外字段列表
        :return: 所有字段取值列表
        """
        # return cls._member_names_
        values = [field.value for field in cls if field.value != exclude_field]
        if isinstance(extend_fields, list):
            values.extend(extend_fields)
        return values

    @classmethod
    def get_all_fields_name(cls, exclude_field="", extend_fields=None):
        """获取所有字段名称列表

        :param extend_fields: 额外字段列表
        :return: 所有字段名称列表
        """
        names = [field.name for field in cls if field.value != exclude_field]
        if isinstance(extend_fields, list):
            names.extend(extend_fields)

        return names


class EnumItRc(EnumIt):
    """基于EnumIt的枚举子类,增加随机返回值的方法"""

    @classmethod
    def get_one_hot_sale_names(cls, language="US"):
        """
        随机获取指定语言下的某个热销名称
        如果指定的语言不存在,会抛出异常,因此要确保你继承此枚举子类的语言枚举类中包含你指定的语言
        :param lang: 语言代码，默认为"US"
        :return: 随机选择的热销名称字符串
        """

        language = cls[language.upper()]
        # 从该语言的列表中随机选择一个热销名称
        return random.choice(language.value)


class ImageMode(EnumIt):
    """图片名字取值模式
    Attributes:
        NAME_FROM_SKU: 根据SKU生成图片名称
        NAME_FROM_URL: 根据图片链接生成图片名称
        NAME_AS_URL: 使用图片链接作为图片名称
        NAME_MIX: SKU+时间戳+产品名称(todo)
    """

    NAME_FROM_SKU = "name_from_sku"
    NAME_FROM_URL = "name_from_url"
    NAME_AS_URL = "name_as_url"
    # NAME_MIX_SKU_URL
    NAME_MIX = "name_mix"


class DBProductFields(EnumIt):
    """产品字段枚举
    每行定义了一个枚举成员,左侧是name,右侧是value
    Attributes:
        NAME: 产品名称
        CATEGORIES: 产品面包屑
        REGULAR_PRICE: 产品价格
        IMAGES: 产品图片
        ATTRIBUTE_VALUES: 属性值1
        TAGS: 品牌
        SKU: 产品型号
        DESCRIPTION: 产品描述
        PAGE_URL: PageUrl
    """

    NAME = "产品名称"
    CATEGORIES = "产品面包屑"
    REGULAR_PRICE = "产品价格"
    IMAGES = "产品图片"
    ATTRIBUTE_VALUES = "属性值1"
    TAGS = "品牌"  # 会被转换为woocommerce中的TAGS(标签)
    SKU = "产品型号"
    DESCRIPTION = "产品描述"
    PAGE_URL = "PageUrl"


class CSVProductFields(EnumIt):
    """产品数据字段枚举
    Attributes:
        SKU: 产品SKU
        NAME: 产品名称
        CATEGORIES: 产品分类
        REGULAR_PRICE: 产品价格
        SALE_PRICE: 产品折扣价格

        IMAGES: 产品图片
        ATTRIBUTE_VALUES: 属性值
        TAGS: 产品标签
        DESCRIPTION: 产品描述
        PAGE_URL: 产品源页面链接

        ATTRIBUTE_NAME: 属性名称
    """

    SKU = "SKU"
    NAME = "Name"
    CATEGORIES = "Categories"
    REGULAR_PRICE = "Regular price"
    SALE_PRICE = "Sale price"

    ATTRIBUTE_VALUES = "Attribute 1 value(s)"
    ATTRIBUTE_NAME = "Attribute 1 name"

    IMAGES = "Images"
    IMAGES_URL = "ImagesUrl"
    TAGS = "Tags"
    PAGE_URL = "PageUrl"
    DESCRIPTION = "Description"

    @classmethod
    def is_img_url_needed(cls, img_mode):
        """判断指定的图片模式是否需要img_URL = "ImagesUrl"字段

        Args:
            img_mode (ImageMode): 图片模式

        Returns:
            bool: 是否需要

        """
        return img_mode in [
            ImageMode.NAME_FROM_SKU,
            ImageMode.NAME_FROM_URL,
            ImageMode.NAME_MIX,
        ]

    @classmethod
    def get_all_fields_name(
        cls, exclude_field="", extend_fields=None, img_mode=ImageMode.NAME_AS_URL
    ):
        """
        根据模式的不同返回不同的CSV字段名称列表
        :param img_mode: 是否让图片字段仅存放图片名称而不是存放链接
            1. `ImageMode.NAME_AS_URL`时,图片相关字段仅有Images,其他情况有Images,ImagesUrl字段;返回12个字段(可能会变更)
            2. `ImageMode.NAME_FROM_SKU`,`ImageMode.NAME_FROM_URL`时,的差别在于,
               Images字段的取值是sku(变体)还是仅取决于url的文件名截取;返回11个字段(可能会变更)
                而`ImageMode.NAME_MIX`时,是SKU+时间戳+产品名称的模式,和前两种类似
        :return: 对应模式下DB-CSV中间字段名称列表,例如["SKU","NAME",...]
        """
        res = []
        if cls.is_img_url_needed(img_mode):
            res = super().get_all_fields_name(
                exclude_field=exclude_field, extend_fields=extend_fields
            )
        else:
            # 不返回ImagesUrl字段,其他字段返回
            img_url = CSVProductFields.IMAGES_URL.name
            res = [field.name for field in cls if field.name not in [img_url]]
        return res

    @classmethod
    def get_all_fields_value(
        cls, exclude_field="", extend_fields=None, img_mode=ImageMode.NAME_AS_URL
    ):
        """根据模式的不同返回不同的CSV字段取值列表

        :param img_mode: 是否将图片是否仅存放图片名称而不是存放链接,参考get_all_fields_name方法的说明
        :return: 对应模式下的CSV字段取值列表,例如["SKU","Name",...]
        """
        res = []
        if cls.is_img_url_needed(img_mode):
            res = super().get_all_fields_value(
                exclude_field=exclude_field, extend_fields=extend_fields
            )
        else:
            img_url = CSVProductFields.IMAGES_URL.name
            res = [field.value for field in cls if field.name not in [img_url]]
        return res


class LanguagesHotSale(EnumItRc):
    """语言枚举
    新品, 热卖, 促销, 限时抢购, 超值, 精选, 今日特价
    """

    US = [
        "New Arrival",
        "Best Sellers",
        "Promotion",
        # "Flash Deal",
        # "Best Value",
        # "Editor's Pick",
        # "Today’s Special",
    ]
    UK = [
        "New In",
        "Best Seller",
        "Special Offer",
        # "Flash Sale",
        # "Great Value",
        # "Top Picks",
        # "Today’s Deal",
    ]
    IT = [
        "Novità",
        "Più venduti",
        "Offerta speciale",
        # "Offerta lampo",
        # "Miglior valore",
        # "Scelti per te",
        # "Offerta del giorno",
    ]
    DE = [
        "Neuheiten",
        "Bestseller",
        "Sonderangebot",
        # "Blitzangebot",
        # "Top Preis",
        # "Empfehlung",
        # "Angebot des Tages",
    ]
    ES = [
        "Novedades",
        "Más vendido",
        "Promoción",
        # "Oferta flash",
        # "Mejor valor",
        # "Selección",
        # "Oferta del día",
    ]
    FR = [
        "Nouveautés",
        "Meilleures ventes",
        "Promotion",
        # "Vente flash",
        # "Bon plan",
        # "Notre sélection",
        # "Offre du jour",
    ]


class UploadMode(Enum):
    """产品上传模式枚举

    Attributes:
        JUMP_IF_EXIST: 创建失败时跳过当前产品（默认模式）
        TRY_CREATE_ONLY: 仅尝试创建新产品，如果产品已存在则不更新
        UPDATE_IF_EXIST: 直接创建失败时尝试用PUT方法更新产品
        RESUME_FROM_DB: 从数据库恢复上传进度
        RESUME_FROM_LOG: 从日志文件恢复上传进度

    模式详细说明：
    1. FLEXIBLE (默认模式)
       - 尝试从log文件恢复进度，如果log文件不存在,则认为是首次上传
       - 是下面的基础模式RESUME_FROM_LOG到TRY_CREATE_ONLY的自动选择模式
    2. JUMP_IF_EXIST
       - 跳过已存在的商品
       - 比TRY_CREATE_ONLY有更好的性能表现
       - 适用场景：常规上传
    3. TRY_CREATE_ONLY
       - 仅创建新商品
       - 遇到SKU冲突时直接跳过
       - 适用场景：首次上传或确定无重复SKU时

    4. UPDATE_IF_EXIST (强制更新)
       - 自动更新已存在的商品
       - 适用场景：需要覆盖更新商品信息时

    5. RESUME_FROM_DB (断点续传)
       - 从WooCommerce数据库读取已上传记录
       - 优点：100%准确
       - 缺点：首次查询较慢

    6. RESUME_FROM_LOG (快速恢复)
       - 从本地日志文件恢复进度
       - 优点：恢复速度极快
       - 要求：必须使用此代码生成的日志文件,指定log日志文件路径
    """

    FLEXIBLE = "flexible"
    JUMP_IF_EXIST = "jump_if_exist"
    TRY_CREATE_ONLY = "try_create_only"
    UPDATE_IF_EXIST = "update_if_exist"
    RESUME_FROM_DATABASE = "resume_from_database"
    RESUME_FROM_LOG_FILE = "resume_from_log_file"


class FetchMode(Enum):
    """产品获取模式枚举

    Attributes:
        FROM_CACHE: 从缓存中获取产品
        FROM_DATABASE: 从数据库中恢复进度
        FROM_LOG_FILE: 从本地日志文件恢复进度
        NO_FETCH: 不获取已上传产品

    """

    FROM_CACHE = "from_cache"
    FROM_DATABASE = "from_database"
    FROM_LOG_FILE = "from_log_file"
    NO_FETCH = "no_fetch"


class ResponseDataFields(Enum):
    """响应数据字段枚举
    Attributes:
        ID: 产品ID
        NAME: 产品名称
        SKU: 产品SKU
        STATUS: 产品状态
        MESSAGE: 错误信息
        TOTAL: 总数
    """

    ID = "id"
    NAME = "name"
    SKU = "sku"
    STATUS = "status"
    MESSAGE = "message"
    TOTAL = "total"


##
