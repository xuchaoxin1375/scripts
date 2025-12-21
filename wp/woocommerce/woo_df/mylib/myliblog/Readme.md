## 多模块中的日志

无论对 `logging.getLogger('someLogger')` 进行多少次调用，都会返回同一个 logger 对象的引用。不仅在同一个模块内如此，只要是在同一个 Python 解释器进程中，跨模块调用也是一样。

一个具体的带有日志的 Python 库设计中的建议：

- **命名规范**
- **NullHandler 的使用**
- **不主动添加 Handler**
- **不在根 Logger 中记录日志**
- **提供文档说明**

---

## ✅ 示例：一个名为 `mylib` 的库

### 📁 项目结构

```
mylib/
├── __init__.py
├── core.py
└── utils.py
```

---

## 🧱 第一步：定义库的 logger 命名规则

我们遵循以下原则：

- 所有模块都使用以 `mylib` 为前缀的 logger；
- 使用 `__name__` 来自动继承层级结构；
- 不使用 root logger；
- 在库的顶层 logger 添加 `NullHandler()`。

---

### 🔧 `mylib/__init__.py`

```python
import logging
from logging import NullHandler

# 创建库的顶级 logger
logger = logging.getLogger(__name__)  # __name__ == 'mylib'

# 避免在未配置时输出日志到 stderr
logger.addHandler(NullHandler())
```

📌 **作用**：
- 如果用户没有配置 logging，就不会有任何输出；
- 用户可以通过配置 `mylib.*` 的 logger 来控制日志行为；
- 符合官方推荐做法。

---

### 📜 `mylib/core.py`

```python
import logging

logger = logging.getLogger(__name__)  # __name__ == 'mylib.core'

def do_something():
    logger.debug("Doing something in core module")
    logger.info("Core module is working")
    logger.warning("This is a warning from core module")
```

---

### 📜 `mylib/utils.py`

```python
import logging

logger = logging.getLogger(__name__)  # __name__ == 'mylib.utils'

def helper():
    logger.debug("Helper function is running")
    logger.info("Some useful info from utils")
```

---

## 📚 第二步：编写库文档说明

在你的库的文档中，**必须明确说明以下内容**：

> ### 日志使用说明（Logging Usage）
>
> 本库使用 Python 标准 `logging` 模块进行日志记录。
>
> - 所有日志事件都通过名为 `mylib.*` 的 logger 发出（如 `mylib.core`, `mylib.utils`）。
> - 默认情况下，如果你的应用程序未配置日志系统，则不会有任何输出（已添加 `NullHandler`）。
> - 如果你想启用日志，请在你的应用程序中配置 `mylib` 或其子模块的日志器。
> - 推荐不要修改 `propagate` 属性，除非你清楚后果。
> - 不要将 handler 添加到库代码中，应由应用程序开发者配置。
>
> #### 示例：启用所有 mylib 的日志输出（DEBUG 级别）
>
> ```python
> import logging
> logging.basicConfig(level=logging.DEBUG)
> ```
>
> 或者更精细地控制：
>
> ```python
> import logging
> logging.getLogger('mylib').setLevel(logging.DEBUG)
> handler = logging.StreamHandler()
> formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
> handler.setFormatter(formatter)
> logging.getLogger('mylib').addHandler(handler)
> ```

---

## 🧪 第三步：测试无配置情况下的默认行为

```python
from mylib import core

core.do_something()  # 不会输出任何日志，因为没有配置
```

✅ 输出结果：**无输出**

---

## 🧪 第四步：测试用户自定义配置后的行为

```python
import logging
from mylib import core, utils

# 启用 DEBUG 级别并添加控制台输出
logging.basicConfig(level=logging.DEBUG)

core.do_something()
utils.helper()
```

✅ 输出示例：

```
DEBUG:mylib.core:Doing something in core module
INFO:mylib.core:Core module is working
WARNING:mylib.core:This is a warning from core module
DEBUG:mylib.utils:Helper function is running
INFO:mylib.utils:Some useful info from utils
```

---

## ✅ 总结：库作者应该怎么做？

| 要求 | 实现方式 |
|------|----------|
| 不使用 root logger | 使用 `__name__` 构造层级 logger |
| 提供统一命名空间 | 如 `mylib`, `mylib.moduleA` |
| 默认不输出日志 | 添加 `NullHandler()` |
| 不添加任何 Handler | 由应用开发者决定输出方式 |
| 文档中说明日志使用 | 明确 logger 名称、级别、配置方法 |
| 支持灵活配置 | 允许用户设置不同 level 和 handler |

---

## 📌 最佳实践建议（给库作者）

1. **永远不要调用 `basicConfig()` 或添加 `StreamHandler` 到库中**；
2. **始终使用 `__name__` 获取 logger**，以便继承层级；
3. **避免修改 propagate 属性**；
4. **确保 NullHandler 已添加到顶层 logger**；
5. **文档清晰说明如何启用和定制日志输出**；
6. **鼓励用户使用 logging.config.dictConfig 或 fileConfig 进行集中管理**。

---

如果你想发布一个专业的 Python 库，这样的日志设计是**标准且推荐的做法**。这样可以保证：

- 用户能完全控制日志行为；
- 日志输出不会干扰主程序；
- 易于调试和测试；
- 遵循社区最佳实践。

如需进一步封装或支持 JSON/YAML 配置格式，也可以继续扩展。需要我帮你写一个基于 YAML 的配置示例吗？