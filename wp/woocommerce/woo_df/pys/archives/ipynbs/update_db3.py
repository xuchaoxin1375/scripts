"""更改db3文件
例如更改错误的价格数量级
"""

import sqlite3

db_path = r"C:\火车采集器V10.27\Data\251\SpiderResult.db3"
default_table = "Content"
con = sqlite3.connect(db_path)
res = None
with con:
    con.row_factory = sqlite3.Row
    cur = con.execute(f"select * from {default_table}")
    res = cur.fetchmany()
# print(res)
for row in res:
    # print(dict(row))
    print(dict(row))
