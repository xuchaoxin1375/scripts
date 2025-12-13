import argparse
import os
import re
from datetime import datetime

import pandas as pd

# 如果当前的系统是windows,则使用以下常量
SITE_BIRTH_CSV = "/www/site_birth.csv"
SITE_TABLE_CONF = "/www/site_table.conf"
NGINX_VHOST_ROOT = "/www/server/panel/vhost/nginx"

if os.name == "nt":
    SITE_BIRTH_CSV = "./site_birth.csv"
    SITE_TABLE_CONF = "./site_table.conf"
    NGINX_VHOST_ROOT = "../nginx_vhost_config_demos/"


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


def set_config(vhost_config, switch_to="old", init_as="", replace=False):
    """新站转老站的配置修改
    可选:修改建站日期表中的行状态和更新日期字段

    参数:
        vhost_config: 虚拟主机配置文件
        switch_mode: 'old' or 'young'
        init_as: 对于未插入配置,视为老站配置还是新站配置(放空则取决于switch_mode)
        replace: 是否替换源文件
    """
    config = ""
    with open(vhost_config, "r", encoding="utf-8") as f:
        config = f.read()
        # print(config)
        # return config
        # 配置文件存在相关标记
        if config.find(CUSTOM_CONFIG_START) >= 0:  # -1表示不存在
            print(f"CUSTOM_CONFIG_START exist in [{vhost_config}] configuration.")

            if switch_to == "old":

                if config.find(COM_LIMIT_RATE_SEG) >= 0:
                    # 如果原配置已经存在目标配置,则不进行替换(尽量不动配置文件,检查并维护配置文件不意味着内容移动要变更)
                    print("COM_LIMIT_RATE_SEG exist! no need to replace.")
                else:
                    print("replacement need to apply. set to old.")
                    # print(config)

                    # config=config.replace(COM_CONF_SEG,COM_LIMIT_RATE_SEG) #容错性不足
                    config = replace_seg_regex.sub(COM_LIMIT_RATE_SEG, config)

                    # res_list=replace_seg_regex.findall(config)
                    # print(res_list)
            elif switch_to == "young":
                if config.find(COM_CONF_SEG) >= 0:
                    print("COM_CONF_SEG exist! no need to replace.")
                else:
                    print("replacement need to apply.set to young.")
                    config = replace_seg_regex.sub(COM_CONF_SEG, config)

        else:
            print("Custom config not exists")
            # 初次插入
            if init_as == "":
                if switch_to == "old":
                    init_as = COM_LIMIT_RATE_SEG
                elif switch_to == "young":
                    init_as = COM_CONF_SEG

            # 将 init_as 插入到INIT_INSERT_BEFORE_MARK 上一行
            config = config.replace(
                INIT_INSERT_BEFORE_MARK,
                init_as + "\n" + INIT_INSERT_BEFORE_MARK,
            )
    if replace:
        with open(vhost_config, "w", encoding="utf-8") as f:
            f.write(config)

    return config


def get_filtered(site_birth_log=SITE_BIRTH_CSV, mode="old", only_status_changed=True):
    """
    计算年轻站点,待后续处理相应的配置文件

    Args:
        site_birth_log:网站创建日期记录文件
        mode: 'young' or 'old'
        only_status_changed: 在基于建站日期满足指定模式外,还要求状态变更(比如从yong->old)作为附加过滤条件


    """
    # 读取CSV文件
    df = pd.read_csv(site_birth_log)

    # 将birth_time列转换为datetime类型
    df["birth_time"] = pd.to_datetime(df["birth_time"])

    # 获取当前时间
    current_time = datetime.now()

    # 过滤出合适的行

    # 替换原有的 if-elif 段落（第98~102行）
    # 使用 pd.Timestamp 统一时间类型，并缓存时间差以提高效率
    current_timestamp = pd.Timestamp.now()
    age_in_days = (current_timestamp - df["birth_time"]).dt.days  # type: ignore

    if mode == "old":
        filtered_df = df[age_in_days >= DAYS]
    elif mode == "young":
        filtered_df = df[age_in_days < DAYS]
    elif mode == "all":
        filtered_df = df
        # print(f"warning mode: {mode} is not common mode,all domain will be returned!")
    else:
        raise ValueError("Invalid mode. Expected 'young' or 'old'.")
        # filtered_df = df
    if only_status_changed and "status" in df.columns:
        filtered_df = filtered_df[filtered_df["status"] != mode]
    # print(filtered_df)
    domains = filtered_df["domain"]
    domains = list(domains)
    return domains


def update_sites_conf(mode="old", update_log=True, all_sites=False, dry_run=False):
    """
    根据指定的状态的站(old/young),将配置文件做对应状态的更新

    Args:
        mode: 将扫描出的待更新站点(配置)更新到'young' or 'old'模式
        update_log: 是否更新建站日期表
        all_sites: 是否更新所有站点到mode所指的模式
        dry_run: 预览模式，仅打印将被处理的站点和配置文件，不做实际修改
    """
    if all_sites:
        domains = get_filtered(SITE_BIRTH_CSV, mode="all")
    else:
        domains = get_filtered(SITE_BIRTH_CSV, mode=mode)
    vhost_confs = []
    for domain in domains:
        path = os.path.join(NGINX_VHOST_ROOT, domain) + ".conf"
        vhost_confs.append(path)

    if dry_run:
        print(f"将处理的站点({len(domains)}):", ", ".join(domains))
        for path in vhost_confs:
            print(f"配置文件: {path}")
        return

    df = None
    if update_log:
        current_time = datetime.now()
        df = pd.read_csv(SITE_BIRTH_CSV)
        # 更新状态和更新时间字段
        df.loc[df["domain"].isin(domains), "update_time"] = current_time
        df.loc[df["domain"].isin(domains), "status"] = mode

    for config in vhost_confs:
        set_config(vhost_config=config, switch_to=mode, replace=True)

    if update_log and df is not None:
        df.to_csv(SITE_BIRTH_CSV, index=False)


def parse_args():
    """
    设置和解析命令行参数
    """
    parser = argparse.ArgumentParser(
        description="批量更新nginx虚拟主机配置文件为新站/老站模式，并可同步更新建站日期表状态。"
    )
    parser.add_argument(
        "-m",
        "--mode",
        choices=["old", "young"],
        default="old",
        help="目标模式: old(老站) 或 young(新站)，默认old",
    )
    parser.add_argument(
        "-n",
        "--no-log",
        action="store_true",
        help="不更新建站日期表(status/update_time)",
    )
    parser.add_argument(
        "-a",
        "--all-sites",
        action="store_true",
        help="对所有站点强制切换到目标模式(不区分当前状态)",
    )
    parser.add_argument(
        "-d", "--days", type=int, default=DAYS, help=f"新老站天数阈值(默认{DAYS}天)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="仅打印将被处理的站点和配置文件,不做实际修改",
    )
    return parser.parse_args()


def main():
    """主函数"""
    args = parse_args()
    update_sites_conf(
        mode=args.mode,
        update_log=not args.no_log,
        all_sites=args.all_sites,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
