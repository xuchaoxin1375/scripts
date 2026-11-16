import { Layers, Plus, RefreshCw, X } from "lucide-react";
import type { Attachments } from "../types";

type Props = {
  account: string;
  zone: string;
  zoneStatus?: string;
  recordCount: number;
  selectedCount: number;
  refreshing: boolean;
  mode: "local" | "server";
  attachments: Attachments;
  onRefresh: () => void;
  onAdd: () => void;
  onBatch: () => void;
  onClearAttachment: (kind: "whitelist" | "resume") => void;
};

export default function ScopeBar({
  account,
  zone,
  zoneStatus,
  recordCount,
  selectedCount,
  refreshing,
  mode,
  attachments,
  onRefresh,
  onAdd,
  onBatch,
  onClearAttachment,
}: Props) {
  return (
    <>
      <header className="page-head workspace-head">
        <div className="page-head-copy">
          <div className="eyebrow">DNS</div>
          <h1>DNS 记录</h1>
          <p className="page-sub">
            {account ? `账号 ${account} · ` : ""}
            管理 {zone || "当前域名"} 的解析记录；批量写入先预览，确认后执行。
          </p>
        </div>
        <div className="page-actions">
          <button className="button" onClick={onBatch} disabled={!zone}>
            <Layers size={15} aria-hidden="true" />
            批量操作
          </button>
          <button
            className="button primary"
            onClick={onAdd}
            disabled={!zone}
            data-add-record
          >
            <Plus size={15} aria-hidden="true" />
            新增记录
          </button>
        </div>
      </header>

      <div className="context-strip" aria-label="当前范围">
        <span
          className={`dot ${zoneStatus || ""}`}
          aria-hidden="true"
        />
        <strong className="context-zone" title={zone || undefined}>
          {zone || "未选择域名"}
        </strong>
        {zoneStatus && (
          <span className={`status-badge ${zoneStatus}`}>{zoneStatus}</span>
        )}
        <span className="context-meta">{recordCount} 条记录</span>
        <span className="context-meta">
          {selectedCount > 0 ? `已选 ${selectedCount} 条` : "未选择记录"}
        </span>

        {(attachments.whitelist || attachments.resume) && (
          <span className="scope-attachments">
            {attachments.whitelist && (
              <span className="scope-chip">
                白名单 {attachments.whitelist.count} 域
                <button
                  type="button"
                  aria-label="移除白名单"
                  onClick={() => onClearAttachment("whitelist")}
                >
                  <X size={12} aria-hidden="true" />
                </button>
              </span>
            )}
            {attachments.resume && (
              <span className="scope-chip">
                重跑清单 {attachments.resume.rows} 行
                <button
                  type="button"
                  aria-label="移除重跑清单"
                  onClick={() => onClearAttachment("resume")}
                >
                  <X size={12} aria-hidden="true" />
                </button>
              </span>
            )}
          </span>
        )}

        <span className="strip-spacer" />
        <span className="refresh-note">
          {refreshing ? "刷新中…" : mode === "server" ? "服务端分页" : "本地已加载"}
        </span>
        <button
          className="button ghost"
          onClick={onRefresh}
          disabled={refreshing}
        >
          <RefreshCw
            size={15}
            aria-hidden="true"
            className={refreshing ? "spin" : undefined}
          />
          {refreshing ? "刷新中" : "刷新"}
        </button>
      </div>
    </>
  );
}
