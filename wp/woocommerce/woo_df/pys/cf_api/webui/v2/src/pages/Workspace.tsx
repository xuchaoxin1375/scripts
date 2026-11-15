import { AlertTriangle, Layers, ListChecks, Trash2, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
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
import OperationsDrawer from "../components/OperationsDrawer";
import {
  AddRecordDialog,
  RecordEditDialog,
} from "../components/RecordDialogs";
import { useDialogFocus } from "../shared/useDialogFocus";
import { shortName } from "../shared/names";

type Props = {
  account: string;
  zone: string;
  zoneStatus?: string;
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
  drawerOpen: boolean;
  onDrawerOpen: (tab?: InspectorTab) => void;
  onDrawerClose: () => void;
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
  onExecutePreview: (jobId: string) => Promise<boolean>;
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
    zoneStatus,
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
    drawerOpen,
    onDrawerOpen,
    onDrawerClose,
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
  const [addOpen, setAddOpen] = useState(false);
  const [previewOpen, setPreviewOpen] = useState(false);
  const [previewJobId, setPreviewJobId] = useState<string | null>(null);
  const [previewPage, setPreviewPage] = useState(1);
  const [submitting, setSubmitting] = useState(false);
  const [bulkContentOpen, setBulkContentOpen] = useState(false);
  const [bulkContentRecords, setBulkContentRecords] = useState<DnsRecord[]>(
    [],
  );
  const [deletingRecords, setDeletingRecords] = useState<DnsRecord[] | null>(
    null,
  );
  const submittingRef = useRef(false);

  const previewJobQuery = useJob(previewJobId, drawerOpen);
  const previewJob = previewJobQuery.data ?? null;
  const previewReady = Boolean(
    previewJob && !["pending", "running"].includes(previewJob.status),
  );
  const previewResults = useJobResults(
    previewJobId,
    previewPage,
    50,
    previewReady && drawerOpen,
    previewJob?.mode ?? "",
  );

  useEffect(() => {
    setEditingRecord(null);
    setAddOpen(false);
    setPreviewOpen(false);
    setPreviewJobId(null);
    setActionMode(null);
    setBulkContentOpen(false);
    setBulkContentRecords([]);
    setDeletingRecords(null);
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
    onDrawerOpen("action");
  }

  function openBatchPanel() {
    onTab("action");
    onDrawerOpen("action");
  }

  function openAddDialog() {
    setAddOpen(true);
    setEditingRecord(null);
    setPreviewOpen(false);
    setPreviewJobId(null);
    setActionMode(null);
    onTab("action");
  }

  function openBulkContentDialog() {
    if (!selectedRecords.length) return;
    setBulkContentRecords(selectedRecords);
    setBulkContentOpen(true);
  }

  function openRecordEditor(record: DnsRecord) {
    setEditingRecord(record);
    setPreviewOpen(false);
    setPreviewJobId(null);
    setActionMode(null);
    onTab("action");
  }

  async function handlePreview(draft: ActionDraft): Promise<boolean> {
    if (submittingRef.current) return false;
    submittingRef.current = true;
    setSubmitting(true);
    try {
      const jobId = await onPreview(draft);
      if (!jobId) return false;
      setPreviewJobId(jobId);
      setPreviewPage(1);
      setPreviewOpen(true);
      onTab("action");
      onDrawerOpen("action");
      return true;
    } finally {
      submittingRef.current = false;
      setSubmitting(false);
    }
  }

  async function execute() {
    if (!previewJobId) {
      onNotify("预览任务尚未就绪");
      return;
    }
    const ok = await onExecutePreview(previewJobId);
    if (!ok) return;
    setPreviewOpen(false);
    setActionMode(null);
    setPreviewJobId(null);
    onClearSelection();
  }

  function closePreview() {
    setPreviewOpen(false);
    setPreviewJobId(null);
  }

  const drawerModalOpen = Boolean(
    editingRecord || addOpen || bulkContentOpen || deletingRecords,
  );
  const runningJobs = jobs.filter(
    (job) => job.status === "running" || job.status === "pending",
  ).length;
  const deleting = deletingRecords;

  return (
    <>
      <div className="workspace">
        <div className="workspace-main">
          <ScopeBar
            account={account}
            zone={zone}
            zoneStatus={zoneStatus}
            recordCount={total}
            selectedCount={selectedIds.size}
            refreshing={refreshing}
            attachments={attachments}
            onRefresh={onRefresh}
            onAdd={openAddDialog}
            onBatch={openBatchPanel}
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
            onEdit={openRecordEditor}
            onDelete={(record) => setDeletingRecords([record])}
            onExport={onExportRecords}
            onRetry={onRetryRecords}
          />
          {selectedIds.size > 0 && (
            <div className="bulk-bar" role="toolbar" aria-label="批量操作">
              <span className="bulk-count">已选 {selectedIds.size} 条</span>
              <span className="bulk-divider" />
              <button
                type="button"
                className="button ghost"
                onClick={openBatchPanel}
              >
                <ListChecks size={15} aria-hidden="true" />
                批量面板
              </button>
              <button
                type="button"
                className="button ghost bulk-extra"
                onClick={openBulkContentDialog}
              >
                <Layers size={15} aria-hidden="true" />
                改选中内容
              </button>
              <button
                type="button"
                className="button ghost bulk-extra"
                onClick={() => startAction("update")}
              >
                按域名批量
              </button>
              <button
                type="button"
                className="button ghost bulk-extra"
                onClick={() => void onBulkProxy(true)}
              >
                设为已代理
              </button>
              <button
                type="button"
                className="button ghost bulk-extra"
                onClick={() => void onBulkProxy(false)}
              >
                设为仅 DNS
              </button>
              <button
                type="button"
                className="button ghost danger-text"
                onClick={() => setDeletingRecords(selectedRecords)}
              >
                <Trash2 size={15} aria-hidden="true" />
                删除
              </button>
              <button
                type="button"
                className="button ghost"
                onClick={onClearSelection}
              >
                <X size={15} aria-hidden="true" />
                清除
              </button>
            </div>
          )}
        </div>
      </div>

      <OperationsDrawer
        open={drawerOpen}
        tab={inspectorTab}
        onTab={onTab}
        onClose={onDrawerClose}
        modalOpen={drawerModalOpen}
        account={account}
        zone={zone}
        selectedCount={selectedIds.size}
        runningJobs={runningJobs}
      >
        <Inspector
          tab={inspectorTab}
          visible={drawerOpen}
          account={account}
          zone={zone}
          selectedRecords={selectedRecords}
          selectedCount={selectedIds.size}
          onBulkContentOpen={openBulkContentDialog}
          onBulkDeleteOpen={() => setDeletingRecords(selectedRecords)}
          onClearSelection={onClearSelection}
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
      </OperationsDrawer>

      {editingRecord && (
        <RecordEditDialog
          record={editingRecord}
          zone={zone}
          onClose={() => setEditingRecord(null)}
          onSave={onSaveRecord}
        />
      )}

      {addOpen && (
        <AddRecordDialog
          zone={zone}
          onClose={() => setAddOpen(false)}
          onSubmit={handlePreview}
        />
      )}

      {bulkContentOpen && (
        <BulkContentDialog
          records={bulkContentRecords}
          zone={zone}
          onCancel={() => {
            setBulkContentOpen(false);
            setBulkContentRecords([]);
          }}
          onConfirm={(content) =>
            onBulkContent(
              bulkContentRecords.map((record) => record.id),
              content,
            )
          }
        />
      )}

      {deleting && (
        <BulkDeleteDialog
          records={deleting}
          zone={zone}
          onCancel={() => setDeletingRecords(null)}
          onConfirm={() => onBulkDelete(deleting.map((record) => record.id))}
        />
      )}
    </>
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
  const busyRef = useRef(false);
  busyRef.current = busy;

  function closeIfIdle() {
    if (!busyRef.current) onCancel();
  }
  const dialogRef = useDialogFocus(closeIfIdle);

  async function submit() {
    if (busyRef.current) return;
    if (!content.trim()) {
      setError("请填写新内容");
      return;
    }
    setBusy(true);
    busyRef.current = true;
    setError("");
    const ok = await onConfirm(content.trim());
    setBusy(false);
    busyRef.current = false;
    if (ok) {
      onCancel();
    } else {
      setError("批量更新失败，请查看提示后重试");
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onClick={closeIfIdle}>
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="bulk-content-title"
        ref={dialogRef}
        onClick={(event) => event.stopPropagation()}
      >
        <header className="modal-head">
          <div className="modal-head-copy">
            <h2 id="bulk-content-title">改选中记录内容</h2>
            <p className="modal-subtitle">{zone} · 直接写入</p>
          </div>
          <button
            type="button"
            className="icon-button"
            onClick={closeIfIdle}
            disabled={busy}
            aria-label="关闭"
          >
            <X size={18} aria-hidden="true" />
          </button>
        </header>
        <form
          className="modal-form"
          onSubmit={(event) => {
            event.preventDefault();
            void submit();
          }}
          noValidate
        >
          <div className="modal-body">
            <p className="modal-copy">
              将直接写入 {records.length} 条记录（{zone}），不经过预览任务。
            </p>
            <div className="dialog-list">
              {records.slice(0, 6).map((record) => (
                <span key={record.id}>
                  <strong>{shortName(record.name, zone)}</strong>{" "}
                  <em>{record.type}</em> <code>{record.content}</code>
                </span>
              ))}
              {records.length > 6 && <span>… 另有 {records.length - 6} 条</span>}
            </div>
            <div className="field">
              <label htmlFor="bulk-content-input">新内容</label>
              <input
                id="bulk-content-input"
                value={content}
                onChange={(event) => {
                  setContent(event.target.value);
                  if (error) setError("");
                }}
                placeholder="198.51.100.10 或 target.example.net"
                data-dialog-initial
                autoComplete="off"
                spellCheck={false}
              />
            </div>
            {error && (
              <div className="inline-warning" role="alert">
                <AlertTriangle size={16} aria-hidden="true" />
                <span>{error}</span>
              </div>
            )}
            <div className="inline-warning">
              <AlertTriangle size={16} aria-hidden="true" />
              <span>
                仅改内容，保留类型、名称、代理与 TTL；任一条校验失败会跳过并计入失败。
              </span>
            </div>
          </div>
          <footer className="modal-actions">
            <button
              type="button"
              className="button ghost"
              onClick={closeIfIdle}
              disabled={busy}
            >
              取消
            </button>
            <button type="submit" className="button primary" disabled={busy}>
              {busy ? "写入中…" : "确认写入"}
            </button>
          </footer>
        </form>
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
  const busyRef = useRef(false);
  busyRef.current = busy;

  function closeIfIdle() {
    if (!busyRef.current) onCancel();
  }
  const dialogRef = useDialogFocus(closeIfIdle);

  async function submit() {
    if (busyRef.current || !ack) return;
    setBusy(true);
    busyRef.current = true;
    setError("");
    const ok = await onConfirm();
    setBusy(false);
    busyRef.current = false;
    if (ok) {
      onCancel();
    } else {
      setError("删除失败，请查看提示后重试");
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onClick={closeIfIdle}>
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="bulk-delete-title"
        ref={dialogRef}
        onClick={(event) => event.stopPropagation()}
      >
        <header className="modal-head">
          <div className="modal-head-copy">
            <h2 id="bulk-delete-title">
              {records.length === 1 ? "删除记录" : "删除选中记录"}
            </h2>
            <p className="modal-subtitle">{zone} · 不可撤销</p>
          </div>
          <button
            type="button"
            className="icon-button"
            onClick={closeIfIdle}
            disabled={busy}
            aria-label="关闭"
          >
            <X size={18} aria-hidden="true" />
          </button>
        </header>
        <form
          className="modal-form"
          onSubmit={(event) => {
            event.preventDefault();
            void submit();
          }}
          noValidate
        >
          <div className="modal-body">
            <p className="modal-copy">
              将永久删除 {records.length} 条记录（{zone}），无法撤销。
            </p>
            <div className="dialog-list">
              {records.slice(0, 6).map((record) => (
                <span key={record.id}>
                  <strong>{shortName(record.name, zone)}</strong>{" "}
                  <em>{record.type}</em> <code>{record.content}</code>
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
            {error && (
              <div className="inline-warning" role="alert">
                <AlertTriangle size={16} aria-hidden="true" />
                <span>{error}</span>
              </div>
            )}
          </div>
          <footer className="modal-actions">
            <button
              type="button"
              className="button ghost"
              onClick={closeIfIdle}
              disabled={busy}
            >
              取消
            </button>
            <button
              type="submit"
              className="button danger-solid"
              disabled={!ack || busy}
            >
              {busy ? "删除中…" : `删除 ${records.length} 条`}
            </button>
          </footer>
        </form>
      </div>
    </div>
  );
}
