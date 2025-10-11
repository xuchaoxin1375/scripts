import pymysql
import time
import logging


class MySQLConnectionManager:
    """MySQL连接管理器 - 处理连接断开和重试"""

    def __init__(self, config, max_retries=3, retry_delay=5):
        """初始化连接管理器

        Args:
            config: MySQL连接配置字典
            max_retries: 最大重试次数
            retry_delay: 重试间隔(秒)
        """
        self.config = config
        self.connection = None
        self.cursor = None
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self.is_connected = False

    def connect(self):
        """建立数据库连接"""
        if self.is_connected:
            return True

        try:
            # 连接到MySQL数据库
            self.connection = pymysql.connect(
                host=self.config.get("host", "localhost"),
                user=self.config.get("user", "root"),
                password=self.config.get("password", ""),
                database=self.config.get("database", ""),
                port=self.config.get("port", 3306),
                charset="utf8mb4",
                cursorclass=pymysql.cursors.DictCursor,
                # 添加以下连接参数提高性能
                autocommit=False,  # 手动控制事务
                connect_timeout=60,
                read_timeout=600,  # 增加读取超时时间到10分钟
                write_timeout=600,  # 增加写入超时时间到10分钟
            )

            # 创建游标
            self.cursor = self.connection.cursor()

            # 设置数据库性能参数
            self.cursor.execute(
                "SET SESSION bulk_insert_buffer_size = 67108864"
            )  # 增加到64MB
            self.cursor.execute("SET SESSION unique_checks = 0")  # 关闭唯一性检查
            self.cursor.execute("SET SESSION foreign_key_checks = 0")  # 关闭外键检查
            self.cursor.execute(
                "SET SESSION net_read_timeout = 600"
            )  # 增加网络读取超时
            self.cursor.execute(
                "SET SESSION net_write_timeout = 600"
            )  # 增加网络写入超时
            self.cursor.execute(
                "SET SESSION wait_timeout = 28800"
            )  # 增加等待超时(8小时)

            self.is_connected = True
            return True
        except Exception as e:
            print(f"连接MySQL数据库失败: {e}")
            self.is_connected = False
            return False

    def execute(self, query, params=None, retry_on_failure=True):
        """执行SQL查询，自动处理连接断开的情况

        Args:
            query: SQL查询语句
            params: 查询参数
            retry_on_failure: 是否在失败时重试

        Returns:
            查询结果
        """
        if not self.is_connected:
            if not self.connect():
                raise Exception("无法连接到数据库")

        retries = 0
        while retries <= self.max_retries:
            try:
                self.cursor.execute(query, params)
                return self.cursor.fetchall() if self.cursor.rowcount > 0 else None
            except (pymysql.err.OperationalError, pymysql.err.InterfaceError) as e:
                # 检查是否是连接断开错误
                if e.args[0] in (2006, 2013, 2003, 2002):  # 连接断开的错误代码
                    print(
                        f"数据库连接断开，尝试重新连接 (尝试 {retries+1}/{self.max_retries+1})"
                    )
                    self.is_connected = False

                    if not retry_on_failure or retries >= self.max_retries:
                        raise

                    # 等待一段时间后重试
                    time.sleep(self.retry_delay)
                    self.connect()
                    retries += 1
                else:
                    # 其他类型的错误，直接抛出
                    raise
            except Exception as e:
                # 其他未预期的错误
                print(f"执行查询时出错: {e}")
                raise

    def execute_many(self, query, params_list, batch_size=100):
        """批量执行SQL查询

        Args:
            query: SQL查询语句
            params_list: 参数列表
            batch_size: 每批处理的数量
        """
        if not self.is_connected:
            if not self.connect():
                raise Exception("无法连接到数据库")

        # 分批处理
        total = len(params_list)
        for i in range(0, total, batch_size):
            batch = params_list[i : i + batch_size]
            retries = 0
            while retries <= self.max_retries:
                try:
                    self.cursor.executemany(query, batch)
                    break
                except (pymysql.err.OperationalError, pymysql.err.InterfaceError) as e:
                    # 检查是否是连接断开错误
                    if e.args[0] in (2006, 2013, 2003, 2002):  # 连接断开的错误代码
                        print(
                            f"数据库连接断开，尝试重新连接 (尝试 {retries+1}/{self.max_retries+1})"
                        )
                        self.is_connected = False

                        if retries >= self.max_retries:
                            raise

                        # 等待一段时间后重试
                        time.sleep(self.retry_delay)
                        self.connect()
                        retries += 1
                    else:
                        # 其他类型的错误，直接抛出
                        raise
                except Exception as e:
                    # 其他未预期的错误
                    print(f"执行批量查询时出错: {e}")
                    raise

            # 每处理5批次提交一次事务，避免事务过大
            if (i // batch_size) % 5 == 0:
                self.commit()
                print(f"已处理 {min(i+batch_size, total)}/{total} 条记录")

    def commit(self):
        """提交事务"""
        if self.is_connected:
            try:
                self.connection.commit()
            except (pymysql.err.OperationalError, pymysql.err.InterfaceError) as e:
                # 如果提交时连接已断开，尝试重新连接并重试
                if e.args[0] in (2006, 2013, 2003, 2002):
                    print("提交事务时连接断开，尝试重新连接")
                    self.is_connected = False
                    if self.connect():
                        self.connection.commit()
                    else:
                        raise Exception("无法重新连接到数据库")
                else:
                    raise

    def rollback(self):
        """回滚事务"""
        if self.is_connected:
            try:
                self.connection.rollback()
            except:
                # 如果回滚失败，忽略错误
                pass

    def close(self):
        """关闭连接"""
        if self.cursor:
            try:
                self.cursor.close()
            except:
                pass

        if self.connection:
            try:
                self.connection.close()
            except:
                pass

        self.is_connected = False
