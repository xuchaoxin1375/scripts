"""
wp woocommerce 数据库直插产品数据导入器
"""

import os
import random
import argparse
import re
import string
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from comutils import get_desktop_path, get_now_time_str

import pandas as pd
import phpserialize
import pymysql
from PIL import Image
from tqdm import tqdm
from unidecode import unidecode
from woosqlitedb import process_image_csv

IMG_DIR = r"    ".strip()  # 图片目录
CSV_DIR = r"    ".strip()  # CSV文件目录

DB_NAME = " "  # 数据库名🎈

DB_HOST = "localhost"  # 数据库主机名
DB_USER = "root"  # 数据库用户名
PASSWORD = os.environ.get("MySqlKey_LOCAL")


def parse_args():
    """命令行方式使用本脚本"""
    parser = argparse.ArgumentParser(
        description="WooCommerce Product Importer CLI Tool"
    )

    parser.add_argument(
        "-c",
        "--csv-path",
        type=str,
        required=True,
        help="Path to the CSV file or directory containing multiple CSV files",
    )
    parser.add_argument(
        "-i",
        "--img-dir",
        type=str,
        # default=IMG_DIR,
        help="Directory containing product images",
    )
    parser.add_argument(
        "--db-host",
        type=str,
        default=DB_HOST,
        help=f"Database host (default: {DB_HOST})",
    )
    parser.add_argument(
        "--db-user",
        type=str,
        default=DB_USER,
        help=f"Database user (default: {DB_USER})",
    )
    parser.add_argument(
        "--db-password",
        type=str,
        default=PASSWORD,
        help=f"Database password (default: {PASSWORD or "建议:配置数据库密码到环境变量比较方便(临时指定也是允许的)"})",
    )
    parser.add_argument(
        "--db-name",
        type=str,
        # default=DB_NAME,
        required=True,
        help="Database name",
    )
    parser.add_argument(
        "-a",
        "--add-sqlfile",
        default="",
        help="可选的,当你需要从外部导入额外的sql文件时使用,可以是包含一个sql语句的片段"
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        default=20,
        help="Number of threads for parallel processing ",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=100,
        help="Number of products per batch (default: 100)",
    )
    parser.add_argument(
        "-u",
        "--update-slugs",
        action="store_true",
        help="Whether to update product slugs after import",
    )

    return parser.parse_args()


class WooCommerceProductImporter:
    """WooCommerce产品导入器"""

    def __init__(
        self, db_config, img_dir="product_images", max_workers=4, batch_size=50
    ):
        """
        初始化导入器

        :param db_config: 数据库连接配置
        :param img_dir: 本地图片目录路径
        :param max_workers: 最大线程数
        :param batch_size: 每批处理的产品数量
        """
        self.db_config = db_config
        self.img_dir = img_dir
        self.max_workers = max_workers
        self.batch_size = batch_size
        self.lock = threading.Lock()
        # 共用一个数据库连接影响并发部分代码
        self.conn = pymysql.connect(**self.db_config)
        os.makedirs(img_dir, exist_ok=True)

    def import_products(self, csv_path):
        """主导入方法"""
        start_time = datetime.now()

        # 读取CSV文件
        try:
            df = pd.read_csv(csv_path, encoding="utf-8")
            # df = pd.read_csv(csv_path, encoding='latin1', errors='replace')
            total_products = len(df)
            print(
                f"开始导入 {total_products} 个产品，使用 {self.max_workers} 个线程..."
            )
        except Exception as e:
            print(f"读取CSV文件失败: {str(e)}")
            return

        # 分块处理
        chunks = [
            df[i : i + self.batch_size]
            for i in range(0, total_products, self.batch_size)
        ]

        # 使用线程池处理
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            futures = [executor.submit(self._process_batch, chunk) for chunk in chunks]

            # 进度条显示
            with tqdm(total=len(chunks), desc="处理批次") as pbar:
                for future in as_completed(futures):
                    try:
                        future.result()
                        pbar.update(1)
                    except Exception as e:
                        print(f"处理批次失败: {str(e)}")

        # 后期处理
        # self.post_import_processing()
        elapsed = (datetime.now() - start_time).total_seconds()
        print(f"\n导入完成，耗时 {elapsed:.2f} 秒")

    def _process_batch(self, chunk):
        """处理一个批次的产品数据（使用真实INSERT返回的ID）"""
        conn = pymysql.connect(**self.db_config)
        try:
            with conn.cursor() as cursor:
                # 准备数据容器（不再预先计算ID）
                product_data = []
                meta_data = []
                term_data = []

                for _, row in chunk.iterrows():
                    # 收集产品基础数据
                    product_name = row.get("Name", "")
                    slug = self._generate_slug(product_name)

                    if "Description" in row and pd.notna(row["Description"]):
                        description = self._escape_html_for_sql(
                            str(row.get("Description", ""))
                        )
                    else:
                        description = ""
                    product_name = self._escape_html_for_sql(str(product_name))

                    product_data.append(
                        (
                            product_name,
                            "product",
                            "publish",
                            description,
                            row.get("Short_description", ""),
                            datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                            datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                            datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                            datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                            "",
                            "",
                            slug,
                        )
                    )

                # 批量插入产品（获取真实ID）
                product_ids = []
                with self.lock:
                    for data in product_data:
                        cursor.execute(
                            """INSERT INTO wp_posts 
                            (post_title, post_type, post_status, post_content, 
                            post_excerpt, post_date, post_date_gmt, post_modified, post_modified_gmt,
                            to_ping, pinged, post_name)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                            data,
                        )
                        product_id = cursor.lastrowid
                        product_ids.append(product_id)

                    # 处理每个产品的元数据和分类
                    for product_id, (_, row) in zip(product_ids, chunk.iterrows()):
                        # 产品元数据
                        processed_terms = set()
                        meta_values = [
                            (product_id, "_product_type", "simple"),
                            (
                                product_id,
                                "_regular_price",
                                float(row.get("Regular price", 0)),
                            ),
                            (product_id, "_price", float(row.get("Sale price", 0))),
                            (
                                product_id,
                                "_sale_price",
                                float(row.get("Sale price", 0)),
                            ),
                            (product_id, "_sku", row.get("SKU", "")),
                            (
                                product_id,
                                "_stock_status",
                                row.get("stock_status", "instock"),
                            ),
                            (
                                product_id,
                                "_manage_stock",
                                row.get("manage_stock", "no"),
                            ),
                        ]

                        if "stock_quantity" in row and pd.notna(row["stock_quantity"]):
                            meta_values.append(
                                (product_id, "_stock", int(row["stock_quantity"]))
                            )

                        meta_data.extend(meta_values)

                        # 处理图片
                        if "Images" in row and pd.notna(row["Images"]):
                            self._process_product_image(
                                cursor, product_id, row["Images"]
                            )

                            # 处理分类
                        categoriestr = row.get("Categories", "")
                        if "Categories" in row and pd.notna(row["Categories"]):
                            for category in str(row["Categories"]).split("|"):
                                category = category.strip()
                                category = self._escape_html_for_sql(str(category))
                                if category and category not in processed_terms:
                                    term_id = self._get_or_create_term(
                                        cursor, category, "product_cat"
                                    )
                                    if term_id:
                                        # 检查关系是否已存在
                                        cursor.execute(
                                            """SELECT 1 FROM wp_term_relationships 
                                            WHERE object_id = %s AND term_taxonomy_id = %s""",
                                            (product_id, term_id),
                                        )
                                        if not cursor.fetchone():
                                            term_data.append((product_id, term_id))
                                        processed_terms.add(category)

                        # 处理标签
                        tags = row.get("Tags", "")
                        if "Tags" in row and pd.notna(tags):
                            for tag in str(tags).split("|"):
                                tag = tag.strip()
                                tag = self._escape_html_for_sql(str(tag))
                                if tag and tag not in processed_terms:
                                    term_id = self._get_or_create_term(
                                        cursor, tag, "product_tag"
                                    )
                                    if term_id:
                                        # 检查关系是否已存在
                                        cursor.execute(
                                            """SELECT 1 FROM wp_term_relationships 
                                            WHERE object_id = %s AND term_taxonomy_id = %s""",
                                            (product_id, term_id),
                                        )
                                        if not cursor.fetchone():
                                            term_data.append((product_id, term_id))
                                        processed_terms.add(tag)

                        # 处理简单产品属性
                        if "Attribute 1 value(s)" in row and pd.notna(
                            row["Attribute 1 value(s)"]
                        ):
                            attrvalues = self._escape_html_for_sql(
                                str(row["Attribute 1 value(s)"])
                            )
                            self._process_simple_attributes(
                                cursor, product_id, attrvalues
                            )

                    # 批量插入元数据
                    if meta_data:
                        cursor.executemany(
                            """INSERT INTO wp_postmeta 
                            (post_id, meta_key, meta_value)
                            VALUES (%s, %s, %s)""",
                            meta_data,
                        )

                    # 批量插入分类关系
                    if term_data:
                        cursor.executemany(
                            """INSERT INTO wp_term_relationships 
                            (object_id, term_taxonomy_id)
                            VALUES (%s, %s)""",
                            term_data,
                        )

                    conn.commit()

        except Exception as e:
            conn.rollback()
            raise Exception(f"批次处理失败: {str(e)}")
        finally:
            conn.close()

    def _term_exists(self, cursor, term_name, taxonomy):
        """检查分类/标签是否存在"""
        cursor.execute(
            """SELECT t.term_id 
            FROM wp_terms t
            JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
            WHERE (t.name = %s OR t.slug = %s) AND tt.taxonomy = %s""",
            (term_name, self._generate_slug(term_name), taxonomy),
        )
        return cursor.fetchone()

    def _escape_html_for_sql(self, text):
        """转义HTML内容中的特殊字符"""
        if pd.isna(text):
            return ""

        text = str(text)
        # 替换可能引起问题的字符
        text = text.replace("\\", "\\\\")  # 先替换反斜杠
        text = text.replace("'", "'")
        text = text.replace('"', '"')
        return text

    def _process_simple_attributes(self, cursor, product_id, attributes_str):
        if pd.isna(attributes_str) or not str(attributes_str).strip():
            return

        attribute_name = "mycustom"
        attribute_value = str(attributes_str)

        # 手动构建PHP序列化字符串
        value_length = len(attribute_value.encode("utf-8"))  # 获取UTF-8编码的字节长度
        serialized_value = f's:{value_length}:"{attribute_value}";'

        php_serialized = (
            f'a:1:{{s:{len(attribute_name)}:"{attribute_name}";'
            f'a:6:{{s:4:"name";s:{len(attribute_name)}:"{attribute_name}";'
            f's:5:"value";{serialized_value}'
            f's:8:"position";i:0;'
            f's:10:"is_visible";i:0;'
            f's:12:"is_variation";i:0;'
            f's:11:"is_taxonomy";i:0;}}}}'
        )

        # 插入到wp_postmeta表
        cursor.execute(
            """INSERT INTO wp_postmeta 
            (post_id, meta_key, meta_value)
            VALUES (%s, %s, %s)""",
            (product_id, "_product_attributes", php_serialized),
        )

    def _php_serialize(self, data):

        if isinstance(data, dict):
            result = []
            for key, value in data.items():
                serialized_key = self._php_serialize(key)
                serialized_value = self._php_serialize(value)
                result.append(f"{serialized_key}{serialized_value}")
            return f"a:{len(data)}:{{" + "".join(result) + "}"
        elif isinstance(data, str):
            return f's:{len(data)}:"{data}";'
        elif isinstance(data, int):
            return f"i:{data};"
        elif isinstance(data, bool):
            return f"b:{1 if data else 0};"
        else:
            return ""

    def _process_product_image(self, cursor, product_id, img_file):
        """处理产品图片关联"""
        img_path = os.path.join(self.img_dir, img_file)

        if not os.path.exists(img_path):
            print(f"警告: 图片文件不存在 - {img_path}")
            time.sleep(0.1)  # 延迟0.1秒，避免频繁访问文件系统
            return

        # 获取当前年月
        year = datetime.now().year
        # month = datetime.now().month
        # formatted_month = "{:02}".format(month)
        # 插入附件记录

        cursor.execute(
            """INSERT INTO wp_posts 
            (post_author, post_date, post_date_gmt, post_title, post_status, 
             comment_status, ping_status, post_name, post_modified, post_modified_gmt, 
             post_type, guid, to_ping, pinged,post_mime_type,post_parent)
            VALUES 
            (1, %s, %s, %s, 'inherit', 'open', 'closed', %s, %s, %s, 
             'attachment', %s, '', '','image/webp', %s)""",
            (
                datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                os.path.splitext(img_file)[0],
                os.path.splitext(img_file)[0],
                datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                # f"/wp-content/uploads/{year}/{formatted_month}/{img_file}",
                f"/wp-content/uploads/{year}/{img_file}",
                product_id,
            ),
        )
        attachment_id = cursor.lastrowid

        # 插入附件元数据
        # 获取图片实际尺寸
        try:

            with Image.open(img_path) as img:
                width, height = img.size
        except ImportError:
            print("警告: Pillow未安装，使用默认尺寸600x600")
            width, height = 600, 600
        except Exception as e:
            print(f"获取图片尺寸失败: {str(e)}，使用默认尺寸600x600")
            width, height = 600, 600
        meta_data = [
            (
                attachment_id,
                "_wp_attached_file",
                # f"{year}/{formatted_month}/{img_file}",
                f"{year}/{img_file}",
            ),
            (
                attachment_id,
                "_wp_attachment_metadata",
                self._generate_attachment_metadata(img_path, width, height),
            ),
            (attachment_id, "_wp_attachment_img_alt", ""),
        ]

        # 添加尺寸信息（如果成功获取）
        if width > 0 and height > 0:
            meta_data.extend(
                [
                    (attachment_id, "_wp_attachment_width", width),
                    (attachment_id, "_wp_attachment_height", height),
                ]
            )

        # 批量插入元数据
        cursor.executemany(
            """INSERT INTO wp_postmeta 
            (post_id, meta_key, meta_value)
            VALUES (%s, %s, %s)""",
            meta_data,
        )
        # 设置产品特色图片
        cursor.execute(
            """INSERT INTO wp_postmeta 
            (post_id, meta_key, meta_value)
            VALUES (%s, '_thumbnail_id', %s)""",
            (product_id, attachment_id),
        )

    # 需要安装该库：pip install phpserialize

    def _generate_attachment_metadata(self, img_path, width, height):
        """生成附件元数据（PHP 序列化格式）"""
        file_name = os.path.basename(img_path)
        year = datetime.now().year
        month = datetime.now().month
        formatted_month = "{:02}".format(month)

        metadata = {
            "width": width,
            "height": height,
            "file": f"{year}/{formatted_month}/{file_name}",
            "filesize": (os.path.getsize(img_path) if os.path.exists(img_path) else 0),
            "sizes": {},  # WordPress 默认缩略图信息
            "img_meta": {
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

        # 使用 phpserialize 库进行序列化
        return phpserialize.dumps(metadata).decode("latin1")  # 保持 WordPress 兼容性

    def _get_or_create_term(self, cursor, term_name, taxonomy):
        """获取或创建分类/标签（增强版）"""
        slug = self._generate_slug(term_name)

        # 检查是否已存在
        cursor.execute(
            """SELECT tt.term_taxonomy_id, tt.count 
            FROM wp_terms t
            JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
            WHERE (t.name = %s OR t.slug = %s) AND tt.taxonomy = %s""",
            (term_name, slug, taxonomy),
        )
        result = cursor.fetchone()

        if result:
            term_taxonomy_id, count = result
            # 更新分类计数（临时标记，实际计数会在后期处理中统一更新）
            cursor.execute(
                """UPDATE wp_term_taxonomy 
                SET count = %s 
                WHERE term_taxonomy_id = %s""",
                (count + 1, term_taxonomy_id),
            )
            return term_taxonomy_id

        # 创建新术语
        cursor.execute(
            """INSERT INTO wp_terms 
            (name, slug)
            VALUES (%s, %s)""",
            (term_name, slug),
        )
        term_id = cursor.lastrowid

        # 关联分类法（初始计数设为1）
        cursor.execute(
            """INSERT INTO wp_term_taxonomy 
            (term_id, taxonomy, description, parent, count)
            VALUES (%s, %s, '', 0, 1)""",
            (term_id, taxonomy),
        )

        term_taxonomy_id = cursor.lastrowid
        return term_taxonomy_id

    def _generate_slug(self, name):

        # 转换为ASCII字符
        slug = unidecode(name)
        # 转换为小写
        slug = slug.lower()
        # 替换非字母数字字符为连字符
        slug = re.sub(r"[^a-z0-9]+", "-", slug)
        # 移除首尾的连字符
        slug = slug.strip("-")
        # 限制长度
        slug = slug[:200]
        # 如果没有有效字符，使用随机字符串
        if not slug:

            slug = "".join(random.choices(string.ascii_lowercase + string.digits, k=8))

        return slug

    def convert_tags_to_categories(self):
        """将只有标签没有分类的产品的标签转为分类(可选,如果已经保证了总是有分类,可以跳过此步骤)"""
        print("开始将只有标签的产品转为分类...")
        conn = pymysql.connect(**self.db_config)
        try:
            with conn.cursor() as cursor:
                # 开始事务
                # conn.begin()

                # 1. 找出需要转换的标签
                query = """
                    SELECT tt.term_taxonomy_id, tt.term_id
                    FROM wp_term_taxonomy tt
                    JOIN wp_term_relationships rel ON tt.term_taxonomy_id = rel.term_taxonomy_id
                    JOIN wp_posts p ON rel.object_id = p.ID
                    WHERE tt.taxonomy = 'product_tag'
                    AND p.post_type = 'product'
                    AND p.post_status = 'publish'
                    AND NOT EXISTS (
                        SELECT 1 
                        FROM wp_term_relationships rel2
                        JOIN wp_term_taxonomy tt2 ON rel2.term_taxonomy_id = tt2.term_taxonomy_id
                        WHERE rel2.object_id = p.ID
                        AND tt2.taxonomy = 'product_cat'
                    )
                """

                cursor.execute(query)
                tags_to_convert = cursor.fetchall()

                count = len(tags_to_convert)
                print(f"找到 {count} 个需要转换的标签")

                if count > 0:
                    # 2. 更新这些标签的分类法类型为product_cat
                    update_query = """
                        UPDATE wp_term_taxonomy
                        SET taxonomy = 'product_cat'
                        WHERE term_taxonomy_id = %s
                    """

                    for tag in tags_to_convert:
                        cursor.execute(update_query, (tag[0],))

                    print(f"成功将 {count} 个标签转为分类")

        except Exception as e:
            conn.rollback()
            print(f"转换标签为分类失败: {str(e)}")
            raise
        finally:
            conn.close()

    def post_import_processing(self):
        """导入后处理"""
        print("正在执行后期处理...")
        # conn = self.conn
        conn=pymysql.connect(**self.db_config)
        try:
            with conn.cursor() as cursor:

                # 将只有标签的产品转为分类
                # self.convert_tags_to_categories()

                # 1. 更新分类计数（确保准确）
                cursor.execute(
                    """
                    UPDATE wp_term_taxonomy tt
                    SET count = (
                        SELECT COUNT(DISTINCT tr.object_id)
                        FROM wp_term_relationships tr
                        JOIN wp_posts p ON tr.object_id = p.ID
                        WHERE tr.term_taxonomy_id = tt.term_taxonomy_id
                        AND p.post_type = 'product'
                        AND p.post_status = 'publish'
                    )
                    WHERE tt.taxonomy IN ('product_cat', 'product_tag')
                """
                )

                # 2. 清理空分类
                cursor.execute(
                    """
                    DELETE tt, t
                    FROM wp_term_taxonomy tt
                    LEFT JOIN wp_terms t ON tt.term_id = t.term_id
                    WHERE tt.count = 0
                    AND tt.taxonomy = 'product_cat'
                """
                )

                # 4. 更新产品查找表
                cursor.execute("TRUNCATE TABLE wp_wc_product_meta_lookup")
                cursor.execute(
                    """
                    INSERT INTO wp_wc_product_meta_lookup
                    (product_id, sku, min_price, max_price)
                    SELECT 
                        p.ID, 
                        MAX(CASE WHEN pm.meta_key = '_sku' THEN pm.meta_value ELSE '' END),
                        MIN(CAST(COALESCE(NULLIF(pm2.meta_value, ''), '0') AS DECIMAL(10,2))),
                        MAX(CAST(COALESCE(NULLIF(pm2.meta_value, ''), '0') AS DECIMAL(10,2)))
                    FROM wp_posts p
                    LEFT JOIN wp_postmeta pm ON p.ID = pm.post_id AND pm.meta_key = '_sku'
                    LEFT JOIN wp_postmeta pm2 ON p.ID = pm2.post_id AND pm2.meta_key = '_price'
                    WHERE p.post_type = 'product'
                    GROUP BY p.ID
                """
                )

                # 5. 清理缓存
                cursor.execute(
                    "DELETE FROM wp_options WHERE option_name LIKE '_transient_wc_%'"
                )
                cursor.execute(
                    "DELETE FROM wp_options WHERE option_name LIKE '_transient_timeout_wc_%'"
                )

                # 6. 强制更新分类层级（解决有时分类不显示的问题）
                cursor.execute(
                    """
                    UPDATE wp_term_taxonomy 
                    SET parent = 0 
                    WHERE taxonomy = 'product_cat' 
                    AND parent IS NULL
                """
                )

                conn.commit()
                print("后期处理完成")

        except Exception as e:
            conn.rollback()
            print(f"后期处理失败: {str(e)}")
        finally:
            conn.close()
    def additional_processing(self, sql_path):
        """ 读取外部sql文件进行处理
         文件存在性检查交由open函数处理即可
        """
        if sql_path:
            print("正在尝试执行外部sql文件处理...")
        with open(sql_path, 'r', encoding='utf-8') as f:
            sql = f.read()
        # conn = self.conn
        conn = pymysql.connect(
         **self.db_config
        )
        try:
            with conn.cursor() as cursor:
                cursor.execute(sql)
                conn.commit()
                print("外部sql文件处理完成")
        except Exception as e:
            conn.rollback()
            print(f"外部sql文件处理失败: {str(e)}")
        finally:
            conn.close()

    def update_product_slugs(self):
        """更新所有产品的 slug，格式为 post_name-ID
        -- 通常wp数据库限制slug长度200字符(打满不是很好,可能会遇到404),这里先将长度限制到180,然后做后缀id拼接防止重复slug处理(冗余的20位保存id绰绰有余)
        -- 在产品导入环节中执行的slug规范化处理,长度限制以及id后缀区分同名产品(testing...)
        小心slug中对`-`的限制,不允许`-`连续出现,否则会导致产品详情页404


        """
        update_sql = """
            UPDATE wp_posts AS p
                JOIN (
                    SELECT ID,
                        post_name,
                        CONCAT(
                            LEFT(
                                post_name,
                                180
                            ),
                            ID
                        ) AS new_slug
                    FROM wp_posts
                    WHERE post_type = 'product'
                        AND post_status != 'trash'
                ) AS sub ON p.ID = sub.ID
            SET p.post_name = sub.new_slug
            WHERE p.post_type = 'product';
        """
        self._execute_sql(update_sql)
        print("✅ 成功更新产品 slug")
    def update_product_title(self):
        """部分产品名不规范,比如包含采集中处理不当的或多余的字符串片段
        或者可选的做名称截断
        """
        
        update_sql = """
            UPDATE wp_posts
            SET
                post_title =
            REPLACE (post_title, '产品名称中包含顶级域名,检查并适当处理后再继续!', '')
            WHERE
                post_type = 'product';
        """
        self._execute_sql(update_sql)
        print("清理产品标题多余文字")
    def _execute_sql(self, sql):
        conn = pymysql.connect(**self.db_config)
        try:
            with conn.cursor() as cursor:
                cursor.execute(sql)
                conn.commit()
            
        except Exception as e:
            conn.rollback()
            print(f"❌ 更新产品 slug 失败: {str(e)}")
        finally:
            conn.close()


if __name__ == "__main__":
    # 解析命令行参数
    args = parse_args()
    # 处理图片
    csv_path = args.csv_path or CSV_DIR
    img_dir = args.img_dir or IMG_DIR
    desktop = get_desktop_path()
    backup_csv_dir = os.path.join(desktop, f"backup_csvs/{get_now_time_str()}")
    # 对csv做必要的处理🎈
    process_image_csv(img_dir=img_dir, csv_dir=csv_path,backup_dir=backup_csv_dir)
    go = input("是否继续?(y/n) [default:y]").strip().lower()
    if go not in ("", "y", "yes"):
        print("操作已取消。")
        exit()
    else:
        print("继续,开始导入产品数据到数据库...")

    # 数据库配置
    db_config = {
        "host": args.db_host,
        "user": args.db_user,
        "database": args.db_name,
        "password": args.db_password,
        "charset": "utf8mb4",
        "connect_timeout": 900,
        "read_timeout": 1600,
        "write_timeout": 1600,
        "client_flag":pymysql.constants.CLIENT.MULTI_STATEMENTS,
        "init_command": 'SET SESSION sql_mode="NO_ENGINE_SUBSTITUTION"',
    }

    # 创建导入器实例
    importer = WooCommerceProductImporter(
        db_config=db_config,
        img_dir=img_dir,
        max_workers=args.max_workers,
        batch_size=args.batch_size,
    )

    # 执行导入(针对输入的路径是文件还是文件夹采取针对性的导入)
    if os.path.isfile(csv_path) and csv_path.endswith(".csv"):
        print(f"Processing single CSV file: {csv_path}")
        importer.import_products(csv_path)
    elif os.path.isdir(csv_path):
        for csv_file in os.listdir(csv_path):
            if csv_file.endswith(".csv"):
                p = os.path.abspath(os.path.join(csv_path, csv_file))
                print(f"Processing file: {p}")
                importer.import_products(p)
    else:
        print(
            "Invalid CSV path provided. Please specify a valid CSV file or directory."
        )

    # 后期处理
    importer.post_import_processing()
    importer.update_product_title()

    if args.update_slugs:
        importer.update_product_slugs()
    if args.add_sqlfile:
        importer.additional_processing(args.add_sqlfile)
