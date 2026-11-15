import { useEffect, useState } from "react";
import { Layers, Trash2, X } from "lucide-react";
import type {
  ActionDraft,
  ActionMode,
  DnsRecord,
  InspectorTab,
  Job,
  PreviewRow,
  RecordPatchValues,
} from "../types";
import { buildPreview } from "../lib/actions";
import { useJob } from "../api/hooks";
import ScopeBar from "../components/ScopeBar";
import RecordsTable from "../components/RecordsTable";
import Inspector from "../components/Inspector";

type Props = {
  account: string;
  zone: string;
  records: DnsRecord[];
  selectedIds: Set<string>;
  selectedRecords: DnsRecord[];
  selectedJob: Job | null;
  jobs: Job[];
  inspectorTab: InspectorTab;
  loading: boolean;
  onTab: (tab: InspectorTab) => void;
  onToggleRecord: (id: string) => void;
  onToggleAll: (items: DnsRecord[]) => void;
  onClearSelection: () => void;
  onSelectJob: (job: Job | null) => void;
  onRefresh: () => void;
  onPreview: (draft: ActionDraft) => Promise<string | null>;
  onExecutePreview: (jobId: string) => Promise<void>;
  onRerun: (jobId: string) => Promise<void>;
  onCancel: (jobId: string) => Promise<void>;
  onDownload: (jobId: string, kind: "failures" | "anomalies") => Promise<void>;
  onBulkProxy: (proxied: boolean) => Promise<void>;
  onSaveRecord: (
    recordId: string,
    patch: RecordPatchValues,
  ) => Promise<boolean>;
  onNotify: (message: string) => void;
};

export default function Workspace(props: Props) {
  const {
    account,
    zone,
    records,
    selectedIds,
    selectedRecords,
    selectedJob,
    jobs,
    inspectorTab,
    loading,
    onTab,
    onToggleRecord,
    onToggleAll,
    onClearSelection,
    onSelectJob,
    onRefresh,
    onPreview,
    onExecutePreview,
    onRerun,
    onCancel,
    onDownload,
    onBulkProxy,
    onSaveRecord,
    onNotify,
  } = props;

  const [actionMode, setActionMode] = useState<ActionMode | null>(null);
  const [editingRecord, setEditingRecord] = useState<DnsRecord | null>(null);
  const [previewOpen, setPreviewOpen] = useState(false);
  const [previewRows, setPreviewRows] = useState<PreviewRow[]>([]);
  const [previewJobId, setPreviewJobId] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const previewJobQuery = useJob(previewJobId);
  const previewJob = previewJobQuery.data ?? null;

  useEffect(() => {
    setEditingRecord(null);
  }, [zone]);

  function startAction(mode: ActionMode) {
    setActionMode(mode);
    setPreviewOpen(false);
    setPreviewJobId(null);
    onTab("action");
  }

  async function handlePreview(draft: ActionDraft) {
    setSubmitting(true);
    const jobId = await onPreview(draft);
    setSubmitting(false);
    if (!jobId) return;
    setPreviewRows(buildPreview(records, draft));
    setPreviewJobId(jobId);
    setPreviewOpen(true);
  }

  async function execute() {
    if (!previewJobId) {
      onNotify("预览任务尚未就绪");
      return;
    }
    await onExecutePreview(previewJobId);
    setPreviewOpen(false);
    setActionMode(null);
    setPreviewJobId(null);
    onClearSelection();
  }

  return (
    <div className="workspace">
      <div className="workspace-main">
        <ScopeBar
          account={account}
          zone={zone}
          recordCount={records.length}
          selectedCount={selectedIds.size}
          onRefresh={onRefresh}
          onAdd={() => startAction("add")}
          onBatch={() => startAction("update")}
        />
        {loading && <div className="data-banner subtle">正在读取账号、域名或记录…</div>}
        <RecordsTable
          zone={zone}
          records={records}
          selectedIds={selectedIds}
          onToggle={onToggleRecord}
          onToggleAll={onToggleAll}
          onEdit={(record) => setEditingRecord(record)}
          onNotify={onNotify}
        />
        {selectedIds.size > 0 && (
          <div className="bulk-bar" role="toolbar" aria-label="批量操作">
            <span className="bulk-count">已选 {selectedIds.size} 条</span>
            <span className="bulk-divider" />
            <button className="button ghost" onClick={() => startAction("update")}>
              <Layers size={15} /> 批量更新
            </button>
            <button className="button ghost" onClick={() => void onBulkProxy(true)}>
              设为已代理
            </button>
            <button className="button ghost" onClick={() => void onBulkProxy(false)}>
              设为仅 DNS
            </button>
            <button
              className="button ghost danger-text"
              onClick={() => onNotify("删除需在预览后确认")}
            >
              <Trash2 size={15} /> 删除
            </button>
            <button className="button ghost" onClick={onClearSelection}>
              <X size={15} /> 清除
            </button>
          </div>
        )}
      </div>

      <Inspector
        tab={inspectorTab}
        onTab={onTab}
        account={account}
        zone={zone}
        selectedRecords={selectedRecords}
        editingRecord={editingRecord}
        onCancelEdit={() => setEditingRecord(null)}
        onSaveRecord={async (recordId, patch) => {
          const ok = await onSaveRecord(recordId, patch);
          if (ok) setEditingRecord(null);
          return ok;
        }}
        actionMode={actionMode}
        onActionMode={(mode) => {
          setActionMode(mode);
          setPreviewOpen(false);
          setPreviewJobId(null);
        }}
        previewOpen={previewOpen}
        previewRows={previewRows}
        previewJobId={previewJobId}
        previewJob={previewJob}
        submitting={submitting}
        onPreview={handlePreview}
        onBack={() => setPreviewOpen(false)}
        onExecute={execute}
        jobs={jobs}
        selectedJob={selectedJob}
        onSelectJob={onSelectJob}
        onRerun={onRerun}
        onCancel={onCancel}
        onDownload={onDownload}
        onExecutePreview={onExecutePreview}
        onNotify={onNotify}
      />
    </div>
  );
}
