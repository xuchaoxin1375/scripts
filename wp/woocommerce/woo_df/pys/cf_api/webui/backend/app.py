# -*- coding: utf-8 -*-
"""FastAPI 组装：/api/v1 主接口 + /api 兼容旧端 + SPA 回退防穿越。

- 预设同源：/api/v1/meta 下发 SPEED_PRESETS、默认值与快照/导出目录。
- 分页一律服务端，上限 200/页；records 先全量取再过滤分页。
- 日志增量拉取 offset/limit；失败清单 CSV 含 BOM 下发。
- 安全：默认仅监听 127.0.0.1（start_web_ui 保证）；口令走 X-Auth-Token。
"""

from __future__ import annotations

import csv
import io
import json
import os
import tempfile
from typing import Any, Optional

from fastapi import FastAPI, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field

from . import db, deps, engine_adapter, jobs
from .validate import validate_job_params, validate_single_record


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


class BulkDelete(BaseModel):
    account: str = ""
    zone: str = ""
    ids: list[str] = Field(default_factory=list)


class BulkUpdate(BaseModel):
    account: str = ""
    zone: str = ""
    ids: list[str] = Field(default_factory=list)
    proxied: Optional[bool] = None
    ttl: Optional[int] = None


class BulkRestore(BaseModel):
    account: str = ""
    zone: str = ""
    records: list[RecordBody] = Field(default_factory=list)


class RecordImport(BaseModel):
    account: str = ""
    zone: str = ""
    records: list[RecordBody] = Field(default_factory=list)
    dry_run: bool = True


def _check_auth(password: str, token: Optional[str]) -> None:
    if not password:
        return
    if token != password:
        raise HTTPException(status_code=401, detail="未授权")


def _canon_name(name: str, zone_name: str) -> str:
    """写路径名称归一化为完整域名。

    编辑器按参考稿使用短名（`@` 表根域名）；接口写入统一转完整域名，
    与读取路径的原始格式一致，避免改名语义漂移。
    """
    short = (name or "").strip()
    zone = (zone_name or "").strip()
    if not short or short == "@":
        return zone
    if not zone:
        return short
    low, zlow = short.lower(), zone.lower()
    if low == zlow or low.endswith("." + zlow):
        return short
    if "." not in short:
        return f"{short}.{zone}"
    return short


def _lookup(names: list[str]) -> list[dict]:
    accounts = deps.get_accounts()
    by_name = {(a.get("name") or a.get("email") or "unknown"): a for a in accounts}
    missing = [n for n in names if n not in by_name]
    if missing:
        raise HTTPException(status_code=400, detail=f"未知账号: {missing}")
    return [by_name[n] for n in names]


def _paginate(items: list[Any], page: int, per_page: int) -> dict[str, Any]:
    per_page = max(1, min(200, per_page))
    page = max(1, page)
    total = len(items)
    start = (page - 1) * per_page
    return {
        "total": total,
        "page": page,
        "per_page": per_page,
        "items": items[start : start + per_page],
    }


def _meta() -> dict[str, Any]:
    eng = engine_adapter.engine()
    dirs = deps.default_dirs()
    pool = deps.get_proxy_pool()
    return {
        "version": str(getattr(eng, "VERSION", "")),
        "speed_presets": dict(getattr(eng, "SPEED_PRESETS", {})),
        "defaults": {
            "dry_run": True,
            "record_type": "auto",
            "speed": "eco",
            "scope": "account",
            "max_retries": int(getattr(eng, "DEFAULT_API_MAX_RETRIES", 5)),
            "export_fmt": "json",
        },
        "dirs": dirs,
        "requires_auth": bool(deps.get_password()),
        "config_path": deps.get_config_path(),
        "proxy": {
            "mode": getattr(pool, "mode", ""),
            "count": len(getattr(pool, "urls", []) or []),
        },
    }


def create_app(frontend: str = "") -> FastAPI:
    """构建 FastAPI 应用（测试与启动共用）。"""
    app = FastAPI(title="Cloudflare DNS WebUI")

    def _auth(
        token: Optional[str] = Header(default=None, alias="X-Auth-Token"),
    ) -> None:
        _check_auth(deps.get_password(), token)

    # ---- meta ----
    @app.get("/api/v1/meta")
    def meta_v1(_: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        return _meta()

    @app.get("/api/meta")
    def meta_compat(_: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        return _meta()

    # ---- accounts ----
    def _accounts_payload() -> dict[str, Any]:
        try:
            accounts = deps.get_accounts()
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        return {"items": engine_adapter.masked_accounts(accounts)}

    @app.get("/api/v1/accounts")
    def accounts_v1(_: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        return _accounts_payload()

    @app.get("/api/accounts")
    def accounts_compat(_: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        accounts = _accounts_payload()["items"]
        return {"accounts": accounts}

    # ---- zones ----
    @app.get("/api/v1/zones")
    def zones(
        account: str,
        filter: str = "",  # noqa: A002 - 与历史查询参数名保持兼容
        status: str = "all",
        page: int = 1,
        per_page: int = 50,
        _: None = _auth(),  # type: ignore[valid-type]
    ) -> dict[str, Any]:
        matched = _lookup([account])
        try:
            all_zones = engine_adapter.get_zones(matched[0])
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        keyword = (filter or "").strip().lower()
        want_status = (status or "all").strip().lower()
        rows = [
            {
                "name": z.get("name", ""),
                "status": z.get("status", ""),
                "id": z.get("id", ""),
            }
            for z in all_zones
            if keyword in str(z.get("name", "")).lower()
            and (want_status == "all" or str(z.get("status", "")) == want_status)
        ]
        data = _paginate(rows, page, per_page)
        data.update({"account": account})
        return data

    @app.get("/api/v1/zones.csv")
    def zones_csv(
        account: str,
        filter: str = "",  # noqa: A002 - 与 zones 查询同名保持一致
        status: str = "all",
        _: None = _auth(),  # type: ignore[valid-type]
    ) -> Response:
        matched = _lookup([account])
        try:
            all_zones = engine_adapter.get_zones(matched[0])
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        keyword = (filter or "").strip().lower()
        want_status = (status or "all").strip().lower()
        eng = engine_adapter.engine()
        buf = io.StringIO()
        writer = csv.DictWriter(buf, fieldnames=list(eng.ZONES_CSV_FIELDNAMES))
        writer.writeheader()
        count = 0
        for z in all_zones:
            if keyword and keyword not in str(z.get("name", "")).lower():
                continue
            if want_status != "all" and str(z.get("status", "")) != want_status:
                continue
            writer.writerow(
                {
                    "account": account,
                    "name": z.get("name", ""),
                    "status": z.get("status", ""),
                    "zone_id": z.get("id", ""),
                    "nameservers": ";".join(z.get("name_servers") or []),
                }
            )
            count += 1
            if count >= 5000:
                break
        return Response(
            content="\ufeff" + buf.getvalue(),
            media_type="text/csv; charset=utf-8",
            headers={
                "Content-Disposition": f"attachment; filename=zones_{account}.csv"
            },
        )

    @app.post("/api/v1/whitelist-upload")
    async def whitelist_upload(file: UploadFile, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        data = await file.read()
        if len(data) > 2 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="文件过大（上限 2MB）")
        handle = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
        try:
            handle.write(data)
        finally:
            handle.close()
        try:
            domains = engine_adapter.load_whitelist_strict(handle.name)
        except engine_adapter.EngineError as exc:
            try:
                os.unlink(handle.name)
            except OSError:
                pass
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        return {"path": handle.name, "count": len(domains), "domains": domains[:200]}

    # ---- records ----
    @app.get("/api/v1/records")
    def records(
        account: str,
        zone: str,
        type: str = "ALL",  # noqa: A002 - 查询参数名与 Cloudflare 语义对齐
        search: str = "",
        page: int = 1,
        per_page: int = 50,
        sort: str = "",
        proxied: str = "all",
        _: None = _auth(),  # type: ignore[valid-type]
    ) -> dict[str, Any]:
        matched = _lookup([account])
        try:
            all_zones = engine_adapter.get_zones(matched[0])
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        zone_id = ""
        for item in all_zones:
            if str(item.get("name", "")).lower() == zone.strip().lower():
                zone_id = item.get("id", "")
                break
        if not zone_id:
            raise HTTPException(status_code=404, detail=f"域名不在该账号中: {zone}")
        try:
            all_records = engine_adapter.get_records(matched[0], zone_id, "ALL")
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        keyword = (search or "").strip().lower()
        wanted = (type or "ALL").strip().upper()
        proxy_want = (proxied or "all").strip().lower()
        rows = []
        for record in all_records:
            if (
                wanted not in {"", "ALL"}
                and str(record.get("type", "")).upper() != wanted
            ):
                continue
            if proxy_want in {"true", "1", "proxied", "on"} and not bool(
                record.get("proxied", False)
            ):
                continue
            if proxy_want in {"false", "0", "dns", "off"} and bool(
                record.get("proxied", False)
            ):
                continue
            if (
                keyword
                and keyword not in str(record.get("name", "")).lower()
                and keyword not in str(record.get("content", "")).lower()
            ):
                continue
            rows.append(engine_adapter.slim_record(record))
        skey = (sort or "").strip()
        if skey in {"type", "-type", "name", "-name", "content", "-content"}:
            rev = skey.startswith("-")
            field = skey.lstrip("-")
            rows.sort(
                key=lambda r: (
                    str(r.get(field, "")),
                    str(r.get("name", "")),
                    str(r.get("type", "")),
                ),
                reverse=rev,
            )
        data = _paginate(rows, page, per_page)
        data.update({"account": account, "zone": zone})
        return data

    # ---- single record ----
    def _resolve_zone(account: dict, zone: str) -> tuple[str, str]:
        try:
            all_zones = engine_adapter.get_zones(account)
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        for item in all_zones:
            if str(item.get("name", "")).lower() == zone.strip().lower():
                return str(item.get("id", "")), str(item.get("name", zone))
        raise HTTPException(status_code=404, detail=f"域名不在该账号中: {zone}")

    @app.post("/api/v1/records")
    def single_record(body: SingleRecord, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        err = validate_single_record(body.model_dump())
        if err:
            raise HTTPException(status_code=400, detail=err)
        matched = _lookup([body.account])
        zone_id, zone_name = _resolve_zone(matched[0], body.zone)
        name = body.name.strip() or "@"
        want_comment = body.comment or ""
        short_l = name.lower()
        fqdn_l = f"{name}.{zone_name}".lower() if name != "@" else zone_name.lower()
        def _same_name(raw: str) -> bool:
            rl = (raw or "").lower()
            return rl == short_l or rl == fqdn_l or rl == zone_name.lower() and short_l == "@"
        try:
            updater = engine_adapter.build_updater(matched[0])
            before = updater.get_dns_records(zone_id, body.type.upper())
        except Exception:
            before = []
        existing_comment = ""
        for item in before:
            if _same_name(str(item.get("name", ""))) and str(
                item.get("type", "")
            ).upper() == body.type.upper():
                existing_comment = str(item.get("comment") or "")
                break
        try:
            status, msg = updater.ensure_dns_record(
                zone_id,
                zone_name,
                name,
                body.type.upper(),
                body.content.strip(),
                proxied=bool(body.proxied),
                ttl=int(body.ttl),
                priority=body.priority,
            )
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=f"写入失败: {exc}") from exc
        desired_comment = want_comment or existing_comment
        if desired_comment != existing_comment:
            try:
                after = updater.get_dns_records(zone_id, body.type.upper())
            except Exception as exc:  # noqa: BLE001
                raise HTTPException(status_code=502, detail=f"备注回写前读取失败: {exc}") from exc
            target = None
            for item in after:
                if not _same_name(str(item.get("name", ""))):
                    continue
                if str(item.get("type", "")).upper() == body.type.upper():
                    if str(item.get("content", "")) == body.content.strip():
                        target = item
                        break
                    if target is None:
                        target = item
            if target is None:
                raise HTTPException(status_code=502, detail="写入后未找到记录，备注未回写")
            try:
                engine_adapter.write_record_full(
                    updater,
                    zone_id,
                    str(target.get("id", "")),
                    {
                        "type": str(target.get("type", body.type.upper())),
                        "name": str(target.get("name", name)),
                        "content": str(target.get("content", body.content.strip())),
                        "proxied": bool(target.get("proxied", body.proxied)),
                        "ttl": int(target.get("ttl", body.ttl) or body.ttl),
                        "comment": desired_comment,
                        "priority": body.priority,
                    },
                )
            except Exception as exc:  # noqa: BLE001
                raise HTTPException(status_code=502, detail=f"备注回写失败: {exc}") from exc
            msg = f"{msg}（备注已回写）"
        if status == "error":
            raise HTTPException(status_code=502, detail=msg)
        try:
            db.audit(
                "single_upsert",
                account=body.account,
                detail=f"{zone_name} {body.type} {name}",
            )
        except Exception:
            pass
        return {"status": status, "message": msg}

    @app.patch("/api/v1/records")
    def patch_record(body: RecordPatch, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        if not body.id.strip():
            raise HTTPException(status_code=400, detail="缺少记录 id")
        matched = _lookup([body.account])
        zone_id, zone_name = _resolve_zone(matched[0], body.zone)
        try:
            updater = engine_adapter.build_updater(matched[0])
            existing_all = updater.get_dns_records(zone_id, "ALL")
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=f"读取记录失败: {exc}") from exc
        current = next(
            (r for r in existing_all if str(r.get("id", "")) == body.id.strip()), None
        )
        if current is None:
            raise HTTPException(status_code=404, detail="记录不存在")
        merged = {
            "type": (body.type or str(current.get("type", "A"))).upper(),
            "name": (body.name.strip() if body.name else "")
            or str(current.get("name", "")),
            "content": body.content
            if body.content is not None
            else str(current.get("content", "")),
            "proxied": body.proxied
            if body.proxied is not None
            else bool(current.get("proxied", False)),
            "ttl": body.ttl
            if body.ttl is not None
            else int(current.get("ttl", 1) or 1),
            "comment": body.comment
            if body.comment is not None
            else str(current.get("comment") or ""),
            "priority": body.priority
            if body.priority is not None
            else current.get("priority", None),
        }
        merged["name"] = _canon_name(str(merged["name"]), zone_name)
        err = validate_single_record(merged)
        if err:
            raise HTTPException(status_code=400, detail=err)
        comment_changed = merged["comment"] != str(current.get("comment") or "")
        prio_before = current.get("priority", None)
        try:
            prio_before = int(prio_before) if prio_before is not None else None
        except (TypeError, ValueError):
            prio_before = None
        priority_changed = (merged["priority"] is None) != (prio_before is None) or (
            merged["priority"] is not None
            and prio_before is not None
            and int(merged["priority"]) != prio_before
        )
        try:
            if comment_changed or priority_changed:
                engine_adapter.write_record_full(
                    updater,
                    zone_id,
                    str(current.get("id", "")),
                    {
                        "type": str(merged["type"]),
                        "name": str(merged["name"]),
                        "content": str(merged["content"]),
                        "proxied": bool(merged["proxied"]),
                        "ttl": int(merged["ttl"]),
                        "comment": str(merged["comment"]),
                        "priority": merged["priority"],
                    },
                )
            else:
                updater.update_dns_record(
                    zone_id=zone_id,
                    record_id=str(current.get("id", "")),
                    record_name=str(merged["name"]),
                    new_content=str(merged["content"]),
                    proxied=bool(merged["proxied"]),
                    ttl=int(merged["ttl"]),
                    record_type=str(merged["type"]),
                )
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=f"更新失败: {exc}") from exc
        try:
            db.audit(
                "single_patch",
                account=body.account,
                detail=f"{zone_name} {merged['type']} {body.id}",
            )
        except Exception:
            pass
        return {"status": "updated", "message": "已更新"}

    @app.delete("/api/v1/records")
    def delete_record(
        account: str, zone: str, id: str, _: None = _auth()
    ) -> dict[str, Any]:  # type: ignore[valid-type]
        if not id.strip():
            raise HTTPException(status_code=400, detail="缺少记录 id")
        matched = _lookup([account])
        zone_id, zone_name = _resolve_zone(matched[0], zone)
        try:
            updater = engine_adapter.build_updater(matched[0])
            updater.delete_dns_record(zone_id, id.strip())
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=f"删除失败: {exc}") from exc
        try:
            db.audit("single_delete", account=account, detail=f"{zone_name} {id}")
        except Exception:
            pass
        return {"status": "deleted"}

    def _import_item_error(index: int, item: RecordBody) -> Optional[str]:
        name = (item.name or "").strip()
        if not name:
            return f"第{index}条：名称必填"
        err = validate_single_record(
            {
                "type": (item.type or "").upper().strip(),
                "content": item.content,
                "proxied": bool(item.proxied),
                "ttl": int(item.ttl or 1),
                "comment": item.comment or "",
                "priority": item.priority,
            }
        )
        return f"第{index}条：{err}" if err else None

    @app.post("/api/v1/records/bulk-delete")
    def bulk_delete(body: BulkDelete, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        ids = [str(i).strip() for i in (body.ids or []) if str(i).strip()]
        ids = list(dict.fromkeys(ids))
        if not ids:
            return {"deleted": [], "failed": [], "total": 0}
        if len(ids) > 200:
            raise HTTPException(status_code=400, detail="单次批量删除至多 200 条")
        matched = _lookup([body.account])
        zone_id, zone_name = _resolve_zone(matched[0], body.zone)
        updater = engine_adapter.build_updater(matched[0])
        try:
            existing = updater.get_dns_records(zone_id, "ALL")
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=f"读取记录失败: {exc}") from exc
        by_id = {str(r.get("id", "")): r for r in existing if isinstance(r, dict)}
        deleted: list[dict[str, Any]] = []
        failed: list[dict[str, str]] = []
        for rid in ids:
            current = by_id.get(rid)
            if current is None:
                failed.append({"id": rid, "error": "记录不存在（可能已被删除）"})
                continue
            try:
                updater.delete_dns_record(zone_id, rid)
            except Exception as exc:  # noqa: BLE001
                failed.append({"id": rid, "error": f"删除失败: {exc}"})
                continue
            deleted.append(engine_adapter.slim_record(current))
        try:
            db.audit(
                "bulk_delete",
                account=body.account,
                detail=f"{zone_name} 删除 {len(deleted)} 条，失败 {len(failed)} 条",
            )
        except Exception:
            pass
        return {"deleted": deleted, "failed": failed, "total": len(ids)}

    @app.post("/api/v1/records/bulk-update")
    def bulk_update(body: BulkUpdate, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        ids = [str(i).strip() for i in (body.ids or []) if str(i).strip()]
        ids = list(dict.fromkeys(ids))
        if not ids:
            return {"updated": [], "prev": [], "failed": [], "total": 0}
        if len(ids) > 200:
            raise HTTPException(status_code=400, detail="单次批量更新至多 200 条")
        if body.proxied is None and body.ttl is None:
            raise HTTPException(status_code=400, detail="批量更新至少指定 proxied 或 ttl 其一")
        matched = _lookup([body.account])
        zone_id, zone_name = _resolve_zone(matched[0], body.zone)
        updater = engine_adapter.build_updater(matched[0])
        try:
            existing = updater.get_dns_records(zone_id, "ALL")
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=f"读取记录失败: {exc}") from exc
        by_id = {str(r.get("id", "")): r for r in existing if isinstance(r, dict)}
        updated: list[dict[str, Any]] = []
        prev: list[dict[str, Any]] = []
        failed: list[dict[str, str]] = []
        for rid in ids:
            current = by_id.get(rid)
            if current is None:
                failed.append({"id": rid, "error": "记录不存在（可能已被删除）"})
                continue
            merged = {
                "type": str(current.get("type", "A")).upper(),
                "content": str(current.get("content", "")),
                "proxied": body.proxied
                if body.proxied is not None
                else bool(current.get("proxied", False)),
                "ttl": body.ttl
                if body.ttl is not None
                else int(current.get("ttl", 1) or 1),
                "comment": str(current.get("comment") or ""),
                "priority": current.get("priority", None),
            }
            err = validate_single_record(merged)
            if err:
                failed.append({"id": rid, "error": err})
                continue
            try:
                engine_adapter.write_record_full(
                    updater,
                    zone_id,
                    rid,
                    {
                        "type": merged["type"],
                        "name": str(current.get("name", "")),
                        "content": merged["content"],
                        "proxied": bool(merged["proxied"]),
                        "ttl": int(merged["ttl"]),
                        "comment": merged["comment"],
                        "priority": merged["priority"],
                    },
                )
            except Exception as exc:  # noqa: BLE001
                failed.append({"id": rid, "error": f"更新失败: {exc}"})
                continue
            prev.append(engine_adapter.slim_record(current))
            updated.append(rid)
        try:
            db.audit(
                "bulk_update",
                account=body.account,
                detail=f"{zone_name} 更新 {len(updated)} 条，失败 {len(failed)} 条",
            )
        except Exception:
            pass
        return {"updated": updated, "prev": prev, "failed": failed, "total": len(ids)}

    @app.post("/api/v1/records/bulk-restore")
    def bulk_restore(body: BulkRestore, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        items = list(body.records or [])
        if not items:
            return {"restored": [], "failed": [], "total": 0}
        if len(items) > 200:
            raise HTTPException(status_code=400, detail="单次批量恢复至多 200 条")
        for index, item in enumerate(items, start=1):
            err = _import_item_error(index, item)
            if err:
                raise HTTPException(status_code=400, detail=f"恢复前校验失败，零写入：{err}")
        matched = _lookup([body.account])
        zone_id, zone_name = _resolve_zone(matched[0], body.zone)
        updater = engine_adapter.build_updater(matched[0])
        restored: list[dict[str, Any]] = []
        failed: list[dict[str, Any]] = []
        for index, item in enumerate(items, start=1):
            try:
                created = engine_adapter.create_record_full(
                    updater,
                    zone_id,
                    {
                        "type": (item.type or "").upper().strip(),
                        "name": _canon_name((item.name or "").strip() or "@", zone_name),
                        "content": item.content,
                        "proxied": bool(item.proxied),
                        "ttl": int(item.ttl or 1),
                        "comment": item.comment or "",
                        "priority": item.priority,
                    },
                )
            except Exception as exc:  # noqa: BLE001
                failed.append({"index": index, "error": f"恢复失败: {exc}"})
                continue
            rid = ""
            try:
                rid = str((created.get("result") or {}).get("id", ""))
            except Exception:
                rid = ""
            restored.append({"index": index, "id": rid})
        try:
            db.audit(
                "bulk_restore",
                account=body.account,
                detail=f"{zone_name} 恢复 {len(restored)} 条，失败 {len(failed)} 条",
            )
        except Exception:
            pass
        return {"restored": restored, "failed": failed, "total": len(items)}

    @app.post("/api/v1/records/import")
    def import_records(body: RecordImport, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        items = list(body.records or [])
        if len(items) > 200:
            raise HTTPException(status_code=400, detail="单次导入至多 200 条")
        if len(json.dumps([i.model_dump() for i in items], ensure_ascii=False)) > 1048576:
            raise HTTPException(status_code=400, detail="导入载荷超过 1MB 上限")
        seen: set[tuple[str, str, str]] = set()
        for index, item in enumerate(items, start=1):
            err = _import_item_error(index, item)
            if err:
                raise HTTPException(status_code=400, detail=f"导入拒绝，零写入：{err}")
            key = (
                (item.type or "").upper().strip(),
                (item.name or "").strip().lower(),
                item.content,
            )
            if key in seen:
                raise HTTPException(
                    status_code=400,
                    detail=f"导入拒绝，零写入：第{index}条与文件内已有条目重复",
                )
            seen.add(key)
        if body.dry_run:
            return {"checked": len(items), "errors": []}
        matched = _lookup([body.account])
        _resolve_zone(matched[0], body.zone)
        added = updated = unchanged = 0
        failed: list[dict[str, Any]] = []
        for index, item in enumerate(items, start=1):
            try:
                result = single_record(
                    SingleRecord(
                        account=body.account,
                        zone=body.zone,
                        name=item.name,
                        type=item.type,
                        content=item.content,
                        proxied=bool(item.proxied),
                        ttl=int(item.ttl or 1),
                        comment=item.comment or "",
                        priority=item.priority,
                    )
                )
            except HTTPException as exc:
                failed.append({"index": index, "error": str(exc.detail)})
                continue
            status = str(result.get("status", ""))
            if status == "added":
                added += 1
            elif status == "updated":
                updated += 1
            else:
                unchanged += 1
        try:
            db.audit(
                "records_import",
                account=body.account,
                detail=f"{body.zone} 导入：新增 {added} 更新 {updated} 未变 {unchanged} 失败 {len(failed)}",
            )
        except Exception:
            pass
        return {
            "added": added,
            "updated": updated,
            "unchanged": unchanged,
            "failed": failed,
            "total": len(items),
        }

    # ---- cross-account find (CLI -f) ----
    @app.get("/api/v1/find")
    def find_domain(domain: str, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        eng = engine_adapter.engine()
        target = (eng.get_main_domain_name_from_str(domain) or domain.strip()).lower()
        if not target:
            raise HTTPException(status_code=400, detail="域名无效")
        try:
            accounts = deps.get_accounts()
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        found: list[dict[str, Any]] = []
        for account in accounts:
            name = account.get("name") or account.get("email") or "unknown"
            try:
                updater = engine_adapter.build_updater(account)
                if not updater.zone_exists(target):
                    continue
                zone = updater.get_zone_by_name(target) or {}
                info: dict[str, Any] = {
                    "account": name,
                    "zone": zone.get("name", target),
                    "zone_id": zone.get("id", ""),
                    "status": zone.get("status", ""),
                }
                zid = zone.get("id", "")
                if zid:
                    try:
                        info["record_count"] = len(updater.get_dns_records(zid, "ALL"))
                    except Exception:
                        info["record_count"] = "?"
                found.append(info)
            except Exception as exc:  # noqa: BLE001 - 单账号失败不中断全账号查找
                found.append({"account": name, "error": str(exc)})
        return {
            "domain": target,
            "found": len([f for f in found if "error" not in f]),
            "results": found,
        }

    # ---- activation check ----
    @app.post("/api/v1/zones/activation-check")
    def activation_check(payload: dict[str, Any], _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        account = str(payload.get("account", ""))
        zone = str(payload.get("zone", ""))
        matched = _lookup([account])
        zone_id, zone_name = _resolve_zone(matched[0], zone)
        try:
            updater = engine_adapter.build_updater(matched[0])
            updater.trigger_activation_check(zone_id)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=f"催激活失败: {exc}") from exc
        return {"account": account, "zone": zone_name, "triggered": True}

    # ---- jobs ----
    @app.post("/api/v1/jobs")
    def submit_job(body: JobSubmit, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        matched = _lookup(list(body.accounts or []))
        resume_entries = None
        if body.resume_csv:
            try:
                resume_entries = engine_adapter.load_resume_entries_strict(
                    body.resume_csv
                )
            except engine_adapter.EngineError as exc:
                raise HTTPException(status_code=400, detail=str(exc)) from exc
        params: dict[str, Any] = {
            "mode": body.mode,
            "record_type": body.record_type,
            "old_content": body.old_content,
            "new_content": body.new_content,
            "delete_ip": body.delete_ip,
            "delete_zone_mode": body.delete_zone_mode,
            "set_proxied": body.set_proxied,
            "set_ttl": body.set_ttl,
            "include_subdomains": body.include_subdomains,
            "whitelist": list(body.whitelist or []),
            "domains": list(body.domains or []),
            "resume_entries": resume_entries,
            "backup_dir": body.backup_dir,
            "confirm": body.confirm,
            "add_domain": body.add_domain,
            "add_records": list(body.add_records or []),
            "proxied": body.proxied,
            "ttl": body.ttl,
            "allow_multi_value": body.allow_multi_value,
            "export_fmt": body.export_fmt,
            "export_dir": body.export_dir or deps.default_dirs()["export_dir"],
            "server_ip": body.server_ip,
            "forward_email": body.forward_email,
            "ssl_mode": body.ssl_mode,
            "do_dns": body.do_dns,
            "do_activation": body.do_activation,
            "do_email": body.do_email,
            "do_ssl": body.do_ssl,
            "do_security": body.do_security,
            "do_optimize": body.do_optimize,
        }
        if body.whitelist_file:
            try:
                params["whitelist"] = list(
                    params["whitelist"]
                ) + engine_adapter.load_whitelist_strict(body.whitelist_file)
            except engine_adapter.EngineError as exc:
                raise HTTPException(status_code=400, detail=str(exc)) from exc
        params["create_zone"] = body.create_zone
        params["activation_timeout"] = body.activation_timeout
        params["activation_interval"] = body.activation_interval
        # add_records 服务端预检，避免整任务跑起来才报错
        if params.get("add_records"):
            eng = engine_adapter.engine()
            for spec in params["add_records"]:
                try:
                    eng.parse_add_record_spec(spec)
                except ValueError as exc:
                    raise HTTPException(status_code=400, detail=str(exc)) from exc
        err = validate_job_params(params, list(body.accounts or []))
        if err:
            raise HTTPException(status_code=400, detail=err)
        eng = engine_adapter.engine()
        if body.speed not in getattr(eng, "SPEED_PRESETS", {}):
            raise HTTPException(
                status_code=400, detail=f"不支持的速度档位: {body.speed}"
            )
        if body.scope not in {"account", "global"}:
            raise HTTPException(
                status_code=400, detail=f"不支持的限速范围: {body.scope}"
            )
        preset = eng.SPEED_PRESETS[body.speed]
        workers = (
            int(preset["workers"])
            if body.workers is None
            else max(1, min(20, int(body.workers)))
        )
        interval = (
            float(preset["request_interval"])
            if body.request_interval is None
            else max(0.0, float(body.request_interval))
        )
        if body.account_workers is not None and (
            int(body.account_workers) < 1 or int(body.account_workers) > 20
        ):
            raise HTTPException(status_code=400, detail="账号并发数需为 1~20")
        if body.max_retries is not None and int(body.max_retries) < 0:
            raise HTTPException(status_code=400, detail="重试次数不能为负")
        for name, val in (
            ("retry_base", body.retry_base),
            ("retry_max", body.retry_max),
        ):
            if val is not None and float(val) <= 0:
                raise HTTPException(status_code=400, detail=f"{name} 必须大于 0")
        speed = {
            "workers": workers,
            "interval": interval,
            "scope": body.scope,
            "max_retries": int(body.max_retries),
            "retry_base": float(body.retry_base)
            if body.retry_base is not None
            else None,
            "retry_max": float(body.retry_max) if body.retry_max is not None else None,
            "account_workers": int(body.account_workers)
            if body.account_workers is not None
            else None,
        }
        manager = deps.get_manager()
        label = (
            body.label
            or f"{'预览' if body.dry_run else '执行'} {body.mode} x{len(matched)}账号"
        )
        job_id = manager.submit(
            label,
            "preview" if body.dry_run else "execute",
            jobs.run_operation_job,
            [a.get("name") or "" for a in matched],
            accounts=matched,
            params=params,
            speed=speed,
            proxy_pool=deps.get_proxy_pool(),
            dry_run=body.dry_run,
        )
        try:
            db.audit(
                "execute",
                account=",".join(a.get("name") or "" for a in matched),
                detail=label,
            )
        except Exception:
            pass
        return {"job_id": job_id}

    @app.get("/api/v1/jobs")
    def list_jobs(_: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        return {"jobs": deps.get_manager().list()}

    @app.get("/api/v1/jobs/{job_id}")
    def get_job(job_id: str, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        return job.snapshot()

    @app.get("/api/v1/jobs/{job_id}/zones")
    def job_zones(job_id: str, account: str, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        return {"job_id": job_id, "account": account, **job.zone_detail(account)}

    @app.get("/api/v1/jobs/{job_id}/results")
    def job_results(
        job_id: str, page: int = 1, per_page: int = 50, _: None = _auth()
    ) -> dict[str, Any]:  # type: ignore[valid-type]
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        with job._lock:
            results = list(job.results)
        data = _paginate(results, page, per_page)
        data.update({"job_id": job_id})
        return data

    @app.get("/api/v1/jobs/{job_id}/logs")
    def job_logs(
        job_id: str, offset: int = 0, limit: int = 500, _: None = _auth()
    ) -> dict[str, Any]:  # type: ignore[valid-type]
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        total, lines = job.read_logs(offset, limit)
        return {
            "job_id": job_id,
            "total": total,
            "offset": max(0, offset),
            "logs": lines,
        }

    @app.get("/api/v1/jobs/{job_id}/failures")
    def job_failures(
        job_id: str, page: int = 1, per_page: int = 50, _: None = _auth()
    ) -> dict[str, Any]:  # type: ignore[valid-type]
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        with job._lock:
            rows = list(job.failure_rows)
        data = _paginate(rows, page, per_page)
        data.update({"job_id": job_id})
        return data

    @app.get("/api/v1/jobs/{job_id}/failures.csv")
    def job_failures_csv(job_id: str, _: None = _auth()) -> Response:  # type: ignore[valid-type]
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        if not job.failure_rows:
            raise HTTPException(status_code=404, detail="该任务无失败清单")
        text = jobs.failures_csv_text(job)
        return Response(
            content="\ufeff" + text,
            media_type="text/csv; charset=utf-8",
            headers={
                "Content-Disposition": f"attachment; filename=failures_{job_id}.csv"
            },
        )

    @app.post("/api/v1/jobs/{job_id}/cancel")
    def job_cancel(job_id: str, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        ok = deps.get_manager().cancel(job_id)
        if not ok:
            raise HTTPException(
                status_code=409, detail="任务不可取消（不存在或已结束）"
            )
        return {"job_id": job_id, "cancelled": True}

    @app.get("/api/v1/jobs/{job_id}/exports")
    def job_exports(job_id: str, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        with job._lock:
            results = list(job.results)
        items = [
            {"index": n, "zone": r.get("zone", ""), "path": str(r.get("new") or "")}
            for n, r in enumerate(results)
            if r.get("status") == "exported" and r.get("new")
        ]
        return {"job_id": job_id, "total": len(items), "items": items}

    @app.get("/api/v1/jobs/{job_id}/exports/{index}")
    def job_export_file(job_id: str, index: int, _: None = _auth()) -> FileResponse:  # type: ignore[valid-type]
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        with job._lock:
            results = list(job.results)
        exported = [
            r for r in results if r.get("status") == "exported" and r.get("new")
        ]
        if index < 0 or index >= len(exported):
            raise HTTPException(status_code=404, detail="导出文件不存在")
        raw = str(exported[index].get("new") or "")
        candidate = os.path.realpath(raw)
        allowed = {
            os.path.realpath(d)
            for d in {
                deps.default_dirs()["export_dir"],
                deps.default_dirs()["backup_dir"],
                "./cf_export",
                "./cf_backup",
            }
        }
        if not any(
            candidate == base or candidate.startswith(base + os.sep) for base in allowed
        ):
            raise HTTPException(status_code=403, detail="导出路径不在允许目录内")
        if not os.path.isfile(candidate):
            raise HTTPException(status_code=404, detail="导出文件已不在磁盘上")
        return FileResponse(candidate)

    @app.post("/api/v1/resume-preview")
    async def resume_preview(request: Request, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        data = await request.body()
        if len(data) > 2 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="文件过大（上限 2MB）")
        try:
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise HTTPException(status_code=400, detail=f"清单解码失败: {exc}") from exc
        reader = csv.DictReader(io.StringIO(text))
        if reader.fieldnames is None:
            raise HTTPException(status_code=400, detail="清单为空")
        lowered = {str(n or "").strip().lower() for n in reader.fieldnames}
        if "zone" not in lowered:
            raise HTTPException(status_code=400, detail="重跑文件缺少 zone 列")
        rows = [r for r in reader if any(str(v or "").strip() for v in r.values())]
        preview = [
            {
                "account": str(r.get("account") or r.get("Account") or ""),
                "zone": str(r.get("zone") or r.get("Zone") or ""),
            }
            for r in rows[:50]
        ]
        return {"rows": len(rows), "preview": preview}

    @app.post("/api/v1/resume-upload")
    async def resume_upload(file: UploadFile, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        data = await file.read()
        if len(data) > 2 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="文件过大（上限 2MB）")
        handle = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
        try:
            handle.write(data)
        finally:
            handle.close()
        try:
            entries = engine_adapter.load_resume_entries_strict(handle.name)
        except engine_adapter.EngineError as exc:
            try:
                os.unlink(handle.name)
            except OSError:
                pass
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        zones = sorted({z for _a, z in entries if z})
        return {"path": handle.name, "rows": len(entries), "zones": zones[:100]}

    @app.get("/api/v1/history")
    def history(limit: int = 50, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        try:
            return {"items": db.list_history(limit)}
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc)) from exc

    @app.get("/api/v1/audit")
    def audit(limit: int = 50, _: None = _auth()) -> dict[str, Any]:  # type: ignore[valid-type]
        try:
            return {"items": db.list_audit(limit)}
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=502, detail=str(exc)) from exc

    # ---- SPA ----
    base = os.path.abspath(frontend) if frontend else ""
    if base and os.path.isdir(base):

        @app.get("/")
        def index() -> FileResponse:
            page = os.path.join(base, "index.html")
            if not os.path.exists(page):
                raise HTTPException(status_code=500, detail="前端页面缺失")
            return FileResponse(page, media_type="text/html; charset=utf-8")

        @app.get("/{path:path}")
        def spa(path: str) -> FileResponse:
            if path.startswith("api/"):
                raise HTTPException(status_code=404, detail="接口不存在")
            candidate = os.path.abspath(os.path.join(base, path))
            if candidate.startswith(base + os.sep) and os.path.isfile(candidate):
                return FileResponse(candidate)
            return FileResponse(
                os.path.join(base, "index.html"), media_type="text/html; charset=utf-8"
            )

    return app
