"""Web UI 包：FastAPI + 纯静态前端的 Cloudflare DNS 可视化操作台。"""

from . import engine_adapter as engine_adapter  # noqa: F401
from . import jobs as jobs  # noqa: F401
from . import rest as rest  # noqa: F401
from . import server as server  # noqa: F401
from .server import create_app as create_app  # noqa: F401
