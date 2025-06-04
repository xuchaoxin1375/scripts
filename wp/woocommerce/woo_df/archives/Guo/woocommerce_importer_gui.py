import os
import sys
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import threading
import io
import queue  # 添加队列模块
import time   # 添加时间模块
import contextlib
from csvinserttowoocommercebak3 import WooCommerceImporter
from mysql_connection_manager import MySQLConnectionManager  # 导入连接管理器

class RedirectText:
    """用于重定向输出到文本控件"""
    def __init__(self, text_widget):
        self.text_widget = text_widget
        self.buffer = ""

    def write(self, string):
        self.buffer += string
        # 每100个字符更新一次UI，避免频繁更新
        if len(self.buffer) > 100 or '\n' in self.buffer:
            self.update_text_widget()
    
    def update_text_widget(self):
        self.text_widget.config(state=tk.NORMAL)
        self.text_widget.insert(tk.END, self.buffer)
        self.text_widget.see(tk.END)
        self.text_widget.config(state=tk.DISABLED)
        self.buffer = ""
    
    def flush(self):
        if self.buffer:
            self.update_text_widget()

class WooCommerceImporterGUI:
    # 修改进度条初始化部分
    def __init__(self, root):
        self.root = root
        self.root.title("WooCommerce产品导入工具")
        self.root.geometry("800x600")
        self.root.minsize(800, 600)
        
        # 创建主框架
        main_frame = ttk.Frame(root, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # 创建配置框架
        config_frame = ttk.LabelFrame(main_frame, text="数据库配置", padding="10")
        config_frame.pack(fill=tk.X, pady=5)
        
        # 数据库配置
        ttk.Label(config_frame, text="主机:").grid(row=0, column=0, sticky=tk.W, padx=5, pady=2)
        self.host_var = tk.StringVar(value="localhost")
        ttk.Entry(config_frame, textvariable=self.host_var, width=20).grid(row=0, column=1, sticky=tk.W, padx=5, pady=2)
        
        ttk.Label(config_frame, text="用户名:").grid(row=0, column=2, sticky=tk.W, padx=5, pady=2)
        self.user_var = tk.StringVar(value="root")
        ttk.Entry(config_frame, textvariable=self.user_var, width=20).grid(row=0, column=3, sticky=tk.W, padx=5, pady=2)
        
        ttk.Label(config_frame, text="密码:").grid(row=1, column=0, sticky=tk.W, padx=5, pady=2)
        self.password_var = tk.StringVar(value="root")
        ttk.Entry(config_frame, textvariable=self.password_var, width=20, show="*").grid(row=1, column=1, sticky=tk.W, padx=5, pady=2)
        
        ttk.Label(config_frame, text="数据库:").grid(row=1, column=2, sticky=tk.W, padx=5, pady=2)
        self.database_var = tk.StringVar(value="meiguo-chuanbo03")
        ttk.Entry(config_frame, textvariable=self.database_var, width=20).grid(row=1, column=3, sticky=tk.W, padx=5, pady=2)
        
        ttk.Label(config_frame, text="端口:").grid(row=2, column=0, sticky=tk.W, padx=5, pady=2)
        self.port_var = tk.StringVar(value="3306")
        ttk.Entry(config_frame, textvariable=self.port_var, width=20).grid(row=2, column=1, sticky=tk.W, padx=5, pady=2)
        
        # 路径配置框架
        path_frame = ttk.LabelFrame(main_frame, text="路径配置", padding="10")
        path_frame.pack(fill=tk.X, pady=5)
        
        # WordPress站点目录
        ttk.Label(path_frame, text="WordPress站点目录:").grid(row=0, column=0, sticky=tk.W, padx=5, pady=2)
        self.wp_dir_var = tk.StringVar(value=r"D:\phpstudy_pro\WWW\meiguo-chuanbo03")
        wp_dir_entry = ttk.Entry(path_frame, textvariable=self.wp_dir_var, width=50)
        wp_dir_entry.grid(row=0, column=1, sticky=tk.W+tk.E, padx=5, pady=2)
        ttk.Button(path_frame, text="浏览...", command=lambda: self.browse_directory(self.wp_dir_var)).grid(row=0, column=2, padx=5, pady=2)
        
        # 数据源文件
        ttk.Label(path_frame, text="数据源文件:").grid(row=1, column=0, sticky=tk.W, padx=5, pady=2)
        self.source_path_var = tk.StringVar(value=r"D:\MyProject1\chuanbo\分割\split_2\split_2.csv")
        source_path_entry = ttk.Entry(path_frame, textvariable=self.source_path_var, width=50)
        source_path_entry.grid(row=1, column=1, sticky=tk.W+tk.E, padx=5, pady=2)
        ttk.Button(path_frame, text="浏览...", command=lambda: self.browse_file(self.source_path_var)).grid(row=1, column=2, padx=5, pady=2)
        
        # 操作按钮框架
        button_frame = ttk.Frame(main_frame)
        button_frame.pack(fill=tk.X, pady=10)
        
        # 导入按钮
        self.import_button = ttk.Button(button_frame, text="导入产品", command=self.import_products)
        self.import_button.pack(side=tk.LEFT, padx=5)
        
        # 重生成图片元数据按钮
        self.regenerate_button = ttk.Button(button_frame, text="重生成图片元数据", command=self.regenerate_images)
        self.regenerate_button.pack(side=tk.LEFT, padx=5)
        
        # 进度条
        self.progress = ttk.Progressbar(main_frame, orient=tk.HORIZONTAL, length=100, mode='determinate')
        self.progress.pack(fill=tk.X, pady=5)
        
        # 日志框架
        log_frame = ttk.LabelFrame(main_frame, text="运行日志", padding="10")
        log_frame.pack(fill=tk.BOTH, expand=True, pady=5)
        
        # 日志文本框
        self.log_text = tk.Text(log_frame, wrap=tk.WORD, state=tk.DISABLED)
        self.log_text.pack(fill=tk.BOTH, expand=True)
        
        # 添加滚动条
        scrollbar = ttk.Scrollbar(self.log_text, command=self.log_text.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_text.config(yscrollcommand=scrollbar.set)
        
        # 重定向标准输出到日志文本框
        self.redirect = RedirectText(self.log_text)
        
    def browse_directory(self, var):
        """浏览并选择目录"""
        directory = filedialog.askdirectory(initialdir=var.get())
        if directory:
            var.set(directory)
    
    def browse_file(self, var):
        """浏览并选择文件"""
        filetypes = [("CSV文件", "*.csv"), ("DB3文件", "*.db3"), ("所有文件", "*.*")]
        filename = filedialog.askopenfilename(initialdir=os.path.dirname(var.get()), 
                                             filetypes=filetypes)
        if filename:
            var.set(filename)
    
    def get_mysql_config(self):
        """获取MySQL配置"""
        return {
            'host': self.host_var.get(),
            'user': self.user_var.get(),
            'password': self.password_var.get(),
            'database': self.database_var.get(),
            'port': int(self.port_var.get())
        }
    
    # 删除重复的导入语句
    # 在导入部分添加
    import os
    import sys
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
    import threading
    import io
    import queue  # 添加队列模块
    import time   # 添加时间模块
    from csvinserttowoocommercebak3 import WooCommerceImporter
    from mysql_connection_manager import MySQLConnectionManager  # 导入连接管理器
    
    # 在 _import_products_thread 方法中使用连接管理器
    def _import_products_thread(self, source_path):
        """在线程中运行导入操作"""
        # 创建重定向类，将输出重定向到消息队列
        class ThreadRedirector:
            def __init__(self, queue):
                self.queue = queue
                
            def write(self, message):
                if message.strip():  # 忽略空消息
                    self.queue.put(message.strip())
                    
            def flush(self):
                pass
        
        # 创建消息队列
        self.message_queue = queue.Queue()
        
        # 重定向标准输出
        old_stdout = sys.stdout
        sys.stdout = ThreadRedirector(self.message_queue)
        
        try:
            # 创建导入器实例
            importer = WooCommerceImporter(self.get_mysql_config(), self.wp_dir_var.get())
            
            # 创建并使用连接管理器
            mysql_config = self.get_mysql_config()
            connection_manager = MySQLConnectionManager(mysql_config, max_retries=5, retry_delay=10)
            importer.use_connection_manager(connection_manager)
            
            # 导入产品
            print(f"开始导入产品数据，源路径: {source_path}")
            importer.import_products(source_path)
            print("导入完成")
            
            # 在主线程中显示完成消息
            self.root.after(0, lambda: messagebox.showinfo("完成", "产品导入完成"))
        except Exception as e:
            print(f"导入过程中出错: {e}")
            # 在主线程中显示错误消息
            self.root.after(0, lambda: messagebox.showerror("错误", f"导入过程中出错: {e}"))
        finally:
            # 恢复标准输出
            sys.stdout = old_stdout
            
            # 在主线程中停止进度条并启用按钮
            self.root.after(0, self._reset_ui)
    
    # 添加消息队列处理方法
    # 修改进度条显示方式
    
    # 当前进度条使用的是不确定模式(indeterminate mode)，它会来回滚动，不显示实际进度。
    # 我们需要将其改为确定模式(determinate mode)，显示实际进度百分比。
    
    def import_products(self):
        """导入产品"""
        source_path = self.source_path_var.get()
        
        if not source_path:
            messagebox.showerror("错误", "请选择源文件或目录")
            return
            
        if not os.path.exists(source_path):
            messagebox.showerror("错误", f"源路径不存在: {source_path}")
            return
            
        # 禁用按钮，防止重复点击
        self.import_button.config(state=tk.DISABLED)
        self.regenerate_button.config(state=tk.DISABLED)
        
        # 重置并显示进度条
        self.progress["value"] = 0
        
        # 创建并启动导入线程
        self.import_thread = threading.Thread(target=self._import_products_thread, args=(source_path,))
        self.import_thread.daemon = True  # 设置为守护线程，这样主程序退出时线程也会退出
        self.import_thread.start()
        
        # 启动定期检查队列的函数
        self.root.after(100, self._check_message_queue)
    
    # 将这两个方法移出import_products方法，修正缩进级别
    def update_progress(self, value, maximum=100):
        """更新进度条"""
        if maximum > 0:
            percentage = min(100, int((value / maximum) * 100))
            self.progress["value"] = percentage
            self.progress["maximum"] = 100

    def _check_message_queue(self):
        """定期检查消息队列，更新UI"""
        try:
            # 非阻塞方式检查队列
            while True:
                message = self.message_queue.get_nowait()
                
                # 检查是否是进度更新消息
                if message.startswith("PROGRESS:"):
                    try:
                        # 格式: "PROGRESS:当前值:最大值"
                        _, current, maximum = message.split(":")
                        self.update_progress(int(current), int(maximum))
                    except:
                        pass
                else:
                    # 将消息添加到文本框
                    self.log_text.config(state=tk.NORMAL)
                    self.log_text.insert(tk.END, message + "\n")
                    self.log_text.see(tk.END)  # 滚动到底部
                    self.log_text.config(state=tk.DISABLED)
                
                self.message_queue.task_done()
        except (queue.Empty, AttributeError):
            pass
        
        # 检查导入线程是否仍在运行
        if hasattr(self, 'import_thread') and self.import_thread.is_alive():
            # 如果线程仍在运行，继续定期检查
            self.root.after(100, self._check_message_queue)
        else:
            # 线程已结束，重置UI
            self._reset_ui()
    
    def regenerate_images(self):
        """重新生成图片元数据"""
        # 禁用按钮，启动进度条
        self.import_button.config(state=tk.DISABLED)
        self.regenerate_button.config(state=tk.DISABLED)
        self.progress.start()
        
        # 在新线程中运行重生成操作
        threading.Thread(target=self._regenerate_images_thread).start()
    
    def _regenerate_images_thread(self):
        """在线程中运行重生成操作"""
        # 重定向标准输出
        old_stdout = sys.stdout
        sys.stdout = self.redirect
        
        try:
            # 创建导入器实例
            importer = WooCommerceImporter(self.get_mysql_config(), self.wp_dir_var.get())
            
            # 重新生成图片元数据
            print("开始重新生成所有产品图片的元数据...")
            importer.connect_mysql()
            importer.regenerate_image_metadata()
            importer.close_connections()
            print("重新生成图片元数据完成")
            
            # 在主线程中显示完成消息
            self.root.after(0, lambda: messagebox.showinfo("完成", "图片元数据重生成完成"))
        except Exception as e:
            print(f"重生成过程中出错: {e}")
            # 在主线程中显示错误消息
            self.root.after(0, lambda: messagebox.showerror("错误", f"重生成过程中出错: {e}"))
        finally:
            # 恢复标准输出
            sys.stdout = old_stdout
            
            # 在主线程中停止进度条并启用按钮
            self.root.after(0, self._reset_ui)
    
    def _reset_ui(self):
        """重置UI状态"""
        self.progress.stop()
        self.import_button.config(state=tk.NORMAL)
        self.regenerate_button.config(state=tk.NORMAL)

if __name__ == "__main__":
    root = tk.Tk()
    app = WooCommerceImporterGUI(root)
    root.mainloop()