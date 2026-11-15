import {
  ArrowDownAZ,
  ArrowUpAZ,
  Download,
  Pencil,
  Search,
  SlidersHorizontal,
} from "lucide-react";
import { useMemo, useState } from "react";
import type { DnsRecord } from "../types";

type Props = {
  zone: string;
  records: DnsRecord[];
  selectedIds: Set<string>;
  onToggle: (id: string) => void;
  onToggleAll: (items: DnsRecord[]) => void;
  onEdit: (record: DnsRecord) => void;
  onNotify: (message: string) => void;
};

type SortKey = "name" | "type" | "content";

function shortName(full: string, zone: string) {
  if (!zone) return full;
  const lower = full.toLowerCase();
  const suffix = `.${zone.toLowerCase()}`;
  if (lower === zone.toLowerCase()) return "@";
  if (lower.endsWith(suffix)) return full.slice(0, full.length - suffix.length);
  return full;
}

function typeClass(type: string) {
  const key = type.toLowerCase();
  if (key === "a") return "type-a";
  if (key === "aaaa") return "type-aaaa";
  if (key === "cname") return "type-cname";
  if (key === "mx") return "type-mx";
  return "type-other";
}

export default function RecordsTable({
  zone,
  records,
  selectedIds,
  onToggle,
  onToggleAll,
  onEdit,
  onNotify,
}: Props) {
  const [query, setQuery] = useState("");
  const [type, setType] = useState("ALL");
  const [proxy, setProxy] = useState("all");
  const [sort, setSort] = useState<{ key: SortKey; direction: "asc" | "desc" }>({
    key: "name",
    direction: "asc",
  });

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    const filtered = records.filter((record) => {
      if (type !== "ALL" && record.type !== type) return false;
      if (proxy === "proxied" && !record.proxied) return false;
      if (proxy === "dnsonly" && record.proxied) return false;
      if (
        q &&
        !record.name.toLowerCase().includes(q) &&
        !record.content.toLowerCase().includes(q)
      ) {
        return false;
      }
      return true;
    });
    const direction = sort.direction === "asc" ? 1 : -1;
    return [...filtered].sort((a, b) => {
      const left = String(a[sort.key] ?? "");
      const right = String(b[sort.key] ?? "");
      return left.localeCompare(right, "zh-CN") * direction;
    });
  }, [records, query, type, proxy, sort]);

  const allSelected = visible.length > 0 && visible.every((record) => selectedIds.has(record.id));
  const partiallySelected = visible.some((record) => selectedIds.has(record.id)) && !allSelected;

  function changeSort(key: SortKey) {
    setSort((current) =>
      current.key === key
        ? { key, direction: current.direction === "asc" ? "desc" : "asc" }
        : { key, direction: "asc" },
    );
  }

  function sortIcon(key: SortKey) {
    if (sort.key !== key) return <ArrowDownAZ size={13} className="muted-icon" />;
    return sort.direction === "asc" ? (
      <ArrowUpAZ size={13} />
    ) : (
      <ArrowDownAZ size={13} />
    );
  }

  return (
    <section className="records-panel" aria-label="DNS 记录">
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
          <select value={type} onChange={(event) => setType(event.target.value)}>
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
          <select value={proxy} onChange={(event) => setProxy(event.target.value)}>
            <option value="all">全部代理</option>
            <option value="proxied">已代理</option>
            <option value="dnsonly">仅 DNS</option>
          </select>
        </label>
        <button className="button ghost" onClick={() => onNotify("列显示设置将在下一步接入")}>
          <SlidersHorizontal size={15} /> 显示
        </button>
        <button className="button ghost" onClick={() => onNotify("导出当前范围（原型）")}>
          <Download size={15} /> 导出
        </button>
      </div>

      <div className="table-wrap">
        <table className="records-table">
          <caption className="sr-only">DNS 记录列表</caption>
          <colgroup>
            <col style={{ width: 36 }} />
            <col style={{ width: 190 }} />
            <col style={{ width: 84 }} />
            <col />
            <col style={{ width: 96 }} />
            <col style={{ width: 64 }} />
            <col style={{ width: 100 }} />
            <col style={{ width: 76 }} />
          </colgroup>
          <thead>
            <tr>
              <th className="check-cell">
                <input
                  type="checkbox"
                  checked={allSelected}
                  ref={(element) => {
                    if (element) element.indeterminate = partiallySelected;
                  }}
                  onChange={() => onToggleAll(visible)}
                  aria-label="全选当前页记录"
                />
              </th>
              <th aria-sort={sort.key === "name" ? (sort.direction === "asc" ? "ascending" : "descending") : "none"}>
                <button onClick={() => changeSort("name")}>名称 {sortIcon("name")}</button>
              </th>
              <th aria-sort={sort.key === "type" ? (sort.direction === "asc" ? "ascending" : "descending") : "none"}>
                <button onClick={() => changeSort("type")}>类型 {sortIcon("type")}</button>
              </th>
              <th aria-sort={sort.key === "content" ? (sort.direction === "asc" ? "ascending" : "descending") : "none"}>
                <button onClick={() => changeSort("content")}>内容 {sortIcon("content")}</button>
              </th>
              <th>代理</th>
              <th>TTL</th>
              <th>备注</th>
              <th className="sticky-action">操作</th>
            </tr>
          </thead>
          <tbody>
            {visible.map((record) => {
              const selected = selectedIds.has(record.id);
              return (
                <tr
                  key={record.id}
                  className={selected ? "selected" : ""}
                  onClick={() => onToggle(record.id)}
                >
                  <td className="check-cell" onClick={(event) => event.stopPropagation()}>
                    <input
                      type="checkbox"
                      checked={selected}
                      onChange={() => onToggle(record.id)}
                      aria-label={`选择 ${shortName(record.name, zone)}`}
                    />
                  </td>
                  <td className="name-cell">
                    <span className="record-name" title={record.name}>
                      {shortName(record.name, zone)}
                    </span>
                    {record.name.startsWith("*") && shortName(record.name, zone) !== "*" && (
                      <span className="wildcard-mark">*</span>
                    )}
                  </td>
                  <td>
                    <span className={`type-pill ${typeClass(record.type)}`}>{record.type}</span>
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
                  <td className="sticky-action" onClick={(event) => event.stopPropagation()}>
                    <button className="row-action" onClick={() => onEdit(record)}>
                      <Pencil size={13} /> 编辑
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {visible.length === 0 && (
          <div className="empty-state">
            <p className="empty-title">没有匹配记录</p>
            <p className="empty-copy">调整搜索或筛选条件，或清除过滤后重试。</p>
            <button
              className="button"
              onClick={() => {
                setQuery("");
                setType("ALL");
                setProxy("all");
              }}
            >
              清除过滤
            </button>
          </div>
        )}
      </div>

      <div className="record-cards" aria-label="DNS 记录卡片">
        {visible.map((record) => {
          const selected = selectedIds.has(record.id);
          return (
            <article
              key={record.id}
              className={`record-card ${selected ? "selected" : ""}`}
              onClick={() => onToggle(record.id)}
            >
              <div className="record-card-head">
                <input
                  type="checkbox"
                  checked={selected}
                  onChange={() => onToggle(record.id)}
                  onClick={(event) => event.stopPropagation()}
                  aria-label={`选择 ${shortName(record.name, zone)}`}
                />
                <strong className="record-name">{shortName(record.name, zone)}</strong>
                <span className={`type-pill ${typeClass(record.type)}`}>{record.type}</span>
                <button
                  className="row-action"
                  onClick={(event) => {
                    event.stopPropagation();
                    onEdit(record);
                  }}
                >
                  <Pencil size={13} /> 编辑
                </button>
              </div>
              <code className="record-card-content">{record.content}</code>
              <div className="record-card-meta">
                <span>{record.proxied ? "已代理" : "仅 DNS"}</span>
                <span>TTL {record.ttl === 1 ? "自动" : record.ttl}</span>
                {record.comment && <span>备注 {record.comment}</span>}
              </div>
            </article>
          );
        })}
        {visible.length === 0 && (
          <div className="empty-state">
            <p className="empty-title">没有匹配记录</p>
            <p className="empty-copy">调整搜索或筛选条件，或清除过滤后重试。</p>
          </div>
        )}
      </div>

      <footer className="records-footer">
        <span>
          第 1–{visible.length} 条，共 {visible.length} 条 · {zone || "未选择域名"}
        </span>
        <span className="pager" aria-label="分页（原型）">
          <button className="button ghost" disabled>
            上一页
          </button>
          <button className="button ghost" disabled>
            下一页
          </button>
        </span>
      </footer>
    </section>
  );
}
