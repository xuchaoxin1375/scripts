# -*- coding: utf-8 -*-
"""运行时出口代理：保存代理列表、总开关与单项开关，重建内存代理池。

配置仅驻当前进程；重启 WebUI 后回到启动参数或直连。
代理 URL 含凭据，只在服务端保存，下发给界面时脱敏。
"""

from __future__ import annotations

from typing import Any

from .. import deps, engine_adapter

PROXY_MODES = ("round-robin", "sticky", "failover")
MAX_PROXIES = 50


def _validate_proxy_url(eng: Any, text: str) -> str:
    try:
        return eng.validate_proxy_url(text)
    except ValueError as exc:
        shown = eng.sanitize_proxy_url(text)
        raise ValueError(
            "代理地址格式错误，需为 http(s)://[user:pass@]host:port，"
            f"收到: {shown}"
        ) from exc


def proxy_payload() -> dict[str, Any]:
    """返回可下发的代理配置；proxies 中 url 已脱敏，不含 userinfo。"""
    eng = engine_adapter.engine()
    state = deps.get_proxy_config()
    with state.lock:
        entries = [
            {
                "id": entry.id,
                "url": eng.sanitize_proxy_url(entry.url),
                "enabled": bool(entry.enabled),
            }
            for entry in state.entries
        ]
        master = bool(state.enabled)
        mode = state.mode
        enabled_count = sum(1 for entry in state.entries if entry.enabled)
        pool = deps.get_proxy_pool()
        active_count = len(getattr(pool, "urls", []) or [])
    return {
        "enabled": master,
        "mode": mode,
        "proxies": entries,
        "count": active_count,
        "total": len(entries),
        "enabled_count": enabled_count,
        "active": bool(master and active_count),
        "persisted": False,
    }


def apply_proxy_settings(
    enabled: bool,
    mode: str,
    proxies: list[dict[str, Any]],
) -> dict[str, Any]:
    """保存配置并按总开关与单项开关重建代理池。

    已有条目可只传 id 保留原地址与凭据；新增条目必须带 url。
    """
    eng = engine_adapter.engine()
    normalized_mode = (mode or "round-robin").strip().lower()
    if normalized_mode not in PROXY_MODES:
        raise ValueError(f"不支持的代理模式: {mode}")

    state = deps.get_proxy_config()
    with state.lock:
        existing = {entry.id: entry for entry in state.entries}
        new_entries: list[deps.ProxyEntry] = []
        seen_ids: set[str] = set()
        for item in proxies or []:
            item_id = str(item.get("id") or "").strip()
            raw_url = item.get("url")
            item_enabled = bool(item.get("enabled", True))
            if item_id:
                current = existing.get(item_id)
                if current is None or item_id in seen_ids:
                    raise ValueError("代理条目不存在或重复，请刷新后重试")
                seen_ids.add(item_id)
                url = current.url
                if raw_url is not None and str(raw_url).strip():
                    url = _validate_proxy_url(eng, str(raw_url))
                new_entries.append(
                    deps.ProxyEntry(id=current.id, url=url, enabled=item_enabled)
                )
            else:
                text = str(raw_url or "").strip()
                if not text:
                    raise ValueError("新增代理必须提供地址")
                url = _validate_proxy_url(eng, text)
                new_id = deps.new_proxy_id()
                while new_id in existing or new_id in seen_ids:
                    new_id = deps.new_proxy_id()
                seen_ids.add(new_id)
                new_entries.append(
                    deps.ProxyEntry(id=new_id, url=url, enabled=item_enabled)
                )

        # 同地址只保留一条；任一条启用即视为启用，避免重复代理占多个槽位。
        deduped: dict[str, deps.ProxyEntry] = {}
        for entry in new_entries:
            if entry.url in deduped:
                if entry.enabled:
                    deduped[entry.url].enabled = True
            else:
                deduped[entry.url] = entry
        new_entries = list(deduped.values())
        if len(new_entries) > MAX_PROXIES:
            raise ValueError(f"代理数量最多 {MAX_PROXIES} 个，收到 {len(new_entries)} 个")

        active_urls = (
            [entry.url for entry in new_entries if entry.enabled] if enabled else []
        )
        pool = (
            eng.ProxyPool(active_urls, mode=normalized_mode) if active_urls else None
        )
        state.enabled = bool(enabled)
        state.mode = normalized_mode
        state.entries = new_entries
        deps.set_proxy_pool(pool)

    return proxy_payload()
