"""更改db3文件
例如更改错误的价格数量级
"""

import sqlite3

db_path = r"C:\火车采集器V10.27\Data\251\SpiderResult.db3"
default_table = "Content"
con = sqlite3.connect(db_path)
res = None
with con:
    # 查看表的所有字段
    info = con.execute(f"PRAGMA table_info({default_table})")
    print(info.fetchall())

    # 指定查询返回的形式
    # con.row_factory = sqlite3.Row
    # 读取一批数据
    # cur = con.execute(f"select * from {default_table}")
    # res = cur.fetchmany()
    # 将产品价格字段取值为1的修改为1300,将取值为2的修改为2300
    # con.execute(f"update {default_table} set 产品价格 = 1300 where 产品价格 = 1")
    # con.execute(f"update {default_table} set 产品价格 = 2300 where 产品价格 = 2")
    # con.execute(f"update {default_table} set 产品价格 = 3300 where 产品价格 = 3")
    con.execute(f"update {default_table} set 产品价格 = 4300 where 产品价格 = 4")
    con.execute(f"update {default_table} set 产品价格 = 5300 where 产品价格 = 5")
    con.execute(f"update {default_table} set 产品价格 = 6300 where 产品价格 = 6")
    con.execute(f"update {default_table} set 产品价格 = 7300 where 产品价格 = 7")
    con.execute(f"update {default_table} set 产品价格 = 8300 where 产品价格 = 8")
    con.execute(f"update {default_table} set 产品价格 = 9300 where 产品价格 = 9")
    # 将价格从高到低排列打印前100行
    cur = con.execute(f"select * from {default_table} order by 产品价格 desc limit 10")
    print(cur.fetchall())
# for row in res:
#     # print(dict(row))
#     print(dict(row))
con.close()
