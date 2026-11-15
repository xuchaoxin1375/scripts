import {
  ArrowDownAZ,
  ArrowUpAZ,
  ChevronLeft,
  ChevronRight,
  Download,
  Loader2,
  Pencil,
  Search,
  Trash2,
} from "lucide-react";
import { useEffect, useState } from "react";
import type { DnsRecord, RecordFilters } from "../types";
import { shortName, zoneSuffix } from "../shared/names";

type Props = {
  zone: string;
  records: DnsRecord[];
  total: number;
  page: number;
  perPage: number;
  loading: boolean;
  fetching: boolean;
  error: string | null;
  filters: RecordFilters;
  selectedIds: Set<string>;
  onFilters: (patch: Partial<RecordFilters>) => void;
  onPage: (page: number) => void;
  onToggle: (record: DnsRecord) => void;
  onToggleAll: (items: DnsRecord[]) => void;
  onEdit: (record: DnsRecord) => void;
  onDelete: (record: DnsRecord) => void;
  onExport: () => void;
  onRetry: () => void;
};

type SortKey = "name" | "type" | "content";

function typeClass(type: string) {
  const key = type.toLowerCase();
  if (key === "a") return "type-a";
  if (key === "aaaa") return "type-aaaa";
  if (key === "cname") return "type-cname";
  if (key === "txt") return "type-txt";
  if (key === "mx") return "type-mx";
  return "type-other";
}

function SkeletonRows({ count = 6 }: { count?: number }) {
  return (
    <>
      {Array.from({ length: count }).map((_, index) => (
        <tr className="skeleton-row" key={index}>
          <td colSpan={8}>
            <span className="skeleton-line" />
          </td>
        </tr>
      ))}
    </>
  );
}

export default function RecordsTable({
  zone,
  records,
  total,
  page,
  perPage,
  loading,
  fetching,
  error,
  filters,
  selectedIds,
  onFilters,
  onPage,
  onToggle,
  onToggleAll,
  onEdit,
  onDelete,
  onExport,
  onRetry,
}: Props) {
  const [query, setQuery] = useState(filters.search);

  useEffect(() => {
    setQuery(filters.search);
  }, [filters.search]);

  useEffect(() => {
    if (query === filters.search) return;
    const timer = window.setTimeout(() => onFilters({ search: query }), 350);
    return () => window.clearTimeout(timer);
  }, [query, filters.search, onFilters]);

  const sortKey = (filters.sort.replace(/^-/, "") || "name") as SortKey;
  const sortDesc = filters.sort.startsWith("-");
  const allSelected =
    records.length > 0 && records.every((record) => selectedIds.has(record.id));
  const partiallySelected =
    records.some((record) => selectedIds.has(record.id)) && !allSelected;
  const pageCount = Math.max(1, Math.ceil(total / Math.max(1, perPage)));
  const start = total === 0 ? 0 : (page - 1) * perPage + 1;
  const end = Math.min(total, (page - 1) * perPage + records.length);
  const hasFilters =
    filters.search.trim() !== "" ||
    filters.type !== "ALL" ||
    filters.proxied !== "all" ||
    query.trim() !== "";

  function changeSort(key: SortKey) {
    const nextDesc = sortKey === key ? !sortDesc : false;
    onFilters({ sort: `${nextDesc ? "-" : ""}${key}` });
  }

  function sortIcon(key: SortKey) {
    if (sortKey !== key) return <ArrowDownAZ size={13} className="muted-icon" />;
    return sortDesc ? <ArrowDownAZ size={13} /> : <ArrowUpAZ size={13} />;
  }

  function clearFilters() {
    setQuery("");
    onFilters({ search: "", type: "ALL", proxied: "all" });
  }

  const emptyTitle = error
    ? "记录加载失败"
    : !zone
      ? "未选择域名"
      : hasFilters
        ? "没有匹配记录"
        : "该域名暂无记录";
  const emptyCopy = error
    ? error
    : !zone
      ? "先在顶部切换账号与域名。"
      : hasFilters
        ? "调整搜索或筛选条件，或清除过滤后重试。"
        : "点击页头的新增记录，或刷新后重试。";

  return (
    <section
      className="records-panel"
      aria-label="DNS 记录"
      aria-busy={loading}
      tabIndex={-1}
      data-focus-fallback
    >
      <div className="records-toolbar">
        <label className="search-field">
          <Search size={15} />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="搜索名称或内容"
            aria-label="搜索记录"
          />
        </label>
        <label className="compact-select">
          <span className="sr-only">记录类型</span>
          <select
            value={filters.type}
            onChange={(event) => onFilters({ type: event.target.value })}
          >
            <option value="ALL">全部类型</option>
            <option value="A">A</option>
            <option value="AAAA">AAAA</option>
            <option value="CNAME">CNAME</option>
            <option value="MX">MX</option>
            <option value="TXT">TXT</option>
          </select>
        </label>
        <label className="compact-select">
          <span className="sr-only">代理状态</span>
          <select
            value={filters.proxied}
            onChange={(event) => onFilters({ proxied: event.target.value })}
          >
            <option value="all">全部代理</option>
            <option value="proxied">已代理</option>
            <option value="dnsonly">仅 DNS</option>
          </select>
        </label>
        <span className="fetch-state" aria-live="polite">
          {fetching ? (
            <>
              <Loader2 size={13} className="spin" /> 加载中
            </>
          ) : (
            `${total} 条`
          )}
        </span>
        <button
          className="button ghost"
          onClick={onExport}
          disabled={total === 0 && selectedIds.size === 0}
        >
          <Download size={15} /> 导出
        </button>
      </div>

      {error && records.length > 0 && (
        <div className="error-inline">
          刷新失败：{error}
          <button className="link-button" onClick={onRetry}>
            重试
          </button>
        </div>
      )}

      <div className="table-wrap" role="region" aria-label="DNS 记录列表" tabIndex={0}>
        <table className="records-table">
          <caption className="sr-only">DNS 记录列表</caption>
          <colgroup>
            <col style={{ width: 38 }} />
            <col style={{ width: 220 }} />
            <col style={{ width: 84 }} />
            <col />
            <col style={{ width: 96 }} />
            <col style={{ width: 64 }} />
            <col style={{ width: 120 }} />
            <col style={{ width: 126 }} />
          </colgroup>
          <thead>
            <tr>
              <th className="check-cell">
                <label className="checkbox-hit">
                  <input
                    type="checkbox"
                    checked={allSelected}
                    ref={(element) => {
                      if (element) element.indeterminate = partiallySelected;
                    }}
                    onChange={() => onToggleAll(records)}
                    aria-label="全选当前页记录"
                  />
                </label>
              </th>
              <th
                aria-sort={
                  sortKey === "name"
                    ? sortDesc
                      ? "descending"
                      : "ascending"
                    : "none"
                }
              >
                <button onClick={() => changeSort("name")}>
                  名称 {sortIcon("name")}
                </button>
              </th>
              <th
                aria-sort={
                  sortKey === "type"
                    ? sortDesc
                      ? "descending"
                      : "ascending"
                    : "none"
                }
              >
                <button onClick={() => changeSort("type")}>
                  类型 {sortIcon("type")}
                </button>
              </th>
              <th
                aria-sort={
                  sortKey === "content"
                    ? sortDesc
                      ? "descending"
                      : "ascending"
                    : "none"
                }
              >
                <button onClick={() => changeSort("content")}>
                  内容 {sortIcon("content")}
                </button>
              </th>
              <th>代理</th>
              <th>TTL</th>
              <th>备注</th>
              <th className="sticky-action">操作</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <SkeletonRows />
            ) : (
              records.map((record) => {
                const selected = selectedIds.has(record.id);
                return (
                  <tr
                    key={record.id}
                    className={selected ? "selected" : ""}
                    onClick={() => onToggle(record)}
                  >
                    <td
                      className="check-cell"
                      onClick={(event) => event.stopPropagation()}
                    >
                      <label className="checkbox-hit">
                        <input
                          type="checkbox"
                          checked={selected}
                          onChange={() => onToggle(record)}
                          aria-label={`选择 ${shortName(record.name, zone)}`}
                        />
                      </label>
                    </td>
                    <td className="name-cell">
                      <span className="record-name" title={record.name}>
                        {shortName(record.name, zone)}
                        {zoneSuffix(record.name, zone) && (
                          <span className="record-zone">
                            {zoneSuffix(record.name, zone)}
                          </span>
                        )}
                      </span>
                      {record.name.startsWith("*") &&
                        shortName(record.name, zone) !== "*" && (
                          <span className="wildcard-mark">*</span>
                        )}
                    </td>
                    <td>
                      <span className={`type-pill ${typeClass(record.type)}`}>
                        {record.type}
                      </span>
                    </td>
                    <td className="content-cell" title={record.content}>
                      <code>{record.content}</code>
                    </td>
                    <td>
                      {record.proxied ? (
                        <span className="proxy-on">
                          <span className="proxy-dot" /> 已代理
                        </span>
                      ) : (
                        <span className="proxy-off">
                          <span className="proxy-dot" /> 仅 DNS
                        </span>
                      )}
                    </td>
                    <td>{record.ttl === 1 ? "自动" : record.ttl}</td>
                    <td className="comment-cell" title={record.comment}>
                      {record.comment || <span className="muted">—</span>}
                    </td>
                    <td
                      className="sticky-action"
                      onClick={(event) => event.stopPropagation()}
                    >
                      <span className="row-actions">
                        <button
                          type="button"
                          className="row-action"
                          onClick={() => onEdit(record)}
                        >
                          <Pencil size={13} aria-hidden="true" /> 编辑
                        </button>
                        <button
                          type="button"
                          className="row-action danger"
                          onClick={() => onDelete(record)}
                        >
                          <Trash2 size={13} aria-hidden="true" /> 删除
                        </button>
                      </span>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
        {!loading && records.length === 0 && (
          <div className="empty-state">
            <p className="empty-title">{emptyTitle}</p>
            <p className="empty-copy">{emptyCopy}</p>
            {error ? (
              <button className="button" onClick={onRetry}>
                重试
              </button>
            ) : (
              hasFilters && (
                <button className="button" onClick={clearFilters}>
                  清除过滤
                </button>
              )
            )}
          </div>
        )}
      </div>

      <div className="record-cards" aria-label="DNS 记录卡片">
        {loading &&
          Array.from({ length: 3 }).map((_, index) => (
            <div className="record-card skeleton-card" key={index}>
              <span className="skeleton-line" />
              <span className="skeleton-line short" />
            </div>
          ))}
        {!loading &&
          records.map((record) => {
            const selected = selectedIds.has(record.id);
            return (
              <article
                key={record.id}
                className={`record-card ${selected ? "selected" : ""}`}
                onClick={() => onToggle(record)}
              >
                <div className="record-card-head">
                  <label
                    className="checkbox-hit"
                    onClick={(event) => event.stopPropagation()}
                  >
                    <input
                      type="checkbox"
                      checked={selected}
                      onChange={() => onToggle(record)}
                      aria-label={`选择 ${shortName(record.name, zone)}`}
                    />
                  </label>
                  <strong className="record-name">
                    {shortName(record.name, zone)}
                  </strong>
                  <span className={`type-pill ${typeClass(record.type)}`}>
                    {record.type}
                  </span>
                </div>
                <code className="record-card-content">{record.content}</code>
                <div className="record-card-meta">
                  <span>{record.proxied ? "已代理" : "仅 DNS"}</span>
                  <span>TTL {record.ttl === 1 ? "自动" : record.ttl}</span>
                  {record.comment && <span>备注 {record.comment}</span>}
                </div>
                <div className="record-card-actions">
                  <button
                    type="button"
                    className="row-action"
                    onClick={(event) => {
                      event.stopPropagation();
                      onEdit(record);
                    }}
                  >
                    <Pencil size={13} aria-hidden="true" /> 编辑
                  </button>
                  <button
                    type="button"
                    className="row-action danger"
                    onClick={(event) => {
                      event.stopPropagation();
                      onDelete(record);
                    }}
                  >
                    <Trash2 size={13} aria-hidden="true" /> 删除
                  </button>
                </div>
              </article>
            );
          })}
        {!loading && records.length === 0 && (
          <div className="empty-state">
            <p className="empty-title">{emptyTitle}</p>
            <p className="empty-copy">{emptyCopy}</p>
            {error ? (
              <button className="button" onClick={onRetry}>
                重试
              </button>
            ) : (
              hasFilters && (
                <button className="button" onClick={clearFilters}>
                  清除过滤
                </button>
              )
            )}
          </div>
        )}
      </div>

      <footer className="records-footer">
        <span>
          {total === 0
            ? "共 0 条"
            : `第 ${start}–${end} 条，共 ${total} 条`}{" "}
          · {zone || "未选择域名"}
        </span>
        <span className="pager" aria-label="分页">
          <button
            type="button"
            className="button ghost"
            onClick={() => onPage(page - 1)}
            disabled={page <= 1 || loading}
          >
            <ChevronLeft size={14} aria-hidden="true" />
            上一页
          </button>
          <span className="page-indicator">
            {page} / {pageCount}
          </span>
          <button
            type="button"
            className="button ghost"
            onClick={() => onPage(page + 1)}
            disabled={page >= pageCount || loading}
          >
            下一页
            <ChevronRight size={14} aria-hidden="true" />
          </button>
        </span>
      </footer>
    </section>
  );
}
