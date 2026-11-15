# -*- coding: utf-8 -*-
"""DNS 记录读取、单条编辑、批量操作与导入。"""

from __future__ import annotations

import json
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException

from .. import db, engine_adapter
from ..auth import require_auth
from ..common import paginate
from ..schemas import (
    BulkDelete,
    BulkRestore,
    BulkUpdate,
    RecordBody,
    RecordImport,
    RecordPatch,
    SingleRecord,
)
from ..services.accounts import lookup_accounts
from ..services.records import canon_name, import_item_error
from ..services.zones import get_zones, resolve_zone
from ..validate import validate_single_record

router = APIRouter(dependencies=[Depends(require_auth)])


@router.get("/api/v1/records")
def records(
    account: str,
    zone: str,
    type: str = "ALL",  # noqa: A002 - 查询参数名与 Cloudflare 语义对齐
    search: str = "",
    page: int = 1,
    per_page: int = 50,
    sort: str = "",
    proxied: str = "all",
) -> dict[str, Any]:
    matched = lookup_accounts([account])
    try:
        all_zones = get_zones(matched[0])
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
        if wanted not in {"", "ALL"} and str(record.get("type", "")).upper() != wanted:
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
    data = paginate(rows, page, per_page)
    data.update({"account": account, "zone": zone})
    return data


@router.post("/api/v1/records")
def single_record(body: SingleRecord) -> dict[str, Any]:
    err = validate_single_record(body.model_dump())
    if err:
        raise HTTPException(status_code=400, detail=err)
    matched = lookup_accounts([body.account])
    zone_id, zone_name = resolve_zone(matched[0], body.zone)
    name = body.name.strip() or "@"
    want_comment = body.comment or ""
    short_l = name.lower()
    fqdn_l = f"{name}.{zone_name}".lower() if name != "@" else zone_name.lower()

    def _same_name(raw: str) -> bool:
        rl = (raw or "").lower()
        return rl == short_l or rl == fqdn_l or rl == zone_name.lower() and short_l == "@"

    try:
        updater = engine_adapter.build_updater(matched[0])
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"初始化写入客户端失败: {exc}") from exc
    try:
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


@router.patch("/api/v1/records")
def patch_record(body: RecordPatch) -> dict[str, Any]:
    if not body.id.strip():
        raise HTTPException(status_code=400, detail="缺少记录 id")
    matched = lookup_accounts([body.account])
    zone_id, zone_name = resolve_zone(matched[0], body.zone)
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
    merged["name"] = canon_name(str(merged["name"]), zone_name)
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


@router.delete("/api/v1/records")
def delete_record(account: str, zone: str, id: str) -> dict[str, Any]:
    if not id.strip():
        raise HTTPException(status_code=400, detail="缺少记录 id")
    matched = lookup_accounts([account])
    zone_id, zone_name = resolve_zone(matched[0], zone)
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
    """兼容旧名称；实际校验在 services.records。"""
    return import_item_error(index, item)


@router.post("/api/v1/records/bulk-delete")
def bulk_delete(body: BulkDelete) -> dict[str, Any]:
    ids = [str(i).strip() for i in (body.ids or []) if str(i).strip()]
    ids = list(dict.fromkeys(ids))
    if not ids:
        return {"deleted": [], "failed": [], "total": 0}
    if len(ids) > 200:
        raise HTTPException(status_code=400, detail="单次批量删除至多 200 条")
    matched = lookup_accounts([body.account])
    zone_id, zone_name = resolve_zone(matched[0], body.zone)
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


@router.post("/api/v1/records/bulk-update")
def bulk_update(body: BulkUpdate) -> dict[str, Any]:
    ids = [str(i).strip() for i in (body.ids or []) if str(i).strip()]
    ids = list(dict.fromkeys(ids))
    if not ids:
        return {"updated": [], "prev": [], "failed": [], "total": 0}
    if len(ids) > 200:
        raise HTTPException(status_code=400, detail="单次批量更新至多 200 条")
    if body.proxied is None and body.ttl is None:
        raise HTTPException(status_code=400, detail="批量更新至少指定 proxied 或 ttl 其一")
    matched = lookup_accounts([body.account])
    zone_id, zone_name = resolve_zone(matched[0], body.zone)
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


@router.post("/api/v1/records/bulk-restore")
def bulk_restore(body: BulkRestore) -> dict[str, Any]:
    items = list(body.records or [])
    if not items:
        return {"restored": [], "failed": [], "total": 0}
    if len(items) > 200:
        raise HTTPException(status_code=400, detail="单次批量恢复至多 200 条")
    for index, item in enumerate(items, start=1):
        err = _import_item_error(index, item)
        if err:
            raise HTTPException(status_code=400, detail=f"恢复前校验失败，零写入：{err}")
    matched = lookup_accounts([body.account])
    zone_id, zone_name = resolve_zone(matched[0], body.zone)
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
                    "name": canon_name((item.name or "").strip() or "@", zone_name),
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


@router.post("/api/v1/records/import")
def import_records(body: RecordImport) -> dict[str, Any]:
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
    matched = lookup_accounts([body.account])
    resolve_zone(matched[0], body.zone)
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
