import os
import pandas as pd
from datetime import datetime
import re

SITE_BIRTH_CSV = "./site_birth.csv"
SITE_TABLE_CONF = "./site_table.conf"
# 本批次建站列表备份文件(可选)
SITE_TABLE_BAK = "./site_table.conf.bak"

NGINX_VHOST_ROOT = "/www/server/panel/vhost/nginx"

# 不要有多余的换行符,防止多伦替换多出大片空白
COM_CONF_SEG = """
    #CUSTOM-CONFIG-START
    include /www/server/nginx/conf/com_basic.conf;
    #CUSTOM-CONFIG-END
"""
COM_LIMIT_RATE_SEG = """
    #CUSTOM-CONFIG-START
    include /www/server/nginx/conf/com_basic.conf;
	include /www/server/nginx/conf/com_limit_rate.conf;
    #CUSTOM-CONFIG-END
"""

CUSTOM_CONFIG_START = "#CUSTOM-CONFIG-START"
replace_seg_regex = re.compile(r"#CUSTOM-CONFIG-START[\s\S]*#CUSTOM-CONFIG-END")
INIT_INSERT_BEFORE_MARK = "    #CERT-APPLY-CHECK--START"
DAYS = 10  # 可根据需要调整


def young2old(vhost_config, init_as=COM_LIMIT_RATE_SEG, replace=False):
    """新站转老站的配置修改

    参数:
        vhost_config: 虚拟主机配置文件
        init_as: 视为老站配置还是新站配置
        replace: 是否替换源文件
    """
    config = ""
    with open(vhost_config, "r") as f:
        config = f.read()
        # print(config)
        # return config
        if config.find(CUSTOM_CONFIG_START) >= 0:  # -1表示不存在
            print("CUSTOM_CONFIG_START exists")
            if config.find(COM_LIMIT_RATE_SEG) >= 0:
                print("COM_LIMIT_RATE_SEG exist! no need to replace.")
            else:
                print("replacement need to apply.")
                # config=config.replace(COM_CONF_SEG,COM_LIMIT_RATE_SEG) #容错性不足
                config = replace_seg_regex.sub(COM_LIMIT_RATE_SEG, config)
                # print(config)

        else:
            print("Custom config not exists")
            # 初次插入
            # 将 COM_COM_LIMIT_RATE_SEG 插入到INIT_INSERT_BEFORE_MARK 上一行
            config = config.replace(
                INIT_INSERT_BEFORE_MARK,
                init_as + "\n" + INIT_INSERT_BEFORE_MARK,
            )
    if replace:
        with open(vhost_config, "w") as f:
            f.write(config)

    return config


def get_young(site_birth_log=SITE_BIRTH_CSV):
    """
    计算年轻站点,待后续处理相应的配置文件

    Args:
        site_birth_log:网站创建日期记录文件


    """
    # 读取CSV文件
    df = pd.read_csv(site_birth_log)

    # 将birth_time列转换为datetime类型
    df["birth_time"] = pd.to_datetime(df["birth_time"])

    # 获取当前时间
    current_time = datetime.now()

    # 过滤出距离当前时间不超过DAYS天的行
    filtered_df = df[(current_time - df["birth_time"]).dt.days <= DAYS]

    # print(filtered_df)
    domains = filtered_df["domain"]
    domains = list(domains)
    return domains


def main():
    domains = get_young(SITE_BIRTH_CSV)
    vhost_confs = []
    for domain in domains:
        # 构造日志文件路径
        path = os.path.join(NGINX_VHOST_ROOT, domain) + ".conf"
        print(path)
        vhost_confs.append(path)

    for config in vhost_confs:
        young2old(config)


if __name__ == "__main__":
    main()
