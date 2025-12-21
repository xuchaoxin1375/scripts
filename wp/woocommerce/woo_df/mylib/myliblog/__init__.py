"""mylib package initializer."""

import logging
from logging import NullHandler

# 创建库的顶级 logger
logger = logging.getLogger(__name__)  # __name__ == 'myliblog'

# 避免在未配置时输出日志到 stderr
logger.addHandler(NullHandler())
print("myliblog package initialized")
