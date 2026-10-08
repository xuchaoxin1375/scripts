# -*- coding: utf-8 -*-
"""持久化：标准库 sqlite3（WAL），库文件放账号配置同目录 cf_web.db。

表：
- jobs_history：终态 upsert，供任务页历史查询。
- audit_log：execute 提交与单条增删改审计。

旧库迁移：缺列则 ALTER TABLE 补列，数据保留（回归 no such column: kind）。
"""

from __future__ import annotations

import os
import sqlite3
import threading
from datetime import datetime, timezone
from typing import Any

_lock = threading.Lock()
_db_path: str = ""

JOBS_COLUMNS = [
    ("id", "TEXT PRIMARY KEY"),
    ("mode", "TEXT"),
    ("status", "TEXT"),
    ("label", "TEXT"),
    ("accounts", "TEXT"),
    ("exit_code", "INTEGER"),
    ("created_at", "TEXT"),
    ("finished_at", "TEXT"),
]

AUDIT_COLUMNS = [
    ("id", "INTEGER PRIMARY KEY AUTOINCREMENT"),
    ("ts", "TEXT"),
    ("kind", "TEXT"),
    ("account", "TEXT"),
    ("detail", "TEXT"),
]


def db_path_for_config(config_path: str) -> str:
    parent = os.path.dirname(os.path.abspath(config_path))
    return os.path.join(parent, "cf_web.db")


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(_db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def _ensure_table(
    conn: sqlite3.Connection, table: str, columns: list[tuple[str, str]]
) -> None:
    existing: set[str] = set()
    try:
        rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
        existing = {str(r["name"]) for r in rows}
    except sqlite3.OperationalError:
        existing = set()
    if not existing:
        defs = ", ".join(
            f"{name} {ddl}" if "PRIMARY KEY" in ddl else f"{name} {ddl}"
            for name, ddl in columns
        )
        # 主键列定义已含类型，直接拼接
        conn.execute(f"CREATE TABLE IF NOT EXISTS {table} ({defs})")
        return
    for name, ddl in columns:
        if name not in existing:
            coltype = ddl.replace(" PRIMARY KEY", "")
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {coltype}")


def init_db(config_path: str) -> str:
    """初始化库文件并执行迁移，返回库路径。"""
    global _db_path
    _db_path = db_path_for_config(config_path)
    with _lock:
        conn = _connect()
        try:
            conn.execute("PRAGMA journal_mode=WAL")
            _ensure_table(conn, "jobs_history", JOBS_COLUMNS)
            _ensure_table(conn, "audit_log", AUDIT_COLUMNS)
            conn.commit()
        finally:
            conn.close()
    return _db_path


def _require_db() -> str:
    if not _db_path:
        raise RuntimeError("db 未初始化")
    return _db_path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def upsert_history(entry: dict[str, Any]) -> None:
    """终态 upsert：同 id 覆盖，保证历史只有一条终态。"""
    _require_db()
    with _lock:
        conn = _connect()
        try:
            _ensure_table(conn, "jobs_history", JOBS_COLUMNS)
            conn.execute(
                "INSERT INTO jobs_history(id, mode, status, label, accounts, exit_code, created_at, finished_at)"
                " VALUES(?,?,?,?,?,?,?,?)"
                " ON CONFLICT(id) DO UPDATE SET mode=excluded.mode, status=excluded.status,"
                " label=excluded.label, accounts=excluded.accounts, exit_code=excluded.exit_code,"
                " finished_at=excluded.finished_at",
                (
                    str(entry.get("id", "")),
                    str(entry.get("mode", "")),
                    str(entry.get("status", "")),
                    str(entry.get("label", "")),
                    str(entry.get("accounts", "")),
                    entry.get("exit_code"),
                    str(entry.get("created_at", "")),
                    str(entry.get("finished_at", "")),
                ),
            )
            conn.commit()
        finally:
            conn.close()


def list_history(limit: int = 50) -> list[dict[str, Any]]:
    _require_db()
    with _lock:
        conn = _connect()
        try:
            _ensure_table(conn, "jobs_history", JOBS_COLUMNS)
            rows = conn.execute(
                "SELECT id, mode, status, label, accounts, exit_code, created_at, finished_at"
                " FROM jobs_history ORDER BY finished_at DESC LIMIT ?",
                (max(1, limit),),
            ).fetchall()
            return [dict(r) for r in rows]
        finally:
            conn.close()


def audit(kind: str, account: str = "", detail: str = "") -> None:
    """记录审计行；kind 如 execute/single_create/single_delete。"""
    _require_db()
    with _lock:
        conn = _connect()
        try:
            _ensure_table(conn, "audit_log", AUDIT_COLUMNS)
            conn.execute(
                "INSERT INTO audit_log(ts, kind, account, detail) VALUES(?,?,?,?)",
                (utc_now(), kind, account, detail),
            )
            conn.commit()
        finally:
            conn.close()


def list_audit(limit: int = 50) -> list[dict[str, Any]]:
    _require_db()
    with _lock:
        conn = _connect()
        try:
            _ensure_table(conn, "audit_log", AUDIT_COLUMNS)
            rows = conn.execute(
                "SELECT id, ts, kind, account, detail FROM audit_log ORDER BY id DESC LIMIT ?",
                (max(1, limit),),
            ).fetchall()
            return [dict(r) for r in rows]
        finally:
            conn.close()
