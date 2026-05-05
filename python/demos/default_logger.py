import logging

# 不进行任何配置，直接使用

# 1. 获取默认的 root logger
root_logger = logging.getLogger()  # 不传名字获取 root
print(f"Logger 名称: {root_logger.name}")           # root
print(f"Logger 级别: {root_logger.level}")          # 30 (WARNING)
print(f"Logger 有效级别: {root_logger.getEffectiveLevel()}")  # 30

# 2. 查看默认处理器
print(f"处理器数量: {len(root_logger.handlers)}")    # 0 (注意: 懒加载!)

# 3. 直接调用模块级函数
logging.debug("DEBUG - 不会显示")     # 级别不够，不输出
logging.info("INFO - 不会显示")       # 级别不够，不输出  
logging.warning("WARNING - 会显示")   # 输出: WARNING:root:WARNING - 会显示
logging.error("ERROR - 会显示")       # 输出: ERROR:root:ERROR - 会显示

# 4. 添加处理器1个
print(f"调用后处理器数量: {len(root_logger.handlers)}")  # 变为1