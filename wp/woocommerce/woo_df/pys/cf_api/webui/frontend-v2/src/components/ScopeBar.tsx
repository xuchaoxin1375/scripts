import { Layers, Plus, RefreshCw } from "lucide-react";

type Props = {
  account: string;
  zone: string;
  recordCount: number;
  selectedCount: number;
  onRefresh: () => void;
  onAdd: () => void;
  onBatch: () => void;
};

export default function ScopeBar({
  account,
  zone,
  recordCount,
  selectedCount,
  onRefresh,
  onAdd,
  onBatch,
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
      </div>
      <div className="scope-actions">
        <button className="button ghost" onClick={onRefresh}>
          <RefreshCw size={15} /> 刷新
        </button>
        <button className="button" onClick={onAdd}>
          <Plus size={15} /> 新增记录
        </button>
        <button className="button primary" onClick={onBatch}>
          <Layers size={15} /> 批量操作
        </button>
      </div>
    </section>
  );
}
