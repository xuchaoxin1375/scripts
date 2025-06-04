"""测试跨模块日志"""

import logging
import myliblog.auxiliary as auxiliary_module

# 创建 本脚本的 日志记录器(分别试验三种方案)
# 1.取名为严格的模块名,从而作为父级日志记录器接受子模块的日志记录
logger = logging.getLogger("myliblog")
# 2.对于库/模块是合适的,但是主调代码中使用相当于'__main__'的名称的记录器
# logger=logging.getLogger(__name__)
# 3.根日志器,接受可能的任何日志记录
# logger = logging.getLogger()

logger.setLevel(logging.DEBUG)
# 创建可记录调试消息的文件处理器(将文件保存到spam.log中)
fh = logging.FileHandler("spam.log", mode="w", encoding="utf-8")
fh.setLevel(logging.DEBUG)
# 创建具有更高日志层级的控制台处理器🎈
ch = logging.StreamHandler()
ch.setLevel(logging.ERROR)

# 创建格式化器并将其添加到处理器
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
fh.setFormatter(formatter)
ch.setFormatter(formatter)
# 将处理器添加到日志记录器
logger.addHandler(fh)
logger.addHandler(ch)

# 模块中的Auxiliary类的日志记录
logger.info("creating an instance of auxiliary_module.Auxiliary")
a = auxiliary_module.Auxiliary()
logger.info("created an instance of auxiliary_module.Auxiliary")


logger.info("calling auxiliary_module.Auxiliary.do_something")
a.do_something()
logger.info("finished auxiliary_module.Auxiliary.do_something")

# 模块级的函数的日志记录
logger.info("calling auxiliary_module.some_function()")
auxiliary_module.some_function()
logger.info("done with auxiliary_module.some_function()")
