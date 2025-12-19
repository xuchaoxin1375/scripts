"""更新nginx站的配置文件(vhost中的conf文件)"""

import argparse
import os
import re
from datetime import datetime

import pandas as pd
from pandas._typing import DropKeep

# 如果当前的系统是windows,则使用以下常量
SITE_BIRTH_CSV = "/www/site_birth.csv"
SITE_TABLE_CONF = "/www/site_table.conf"
NGINX_VHOST_ROOT = "/www/server/panel/vhost/nginx"
BACKUP_DIR = "/www/site_tables"
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
DAYS = 14  # 可根据需要调整

# csv表头
TABLE_HEADER = ("domain", "birth_time", "status", "update_time")
INIT_STATUS = "young"
now = datetime.now()

# 标准日期-时间格式 YYYY-MM-DD HH:MM:SS (时间(时分秒对于此任务不重要,可以仅仅保留日期(年月日)))
dt = now.strftime("%Y-%m-%d %H:%M:%S")
datetime_forfilename = now.strftime("%Y-%m-%d--%H%M%S")

os.makedirs(BACKUP_DIR, exist_ok=True)
SITE_TABLE_BAK = f"{BACKUP_DIR}/site_table.conf.bak.{datetime_forfilename}"


def get_main_domain_name_from_str(url, normalize=True):
    """
        从字符串中提取域名,结构形如 "二级域名.顶级域名",即SLD.TLD;
        对于提取部分的正则,如果允许英文"字母,-,数字")(对于简单容忍其他字符的域名,使用([^/]+)代替([\\w]+)这个部分

        仅提取一个域名,适合于对于一个字符串中仅包含一个确定的域名的情况
        例如,对于更长的结构,"子域名.二级域名.顶级域名"则会丢弃子域名,前缀带有http(s)的部分也会被移除

        Args:
            url (str): 待处理的URL字符串
            normalize (bool, optional): 是否进行规范化处理(移除空格,并且将字母小写化处理). Defaults to True.


        Examples:
# 测试URL列表
urls = [
    "www.domain1.com",
    "domain--name.com",
    "https://www.dom-ain2.com",
    "https://sports.whh3.cn.com",
    "domain-test4.com",
    "http://domain5.com",
    "https://domain6.com/",
    "# https://domain7.com",
    "http://",
    "https://www8./",
    "https:/www9",
]
for url in urls:
    domain = get_main_domain_name_from_str(url)
    print(domain)

# END
    """
    # 使用正则表达式提取域名
    url = str(url)
    # 清理常见的无效url部分
    url = re.sub(r"https?:/*w*\.?/?", "", url)
    # 尝试提取英文域名(注意,\w匹配数字,字母,下划线,但不包括中划线,而域名中允许,因此这里使用[-\w+]表示域名中的可能的字符(小数点.比较特殊,单独处理)
    match = re.search(r"(?:https?://)?(?:www\.)?(([-\w+]+\.)+[-\w+]+)/?", url)
    if match:
        res = match.group(1).strip("/")
        if normalize:
            # 字母小写并且移除空白
            res = re.sub(r"\s+", "", res).lower()
        return res
    return ""



def init_site_birth_log(site_birth_log=SITE_BIRTH_CSV, table_header=TABLE_HEADER):
    """
    检查网站创建日期日志文件(csv)是否存在,如果不存在,则创建此文件,表头为domain,birth_time
    """

    if os.path.exists(site_birth_log) is False:
        print("日志文件不存在,创建模板日志文件(csv)...")
        df = pd.DataFrame(columns=table_header)
        df.to_csv(site_birth_log, index=False)
    else:
        # 检查此文件是否为非空文本文件
        print("日志文件存在,检查是否为空...")
        if os.path.getsize(site_birth_log) > 0:
            print("日志文件存在,读取站点创建日期...")
            df = pd.read_csv(site_birth_log)
        else:
            print("日志文件为空,初始化表头...")
            df = pd.DataFrame(columns=table_header)
    # print(f"各个字段类型{df.dtypes}")
    return df


def maintain_site_birth_log(
    site_birth_log=SITE_BIRTH_CSV,
    site_table=SITE_TABLE_CONF,
    drop_duplicate=True,
    keep: DropKeep = "first",
):
    """维护csv文件

    Args:
        drop_duplicate (bool, optional): 是否删除重复项. Defaults to True.
        keep (str, optional): 保留重复项中的哪一个. Defaults to 'first'.
            可用选项和pandas.DataFrame的drop_duplicates()方法一致
            first,last,False
    """
    df = init_site_birth_log(site_birth_log, TABLE_HEADER)
    site_birth_lines = []
    # 参数检查
    print(f"drop_duplicated={drop_duplicate}")
    print(f"keep={keep}")
    # 检查文件是否存在
    if os.path.exists(site_table) is False:
        print(f"域名列表文件不存在:{site_table},结束操作.")
        return False

    try:
        with open(site_table, mode="r", encoding="utf-8") as f:
            lines = f.readlines()
            # print(lines)
            for line in lines:
                # skip comments or empty lines
                if re.match(r"^\s*(#|$)", line):
                    print(f"skip line:{line.strip()}")
                    continue

                # try to extract domain; ensure match is found before using groups()
                domain_match = re.match(
                    r"^\s*(?:https?://\w*\.)?(?P<domain>[\w.-]+)", line
                )
                if not domain_match:
                    print(f"no domain found in line, skip: {line.strip()}")
                    continue

                domain = domain_match.group("domain").strip()
                # 构造用于插入csv的字典
                site_dict = {
                    "domain": domain,
                    "birth_time": dt,
                    "status": INIT_STATUS,
                    "update_time": dt,
                }
                site_birth_lines.append(site_dict)
    except (FileNotFoundError, PermissionError) as e:
        print(f"读取域名列表文件失败: {e}")
        return False

    print(f"site_birth_lines:{site_birth_lines}")
    df = pd.concat([df, pd.DataFrame(site_birth_lines)], ignore_index=True)
    if drop_duplicate:
        print("移除域名重复的行...")
        df.drop_duplicates(subset=["domain"], keep=keep, inplace=True)
    df.to_csv(site_birth_log, index=False)
    print(f"{df}")

    # 将表格文件备份(重命名的方式)
    ## 移除旧备份文件(如果存在的话),防止多次检查域名列表而反复向建站记录表添加重复域名的记录(不过有去重处理,现在这是可选的)
    if os.path.exists(SITE_TABLE_BAK):
        os.remove(SITE_TABLE_BAK)
    os.rename(site_table, SITE_TABLE_BAK)

    # 创建一个新的站点列表文件site_table,包含一句注释提醒:此域名列表已经处理并清空.
    reset_message = f"# 此域名列表已在 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} 处理并清空。\
    上一轮操作的备份文件路径[{SITE_TABLE_BAK}] \n# 请将新的待处理域名列表添加/覆盖到此处。\n"
    try:
        with open(site_table, mode="w", encoding="utf-8") as f:
            f.write(reset_message)
        print(f"已创建新的空站点列表文件: {site_table}")
    except (FileNotFoundError, PermissionError) as e:
        print(f"警告: 创建新的站点列表文件失败: {e}")
    return True
    # os.system(f"cp {site_table} {SITE_TABLE_BAK}")


def set_config(
    vhost_config, switch_to="old", init_as="", replace=False, remove_blank_lines=True
):
    """新站转老站的配置修改
    可选:修改建站日期表中的行状态和更新日期字段
    移除多余空行,避免大量空白

    参数:
        vhost_config: 虚拟主机配置文件
        switch_mode: 'old' or 'young'
        init_as: 对于未插入配置,视为老站配置还是新站配置(放空则取决于switch_mode)
        replace: 是否替换源文件
    """
    config = ""
    try:
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
            # 移除多余空行(将两个以上连续的空行(兼容中间夹杂其他空白字符的情况)简化为2个空行,避免大量空白)
            if remove_blank_lines:
                print(f"Remove redundant blank lines.")
                config = re.sub(r"\n(\s*\n)+", "\n\n", config)
    except (FileNotFoundError, PermissionError) as e:
        print(f"读取配置文件失败(跳过处理此条目): {e}")
        return None
    if replace and config is not None:
        try:
            with open(vhost_config, "w", encoding="utf-8") as f:
                f.write(config)
        except (FileNotFoundError, PermissionError) as e:
            print(f"写入配置文件失败: {e}")

    return config


def complete_columns(df, log_file=SITE_BIRTH_CSV):
    """判断:如果df包含字段domain,但是不包含TABLE_HEADER中的其他字段,则给出警告,并尝试补全这些字段(默认填写空值)"""
    if "domain" in df.columns and set(df.columns) != set(TABLE_HEADER):
        print(
            f"警告: 文件[{log_file}]中存在domain字段,但其余字段不完整,尝试补全({TABLE_HEADER})..."
        )
        df = df.reindex(columns=TABLE_HEADER)
        # df.fillna("", inplace=True)
        # print(df)
    return df


def get_filtered(
    site_birth_log=SITE_BIRTH_CSV, mode="old", only_status_changed=True, days=DAYS
):
    """
    计算年轻站点,待后续处理相应的配置文件
    记得移除处理domain字段为空的行,避免造成错误(健壮性)

    Args:
        site_birth_log:网站创建日期记录文件
        mode: 'young' or 'old'
        only_status_changed: 在基于建站日期满足指定模式外,还要求状态变更(比如从yong->old)作为附加过滤条件
        days: 默认为DAYS
    """
    # 读取CSV文件
    df = pd.read_csv(site_birth_log)
    df = complete_columns(df, log_file=site_birth_log)
    # # 判断:如果df包含字段domain,但是不包含TABLE_HEADER中的其他字段,则给出警告,并尝试补全这些字段(默认填写空值)
    # if "domain" in df.columns and set(df.columns) != set(TABLE_HEADER):
    #     print(
    #         f"警告: 日志文件[{site_birth_log}]中存在domain字段,但其余字段不完整,尝试补全({TABLE_HEADER})..."
    #     )
    #     df = df.reindex(columns=TABLE_HEADER)
    #     # df.fillna("", inplace=True)
    #     print(df)

    # 移除domain字段中包含http(s)的部分,只保留域名部分
    df["domain"] = df["domain"].apply(get_main_domain_name_from_str)
    # 统一日期格式
    df["birth_time"] = pd.to_datetime(df["birth_time"], format="mixed", errors="coerce")
    df["birth_time"] = df["birth_time"].dt.strftime("%Y-%m-%d %H:%M:%S")  # type: ignore

    # 将birth_time列转换为datetime类型
    df["birth_time"] = pd.to_datetime(df["birth_time"])
    # 查看日期处理后的结果
    print(df)
    df["domain"] = df["domain"].str.strip()
    # 移除域名字段为空的行
    df = df[df["domain"].notna() & (df["domain"] != "")]

    # 获取当前时间
    # current_time = datetime.now()

    # 过滤出合适的行

    # 使用 pd.Timestamp 统一时间类型，并缓存时间差以提高效率
    current_timestamp = pd.Timestamp.now()
    age_in_days = (current_timestamp - df["birth_time"]).dt.days  # type: ignore

    if mode == "old":
        filtered_df = df[age_in_days >= days]
    elif mode == "young":
        filtered_df = df[age_in_days < days]
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


def update_sites_conf(
    site_birth_log=SITE_BIRTH_CSV,
    nginx_vhost_root=NGINX_VHOST_ROOT,
    mode="old",
    update_log=True,
    format_time=True,
    all_sites=False,
    only_status_changed=True,
    dry_run=False,
    days=DAYS,
    remove_vhosts_conf_blank_lines=True,
):
    """
    根据指定的状态的站(old/young),将配置文件做对应状态的更新

    Args:
        mode: 将扫描出的待更新站点(配置)更新到'young' or 'old'模式
        update_log: 是否更新建站日期表
        all_sites: 是否更新所有站点到mode所指的模式
        dry_run: 预览模式，仅打印将被处理的站点和配置文件，不做实际修改
    """
    if all_sites:
        domains = get_filtered(site_birth_log=site_birth_log, mode="all", days=days)
    else:
        domains = get_filtered(
            site_birth_log,
            mode=mode,
            only_status_changed=only_status_changed,
            days=days,
        )
    print(f"处理模式:({mode})")
    print(f"本次处理域名列表预览:{domains}")
    # return False
    vhost_confs = []
    for domain in domains:
        path = os.path.join(nginx_vhost_root, domain) + ".conf"
        vhost_confs.append(path)

    if dry_run:
        print(f"[preview]将处理的站点({len(domains)}):", ", ".join(domains))
        for path in vhost_confs:
            print(f"[preview]配置文件: {path}")
        return

    df = None
    if update_log:
        current_time = datetime.now()
        df = pd.read_csv(site_birth_log)
        df = complete_columns(df, log_file=site_birth_log)
        # 兼容domain字段为url的情况
        df["domain"] = df["domain"].apply(get_main_domain_name_from_str)
        # 更新状态和更新时间字段(注意列字段类型处理)

        if "status" in df.columns:
            df["status"] = df["status"].astype("string")
            df.loc[df["domain"].isin(domains), "status"] = mode
        if "update_time" in df.columns:
            df["update_time"] = df["update_time"].astype("object")
            # df.loc[df["domain"].isin(domains), "update_time"] = current_time.strftime("%Y-%m-%d %H:%M:%S")
            df.loc[df["domain"].isin(domains), "update_time"] = current_time
    for config in vhost_confs:
        set_config(
            vhost_config=config,
            switch_to=mode,
            replace=True,
            remove_blank_lines=remove_vhosts_conf_blank_lines,
        )

    if update_log and df is not None:
        # 移除df中的空行或不规范的行(缺少域名字段值的行)
        df = df[df["domain"].notna() & (df["domain"] != "")]
        if format_time:
            # 确保保存到 CSV 之前日期格式是统一的字符串
            if "birth_time" in df.columns:
                df["birth_time"] = pd.to_datetime(
                    df["birth_time"], format="mixed"
                ).dt.strftime("%Y-%m-%d %H:%M:%S")
        df.to_csv(site_birth_log, index=False)

    print(f"更新完成, 共处理了 {len(domains)} 个站点。")


def parse_args():
    """
    设置和解析命令行参数，支持子命令: maintain, update
    """
    parser = argparse.ArgumentParser(
        description="nginx站点配置批量管理工具: 维护日志或批量更新nginx虚拟主机配置文件。"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    # 公共/全局配置项
    parser.add_argument(
        "-c",
        "--csv",
        "--site-birth-log",
        default=SITE_BIRTH_CSV,
        help=f"站点建站日期表(默认{SITE_BIRTH_CSV})",
    )
    parser.add_argument(
        "-l",
        "--site-table",
        "--site-list",
        "--domain-list",
        default=SITE_TABLE_CONF,
        help=f"新站批次的网站域名列表(默认{SITE_TABLE_CONF})",
    )
    parser.add_argument(
        "-v",
        "--workdir",
        "--nginx-vhost-root",
        default=NGINX_VHOST_ROOT,
        help="nginx虚拟主机配置文件根目录",
    )
    parser.add_argument(
        "--domain-backup-dir",
        default=BACKUP_DIR,
        help="域名列表备份到指定目录(默认{BACKUP_DIR})",
    )
    # maintain 子命令
    parser_maintain = subparsers.add_parser(
        "maintain", help="维护站点创建日志文件(site_birth.csv)"
    )
    parser_maintain.add_argument(
        "-d",
        "--drop-duplicate",
        action="store_true",
        help="删除重复项(默认保留第一个)",
    )
    parser_maintain.add_argument(
        "-k",
        "--keep",
        choices=["first", "last"],
        default="first",
        help="保留重复项中的哪一个(默认first)",
    )

    # update 子命令
    parser_update = subparsers.add_parser(
        "update",
        help="批量更新nginx虚拟主机配置文件为新站/老站模式，并可同步更新建站日期表状态。",
    )
    parser_update.add_argument(
        "-m",
        "--mode",
        choices=["old", "young"],
        default="old",
        help="目标模式: old(老站) 或 young(新站)，默认old",
    )
    parser_update.add_argument(
        "-q",
        "--only-status-changed",
        action="store_true",
        help="仅当计算出来的状态和原日志中的状态不一致时才处理",
    )
    parser_update.add_argument(
        "-n",
        "--no-update-log",
        action="store_true",
        help="不更新建站日期表(status/update_time)",
    )
    parser_update.add_argument(
        "-a",
        "--all-sites",
        action="store_true",
        help="对所有站点强制切换到目标模式(不区分当前状态)",
    )
    parser_update.add_argument(
        "-d", "--days", type=int, default=DAYS, help=f"新老站天数阈值(默认{DAYS}天)"
    )
    parser_update.add_argument(
        "--dry-run",
        action="store_true",
        help="仅打印将被处理的站点和配置文件,不做实际修改",
    )
    return parser.parse_args()


def main():
    """主函数，支持子命令"""
    args = parse_args()
    if args.command == "maintain":
        if args.drop_duplicate:
            maintain_site_birth_log(
                site_birth_log=args.csv,
                site_table=args.site_table,
                drop_duplicate=args.drop_duplicate,
                keep=args.keep,
            )
        else:
            maintain_site_birth_log(site_birth_log=args.csv, site_table=args.site_table)

    elif args.command == "update":
        print(f">开始时间:{datetime.now()}")
        update_sites_conf(
            site_birth_log=args.csv,
            nginx_vhost_root=args.workdir,
            mode=args.mode,
            update_log=not args.no_update_log,
            all_sites=args.all_sites,
            dry_run=args.dry_run,
            only_status_changed=args.only_status_changed,
            days=args.days,
        )
        print(f">结束时间:{datetime.now()}\n")
    else:
        print("未知命令，请使用 --help 查看用法。")


if __name__ == "__main__":
    main()
