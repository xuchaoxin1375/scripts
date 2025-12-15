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
        # 移除域名重复的行
        df.drop_duplicates(subset=["domain"], keep=keep)
    df.to_csv(site_birth_log, index=False)
    print(f"{df}")

    # 将表格文件备份(重命名的方式)
    ## 移除旧备份文件(如果存在的话),防止多次检查域名列表而反复向建站记录表添加重复域名的记录(不过有去重处理,现在这是可选的)
    if os.path.exists(SITE_TABLE_BAK):
        os.remove(SITE_TABLE_BAK)
    os.rename(site_table, SITE_TABLE_BAK)

    # 创建一个新的站点列表文件site_table,包含一句注释提醒:此域名列表已经处理并清空.
    reset_message = f"# 此域名列表已在 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} 处理并清空。\
    上一轮操作的备份文件路径[{SITE_TABLE_BAK}] \n请将新的待处理域名列表添加到此处。\n"
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

    # 将birth_time列转换为datetime类型
    df["birth_time"] = pd.to_datetime(df["birth_time"])
    df["domain"] = df["domain"].str.strip()
    # 移除域名字段为空的行
    df = df[df["domain"].notna() & (df["domain"] != "")]

    # 获取当前时间
    # current_time = datetime.now()

    # 过滤出合适的行

    # 替换原有的 if-elif 段落（第98~102行）
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
    all_sites=False,
    only_status_changed=True,
    dry_run=False,
    days=DAYS,
    remove_blank_lines=True,
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
    print(f"域名列表预览:{domains}")
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
        # 更新状态和更新时间字段
        df.loc[df["domain"].isin(domains), "update_time"] = current_time
        df.loc[df["domain"].isin(domains), "status"] = mode
    for config in vhost_confs:
        set_config(
            vhost_config=config,
            switch_to=mode,
            replace=True,
            remove_blank_lines=remove_blank_lines,
        )

    if update_log and df is not None:
        df.to_csv(site_birth_log, index=False)


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
    else:
        print("未知命令，请使用 --help 查看用法。")


if __name__ == "__main__":
    main()
