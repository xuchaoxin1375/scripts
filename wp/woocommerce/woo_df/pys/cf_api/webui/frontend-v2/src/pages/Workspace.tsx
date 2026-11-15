import { AlertTriangle, Layers, Trash2, X } from "lucide-react";
import { useEffect, useState } from "react";
import type {
  ActionDraft,
  ActionMode,
  Attachments,
  DnsRecord,
  InspectorTab,
  Job,
  RecordFilters,
  RecordPatchValues,
} from "../types";
import { useJob, useJobResults } from "../api/hooks";
import ScopeBar from "../components/ScopeBar";
import RecordsTable from "../components/RecordsTable";
import Inspector from "../components/Inspector";

type Props = {
  account: string;
  zone: string;
  records: DnsRecord[];
  total: number;
  page: number;
  perPage: number;
  loading: boolean;
  fetching: boolean;
  recordsError: string | null;
  filters: RecordFilters;
  selectedIds: Set<string>;
  selectedRecords: DnsRecord[];
  selectedJob: Job | null;
  jobs: Job[];
  jobsLoading: boolean;
  jobsError: string | null;
  inspectorTab: InspectorTab;
  attachments: Attachments;
  defaultBackupDir: string;
  defaultExportDir: string;
  refreshing: boolean;
  onTab: (tab: InspectorTab) => void;
  onToggleRecord: (record: DnsRecord) => void;
  onToggleAll: (items: DnsRecord[]) => void;
  onClearSelection: () => void;
  onFilters: (patch: Partial<RecordFilters>) => void;
  onPage: (page: number) => void;
  onRetryRecords: () => void;
  onRetryJobs: () => void;
  onSelectJob: (job: Job | null) => void;
  onRefresh: () => void;
  onPreview: (draft: ActionDraft) => Promise<string | null>;
  onExecutePreview: (jobId: string) => Promise<void>;
  onRerun: (jobId: string) => Promise<void>;
  onCancel: (jobId: string) => Promise<void>;
  onDownload: (jobId: string, kind: "failures" | "anomalies") => Promise<void>;
  onBulkProxy: (proxied: boolean) => Promise<void>;
  onBulkDelete: (ids: string[]) => Promise<boolean>;
  onBulkContent: (ids: string[], content: string) => Promise<boolean>;
  onSaveRecord: (
    recordId: string,
    patch: RecordPatchValues,
  ) => Promise<boolean>;
  onExportRecords: () => void;
  onClearAttachment: (kind: "whitelist" | "resume") => void;
  onNotify: (message: string) => void;
};

export default function Workspace(props: Props) {
  const {
    account,
    zone,
    records,
    total,
    page,
    perPage,
    loading,
    fetching,
    recordsError,
    filters,
    selectedIds,
    selectedRecords,
    selectedJob,
    jobs,
    jobsLoading,
    jobsError,
    inspectorTab,
    attachments,
    defaultBackupDir,
    defaultExportDir,
    refreshing,
    onTab,
    onToggleRecord,
    onToggleAll,
    onClearSelection,
    onFilters,
    onPage,
    onRetryRecords,
    onRetryJobs,
    onSelectJob,
    onRefresh,
    onPreview,
    onExecutePreview,
    onRerun,
    onCancel,
    onDownload,
    onBulkProxy,
    onBulkDelete,
    onBulkContent,
    onSaveRecord,
    onExportRecords,
    onClearAttachment,
    onNotify,
  } = props;

  const [actionMode, setActionMode] = useState<ActionMode | null>(null);
  const [editingRecord, setEditingRecord] = useState<DnsRecord | null>(null);
  const [previewOpen, setPreviewOpen] = useState(false);
  const [previewJobId, setPreviewJobId] = useState<string | null>(null);
  const [previewPage, setPreviewPage] = useState(1);
  const [submitting, setSubmitting] = useState(false);
  const [bulkContentOpen, setBulkContentOpen] = useState(false);
  const [bulkDeleteOpen, setBulkDeleteOpen] = useState(false);

  const previewJobQuery = useJob(previewJobId);
  const previewJob = previewJobQuery.data ?? null;
  const previewReady = Boolean(
    previewJob && !["pending", "running"].includes(previewJob.status),
  );
  const previewResults = useJobResults(
    previewJobId,
    previewPage,
    50,
    previewReady,
    previewJob?.mode ?? "",
  );

  useEffect(() => {
    setEditingRecord(null);
    setPreviewOpen(false);
    setPreviewJobId(null);
    setActionMode(null);
    setBulkContentOpen(false);
    setBulkDeleteOpen(false);
  }, [zone]);

  useEffect(() => {
    if (!previewJobId || !previewJob) return;
    if (
      !["pending", "running"].includes(previewJob.status) &&
      previewPage > 1
    ) {
      const pages = Math.max(
        1,
        Math.ceil((previewResults.data?.total ?? 0) / 50),
      );
      if (previewPage > pages) setPreviewPage(pages);
    }
  }, [previewJob, previewJobId, previewPage, previewResults.data?.total]);

  function startAction(mode: ActionMode) {
    setActionMode(mode);
    setPreviewOpen(false);
    setPreviewJobId(null);
    setEditingRecord(null);
    onTab("action");
  }

  async function handlePreview(draft: ActionDraft) {
    setSubmitting(true);
    const jobId = await onPreview(draft);
    setSubmitting(false);
    if (!jobId) return;
    setPreviewJobId(jobId);
    setPreviewPage(1);
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

  function closePreview() {
    setPreviewOpen(false);
    setPreviewJobId(null);
  }

  return (
    <div className="workspace">
      <div className="workspace-main">
        <ScopeBar
          account={account}
          zone={zone}
          recordCount={total}
          selectedCount={selectedIds.size}
          refreshing={refreshing}
          attachments={attachments}
          onRefresh={onRefresh}
          onAdd={() => startAction("add")}
          onBatch={() => startAction("update")}
          onClearAttachment={onClearAttachment}
        />
        {loading && <div className="data-banner subtle">正在读取记录…</div>}
        <RecordsTable
          key={zone}
          zone={zone}
          records={records}
          total={total}
          page={page}
          perPage={perPage}
          loading={loading}
          fetching={fetching}
          error={recordsError}
          filters={filters}
          selectedIds={selectedIds}
          onFilters={onFilters}
          onPage={onPage}
          onToggle={onToggleRecord}
          onToggleAll={onToggleAll}
          onEdit={(record) => {
            setEditingRecord(record);
            setPreviewOpen(false);
            setActionMode(null);
            onTab("action");
          }}
          onExport={onExportRecords}
          onRetry={onRetryRecords}
        />
        {selectedIds.size > 0 && (
          <div className="bulk-bar" role="toolbar" aria-label="批量操作">
            <span className="bulk-count">已选 {selectedIds.size} 条</span>
            <span className="bulk-divider" />
            <button
              className="button ghost"
              onClick={() => setBulkContentOpen(true)}
            >
              <Layers size={15} /> 改选中内容
            </button>
            <button className="button ghost" onClick={() => startAction("update")}>
              按域名批量
            </button>
            <button className="button ghost" onClick={() => void onBulkProxy(true)}>
              设为已代理
            </button>
            <button className="button ghost" onClick={() => void onBulkProxy(false)}>
              设为仅 DNS
            </button>
            <button
              className="button ghost danger-text"
              onClick={() => setBulkDeleteOpen(true)}
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
        selectedCount={selectedIds.size}
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
          setEditingRecord(null);
        }}
        previewOpen={previewOpen}
        previewRows={previewResults.data?.rows ?? []}
        previewTotal={previewResults.data?.total ?? 0}
        previewPage={previewPage}
        previewPages={Math.max(
          1,
          Math.ceil((previewResults.data?.total ?? 0) / 50),
        )}
        previewLoading={
          previewJobQuery.isLoading || previewResults.isFetching
        }
        previewJobId={previewJobId}
        previewJob={previewJob}
        submitting={submitting}
        defaultBackupDir={defaultBackupDir}
        defaultExportDir={defaultExportDir}
        onPreview={handlePreview}
        onPreviewPage={setPreviewPage}
        onBack={closePreview}
        onExecute={execute}
        jobs={jobs}
        jobsLoading={jobsLoading}
        jobsError={jobsError}
        selectedJob={selectedJob}
        onSelectJob={onSelectJob}
        onRerun={onRerun}
        onCancel={onCancel}
        onDownload={onDownload}
        onExecutePreview={onExecutePreview}
        onRetryJobs={onRetryJobs}
      />

      {bulkContentOpen && (
        <BulkContentDialog
          records={selectedRecords}
          zone={zone}
          onCancel={() => setBulkContentOpen(false)}
          onConfirm={async (content) => {
            const ok = await onBulkContent([...selectedIds], content);
            if (ok) setBulkContentOpen(false);
            return ok;
          }}
        />
      )}
      {bulkDeleteOpen && (
        <BulkDeleteDialog
          records={selectedRecords}
          zone={zone}
          onCancel={() => setBulkDeleteOpen(false)}
          onConfirm={async () => {
            const ok = await onBulkDelete([...selectedIds]);
            if (ok) setBulkDeleteOpen(false);
            return ok;
          }}
        />
      )}
    </div>
  );
}

function BulkContentDialog({
  records,
  zone,
  onCancel,
  onConfirm,
}: {
  records: DnsRecord[];
  zone: string;
  onCancel: () => void;
  onConfirm: (content: string) => Promise<boolean>;
}) {
  const [content, setContent] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit() {
    if (!content.trim()) {
      setError("请填写新内容");
      return;
    }
    setBusy(true);
    setError("");
    const ok = await onConfirm(content.trim());
    setBusy(false);
    if (!ok) setError("批量更新失败，请查看提示后重试");
  }

  return (
    <div className="modal-backdrop" role="presentation" onClick={onCancel}>
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="bulk-content-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="modal-head">
          <h2 id="bulk-content-title">改选中记录内容</h2>
          <button className="icon-button" aria-label="关闭" onClick={onCancel}>
            <X size={16} />
          </button>
        </header>
        <div className="modal-body">
          <p className="modal-copy">
            将直接写入 {records.length} 条记录（{zone}），不经过预览任务。
          </p>
          <div className="dialog-list">
            {records.slice(0, 6).map((record) => (
              <span key={record.id}>
                <strong>{record.name}</strong> <em>{record.type}</em>{" "}
                <code>{record.content}</code>
              </span>
            ))}
            {records.length > 6 && <span>… 另有 {records.length - 6} 条</span>}
          </div>
          <label className="field">
            <span className="field-label">新内容</span>
            <input
              value={content}
              onChange={(event) => setContent(event.target.value)}
              placeholder="198.51.100.10 或 target.example.net"
              autoFocus
            />
          </label>
          {error && <div className="inline-warning">{error}</div>}
          <div className="inline-warning">
            <AlertTriangle size={16} />
            仅改内容，保留类型、名称、代理与 TTL；任一条校验失败会跳过并计入失败。
          </div>
        </div>
        <footer className="modal-actions">
          <button className="button ghost" onClick={onCancel} disabled={busy}>
            取消
          </button>
          <button
            className="button primary"
            onClick={() => void submit()}
            disabled={busy}
          >
            {busy ? "写入中…" : "确认写入"}
          </button>
        </footer>
      </div>
    </div>
  );
}

function BulkDeleteDialog({
  records,
  zone,
  onCancel,
  onConfirm,
}: {
  records: DnsRecord[];
  zone: string;
  onCancel: () => void;
  onConfirm: () => Promise<boolean>;
}) {
  const [ack, setAck] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit() {
    setBusy(true);
    setError("");
    const ok = await onConfirm();
    setBusy(false);
    if (!ok) setError("删除失败，请查看提示后重试");
  }

  return (
    <div className="modal-backdrop" role="presentation" onClick={onCancel}>
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="bulk-delete-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="modal-head">
          <h2 id="bulk-delete-title">删除选中记录</h2>
          <button className="icon-button" aria-label="关闭" onClick={onCancel}>
            <X size={16} />
          </button>
        </header>
        <div className="modal-body">
          <p className="modal-copy">
            将永久删除 {records.length} 条记录（{zone}），无法撤销。
          </p>
          <div className="dialog-list">
            {records.slice(0, 6).map((record) => (
              <span key={record.id}>
                <strong>{record.name}</strong> <em>{record.type}</em>{" "}
                <code>{record.content}</code>
              </span>
            ))}
            {records.length > 6 && <span>… 另有 {records.length - 6} 条</span>}
          </div>
          <label className="checkbox-line">
            <input
              type="checkbox"
              checked={ack}
              onChange={(event) => setAck(event.target.checked)}
            />
            我已核对范围，确认删除
          </label>
          {error && <div className="inline-warning">{error}</div>}
        </div>
        <footer className="modal-actions">
          <button className="button ghost" onClick={onCancel} disabled={busy}>
            取消
          </button>
          <button
            className="button danger"
            onClick={() => void submit()}
            disabled={!ack || busy}
          >
            {busy ? "删除中…" : `删除 ${records.length} 条`}
          </button>
        </footer>
      </div>
    </div>
  );
}
