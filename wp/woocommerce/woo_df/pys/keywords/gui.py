import subprocess
import threading
import tkinter as tk
from tkinter import filedialog, messagebox
import get_keyword
from get_keyword import ORDERS_FILE, DOMAIN_TABLE_PATH, RESULT_FILE

# import get_keyword.main


def select_file(entry):
    """选择文件"""
    path = filedialog.askopenfilename(filetypes=[("Excel files", "*.xlsx")])
    if path:
        entry.delete(0, tk.END)
        entry.insert(tk.END, path)


def select_directory(entry):
    """选择目录"""
    path = filedialog.askdirectory()
    if path:
        entry.delete(0, tk.END)
        entry.insert(tk.END, path)


def run_script():
    """运行主脚本"""
    orders_file = entry_orders.get()
    domain_path = entry_domains.get()

    if not orders_file or not domain_path:
        messagebox.showwarning("警告", "请填写所有路径！")
        return

    # 在新线程中执行脚本避免界面冻结
    thread = threading.Thread(target=execute_script, args=(orders_file, domain_path))
    thread.start()


def execute_script(orders_file, domain_path):
    try:
        # 调用原始脚本的处理逻辑

        get_keyword.ORDERS_FILE = orders_file
        get_keyword.DOMAIN_TABLE_PATH = domain_path
        get_keyword.main()  # 假设你在原脚本中添加了 main() 函数封装逻辑
        messagebox.showinfo("完成", "处理已完成，请查看结果文件！")
    except Exception as e:
        messagebox.showerror("错误", f"发生错误: {e}")


# 创建主窗口
root = tk.Tk()
root.title("产品关键词国家分析工具")

# 订单文件输入
entry_orders = tk.Entry(root, width=50)
entry_orders.insert(0, ORDERS_FILE)  # 设置默认订单文件路径
entry_orders.grid(row=0, column=1, padx=5, pady=5)

# 站点目录输入
entry_domains = tk.Entry(root, width=50)
entry_domains.insert(0, DOMAIN_TABLE_PATH)  # 设置默认站点目录路径
entry_domains.grid(row=1, column=1, padx=5, pady=5)
# 提示
tk.Label(root, text="（默认路径可修改）").grid(row=0, column=3, padx=5, pady=5)
tk.Label(root, text="（默认目录可修改）").grid(row=1, column=3, padx=5, pady=5)
# 执行按钮
tk.Button(root, text="开始处理", command=run_script).grid(row=2, column=1, pady=10)

# 启动 GUI 主循环
root.mainloop()
