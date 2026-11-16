import {
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  ChevronLeft,
  ChevronRight,
  Download,
  Loader2,
  Pencil,
  RotateCcw,
  Search,
  Trash2,
} from "lucide-react";
import { useEffect, useState } from "react";
import type { DnsRecord, RecordFilters } from "../types";
import { shortName, zoneSuffix } from "../shared/names";
import {
  ResizeHandle,
  useColumnWidths,
  type ColSpec,
} from "./ColumnResize";

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

const SORTABLE_COLUMNS: Array<{ id: SortKey; label: string }> = [
  { id: "name", label: "名称" },
  { id: "type", label: "类型" },
  { id: "content", label: "内容" },
];

// 工具栏排序入口：窄屏卡片视图没有表头，同时承担“重置排序”（默认顺序）。
const SORT_OPTIONS: Array<{ value: string; label: string }> = [
  { value: "", label: "默认顺序" },
  ...SORTABLE_COLUMNS.flatMap((column) => [
    { value: column.id, label: `${column.label}升序` },
    { value: `-${column.id}`, label: `${column.label}降序` },
  ]),
];

const COLUMN_SPECS: ColSpec[] = [
  { id: "name", label: "名称", min: 120, def: 220, max: 520 },
  { id: "type", label: "类型", min: 64, def: 84, max: 160 },
  { id: "content", label: "内容", min: 140, def: 280, max: 720 },
  { id: "proxied", label: "代理", min: 78, def: 96, max: 180 },
  { id: "ttl", label: "TTL", min: 56, def: 64, max: 120 },
  { id: "comment", label: "备注", min: 90, def: 120, max: 360 },
];

const CHECK_W = 38;
const ACTION_W = 132;
const FILLER_MIN = 40;
const FIXED_EXTRA = CHECK_W + ACTION_W;

function isSortKey(id: string): id is SortKey {
  return SORTABLE_COLUMNS.some((column) => column.id === id);
}

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
          <td colSpan={9}>
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
  const colw = useColumnWidths(COLUMN_SPECS, FIXED_EXTRA, FILLER_MIN);

  useEffect(() => {
    setQuery(filters.search);
  }, [filters.search]);

  useEffect(() => {
    if (query === filters.search) return;
    const timer = window.setTimeout(() => onFilters({ search: query }), 150);
    return () => window.clearTimeout(timer);
  }, [query, filters.search, onFilters]);

  const rawSort = filters.sort.trim();
  const rawKey = rawSort.startsWith("-") ? rawSort.slice(1) : rawSort;
  const sortKey = isSortKey(rawKey) ? rawKey : null;
  const sortDesc = rawSort.startsWith("-");
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
    // 两态：新列从升序开始，同列在升序/降序间切换；回到默认顺序用“重置排序”。
    const next = sortKey !== key ? key : sortDesc ? key : `-${key}`;
    onFilters({ sort: next });
  }

  function sortIcon(key: SortKey) {
    if (sortKey !== key) {
      return <ArrowUpDown size={13} className="muted-icon" aria-hidden="true" />;
    }
    return sortDesc ? (
      <ArrowDown size={13} aria-hidden="true" />
    ) : (
      <ArrowUp size={13} aria-hidden="true" />
    );
  }

  function ariaSort(key: SortKey) {
    if (sortKey !== key) return "none" as const;
    return sortDesc ? ("descending" as const) : ("ascending" as const);
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
        <label className="compact-select sort-select">
          <span className="sr-only">排序</span>
          <select
            value={sortKey ? rawSort : ""}
            onChange={(event) => onFilters({ sort: event.target.value })}
          >
            {SORT_OPTIONS.map((option) => (
              <option key={option.value || "default"} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
        {sortKey && (
          <button
            type="button"
            className="button ghost sort-reset"
            onClick={() => onFilters({ sort: "" })}
          >
            <RotateCcw size={14} aria-hidden="true" /> 重置排序
          </button>
        )}
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
        <table
          className="records-table"
          ref={colw.tableRef}
          style={{ minWidth: colw.total }}
        >
          <caption className="sr-only">
            DNS 记录列表。拖动表头右缘的分隔条，或聚焦后使用方向键调整列宽。
          </caption>
          <colgroup>
            <col style={{ width: CHECK_W }} />
            {COLUMN_SPECS.map((spec) => (
              <col
                key={spec.id}
                ref={colw.colRef(spec.id)}
                style={{ width: colw.widths[spec.id] }}
              />
            ))}
            <col />
            <col style={{ width: ACTION_W }} />
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
              {COLUMN_SPECS.map((spec) => {
                const sortableId: SortKey | null = isSortKey(spec.id)
                  ? spec.id
                  : null;
                return (
                  <th
                    key={spec.id}
                    aria-sort={sortableId ? ariaSort(sortableId) : undefined}
                  >
                    {sortableId ? (
                      <button
                        type="button"
                        className={sortKey === sortableId ? "active" : undefined}
                        onClick={() => changeSort(sortableId)}
                      >
                        {spec.label} {sortIcon(sortableId)}
                      </button>
                    ) : (
                      <span>{spec.label}</span>
                    )}
                    <ResizeHandle
                      column={spec.id}
                      label={spec.label}
                      value={colw.widths[spec.id]}
                      min={spec.min}
                      max={spec.max}
                      onPreview={(width) => colw.preview(spec.id, width)}
                      onCommit={(width) => colw.commit(spec.id, width)}
                      onReset={() => colw.reset(spec.id)}
                    />
                  </th>
                );
              })}
              <th className="filler-cell" aria-hidden="true" />
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
                    <td className="filler-cell" aria-hidden="true" />
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
