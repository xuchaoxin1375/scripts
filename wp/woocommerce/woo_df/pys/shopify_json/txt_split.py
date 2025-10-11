import concurrent.futures
import math
import os
import random
import urllib.parse

import pandas as pd
from config import *


# ✅ 统计 txt 行数（非空）
def count_lines(file_path):
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return sum(1 for line in f if line.strip())
    except Exception as e:
        print(f"❌ 读取失败: {file_path} - {e}")
        return 0


# ✅ 递归扫描目录，生成 txt_list.xlsx
def generate_txt_excel_list(
    root_folder, output_excel="txt_list.xlsx", default_lines_per_file=100
):
    txt_records = []

    for dirpath, _, filenames in os.walk(root_folder):
        for filename in filenames:
            if filename.lower().endswith(".txt"):
                full_path = os.path.normpath(
                    os.path.abspath(os.path.join(dirpath, filename))
                )
                line_count = count_lines(full_path)
                txt_records.append(
                    {
                        "txt_file": full_path,
                        "total_lines": line_count,
                        "lines_per_file": default_lines_per_file,
                    }
                )

    if not txt_records:
        print("⚠️ 没有找到任何 .txt 文件")
        return

    df = pd.DataFrame(txt_records)
    df.to_excel(output_excel, index=False)
    print(f"✅ 已生成文件清单: {output_excel}，共 {len(df)} 个文件")


# ✅ 分割单个 TXT 文件
def split_txt_by_line_count(input_file, lines_per_file):
    base_name = os.path.splitext(os.path.basename(input_file))[0]
    folder = os.path.dirname(os.path.abspath(input_file))

    try:
        with open(input_file, "r", encoding="utf-8") as f:
            lines = [line for line in f if line.strip()]
    except FileNotFoundError:
        print(f"❌ 文件未找到: {input_file}")
        return []

    if not lines:
        print(f"⚠️ 文件为空: {input_file}")
        return []

    total_lines = len(lines)
    random.shuffle(lines)

    total_parts = math.ceil(total_lines / lines_per_file)
    all_output_lines = []
    output_files = []

    avg_lines = lines_per_file

    for i in range(total_parts):
        start = i * avg_lines
        end = start + avg_lines
        chunk = lines[start:end]
        output_file = os.path.join(folder, f"{base_name}_{i+1}.txt")
        with open(output_file, "w", encoding="utf-8") as f_out:
            f_out.writelines(chunk)
        print(f"✅ 写入 {output_file}，共 {len(chunk)} 行")
        all_output_lines.extend(chunk)

        output_files.append(
            {
                "input_file": input_file,
                "output_file": output_file,
                "part": i + 1,
                "lines": len(chunk),
            }
        )

    # ✅ 检查最后一个文件是否少于 1/2，合并进前面
    if len(output_files) >= 2 and output_files[-1]["lines"] < avg_lines // 2:
        leftover = all_output_lines[-output_files[-1]["lines"] :]
        last_file = output_files[-1]["output_file"]
        output_files.pop()
        os.remove(last_file)

        # 计算每个文件应该分配的额外行数
        distribute_count = len(leftover) // len(output_files)
        remainder = len(leftover) % len(output_files)

        print(
            f"\nℹ️ 最后一个小文件 ({len(leftover)} 行) 已合并到前面 {len(output_files)} 个文件中"
        )

        # 更新文件并记录新的行数
        for i, file_info in enumerate(output_files):
            path = file_info["output_file"]
            extra_lines = distribute_count + (1 if i < remainder else 0)
            start_idx = i * distribute_count + min(i, remainder)
            end_idx = start_idx + extra_lines

            with open(path, "a", encoding="utf-8") as f_out:
                extra = leftover[start_idx:end_idx]
                f_out.writelines(extra)

            # 更新文件信息中的行数
            file_info["lines"] += extra_lines

        print("\n✅ 最终文件情况:")
        for file_info in output_files:
            print(
                f"   {os.path.basename(file_info['output_file'])}，共 {file_info['lines']} 行"
            )

    return output_files


# ✅ 从 txt_list.xlsx 批量分割 TXT 文件
def batch_split_by_line_count(excel_file, output_excel_file):
    try:
        df = pd.read_excel(excel_file)
    except Exception as e:
        print(f"❌ 无法读取 Excel 文件: {e}")
        return

    if "txt_file" not in df.columns or "lines_per_file" not in df.columns:
        print("❌ Excel 缺少必需的列：txt_file / lines_per_file")
        return

    all_output_records = []

    with concurrent.futures.ThreadPoolExecutor() as executor:
        futures = []
        for _, row in df.iterrows():
            input_file = str(row["txt_file"]).strip()
            try:
                lines_per_file = int(row["lines_per_file"])
            except:
                print(f"⚠️ 无效行数: {row['lines_per_file']} 跳过")
                continue

            if not input_file or lines_per_file <= 0:
                print(f"⚠️ 跳过无效配置: {row}")
                continue

            futures.append(
                executor.submit(split_txt_by_line_count, input_file, lines_per_file)
            )

        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result:
                all_output_records.extend(result)

    if all_output_records:
        out_df = pd.DataFrame(all_output_records)
        out_df.to_excel(output_excel_file, index=False)
        print(f"✅ 所有文件已写入 Excel: {output_excel_file}")
    else:
        print("⚠️ 无分割结果输出")


# ✅ 文件名 URL 解码


def url_decode_rename_files(root_folder):
    for dirpath, _, filenames in os.walk(root_folder):
        for filename in filenames:
            decoded_name = urllib.parse.unquote(filename)
            if decoded_name != filename:
                old_path = os.path.join(dirpath, filename)
                new_path = os.path.join(dirpath, decoded_name)
                try:
                    os.rename(old_path, new_path)
                    print(f"✅ 文件重命名: {filename} → {decoded_name}")
                except Exception as e:
                    print(f"❌ 重命名失败: {filename} - {e}")


# ✅ txt 内容 URL 解码


def url_decode_txt_contents(root_folder):
    for dirpath, _, filenames in os.walk(root_folder):
        for filename in filenames:
            if filename.lower().endswith(".txt"):
                full_path = os.path.join(dirpath, filename)
                try:
                    with open(full_path, "r", encoding="utf-8") as f:
                        lines = f.readlines()
                    decoded_lines = [urllib.parse.unquote(line) for line in lines]
                    with open(full_path, "w", encoding="utf-8") as f:
                        f.writelines(decoded_lines)
                    print(f"✅ 内容解码: {filename}")
                except Exception as e:
                    print(f"❌ 内容解码失败: {filename} - {e}")


# ✅ 一键执行扫描 + 分割
def run_all(scan_root, excel_input, excel_output):
    generate_txt_excel_list(scan_root, excel_input, default_lines_per_file=50000)
    batch_split_by_line_count(excel_input, excel_output)


# ✅ 主程序：交互入口
if __name__ == "__main__":
    scan_root = rf"{JSON_DIR}"
    excel_input = "txt_list.xlsx"
    excel_output = "txt_name.xlsx"

    print("请选择操作：")
    print("1 = 执行文件名 URL 解码 + TXT 文件内容解码")
    print("2 = 扫描目录，生成 txt_list.xlsx")
    print("3 = 按 Excel 配置分割文件并输出 txt_name.xlsx")
    print("4 = 连续执行 2 和 3")

    choice = input("输入 1 / 2 / 3 / 4 后回车: ").strip()

    if choice == "1":
        url_decode_rename_files(scan_root)
        url_decode_txt_contents(scan_root)
    elif choice == "2":
        generate_txt_excel_list(scan_root, excel_input, default_lines_per_file=50000)
    elif choice == "3":
        batch_split_by_line_count(excel_input, excel_output)
    elif choice == "4":
        run_all(scan_root, excel_input, excel_output)
    else:
        print("❌ 无效输入，请输入 1 / 2 / 3 / 4")
