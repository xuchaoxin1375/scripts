"""测试跨模块日志"""

import logging
import myliblog.auxiliary as auxiliary_module

# 创建 'spam_application' 日志记录器
logger = logging.getLogger("myliblog")
logger.setLevel(logging.DEBUG)
# 创建可记录调试消息的文件处理器
fh = logging.FileHandler("spam.log",mode="w", encoding="utf-8")
fh.setLevel(logging.DEBUG)
# 创建具有更高日志层级的控制台处理器
ch = logging.StreamHandler()
ch.setLevel(logging.ERROR)
# 创建格式化器并将其添加到处理器
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
fh.setFormatter(formatter)
ch.setFormatter(formatter)
# 将处理器添加到日志记录器
logger.addHandler(fh)
logger.addHandler(ch)

logger.info("creating an instance of auxiliary_module.Auxiliary")
a = auxiliary_module.Auxiliary()
logger.info("created an instance of auxiliary_module.Auxiliary")
logger.info("calling auxiliary_module.Auxiliary.do_something")
a.do_something()
logger.info("finished auxiliary_module.Auxiliary.do_something")
logger.info("calling auxiliary_module.some_function()")
auxiliary_module.some_function()
logger.info("done with auxiliary_module.some_function()")
