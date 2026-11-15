# -*- coding: utf-8 -*-
"""WebUI 请求/响应模型（Pydantic）。

从 app.py 拆出，保持字段名与默认值不变；路由层只依赖本模块。
"""

from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, Field


class JobSubmit(BaseModel):
    """提交任务请求体（字段与操作表单同源）。"""

    mode: str = "update"
    accounts: list[str] = Field(default_factory=list)
    record_type: str = "auto"
    old_content: Optional[str] = None
    new_content: Optional[str] = None
    delete_ip: Optional[str] = None
    delete_zone_mode: str = "dns"
    set_proxied: Optional[str] = None
    set_ttl: Optional[int] = None
    include_subdomains: bool = True
    whitelist: list[str] = Field(default_factory=list)
    whitelist_file: Optional[str] = None
    domains: list[str] = Field(default_factory=list)
    resume_csv: Optional[str] = None
    backup_dir: Optional[str] = None
    confirm: Optional[str] = None
    add_domain: Optional[str] = None
    add_records: list[str] = Field(default_factory=list)
    proxied: bool = True
    ttl: int = 1
    allow_multi_value: bool = False
    export_fmt: str = "json"
    export_dir: str = ""
    server_ip: str = ""
    forward_email: str = ""
    ssl_mode: str = ""
    create_zone: bool = False
    activation_timeout: Optional[float] = None
    activation_interval: Optional[float] = None
    do_dns: bool = True
    do_activation: bool = True
    do_email: bool = True
    do_ssl: bool = True
    do_security: bool = True
    do_optimize: bool = True
    speed: str = "eco"
    scope: str = "account"
    max_retries: int = 5
    workers: Optional[int] = None
    account_workers: Optional[int] = None
    request_interval: Optional[float] = None
    retry_base: Optional[float] = None
    retry_max: Optional[float] = None
    dry_run: bool = True
    label: Optional[str] = None


class RecordPatch(BaseModel):
    """单条 PATCH：省略字段沿用原值（与 Cloudflare 网页版对齐）。"""

    account: str = ""
    zone: str = ""
    id: str = ""
    name: Optional[str] = None
    type: Optional[str] = None
    content: Optional[str] = None
    proxied: Optional[bool] = None
    ttl: Optional[int] = None
    comment: Optional[str] = None
    priority: Optional[int] = None


class SingleRecord(BaseModel):
    account: str = ""
    zone: str = ""
    name: str = ""
    type: str = "A"
    content: str = ""
    proxied: bool = False
    ttl: int = 1
    comment: str = ""
    priority: Optional[int] = None


class RecordBody(BaseModel):
    """批量恢复与导入的单条载荷（不含账号域名，目标由路径参数给出）。"""

    name: str = ""
    type: str = "A"
    content: str = ""
    proxied: bool = False
    ttl: int = 1
    comment: str = ""
    priority: Optional[int] = None


class EmailRoutingAddressBody(BaseModel):
    """添加邮箱转发目标。"""

    account: str = ""
    email: str = ""


class EmailRoutingCompleteBody(BaseModel):
    """验证通过后启用路由并设置 catch-all。"""

    account: str = ""
    zone: str = ""
    email: str = ""


class BulkDelete(BaseModel):
    account: str = ""
    zone: str = ""
    ids: list[str] = Field(default_factory=list)


class BulkUpdate(BaseModel):
    """按记录 ID 批量改属性或内容；content 为选中记录精确改写。"""

    account: str = ""
    zone: str = ""
    ids: list[str] = Field(default_factory=list)
    proxied: Optional[bool] = None
    ttl: Optional[int] = None
    content: Optional[str] = None


class RecordExport(BaseModel):
    """记录导出：有 ids 导出选中项，否则按筛选条件导出当前范围。"""

    account: str = ""
    zone: str = ""
    ids: list[str] = Field(default_factory=list)
    type: str = "ALL"
    search: str = ""
    proxied: str = "all"


class BulkRestore(BaseModel):
    account: str = ""
    zone: str = ""
    records: list[RecordBody] = Field(default_factory=list)


class RecordImport(BaseModel):
    account: str = ""
    zone: str = ""
    records: list[RecordBody] = Field(default_factory=list)
    dry_run: bool = True
