import csv
import os
import re
import sys

csv.field_size_limit(2147483647)
import sqlite3
import time  # 添加time模块
import uuid
from datetime import datetime, timedelta  # 添加timedelta

import phpserialize
import pymysql


class WooCommerceImporter:
    """WooCommerce产品导入器 - 优化版"""

    def __init__(self, mysql_config, wp_upload_dir=None):
        """初始化导入器"""
        self.mysql_config = mysql_config
        self.mysql_conn = None
        self.cursor = None
        self.wp_posts_columns = []
        self.batch_size = 500  # 批量处理的大小
        self.term_cache = {}  # 添加分类缓存

        # 添加站点URL配置
        self.site_url = "http://" + mysql_config.get("host", "localhost")

        # 添加WordPress上传目录配置
        self.wp_upload_dir = wp_upload_dir

    # 在 connect_mysql 方法中添加更多性能优化参数
    def connect_mysql(self):
        """连接到MySQL数据库"""
        try:
            # 检查是否使用连接管理器
            if hasattr(self, "connection_manager"):
                self.connection_manager.connect()
                self.mysql_conn = self.connection_manager.connection
                self.cursor = self.connection_manager.cursor

                # 获取wp_posts表的列名
                self.cursor.execute("SHOW COLUMNS FROM wp_posts")
                self.wp_posts_columns = [row["Field"] for row in self.cursor.fetchall()]
                print(f"获取到wp_posts表结构，共{len(self.wp_posts_columns)}个字段")

                return

            # 连接到MySQL数据库
            self.mysql_conn = pymysql.connect(
                host=self.mysql_config.get("host", "localhost"),
                user=self.mysql_config.get("user", "root"),
                password=self.mysql_config.get("password", ""),
                database=self.mysql_config.get("database", ""),
                port=self.mysql_config.get("port", 3306),
                charset="utf8mb4",
                cursorclass=pymysql.cursors.DictCursor,
                # 添加以下连接参数提高性能
                autocommit=False,  # 手动控制事务
                connect_timeout=60,
                read_timeout=300,
                write_timeout=300,
            )

            # 创建游标
            self.cursor = self.mysql_conn.cursor()

            # 获取wp_posts表的列名
            self.cursor.execute("SHOW COLUMNS FROM wp_posts")
            self.wp_posts_columns = [row["Field"] for row in self.cursor.fetchall()]
            print(f"获取到wp_posts表结构，共{len(self.wp_posts_columns)}个字段")

            # 设置数据库性能参数 - 只使用会话级别的参数
            self.cursor.execute(
                "SET SESSION bulk_insert_buffer_size = 67108864"
            )  # 增加到64MB
            self.cursor.execute("SET SESSION unique_checks = 0")  # 关闭唯一性检查
            self.cursor.execute("SET SESSION foreign_key_checks = 0")  # 关闭外键检查

        except Exception as e:
            print(f"连接MySQL数据库失败: {e}")
            raise

    # 添加新方法
    def use_connection_manager(self, connection_manager):
        """使用连接管理器替代普通连接"""
        self.connection_manager = connection_manager
        self.mysql_conn = connection_manager.connection
        self.cursor = connection_manager.cursor

    def close_connections(self):
        """关闭数据库连接"""
        if self.cursor:
            self.cursor.close()
        if self.mysql_conn:
            self.mysql_conn.close()

    def read_db3_data(self, db3_path, table_name="Content"):
        """从SQLite .db3文件读取数据"""
        try:
            conn = sqlite3.connect(db3_path)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute(f"SELECT * FROM {table_name}")

            # 获取列名
            columns = [column[0] for column in cursor.description]

            # 跳过第一行（标题行）
            cursor.fetchone()

            # 获取所有产品数据
            products = []
            for row in cursor.fetchall():
                product = {columns[i]: row[i] for i in range(len(columns))}
                products.append(product)

            conn.close()
            return columns, products
        except Exception as e:
            print(f"读取.db3文件失败: {e}")
            raise

    def read_csv_data(self, csv_path):
        """从CSV文件读取数据"""
        try:
            products = []
            # 尝试不同的编码方式
            encodings = ["utf-8", "gbk", "gb2312", "utf-16"]

            for encoding in encodings:
                try:
                    with open(csv_path, "r", encoding=encoding) as f:
                        reader = csv.DictReader(f)
                        columns = reader.fieldnames

                        # 检查必要的列是否存在
                        required_columns = ["产品名称", "产品价格", "产品图片"]
                        missing_columns = [
                            col for col in required_columns if col not in columns
                        ]

                        if missing_columns:
                            print(
                                f"警告: CSV文件缺少必要的列: {', '.join(missing_columns)}"
                            )
                            print(
                                "请确保CSV文件包含以下列: 产品名称, 产品价格, 产品图片, 产品型号, 产品面包屑"
                            )
                            continue

                        # 读取所有行
                        for row in reader:
                            # 清理数据，移除前后空格
                            cleaned_row = {
                                k: v.strip() if isinstance(v, str) else v
                                for k, v in row.items()
                            }
                            products.append(cleaned_row)

                        print(f"成功使用 {encoding} 编码读取CSV文件")
                        return columns, products
                except UnicodeDecodeError:
                    continue
                except Exception as e:
                    print(f"尝试使用 {encoding} 编码读取CSV失败: {e}")
                    continue

            # 如果所有编码都失败
            raise ValueError("无法读取CSV文件，请检查文件格式和编码")
        except Exception as e:
            print(f"读取CSV文件失败: {e}")
            raise

    def get_term_id(self, term_name, taxonomy, parent_id=0):
        """获取或创建分类项的ID"""
        # 使用缓存
        cache_key = f"{term_name}_{taxonomy}_{parent_id}"
        if cache_key in self.term_cache:
            return self.term_cache[cache_key]

        # 检查分类项是否存在
        query = """
        SELECT t.term_id, tt.term_taxonomy_id FROM wp_terms t
        JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
        WHERE t.name = %s AND tt.taxonomy = %s AND tt.parent = %s
        """
        self.cursor.execute(query, (term_name, taxonomy, parent_id))
        result = self.cursor.fetchone()

        if result:
            term_id = result["term_id"]
            self.term_cache[cache_key] = term_id
            return term_id

        # 创建新的分类项
        self.cursor.execute(
            "INSERT INTO wp_terms (name, slug) VALUES (%s, %s)",
            (term_name, self.slugify(term_name)),
        )
        term_id = self.cursor.lastrowid

        # 创建分类法关联
        self.cursor.execute(
            """
        INSERT INTO wp_term_taxonomy (term_id, taxonomy, parent, description, count)
        VALUES (%s, %s, %s, %s, %s)
        """,
            (term_id, taxonomy, parent_id, "", 0),
        )

        # 保存到缓存
        self.term_cache[cache_key] = term_id

        return term_id

    def slugify(self, text):
        """将文本转换为slug格式"""
        text = text.lower()
        text = re.sub(r"[^a-z0-9]+", "-", text)
        text = re.sub(r"-+", "-", text)
        return text.strip("-")

    def process_categories(self, breadcrumb_text):
        """处理面包屑文本，创建分类目录"""
        if not breadcrumb_text:
            return []

        category_ids = []

        # 处理多个分类路径（逗号分隔）
        categories = breadcrumb_text.split(",")

        for category in categories:
            category = category.strip()
            if not category:
                continue

            # 处理层级分类（>分隔）
            hierarchy = category.split(">")
            parent_id = 0

            # 存储此路径中的所有分类ID
            path_category_ids = []

            for level, cat_name in enumerate(hierarchy):
                cat_name = cat_name.strip()
                if not cat_name:
                    continue

                # 获取或创建当前层级的分类
                term_id = self.get_term_id(cat_name, "product_cat", parent_id)
                parent_id = term_id

                # 将每一级分类都添加到路径分类列表中
                path_category_ids.append(term_id)

            # 将此路径中的所有分类ID添加到总分类列表中
            category_ids.extend(path_category_ids)

        # 去重，避免重复添加同一个分类
        return list(set(category_ids))

    def process_tags(self, tags_text):
        """处理标签文本，创建标签"""
        if not tags_text:
            return []

        tag_ids = []
        tags = tags_text.split(",")

        for tag in tags:
            tag = tag.strip()
            if not tag:
                continue

            tag_id = self.get_term_id(tag, "product_tag")
            tag_ids.append(tag_id)

        return tag_ids

    def generate_attachment_metadata(self, file_path, width=800, height=800):
        """生成附件元数据，尝试获取真实图片尺寸"""
        try:
            file_name = os.path.basename(file_path)
            file_type = os.path.splitext(file_name)[1].lower().replace(".", "")

            # 尝试获取真实图片尺寸
            real_width, real_height = width, height  # 默认值

            # 构建图片的完整物理路径
            if self.wp_upload_dir:
                uploads_dir = os.path.join(self.wp_upload_dir, "wp-content", "uploads")
                full_image_path = os.path.join(uploads_dir, file_path)

                # 检查文件是否存在
                if os.path.exists(full_image_path):
                    try:
                        # 使用PIL库读取图片尺寸
                        from PIL import Image

                        with Image.open(full_image_path) as img:
                            real_width, real_height = img.size
                            print(f"获取到图片实际尺寸: {real_width}x{real_height}")
                    except ImportError:
                        print("警告: 未安装PIL库，无法获取图片实际尺寸")
                    except Exception as e:
                        print(f"读取图片尺寸时出错: {e}")

            # 使用更简单的元数据格式，确保尺寸信息正确
            thumbnail_width = max(150, real_width // 4)
            thumbnail_height = max(150, real_height // 4)
            medium_width = max(300, real_width // 2)
            medium_height = max(300, real_height // 2)

            # 构建元数据
            metadata = {
                "width": real_width,
                "height": real_height,
                "file": file_path,
                "sizes": {
                    "thumbnail": {
                        "file": file_name,
                        "width": thumbnail_width,
                        "height": thumbnail_height,
                        "mime-type": f"image/{file_type}",
                    },
                    "medium": {
                        "file": file_name,
                        "width": medium_width,
                        "height": medium_height,
                        "mime-type": f"image/{file_type}",
                    },
                    "woocommerce_thumbnail": {
                        "file": file_name,
                        "width": 300,
                        "height": 300,
                        "mime-type": f"image/{file_type}",
                    },
                    "woocommerce_single": {
                        "file": file_name,
                        "width": 600,
                        "height": 600,
                        "mime-type": f"image/{file_type}",
                    },
                    "woocommerce_gallery_thumbnail": {
                        "file": file_name,
                        "width": 100,
                        "height": 100,
                        "mime-type": f"image/{file_type}",
                    },
                },
                "image_meta": {
                    "aperture": "0",
                    "credit": "",
                    "camera": "",
                    "caption": "",
                    "created_timestamp": "0",
                    "copyright": "",
                    "focal_length": "0",
                    "iso": "0",
                    "shutter_speed": "0",
                    "title": "",
                    "orientation": "0",
                    "keywords": [],
                },
            }

            # 使用PHP序列化库将字典转换为PHP序列化格式
            try:
                import phpserialize

                serialized_metadata = phpserialize.dumps(metadata).decode("utf-8")
                return serialized_metadata
            except ImportError:
                print("警告: 未安装phpserialize库，使用手动序列化")
                # 手动构建序列化字符串（简化版本）
                return (
                    'a:5:{s:5:"width";i:'
                    + str(real_width)
                    + ';s:6:"height";i:'
                    + str(real_height)
                    + ';s:4:"file";'
                    + "s:"
                    + str(len(file_path))
                    + ':"'
                    + file_path
                    + '";s:5:"sizes";a:5:{s:9:"thumbnail";a:4:{'
                    + 's:4:"file";s:'
                    + str(len(file_name))
                    + ':"'
                    + file_name
                    + '";s:5:"width";i:'
                    + str(thumbnail_width)
                    + ";"
                    + 's:6:"height";i:'
                    + str(thumbnail_height)
                    + ';s:9:"mime-type";s:10:"image/'
                    + file_type
                    + '";'
                    + '}s:6:"medium";a:4:{s:4:"file";s:'
                    + str(len(file_name))
                    + ':"'
                    + file_name
                    + '";'
                    + 's:5:"width";i:'
                    + str(medium_width)
                    + ';s:6:"height";i:'
                    + str(medium_height)
                    + ';s:9:"mime-type";'
                    + 's:10:"image/'
                    + file_type
                    + '";}s:20:"woocommerce_thumbnail";a:4:{s:4:"file";s:'
                    + str(len(file_name))
                    + ':"'
                    + file_name
                    + '";'
                    + 's:5:"width";i:300;s:6:"height";i:300;s:9:"mime-type";s:10:"image/'
                    + file_type
                    + '";'
                    + '}s:18:"woocommerce_single";a:4:{s:4:"file";s:'
                    + str(len(file_name))
                    + ':"'
                    + file_name
                    + '";'
                    + 's:5:"width";i:600;s:6:"height";i:600;s:9:"mime-type";s:10:"image/'
                    + file_type
                    + '";'
                    + '}s:29:"woocommerce_gallery_thumbnail";a:4:{s:4:"file";s:'
                    + str(len(file_name))
                    + ':"'
                    + file_name
                    + '";'
                    + 's:5:"width";i:100;s:6:"height";i:100;s:9:"mime-type";s:10:"image/'
                    + file_type
                    + '";}'
                    + '}s:10:"image_meta";a:12:{s:8:"aperture";s:1:"0";s:6:"credit";s:0:"";s:6:"camera";s:0:"";'
                    + 's:7:"caption";s:0:"";s:17:"created_timestamp";s:1:"0";s:9:"copyright";'
                    + 's:0:"";s:12:"focal_length";s:1:"0";s:3:"iso";s:1:"0";s:13:"shutter_speed";'
                    + 's:1:"0";s:5:"title";s:0:"";s:11:"orientation";s:1:"0";s:8:"keywords";a:0:{}}}'
                )

        except Exception as e:
            print("生成附件元数据时出错:", str(e))
            # 返回一个简单的元数据，但使用合理的尺寸
            return (
                'a:5:{s:5:"width";i:800;s:6:"height";i:800;s:4:"file";s:'
                + str(len(file_path))
                + ':"'
                + file_path
                + '";s:5:"sizes";a:5:{s:9:"thumbnail";a:4:{s:4:"file";s:'
                + str(len(file_name))
                + ':"'
                + file_name
                + '";s:5:"width";i:150;s:6:"height";i:150;s:9:"mime-type";s:10:"image/jpeg";}s:6:"medium";a:4:{s:4:"file";s:'
                + str(len(file_name))
                + ':"'
                + file_name
                + '";s:5:"width";i:300;s:6:"height";i:300;s:9:"mime-type";s:10:"image/jpeg";}s:20:"woocommerce_thumbnail";a:4:{s:4:"file";s:'
                + str(len(file_name))
                + ':"'
                + file_name
                + '";s:5:"width";i:300;s:6:"height";i:300;s:9:"mime-type";s:10:"image/jpeg";}s:18:"woocommerce_single";a:4:{s:4:"file";s:'
                + str(len(file_name))
                + ':"'
                + file_name
                + '";s:5:"width";i:600;s:6:"height";i:600;s:9:"mime-type";s:10:"image/jpeg";}s:29:"woocommerce_gallery_thumbnail";a:4:{s:4:"file";s:'
                + str(len(file_name))
                + ':"'
                + file_name
                + '";s:5:"width";i:100;s:6:"height";i:100;s:9:"mime-type";s:10:"image/jpeg";}}s:10:"image_meta";a:0:{}}'
            )

    def batch_check_products_exist(self, skus):
        """批量检查产品是否已存在（基于SKU）"""
        if not skus:
            return set()

        # 过滤掉空SKU
        valid_skus = [sku for sku in skus if sku]
        if not valid_skus:
            return set()

        # 构建参数占位符
        placeholders = ", ".join(["%s"] * len(valid_skus))

        # 批量查询
        query = f"""
        SELECT pm.meta_value as sku FROM wp_posts p
        JOIN wp_postmeta pm ON p.ID = pm.post_id
        WHERE p.post_type = 'product'
        AND pm.meta_key = '_sku'
        AND pm.meta_value IN ({placeholders})
        """

        self.cursor.execute(query, valid_skus)
        results = self.cursor.fetchall()

        # 返回已存在的SKU集合
        return {row["sku"] for row in results}

    def check_image_exists_in_media_library(self, image_url):
        """检查图片是否已存在于WordPress媒体库中（文件系统）"""
        if not image_url:
            return False

        try:
            # 从URL获取文件名
            file_name = os.path.basename(image_url)
            if "?" in file_name:
                file_name = file_name.split("?")[0]

            # 打印调试信息 - 不使用任何格式化
            print("查询图片: " + str(file_name))

            # 使用实例变量中的上传目录
            if not self.wp_upload_dir:
                print("警告: 未设置WordPress上传目录路径")
                return False

            # 自动定位到媒体库目录
            uploads_dir = os.path.join(self.wp_upload_dir, "wp-content", "uploads")

            # 获取当前年月目录
            current_time = datetime.now()
            year = current_time.strftime("%Y")
            month = current_time.strftime("%m")

            # 构建可能的图片路径
            # 1. 检查当前年月目录
            current_month_path = os.path.join(uploads_dir, year, month, file_name)

            # 2. 检查上个月目录（如果当前是月初）
            last_month = current_time.replace(day=1) - timedelta(days=1)
            last_month_year = last_month.strftime("%Y")
            last_month_month = last_month.strftime("%m")
            last_month_path = os.path.join(
                uploads_dir, last_month_year, last_month_month, file_name
            )

            # 3. 直接检查上传根目录
            root_path = os.path.join(uploads_dir, file_name)

            # 检查文件是否存在于任一路径
            if os.path.exists(current_month_path):
                return True
            elif os.path.exists(last_month_path):
                return True
            elif os.path.exists(root_path):
                return True

            # 如果需要，可以添加更多的搜索路径

            # 如果都不存在，返回False
            return False

        except Exception as e:
            # 避免使用任何格式化字符串
            error_msg = "检查图片是否存在时出错: " + str(e)
            print(error_msg)
            return False

    def create_product(self, product_data):
        """创建WooCommerce产品"""
        try:
            # 检查产品是否已存在 - 这个检查已经在批处理中完成，这里可以省略
            sku = product_data.get("产品型号", "")

            # 生成唯一的post_name
            post_name = self.slugify(product_data.get("产品名称", ""))
            if not post_name:
                post_name = "product-" + str(uuid.uuid4())[:8]

            # 准备产品基本信息
            current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            # 修改：确保所有必要字段都有值，特别是日期时间字段和整数字段
            post_data = {
                "post_author": 1,
                "post_date": current_time,
                "post_date_gmt": current_time,
                "post_content": product_data.get("产品描述", ""),
                "post_title": product_data.get("产品名称", ""),
                "post_excerpt": product_data.get("短描述", ""),
                "post_status": "publish",
                "comment_status": "open",
                "ping_status": "closed",
                "post_name": post_name,
                "post_modified": current_time,
                "post_modified_gmt": current_time,
                "post_parent": 0,
                # 在 create_product 方法中，将这行：
                "guid": f"{self.mysql_config.get('host', 'localhost')}/?post_type=product&p=",
                # 修改为：
                "guid": self.mysql_config.get("host", "localhost")
                + "/?post_type=product&p=",
                "menu_order": 0,  # 确保这是整数
                "post_type": "product",
                "comment_count": 0,  # 确保这是整数
                "post_mime_type": "",
                "to_ping": "",
                "pinged": "",
                "post_content_filtered": "",
            }

            # 构建SQL插入语句
            columns = []
            values = []

            for column in self.wp_posts_columns:
                if column in post_data:
                    columns.append(column)
                    values.append(post_data[column])
                elif column == "ID":  # ID是自增的，不需要指定
                    continue
                else:
                    columns.append(column)
                    # 对于datetime类型的字段，不能使用空字符串
                    if column.startswith("post_") and (
                        column.endswith("_date") or column.endswith("_gmt")
                    ):
                        values.append(current_time)
                    # 对于整数类型的字段，使用0而不是空字符串
                    elif column in ["menu_order", "post_parent", "comment_count"]:
                        values.append(0)
                    else:
                        values.append("")

            columns_str = ", ".join(columns)
            placeholders = ", ".join(["%s"] * len(columns))
            query = f"INSERT INTO wp_posts ({columns_str}) VALUES ({placeholders})"

            self.cursor.execute(query, values)
            post_id = self.cursor.lastrowid

            # 准备产品元数据批量插入
            meta_data = {
                "_sku": product_data.get("产品型号", ""),
                "_price": product_data.get("产品价格", "0"),
                "_regular_price": product_data.get("产品价格", "0"),
                "_stock_status": "instock",
                "_manage_stock": "no",
                "_virtual": "no",
                "_downloadable": "no",
                "_visibility": "visible",
                "_product_version": "7.0.0",
            }

            # 如果有特价，添加特价信息
            if "产品特价" in product_data and product_data["产品特价"]:
                meta_data["_sale_price"] = product_data["产品特价"]
                meta_data["_price"] = product_data["产品特价"]  # 当前价格设为特价

            # 批量插入元数据
            meta_values = []
            for meta_key, meta_value in meta_data.items():
                meta_values.append((post_id, meta_key, meta_value))

            self.cursor.executemany(
                """
            INSERT INTO wp_postmeta (post_id, meta_key, meta_value)
            VALUES (%s, %s, %s)
            """,
                meta_values,
            )

            # 处理自定义属性 (mycustom)
            if (
                "属性值1" in product_data
                and product_data["属性值1"]
                and product_data["属性值1"].strip()
            ):
                # 创建属性元数据
                attr_data = {
                    "name": "mycustom",
                    "value": product_data["属性值1"],
                    "position": 0,
                    "is_visible": 1,
                    "is_variation": 0,
                    "is_taxonomy": 0,
                }

                # 将属性数据序列化为WooCommerce格式
                attributes = [attr_data]
                serialized_attrs = (
                    'a:1:{s:8:"mycustom";a:6:{s:4:"name";s:8:"mycustom";s:5:"value";s:'
                    + str(len(attr_data["value"]))
                    + ':"'
                    + attr_data["value"]
                    + '";s:8:"position";i:0;'
                    + 's:10:"is_visible";i:1;s:12:"is_variation";i:0;s:11:"is_taxonomy";i:0;}}'
                )

                self.cursor.execute(
                    """
                INSERT INTO wp_postmeta (post_id, meta_key, meta_value)
                VALUES (%s, '_product_attributes', %s)
                """,
                    (post_id, serialized_attrs),
                )

            # 处理分类
            if "产品面包屑" in product_data and product_data["产品面包屑"]:
                category_ids = self.process_categories(product_data["产品面包屑"])

                # 批量获取term_taxonomy_id
                if category_ids:
                    placeholders = ", ".join(["%s"] * len(category_ids))
                    self.cursor.execute(
                        f"""
                    SELECT term_id, term_taxonomy_id FROM wp_term_taxonomy
                    WHERE term_id IN ({placeholders}) AND taxonomy = 'product_cat'
                    """,
                        category_ids,
                    )

                    term_relations = []
                    term_taxonomy_ids = []

                    for row in self.cursor.fetchall():
                        term_relations.append((post_id, row["term_taxonomy_id"], 0))
                        term_taxonomy_ids.append(row["term_taxonomy_id"])

                    # 批量插入分类关系
                    if term_relations:
                        self.cursor.executemany(
                            """
                        INSERT INTO wp_term_relationships (object_id, term_taxonomy_id, term_order)
                        VALUES (%s, %s, %s)
                        """,
                            term_relations,
                        )

            # 处理产品图片
            if "产品图片" in product_data and product_data["产品图片"]:
                self.process_product_images(post_id, product_data["产品图片"])

            return post_id

        except Exception as e:
            print(f"创建产品失败: {e}")
            return None

    def generate_random_sku(self):
        """生成随机SKU（字母加数字，长度不超过9位）"""
        import random
        import string

        # 生成2-4位字母
        letters_length = random.randint(2, 4)
        letters = "".join(
            random.choice(string.ascii_uppercase) for _ in range(letters_length)
        )

        # 生成剩余的数字，总长度不超过9位
        digits_length = random.randint(3, 9 - letters_length)
        digits = "".join(random.choice(string.digits) for _ in range(digits_length))

        return letters + digits

    def get_random_category(self):
        """从预定义的分类中随机选择一个"""
        import random

        categories = ["feature", "special", "hot sale"]
        return random.choice(categories)

    def process_product_images(self, post_id, image_urls):
        """处理产品图片，支持多个图片URL（逗号分隔）"""
        if not image_urls:
            return

        # 只处理第一张图片作为主图，忽略其他图片以提高性能
        urls = image_urls.split(",")
        if not urls:
            return

        url = urls[0].strip()
        if not url:
            return

        # 从URL获取文件名
        file_name = os.path.basename(url)
        if "?" in file_name:
            file_name = file_name.split("?")[0]

        # 获取当前时间
        current_time = datetime.now()
        formatted_time = current_time.strftime("%Y-%m-%d %H:%M:%S")

        # 创建WordPress标准的年/月目录结构
        year = current_time.strftime("%Y")
        month = current_time.strftime("%m")
        relative_path = year + "/" + month + "/" + file_name

        # 构建guid - 使用相对路径
        guid = (
            "http://"
            + self.mysql_config.get("host", "localhost")
            + "/wp-content/uploads/"
            + relative_path
        )

        # 构建mime类型
        mime_type = "image/" + os.path.splitext(file_name)[1].lower().replace(".", "")

        # 使用简化的元数据
        attachment_data = {
            "post_author": 1,
            "post_date": formatted_time,
            "post_date_gmt": formatted_time,
            "post_content": "",
            "post_title": os.path.splitext(file_name)[0],
            "post_status": "inherit",
            "comment_status": "closed",
            "ping_status": "closed",
            "post_name": self.slugify(os.path.splitext(file_name)[0]),
            "post_parent": post_id,
            "post_modified": formatted_time,
            "post_modified_gmt": formatted_time,
            "guid": guid,
            "post_type": "attachment",
            "menu_order": 0,
            "comment_count": 0,
            "post_mime_type": mime_type,
        }

        # 简化插入逻辑
        columns = []
        values = []
        for column in self.wp_posts_columns:
            if column in attachment_data:
                columns.append(column)
                values.append(attachment_data[column])
            elif column == "ID":
                continue
            else:
                columns.append(column)
                # 对于datetime类型的字段，不能使用空字符串
                if column.startswith("post_") and (
                    column.endswith("_date") or column.endswith("_gmt")
                ):
                    values.append(formatted_time)
                # 对于整数类型的字段，使用0而不是空字符串
                elif column in ["menu_order", "post_parent", "comment_count"]:
                    values.append(0)
                else:
                    values.append("")

        columns_str = ", ".join(columns)
        placeholders = ", ".join(["%s"] * len(columns))
        query = f"INSERT INTO wp_posts ({columns_str}) VALUES ({placeholders})"

        self.cursor.execute(query, values)
        attachment_id = self.cursor.lastrowid

        # 更新guid
        # 在 process_product_images 方法中，将这行：
        self.cursor.execute(
            "UPDATE wp_posts SET guid = %s WHERE ID = %s",
            (
                f"http://{self.mysql_config.get('host', 'localhost')}/wp-content/uploads/{relative_path}",
                attachment_id,
            ),
        )

        # 修改为：
        site_url = "http://" + self.mysql_config.get("host", "localhost")
        full_url = site_url + "/wp-content/uploads/" + relative_path
        self.cursor.execute(
            "UPDATE wp_posts SET guid = %s WHERE ID = %s", (full_url, attachment_id)
        )

        # 添加必要的附件元数据
        attachment_meta = [
            (
                attachment_id,
                "_wp_attached_file",
                relative_path,
            ),  # 关键：设置正确的相对路径
            (
                attachment_id,
                "_wp_attachment_metadata",
                self.generate_attachment_metadata(relative_path),
            ),
        ]

        self.cursor.executemany(
            """
        INSERT INTO wp_postmeta (post_id, meta_key, meta_value)
        VALUES (%s, %s, %s)
        """,
            attachment_meta,
        )

        # 添加WooCommerce特定的图片尺寸设置
        wc_meta = [
            (attachment_id, "_wp_attachment_image_alt", os.path.splitext(file_name)[0]),
            (attachment_id, "_wc_attachment_source", ""),
        ]

        self.cursor.executemany(
            """
        INSERT INTO wp_postmeta (post_id, meta_key, meta_value)
        VALUES (%s, %s, %s)
        """,
            wc_meta,
        )

        # 设置产品特色图片
        product_meta = [(post_id, "_thumbnail_id", str(attachment_id))]

        self.cursor.executemany(
            """
        INSERT INTO wp_postmeta (post_id, meta_key, meta_value)
        VALUES (%s, %s, %s)
        """,
            product_meta,
        )

        return attachment_id

    def _import_single_file(self, source_path):
        """导入单个文件的产品数据"""
        try:
            # 根据文件类型读取数据
            if source_path.endswith(".db3"):
                columns, products = self.read_db3_data(source_path)
            elif source_path.endswith(".csv"):
                columns, products = self.read_csv_data(source_path)
            else:
                raise ValueError("不支持的文件类型，请提供.db3或.csv文件")

            print(f"从 {os.path.basename(source_path)} 读取到 {len(products)} 个产品")

            # 导入产品
            imported_count = 0
            skipped_count = 0
            failed_count = 0
            empty_row_count = 0
            no_image_count = 0
            no_price_count = 0
            no_sku_count = 0
            no_category_count = 0

            # 预处理产品数据，减少重复检查
            valid_products = []
            skus_to_check = []

            # 第一步：过滤无效产品并收集SKU
            for i, product in enumerate(products):
                try:
                    # 检查是否为空行（所有值都为空或只有空格）
                    is_empty_row = True
                    for key, value in product.items():
                        if value and value.strip():
                            is_empty_row = False
                            break

                    if is_empty_row:
                        empty_row_count += 1
                        print(f"跳过空行 {i + 1}/{len(products)}")
                        continue

                    # 检查产品图片是否为空
                    image_url = product.get("产品图片", "").strip()
                    if not image_url:
                        no_image_count += 1
                        print(
                            f"跳过无图片产品 {i + 1}/{len(products)}: {product.get('产品名称', '未命名')}"
                        )
                        continue

                    # 检查图片是否存在于媒体库中
                    if not self.check_image_exists_in_media_library(image_url):
                        no_image_count += 1
                        print(
                            f"跳过图片不存在于媒体库的产品 {i + 1}/{len(products)}: {product.get('产品名称', '未命名')}"
                        )
                        continue

                    # 检查产品价格是否为空
                    price = product.get("产品价格", "").strip()
                    if not price:
                        no_price_count += 1
                        print(
                            f"跳过无价格产品 {i + 1}/{len(products)}: {product.get('产品名称', '未命名')}"
                        )
                        continue

                    # 检查产品型号是否为空，如果为空则生成随机SKU
                    sku = product.get("产品型号", "").strip()
                    if not sku:
                        sku = self.generate_random_sku()
                        product["产品型号"] = sku
                        no_sku_count += 1
                        print(
                            f"为产品生成随机SKU {i + 1}/{len(products)}: {product.get('产品名称', '未命名')} -> {sku}"
                        )

                    # 检查产品分类是否为空，如果为空则分配随机分类
                    if not product.get("产品面包屑", "").strip():
                        product["产品面包屑"] = self.get_random_category()
                        no_category_count += 1
                        print(
                            f"为产品分配随机分类 {i + 1}/{len(products)}: {product.get('产品名称', '未命名')} -> {product['产品面包屑']}"
                        )

                    # 收集有效产品和SKU
                    valid_products.append(product)
                    skus_to_check.append(sku)
                except Exception as e:
                    print(f"处理产品时出错 {i + 1}/{len(products)}: {e}")
                    failed_count += 1
                    continue

            # 第二步：批量检查产品是否已存在
            print(f"\n检查 {len(skus_to_check)} 个产品是否已存在...")
            existing_skus = self.batch_check_products_exist(skus_to_check)
            print(f"发现 {len(existing_skus)} 个产品已存在，将跳过")

            # 第三步：批量导入有效产品
            print(f"\n开始导入 {len(valid_products)} 个有效产品...")

            # 使用事务处理批量导入
            self.mysql_conn.begin()

            batch_size = self.batch_size
            total_batches = (len(valid_products) + batch_size - 1) // batch_size

            for batch_idx in range(total_batches):
                start_idx = batch_idx * batch_size
                end_idx = min((batch_idx + 1) * batch_size, len(valid_products))
                batch_products = valid_products[start_idx:end_idx]

                print(
                    f"\n处理批次 {batch_idx + 1}/{total_batches}，包含 {len(batch_products)} 个产品"
                )
                # 报告进度
                print(f"PROGRESS:{batch_idx + 1}:{total_batches}")

                for i, product in enumerate(batch_products):
                    try:
                        # 检查产品是否已存在
                        sku = product.get("产品型号", "").strip()
                        if sku in existing_skus:
                            skipped_count += 1
                            print(
                                f"跳过已存在产品 {start_idx + i + 1}/{len(valid_products)}: {product.get('产品名称', '未命名')} (SKU: {sku})"
                            )
                            continue

                        # 创建产品
                        post_id = self.create_product(product)

                        if post_id:
                            imported_count += 1
                            if imported_count % 10 == 0:  # 每导入10个产品显示一次进度
                                print(
                                    f"已导入 {imported_count} 个产品，当前: {product.get('产品名称', '未命名')}"
                                )
                        else:
                            failed_count += 1
                            print(
                                f"导入失败 {start_idx + i + 1}/{len(valid_products)}: {product.get('产品名称', '未命名')}"
                            )

                    except Exception as e:
                        failed_count += 1
                        print(
                            f"导入产品时出错 {start_idx + i + 1}/{len(valid_products)}: {e}"
                        )
                        continue

                # 每批次提交一次事务
                self.mysql_conn.commit()
                print(f"批次 {batch_idx + 1}/{total_batches} 完成，已提交到数据库")

                # 开始新的事务
                if batch_idx < total_batches - 1:
                    self.mysql_conn.begin()

            # 更新分类计数
            self.update_term_counts()

            # 显示导入统计
            print("\n导入完成，统计信息:")
            print(f"- 成功导入: {imported_count} 个产品")
            print(f"- 跳过已存在: {skipped_count} 个产品")
            print(f"- 导入失败: {failed_count} 个产品")
            print(f"- 跳过空行: {empty_row_count} 行")
            print(f"- 跳过无图片: {no_image_count} 个产品")
            print(f"- 跳过无价格: {no_price_count} 个产品")
            print(f"- 自动生成SKU: {no_sku_count} 个产品")
            print(f"- 自动分配分类: {no_category_count} 个产品")

            return imported_count, skipped_count, failed_count

        except Exception as e:
            print(f"导入文件 {source_path} 时发生错误: {e}")
            # 如果有活动事务，回滚
            if self.mysql_conn and self.mysql_conn.open:
                self.mysql_conn.rollback()
            return 0, 0, 1

    def import_products(self, source_path):
        """导入产品数据"""
        start_time = time.time()  # 记录开始时间
        start_datetime = datetime.now()  # 记录开始的日期时间
        print(f"开始导入时间: {start_datetime.strftime('%Y-%m-%d %H:%M:%S')}")

        try:
            # 连接到MySQL数据库
            self.connect_mysql()

            # 检查source_path是文件还是目录
            if os.path.isdir(source_path):
                # 如果是目录，获取所有CSV文件
                csv_files = [
                    os.path.join(source_path, f)
                    for f in os.listdir(source_path)
                    if f.endswith(".csv")
                ]

                if not csv_files:
                    raise ValueError(f"在目录 {source_path} 中没有找到CSV文件")

                print(f"在目录 {source_path} 中找到 {len(csv_files)} 个CSV文件")

                # 导入每个CSV文件
                total_imported = 0
                total_skipped = 0
                total_failed = 0

                for i, csv_file in enumerate(csv_files):
                    print(
                        f"\n处理文件 {i+1}/{len(csv_files)}: {os.path.basename(csv_file)}"
                    )
                    # 报告进度
                    print(f"PROGRESS:{i+1}:{len(csv_files)}")

                    imported, skipped, failed = self._import_single_file(csv_file)
                    total_imported += imported
                    total_skipped += skipped
                    total_failed += failed

            else:
                # 如果是单个文件，直接导入
                total_imported, total_skipped, total_failed = self._import_single_file(
                    source_path
                )

            # 计算总用时
            end_time = time.time()
            end_datetime = datetime.now()
            elapsed_seconds = end_time - start_time
            hours, remainder = divmod(int(elapsed_seconds), 3600)
            minutes, seconds = divmod(remainder, 60)

            print("\n时间统计:")
            print(f"- 开始时间: {start_datetime.strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"- 结束时间: {end_datetime.strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"- 总用时: {hours}小时 {minutes}分钟 {seconds}秒")

            # 显示总结
            print("\n导入总结:")
            print(f"- 成功导入: {total_imported} 个产品")
            print(f"- 跳过已存在: {total_skipped} 个产品")
            print(f"- 导入失败: {total_failed} 个产品")

            # 完成进度
            print("PROGRESS:100:100")

            return total_imported, total_skipped, total_failed

        except Exception as e:
            print(f"导入过程中出错: {e}")
            return 0, 0, 0
        finally:
            # 关闭数据库连接
            self.close_connections()

    def update_term_counts(self):
        """更新分类计数和其他收尾工作"""
        print("\n正在更新产品分类计数...")
        self.cursor.execute(
            """
        UPDATE wp_term_taxonomy tt
        SET count = (
            SELECT COUNT(DISTINCT tr.object_id) FROM wp_term_relationships tr
            JOIN wp_posts p ON tr.object_id = p.ID
            WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
            AND p.post_type = 'product'
            AND p.post_status = 'publish'
        )
        WHERE tt.taxonomy = 'product_cat'
        """
        )

        # 确保产品在管理界面显示分类
        print("正在更新产品分类显示...")
        self.cursor.execute(
            """
        UPDATE wp_term_relationships tr
        JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_id
        JOIN wp_posts p ON tr.object_id = p.ID
        SET tr.term_order = 0
        WHERE tt.taxonomy = 'product_cat'
        AND p.post_type = 'product'
        """
        )

        # 清除WordPress缓存
        print("正在刷新WordPress缓存...")
        self.cursor.execute(
            "DELETE FROM wp_options WHERE option_name LIKE '%_transient_%'"
        )

        self.mysql_conn.commit()
        print("已更新所有产品分类的计数和显示")

    def regenerate_image_metadata(self):
        """为所有产品图片重新生成元数据"""
        print("开始重新生成图片元数据...")

        # 获取所有产品的特色图片
        self.cursor.execute(
            """
        SELECT p.ID as product_id, pm.meta_value as thumbnail_id, pm2.meta_value as attached_file
        FROM wp_posts p
        JOIN wp_postmeta pm ON p.ID = pm.post_id AND pm.meta_key = '_thumbnail_id'
        JOIN wp_postmeta pm2 ON pm.meta_value = pm2.post_id AND pm2.meta_key = '_wp_attached_file'
        WHERE p.post_type = 'product'
        AND p.post_status = 'publish'
        """
        )

        images = self.cursor.fetchall()
        print(f"找到 {len(images)} 个产品图片需要更新")

        updated_count = 0
        failed_count = 0

        for image in images:
            try:
                product_id = image["product_id"]
                attachment_id = image["thumbnail_id"]
                file_path = image["attached_file"]

                # 生成新的元数据
                new_metadata = self.generate_attachment_metadata(file_path)

                # 更新元数据
                self.cursor.execute(
                    """
                UPDATE wp_postmeta
                SET meta_value = %s
                WHERE post_id = %s AND meta_key = '_wp_attachment_metadata'
                """,
                    (new_metadata, attachment_id),
                )

                # 添加WooCommerce特定的图片尺寸设置（如果不存在）
                file_name = os.path.basename(file_path)

                # 检查是否已存在alt文本
                self.cursor.execute(
                    """
                SELECT COUNT(*) as count FROM wp_postmeta 
                WHERE post_id = %s AND meta_key = '_wp_attachment_image_alt'
                """,
                    (attachment_id,),
                )

                result = self.cursor.fetchone()
                if result and result["count"] == 0:
                    # 添加alt文本
                    self.cursor.execute(
                        """
                    INSERT INTO wp_postmeta (post_id, meta_key, meta_value)
                    VALUES (%s, %s, %s)
                    """,
                        (
                            attachment_id,
                            "_wp_attachment_image_alt",
                            os.path.splitext(file_name)[0],
                        ),
                    )

                # 检查是否已存在WooCommerce附件源
                self.cursor.execute(
                    """
                SELECT COUNT(*) as count FROM wp_postmeta 
                WHERE post_id = %s AND meta_key = '_wc_attachment_source'
                """,
                    (attachment_id,),
                )

                result = self.cursor.fetchone()
                if result and result["count"] == 0:
                    # 添加WooCommerce附件源
                    self.cursor.execute(
                        """
                    INSERT INTO wp_postmeta (post_id, meta_key, meta_value)
                    VALUES (%s, %s, %s)
                    """,
                        (attachment_id, "_wc_attachment_source", ""),
                    )

                updated_count += 1
                if updated_count % 100 == 0:
                    print(f"已更新 {updated_count}/{len(images)} 个图片元数据")
                    self.mysql_conn.commit()

            except Exception as e:
                failed_count += 1
                print(
                    f"更新图片元数据失败 (产品ID: {product_id}, 图片ID: {attachment_id}): {e}"
                )

        self.mysql_conn.commit()
        print(f"图片元数据重新生成完成: 成功 {updated_count}, 失败 {failed_count}")


# 添加主程序代码
if __name__ == "__main__":
    # 配置MySQL连接信息 - 直接写在程序中
    mysql_config = {
        "host": "localhost",  # 数据库主机
        "user": "root",  # 数据库用户名
        "password": "root",  # 数据库密码
        "database": "meiguo-chuanbo03",  # 数据库名称
        "port": 3306,  # 数据库端口
    }

    # 设置WordPress站点根目录路径
    wp_site_dir = r"D:\phpstudy_pro\WWW\meiguo-chuanbo03"

    # 设置要导入的CSV文件或目录路径
    source_path = (
        r"D:\MyProject1\chuanbo\分割\split_2\split_2.csv"  # 修改为您的实际路径
    )

    # 检查路径是否存在
    if not os.path.exists(source_path):
        print(f"错误: 路径 '{source_path}' 不存在")
        sys.exit(1)

    # 添加一个选项，允许用户选择是导入产品还是重新生成图片元数据
    if len(sys.argv) > 1 and sys.argv[1] == "--regenerate-images":
        print("开始重新生成所有产品图片的元数据...")
        importer = WooCommerceImporter(mysql_config, wp_site_dir)
        importer.connect_mysql()
        importer.regenerate_image_metadata()
        importer.close_connections()
        print("重新生成图片元数据完成")
    else:
        # 创建导入器实例，传入站点根目录路径
        importer = WooCommerceImporter(mysql_config, wp_site_dir)

        # 导入产品
        print(f"开始导入产品数据，源路径: {source_path}")
        importer.import_products(source_path)
        print("导入完成")
"""
您可以使用以下命令重新生成所有产品图片的元数据：
python csvinserttowoocommerce.py --regenerate-images
即解决站点首页、目录页、产品详情页<img width="1" height="1"....> 长宽都为1的问题
"""
