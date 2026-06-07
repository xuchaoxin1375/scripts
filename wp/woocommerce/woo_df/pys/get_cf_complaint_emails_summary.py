""" 
导出cloudflare的投诉信
信件来源: abuse@notify.cloudflare.com  (主要过滤条件)
标题关键词: complaint
将相关信件导出为eml文件到本地某个文件夹中,将此脚本放在同一文件夹中运行,会自动扫描所有eml文件并提取相关信息生成Excel表格

相关邮箱可以转发到163邮箱,然后再163邮箱中批量下载eml文件到本地,再运行此脚本进行处理

"""
import os
import re
import email
from email import policy
from email.parser import BytesParser
from datetime import datetime
import pandas as pd


def extract_text_and_headers(file_path):
    """读取 eml 文件，返回纯文本内容和邮件头对象"""
    try:
        with open(file_path, "rb") as f:
            msg = BytesParser(policy=policy.default).parse(f)

        body = ""
        if msg.is_multipart():
            for part in msg.iter_parts():
                if part.get_content_type() == "text/plain":
                    body = part.get_content()
                    break
            if not body:
                body_part = msg.get_body(preferencelist=("plain", "html"))
                if body_part:
                    body = body_part.get_content()
        else:
            body = msg.get_content()

        return str(body), msg
    except Exception as e:
        print(f"读取错误 {file_path}: {e}")
        return None, None


def get_email_date(msg):
    """从邮件头提取日期并格式化"""
    try:
        date_header = msg.get("Date")
        if not date_header:
            return None

        parsed_date = email.utils.parsedate_to_datetime(date_header)
        return parsed_date.strftime("%Y-%m-%d %H:%M")
    except Exception:
        return None


def get_report_id_from_filename(filename):
    """从文件名提取报告 ID，格式如 [09a91759f94f7133]_..."""
    match = re.search(r"\[([a-zA-Z0-9]+)\]", filename)
    if match:
        return match.group(1)
    return None


def clean_domain(raw_domain):
    """清洗域名：还原混淆字符，移除协议，截断非法字符，去除首尾点号"""
    if not raw_domain:
        return None

    # 1. 还原混淆字符 [.] -> .
    domain = raw_domain.replace("[.]", ".")

    # 2. 移除协议头
    domain = re.sub(r"^h?xxps?://", "", domain)

    # 3. 只保留合法的域名字符
    match = re.match(r"^([a-zA-Z0-9\-\.]+)", domain)
    if match:
        domain = match.group(1)

    # 4. 去除多余部分
    domain = domain.strip("www").strip(".")

    return domain if domain else None


def parse_cloudflare_email(text, filename, msg_headers):
    """解析邮件内容，提取所有关键字段"""
    if not text:
        return None

    data = {
        "domain": None,
        "complainant": None,
        "report_id": None,
        "case_type": "Unknown",
        "copyright_holder": None,
        "company_name": None,
        "received_date": get_email_date(msg_headers),
    }

    # --- 1. 识别案件类型 (动态提取) ---
    # 匹配 "Cloudflare received an [TYPE] complaint regarding"
    # 使用非贪婪匹配 (.+?) 捕获中间的类型描述
    type_match = re.search(
        # r"Cloudflare received an\s+(.+?)\s+(complaint|report) regarding", text, re.IGNORECASE
        r"Cloudflare received an?\s+(.+?)\s+regarding", text, re.IGNORECASE
    )

    if type_match:
        raw_type = type_match.group(1).strip()
        # 规范化大小写：每个单词首字母大写 (例如：trademark infringement -> Trademark Infringement)
        data["case_type"] = raw_type.title()
    else:
        data['case_type'] = 'unkown'
        # 如果正则没匹配到， fallback 到简单的关键词判断
        # if 'Trademark' in text:
        #     data['case_type'] = 'Trademark Infringement'
        # elif 'DMCA' in text or 'Copyright' in text:
        #     data['case_type'] = 'DMCA Copyright'
        # else:
        #     data['case_type'] = 'General/Other'

    # --- 2. 提取 Report ID (双重来源) ---
    id_match = re.search(r"Report ID:\s*([a-zA-Z0-9]+)", text)
    if id_match:
        data["report_id"] = id_match.group(1)
    else:
        file_id = get_report_id_from_filename(filename)
        if file_id:
            data["report_id"] = file_id

    # --- 3. 提取域名 ---
    domain = None

    # 策略 A: "regarding: ..."
    regarding_match = re.search(r"regarding:\s*([a-zA-Z0-9\[\]\.\-]+)", text)
    if regarding_match:
        domain = clean_domain(regarding_match.group(1))

    # 策略 B: "Reported URLs"
    if not domain:
        urls_section = re.search(
            r"Reported URLs:\s*\n(.*?)(?:\n\n|\nOriginal Work|\nBelow are)",
            text,
            re.DOTALL,
        )
        if urls_section:
            first_line = urls_section.group(1).strip().split("\n")[0]
            url_match = re.search(r"h?xxps?://([a-zA-Z0-9\[\]\.\-]+)", first_line)
            if url_match:
                domain = clean_domain(url_match.group(1))

    data["domain"] = domain

    # --- 4. 提取投诉方信息 (兼容 Submitter's 和 Reporter's) ---
    prefix_pattern = r"(?:Submitter|Reporter)"

    complainant = None
    name_match = re.search(rf"{prefix_pattern}'s Name:\s*(.+?)\n", text)
    if name_match:
        complainant = name_match.group(1).strip()

    copyright_holder = None
    ch_match = re.search(r"(Copyright Holder's Name|Trademarked Symbol):\s*(.+?)\n", text)
    if ch_match:
        copyright_holder = ch_match.group(2).strip()

    company_name = None
    comp_match = re.search(rf"{prefix_pattern}'s Company Name:\s*(.+?)\n", text)
    if comp_match:
        company_name = comp_match.group(1).strip()

    data["copyright_holder"] = copyright_holder
    data["company_name"] = company_name

    # 确定主投诉人显示列
    if complainant:
        data["complainant"] = complainant
    elif company_name:
        data["complainant"] = company_name
    elif copyright_holder:
        data["complainant"] = copyright_holder
    else:
        data["complainant"] = "Unknown"

    if data["domain"]:
        return data

    return None


def main():
    target_dir = "."
    output_excel = "Cloudflare_Abuse_Data_Final.xlsx"

    print(f"🔍 正在扫描目录: {os.path.abspath(target_dir)}")

    all_records = []
    failed_files = []

    eml_files = [f for f in os.listdir(target_dir) if f.lower().endswith(".eml")]

    if not eml_files:
        print("❌ 未找到任何 .eml 文件。")
        return

    print(f"📂 发现 {len(eml_files)} 个邮件文件，开始解析...")

    for filename in eml_files:
        file_path = os.path.join(target_dir, filename)
        text, msg_headers = extract_text_and_headers(file_path)

        if text and msg_headers:
            result = parse_cloudflare_email(text, filename, msg_headers)
            if result:
                record = {
                    "收件日期": result.get("received_date", ""),
                    "被投诉域名": result.get("domain", ""),
                    "投诉人/提交者": result.get("complainant", ""),
                    "案件类型": result.get("case_type", ""),
                    "版权持有者 (DMCA)": result.get("copyright_holder", ""),
                    "公司名称 (DMCA)": result.get("company_name", ""),
                    "报告 ID": result.get("report_id", ""),
                    "源文件名": filename,
                }
                all_records.append(record)
            else:
                failed_files.append(filename)
        else:
            failed_files.append(filename)

    if not all_records:
        print("⚠️ 未能从任何邮件中提取到域名信息。")
        return

    df = pd.DataFrame(all_records)

    cols_order = [
        "收件日期",
        "被投诉域名",
        "投诉人/提交者",
        "案件类型",
        "版权持有者 (DMCA)",
        "公司名称 (DMCA)",
        "报告 ID",
        "源文件名",
    ]
    df = df[cols_order]

    # 按收件日期倒序排列
    df = df.sort_values(by="收件日期", ascending=False)

    print(f"💾 正在生成表格: {output_excel} ...")

    with pd.ExcelWriter(output_excel, engine="openpyxl") as writer:
        df.to_excel(writer, sheet_name="提取数据清单", index=False)

        # 自动调整列宽
        worksheet = writer.sheets["提取数据清单"]
        for column in worksheet.columns:
            max_length = 0
            column_letter = column[0].column_letter
            for cell in column:
                try:
                    val_len = len(str(cell.value)) if cell.value is not None else 0
                    if val_len > max_length:
                        max_length = val_len
                except:
                    pass
            adjusted_width = min(max_length + 2, 60)
            worksheet.column_dimensions[column_letter].width = adjusted_width

    print("\n" + "=" * 40)
    print("✅ 处理完成！")
    print("=" * 40)
    print(f"📊 成功提取记录数：{len(all_records)}")
    print(f"⚠️  跳过/失败文件数：{len(failed_files)}")

    if failed_files:
        print(f"   (示例: {', '.join(failed_files[:3])})")

    print("\n📋 数据预览 (前 5 行):")
    print(df.head(5).to_string(index=False))

    print(f"\n📁 文件已保存至: {os.path.abspath(output_excel)}")
    print("   💡 提示：案件类型已从邮件正文动态提取 (如 'Trademark Infringement')。")


if __name__ == "__main__":
    main()
