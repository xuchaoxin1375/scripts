import { Layers, Plus, RefreshCw, X } from "lucide-react";
import type { Attachments } from "../types";

type Props = {
  account: string;
  zone: string;
  recordCount: number;
  selectedCount: number;
  refreshing: boolean;
  attachments: Attachments;
  onRefresh: () => void;
  onAdd: () => void;
  onBatch: () => void;
  onClearAttachment: (kind: "whitelist" | "resume") => void;
};

export default function ScopeBar({
  account,
  zone,
  recordCount,
  selectedCount,
  refreshing,
  attachments,
  onRefresh,
  onAdd,
  onBatch,
  onClearAttachment,
}: Props) {
  return (
    <section className="scope-bar" aria-label="当前范围">
      <div className="scope-main">
        <span className="scope-label">SCOPE</span>
        <span className="scope-path">
          <strong>{account}</strong>
          <span className="scope-sep">/</span>
          <strong>{zone || "未选择域名"}</strong>
        </span>
        <span className="scope-meta">
          {recordCount} 条记录
          {selectedCount > 0 ? ` · 已选 ${selectedCount} 条` : " · 未选择记录"}
        </span>
        {(attachments.whitelist || attachments.resume) && (
          <span className="scope-attachments">
            {attachments.whitelist && (
              <span className="scope-chip">
                白名单 {attachments.whitelist.count} 域
                <button
                  aria-label="移除白名单"
                  onClick={() => onClearAttachment("whitelist")}
                >
                  <X size={12} />
                </button>
              </span>
            )}
            {attachments.resume && (
              <span className="scope-chip">
                重跑清单 {attachments.resume.rows} 行
                <button
                  aria-label="移除重跑清单"
                  onClick={() => onClearAttachment("resume")}
                >
                  <X size={12} />
                </button>
              </span>
            )}
          </span>
        )}
      </div>
      <div className="scope-actions">
        <button className="button ghost" onClick={onRefresh} disabled={refreshing}>
          <RefreshCw size={15} className={refreshing ? "spin" : ""} />
          {refreshing ? "刷新中" : "刷新"}
        </button>
        <button className="button" onClick={onAdd} disabled={!zone}>
          <Plus size={15} /> 新增记录
        </button>
        <button className="button primary" onClick={onBatch} disabled={!zone}>
          <Layers size={15} /> 批量操作
        </button>
      </div>
    </section>
  );
}
