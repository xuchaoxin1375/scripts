import {
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  Asterisk,
  CheckCircle2,
  Download,
  FileJson,
  Globe2,
  Loader2,
  Play,
  Plus,
  RefreshCw,
  RotateCcw,
  ShieldAlert,
  SlidersHorizontal,
  Trash2,
  XCircle,
} from "lucide-react";
import { useState } from "react";
import type { ReactNode } from "react";
import type {
  ActionDraft,
  ActionMode,
  DnsRecord,
  InspectorTab,
  Job,
  PreviewRow,
  RecordPatchValues,
} from "../types";
import {
  downloadJobExport,
  useJobExports,
  useJobLogs,
} from "../api/hooks";

type Props = {
  tab: InspectorTab;
  onTab: (tab: InspectorTab) => void;
  account: string;
  zone: string;
  selectedRecords: DnsRecord[];
  selectedCount: number;
  editingRecord: DnsRecord | null;
  onCancelEdit: () => void;
  onSaveRecord: (
    recordId: string,
    patch: RecordPatchValues,
  ) => Promise<boolean>;
  actionMode: ActionMode | null;
  onActionMode: (mode: ActionMode | null) => void;
  previewOpen: boolean;
  previewRows: PreviewRow[];
  previewTotal: number;
  previewPage: number;
  previewPages: number;
  previewLoading: boolean;
  previewJobId: string | null;
  previewJob: Job | null;
  submitting: boolean;
  defaultBackupDir: string;
  defaultExportDir: string;
  onPreview: (draft: ActionDraft) => void;
  onPreviewPage: (page: number) => void;
  onBack: () => void;
  onExecute: () => void;
  jobs: Job[];
  jobsLoading: boolean;
  jobsError: string | null;
  selectedJob: Job | null;
  onSelectJob: (job: Job | null) => void;
  onRerun: (jobId: string) => Promise<void>;
  onCancel: (jobId: string) => Promise<void>;
  onDownload: (jobId: string, kind: "failures" | "anomalies") => Promise<void>;
  onExecutePreview: (jobId: string) => Promise<void>;
  onRetryJobs: () => void;
};

const ACTION_CARDS: {
  mode: ActionMode;
  title: string;
  copy: string;
  icon: typeof RefreshCw;
  tone?: "danger";
}[] = [
  {
    mode: "update",
    title: "更新记录内容",
    copy: "把选中的 A / AAAA / CNAME 指向新内容",
    icon: RefreshCw,
  },
  {
    mode: "set_attrs",
    title: "设置代理 / TTL",
    copy: "批量改代理状态与 TTL，不改内容",
    icon: SlidersHorizontal,
  },
  {
    mode: "delete_wildcard",
    title: "删除通配符记录",
    copy: "清理名称以 * 开头的记录",
    icon: Asterisk,
    tone: "danger",
  },
  {
    mode: "delete_ip",
    title: "删除指向指定 IP",
    copy: "清理指向旧服务器 IP 的 A / AAAA",
    icon: Trash2,
    tone: "danger",
  },
  {
    mode: "add",
    title: "添加域名或记录",
    copy: "新建 zone，或向当前域名写入记录",
    icon: Plus,
  },
  {
    mode: "export",
    title: "导出 / 备份",
    copy: "导出 JSON / BIND，或生成变更前快照",
    icon: FileJson,
  },
  {
    mode: "provision",
    title: "域名配置向导",
    copy: "DNS + 激活 + 邮箱 + SSL + 安全",
    icon: Globe2,
  },
  {
    mode: "delete_zone",
    title: "清空或删除域名",
    copy: "清空解析，或彻底删除 zone",
    icon: ShieldAlert,
    tone: "danger",
  },
];

export default function Inspector(props: Props) {
  const {
    tab,
    onTab,
    account,
    zone,
    selectedRecords,
    selectedCount,
    editingRecord,
    onCancelEdit,
    onSaveRecord,
    actionMode,
    onActionMode,
    previewOpen,
    previewRows,
    previewTotal,
    previewPage,
    previewPages,
    previewLoading,
    previewJobId,
    previewJob,
    submitting,
    defaultBackupDir,
    defaultExportDir,
    onPreview,
    onPreviewPage,
    onBack,
    onExecute,
    jobs,
    jobsLoading,
    jobsError,
    selectedJob,
    onSelectJob,
    onRerun,
    onCancel,
    onDownload,
    onExecutePreview,
    onRetryJobs,
  } = props;

  return (
    <aside className="inspector" aria-label="操作与任务面板">
      <div className="inspector-tabs" role="tablist" aria-label="检查器">
        <button
          role="tab"
          aria-selected={tab === "action"}
          className={tab === "action" ? "active" : ""}
          onClick={() => onTab("action")}
        >
          操作
        </button>
        <button
          role="tab"
          aria-selected={tab === "tasks"}
          className={tab === "tasks" ? "active" : ""}
          onClick={() => onTab("tasks")}
        >
          任务
          {jobs.some((job) => job.status === "running") && <span className="live-dot" />}
        </button>
      </div>

      {tab === "action" ? (
        <div className="inspector-body">
          {editingRecord ? (
            <RecordEditForm
              record={editingRecord}
              onCancel={onCancelEdit}
              onSave={onSaveRecord}
            />
          ) : previewOpen ? (
            <PreviewPanel
              rows={previewRows}
              offerCount={previewTotal}
              zone={zone}
              jobId={previewJobId}
              job={previewJob}
              loading={previewLoading}
              page={previewPage}
              pages={previewPages}
              onPage={onPreviewPage}
              onBack={onBack}
              onExecute={onExecute}
            />
          ) : actionMode ? (
            <ActionForm
              mode={actionMode}
              account={account}
              zone={zone}
              selectedCount={selectedCount}
              selectedRecords={selectedRecords}
              submitting={submitting}
              defaultBackupDir={defaultBackupDir}
              defaultExportDir={defaultExportDir}
              onBack={() => onActionMode(null)}
              onPreview={onPreview}
            />
          ) : (
            <ActionPicker
              selectedCount={selectedCount}
              zone={zone}
              onPick={onActionMode}
            />
          )}
        </div>
      ) : (
        <div className="inspector-body">
          <TaskPanel
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
        </div>
      )}
    </aside>
  );
}

function ActionPicker({
  selectedCount,
  zone,
  onPick,
}: {
  selectedCount: number;
  zone: string;
  onPick: (mode: ActionMode) => void;
}) {
  return (
    <div className="action-picker">
      <div className="inspector-intro">
        <span className="eyebrow">CONTEXT</span>
        <h2>
          {selectedCount > 0 ? `已选 ${selectedCount} 条（用于预填）` : "选择一个动作"}
        </h2>
        <p>
          {selectedCount > 0
            ? `实际作用范围是 ${zone} 下匹配的记录；先用选中项预填旧内容，再预览确认。`
            : "也可以不选记录，直接对当前域名发起批量操作。"}
        </p>
      </div>
      <div className="action-list">
        {ACTION_CARDS.map((card) => {
          const Icon = card.icon;
          return (
            <button
              key={card.mode}
              className={`action-card ${card.tone === "danger" ? "danger" : ""}`}
              onClick={() => onPick(card.mode)}
            >
              <span className="action-icon">
                <Icon size={17} />
              </span>
              <span className="action-copy">
                <strong>{card.title}</strong>
                <small>{card.copy}</small>
              </span>
              <ArrowRight size={15} className="action-arrow" />
            </button>
          );
        })}
      </div>
    </div>
  );
}

function ActionForm({
  mode,
  account,
  zone,
  selectedCount,
  selectedRecords,
  submitting,
  defaultBackupDir,
  defaultExportDir,
  onBack,
  onPreview,
}: {
  mode: ActionMode;
  account: string;
  zone: string;
  selectedCount: number;
  selectedRecords: DnsRecord[];
  submitting: boolean;
  defaultBackupDir: string;
  defaultExportDir: string;
  onBack: () => void;
  onPreview: (draft: ActionDraft) => void;
}) {
  const sharedType =
    selectedRecords.length > 0 &&
    selectedRecords.every((record) => record.type === selectedRecords[0].type)
      ? selectedRecords[0].type
      : "auto";
  const sharedContent =
    selectedRecords.length > 0 &&
    selectedRecords.every((record) => record.content === selectedRecords[0].content)
      ? selectedRecords[0].content
      : "";
  const [newContent, setNewContent] = useState("");
  const [oldContent, setOldContent] = useState(sharedContent);
  const [recordType, setRecordType] = useState(sharedType);
  const [deleteIp, setDeleteIp] = useState("");
  const [deleteZoneMode, setDeleteZoneMode] = useState("dns");
  const [confirm, setConfirm] = useState("");
  const [backupDir, setBackupDir] = useState(
    defaultBackupDir || "./cf_backup",
  );
  const [proxy, setProxy] = useState("keep");
  const [ttl, setTtl] = useState("");
  const [domain, setDomain] = useState("");
  const [recordsText, setRecordsText] = useState("www:A:198.51.100.10");
  const [addProxied, setAddProxied] = useState("on");
  const [addTtl, setAddTtl] = useState("1");
  const [exportDir, setExportDir] = useState(
    defaultExportDir || "./cf_export",
  );
  const [exportFormat, setExportFormat] = useState("json");
  const [serverIp, setServerIp] = useState("");
  const [forwardEmail, setForwardEmail] = useState("");
  const [sslMode, setSslMode] = useState("");
  const [formError, setFormError] = useState("");

  const card = ACTION_CARDS.find((item) => item.mode === mode);
  const title = card?.title ?? "批量操作";
  const isDanger = card?.tone === "danger";
  const scopeText = "当前域名下匹配记录";

  function submitPreview() {
    if (mode === "update" && !newContent.trim()) {
      setFormError("请填写新内容，例如 198.51.100.10 或目标域名");
      return;
    }
    if (mode === "delete_ip" && !deleteIp.trim()) {
      setFormError("请填写要删除的 IP");
      return;
    }
    if (mode === "delete_zone" && confirm.trim() !== "DELETE") {
      setFormError("删除域名需输入 DELETE 确认");
      return;
    }
    if (mode === "set_attrs" && proxy === "keep" && !ttl.trim()) {
      setFormError("属性设置至少改一项：代理或 TTL");
      return;
    }
    if (mode === "delete_zone" && !backupDir.trim()) {
      setFormError("删域名必须填写快照目录");
      return;
    }
    if (mode === "export" && !exportDir.trim()) {
      setFormError("导出模式必须填写导出目录");
      return;
    }
    setFormError("");
    onPreview({
      mode,
      newContent,
      oldContent,
      recordType,
      deleteIp,
      deleteZoneMode,
      backupDir,
      confirm,
      setProxied: proxy,
      setTtl: ttl,
      addDomain: domain,
      addRecords: recordsText,
      proxied: addProxied === "on",
      ttl: Number(addTtl) || 1,
      exportDir,
      exportFormat,
      serverIp,
      forwardEmail,
      sslMode,
    });
  }

  return (
    <div className="action-form">
      <button className="back-link" onClick={onBack}>
        <ArrowLeft size={15} /> 返回动作列表
      </button>
      <div className="inspector-intro">
        <span className="eyebrow">ACTION</span>
        <h2>{title}</h2>
        <p>
          {account} / {zone} · {scopeText}
        </p>
      </div>

      <div className={`scope-note ${isDanger ? "danger" : ""}`}>
        <span className="scope-note-title">本次范围</span>
        <strong>
          {account} / {zone}
        </strong>
        <span>
          {scopeText}，不会超出当前账号与域名。
          {selectedCount > 0
            ? ` 已选 ${selectedCount} 条仅用于预填/核对，实际按域名范围执行。`
            : ""}
        </span>
      </div>

      {mode === "update" && (
        <>
          <Field label="新内容" hint="A/AAAA 填 IP；CNAME 填目标域名">
            <input
              value={newContent}
              onChange={(event) => setNewContent(event.target.value)}
              placeholder="198.51.100.10 或 target.example.net"
            />
          </Field>
          <Field label="旧内容过滤（可选）" hint="只更新内容匹配的记录">
            <input
              value={oldContent}
              onChange={(event) => setOldContent(event.target.value)}
              placeholder="203.0.113.10"
            />
          </Field>
          {selectedCount > 0 && (
            <p className="form-hint">
              {sharedContent
                ? `已用所选记录预填旧内容：${sharedContent}`
                : "所选记录内容不一致，未自动预填旧内容；请手动填写或留空按类型匹配。"}
            </p>
          )}
          <Field label="记录类型">
            <select value={recordType} onChange={(event) => setRecordType(event.target.value)}>
              <option value="auto">auto（按 IP 推断）</option>
              <option value="A">A</option>
              <option value="AAAA">AAAA</option>
              <option value="CNAME">CNAME</option>
            </select>
          </Field>
        </>
      )}

      {mode === "delete_wildcard" && (
        <div className="inline-warning">
          <AlertTriangle size={16} />
          将删除名称以 <code>*</code> 开头的记录。先预览，再执行；执行后可在任务页下载失败清单。
        </div>
      )}

      {mode === "delete_ip" && (
        <Field label="要删除的 IP" hint="IPv4 扫描 A，IPv6 扫描 AAAA">
          <input
            value={deleteIp}
            onChange={(event) => setDeleteIp(event.target.value)}
            placeholder="203.0.113.10"
          />
        </Field>
      )}

      {mode === "delete_zone" && (
        <div className="danger-box">
          <div className="inline-warning">
            <ShieldAlert size={16} />
            删除域名不可恢复。必须先写快照，再输入 DELETE 确认。
          </div>
          <Field label="删除方式">
            <select
              value={deleteZoneMode}
              onChange={(event) => setDeleteZoneMode(event.target.value)}
            >
              <option value="dns">dns：仅清空解析，保留域名</option>
              <option value="full">full：清空后彻底删除域名</option>
            </select>
          </Field>
          <Field label="快照目录">
            <input value={backupDir} onChange={(event) => setBackupDir(event.target.value)} />
          </Field>
          <Field label="二次确认" hint="输入 DELETE">
            <input
              value={confirm}
              onChange={(event) => setConfirm(event.target.value)}
              placeholder="DELETE"
            />
          </Field>
        </div>
      )}

      {mode === "set_attrs" && (
        <div className="form-grid">
          <Field label="代理状态">
            <select value={proxy} onChange={(event) => setProxy(event.target.value)}>
              <option value="on">启用代理</option>
              <option value="off">仅 DNS</option>
              <option value="keep">不改</option>
            </select>
          </Field>
          <Field label="TTL" hint="空=不改；1=自动">
            <input
              type="number"
              min={1}
              value={ttl}
              onChange={(event) => setTtl(event.target.value)}
              placeholder="不改"
            />
          </Field>
        </div>
      )}

      {mode === "add" && (
        <>
          <Field label="新域名（可选）" hint="留空则向当前域名添加记录">
            <input
              value={domain}
              onChange={(event) => setDomain(event.target.value)}
              placeholder="example.com"
            />
          </Field>
          <Field label="记录" hint="每行 name:type:content">
            <textarea
              rows={4}
              value={recordsText}
              onChange={(event) => setRecordsText(event.target.value)}
            />
          </Field>
          <div className="form-grid">
            <Field label="代理">
              <select
                value={addProxied}
                onChange={(event) => setAddProxied(event.target.value)}
              >
                <option value="on">启用代理</option>
                <option value="off">仅 DNS</option>
              </select>
            </Field>
            <Field label="TTL">
              <input
                type="number"
                value={addTtl}
                min={1}
                onChange={(event) => setAddTtl(event.target.value)}
              />
            </Field>
          </div>
        </>
      )}

      {mode === "export" && (
        <>
          <Field label="导出目录">
            <input
              value={exportDir}
              onChange={(event) => setExportDir(event.target.value)}
            />
          </Field>
          <Field label="格式">
            <select value={exportFormat} onChange={(event) => setExportFormat(event.target.value)}>
              <option value="json">json（可读、可审计）</option>
              <option value="bind">bind（简化记录）</option>
            </select>
          </Field>
        </>
      )}

      {mode === "provision" && (
        <>
          <Field label="默认服务器 IP" hint="无记录配置时生成 @ 与 www">
            <input
              value={serverIp}
              onChange={(event) => setServerIp(event.target.value)}
              placeholder="198.51.100.10"
            />
          </Field>
          <Field label="邮箱转发目标">
            <input
              value={forwardEmail}
              onChange={(event) => setForwardEmail(event.target.value)}
              placeholder="admin@example.com"
            />
          </Field>
          <Field label="SSL 模式">
            <select
              value={sslMode}
              onChange={(event) => setSslMode(event.target.value)}
            >
              <option value="">不改 SSL</option>
              <option value="flexible">flexible</option>
              <option value="full">full</option>
              <option value="strict">strict</option>
              <option value="off">off</option>
            </select>
          </Field>
          <Field label="步骤">
            <div className="step-chips">
              {["DNS", "等激活", "邮箱", "SSL", "安全", "加速"].map((step) => (
                <span key={step} className="step-chip">
                  {step}
                </span>
              ))}
            </div>
          </Field>
          <p className="form-hint">provision 只对当前域名执行；完整流程在高级页配置。</p>
        </>
      )}

      {formError && <div className="inline-warning">{formError}</div>}

      <div className="form-actions">
        <button className="button ghost" onClick={onBack}>
          取消
        </button>
        <button
          className={`button ${isDanger ? "danger" : "primary"}`}
          onClick={submitPreview}
          disabled={submitting}
        >
          {submitting ? "提交中…" : "预览变更"}
        </button>
      </div>
    </div>
  );
}

function RecordEditForm({
  record,
  onCancel,
  onSave,
}: {
  record: DnsRecord;
  onCancel: () => void;
  onSave: (recordId: string, patch: RecordPatchValues) => Promise<boolean>;
}) {
  const [name, setName] = useState(record.name);
  const [type, setType] = useState(record.type);
  const [content, setContent] = useState(record.content);
  const [proxied, setProxied] = useState(record.proxied);
  const [ttl, setTtl] = useState(String(record.ttl || 1));
  const [comment, setComment] = useState(record.comment || "");
  const [priority, setPriority] = useState(
    record.priority == null ? "" : String(record.priority),
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const proxiable = ["A", "AAAA", "CNAME"].includes(type);

  async function save() {
    if (!name.trim()) {
      setError("名称不能为空");
      return;
    }
    if (!content.trim()) {
      setError("内容不能为空");
      return;
    }
    setBusy(true);
    setError("");
    const ok = await onSave(record.id, {
      name: name.trim(),
      type,
      content: content.trim(),
      proxied: proxiable ? proxied : false,
      ttl: proxiable && proxied ? 1 : Number(ttl) || 1,
      comment: comment.trim(),
      priority: type === "MX" ? Number(priority) : null,
    });
    setBusy(false);
    if (!ok) setError("保存失败，请检查字段或稍后重试");
  }

  return (
    <div className="record-edit">
      <button className="back-link" onClick={onCancel}>
        <ArrowLeft size={15} /> 返回
      </button>
      <div className="inspector-intro">
        <span className="eyebrow">EDIT RECORD</span>
        <h2>编辑记录</h2>
        <p>单条 PATCH；保存后刷新当前域名记录。</p>
      </div>
      <Field label="名称">
        <input value={name} onChange={(event) => setName(event.target.value)} />
      </Field>
      <div className="form-grid">
        <Field label="类型">
          <select value={type} onChange={(event) => setType(event.target.value)}>
            {["A", "AAAA", "CNAME", "TXT", "MX"].map((item) => (
              <option key={item} value={item}>
                {item}
              </option>
            ))}
          </select>
        </Field>
        <Field label="TTL" hint={proxied ? "代理开时锁定自动" : "1=自动"}>
          <input
            type="number"
            min={1}
            value={proxiable && proxied ? "1" : ttl}
            disabled={proxiable && proxied}
            onChange={(event) => setTtl(event.target.value)}
          />
        </Field>
      </div>
      <Field label="内容">
        <input value={content} onChange={(event) => setContent(event.target.value)} />
      </Field>
      <div className="form-grid">
        <Field label="代理">
          <label className="checkbox-line">
            <input
              type="checkbox"
              checked={proxiable && proxied}
              disabled={!proxiable}
              onChange={(event) => setProxied(event.target.checked)}
            />
            {proxiable ? "启用 Cloudflare 代理" : `${type} 不可代理`}
          </label>
        </Field>
        {type === "MX" && (
          <Field label="优先级">
            <input
              type="number"
              min={0}
              max={65535}
              value={priority}
              onChange={(event) => setPriority(event.target.value)}
            />
          </Field>
        )}
      </div>
      <Field label="备注" hint={`${comment.length}/100`}>
        <input
          value={comment}
          maxLength={100}
          onChange={(event) => setComment(event.target.value)}
        />
      </Field>
      {error && <div className="inline-warning">{error}</div>}
      <div className="form-actions">
        <button className="button ghost" onClick={onCancel}>
          取消
        </button>
        <button className="button primary" onClick={() => void save()} disabled={busy}>
          {busy ? "保存中…" : "保存记录"}
        </button>
      </div>
    </div>
  );
}

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: ReactNode;
}) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
      {hint && <span className="field-hint">{hint}</span>}
    </label>
  );
}

function PreviewPanel({
  rows,
  offerCount,
  zone,
  jobId,
  job,
  loading,
  page,
  pages,
  onPage,
  onBack,
  onExecute,
}: {
  rows: PreviewRow[];
  offerCount: number;
  zone: string;
  jobId: string | null;
  job: Job | null;
  loading: boolean;
  page: number;
  pages: number;
  onPage: (page: number) => void;
  onBack: () => void;
  onExecute: () => void;
}) {
  const running = job ? ["pending", "running"].includes(job.status) : false;
  const failed = job ? job.status === "failed" || job.failures > 0 : false;
  const ready = job ? job.status === "done" && job.failures === 0 : false;
  const total = job?.records ?? offerCount;
  return (
    <div className="preview-panel">
      <button className="back-link" onClick={onBack}>
        <ArrowLeft size={15} /> 返回修改
      </button>
      <div className="inspector-intro">
        <span className="eyebrow">PREVIEW</span>
        <h2>预览 · 尚未执行</h2>
        <p>
          {running
            ? `${zone} · 预览任务正在读取并核对记录，完成后显示真实 diff。`
            : total > 0
              ? `${zone} · 预览任务返回 ${total} 条变更；确认后才写入 Cloudflare。`
              : `${zone} · 预览任务已结束，没有匹配到需要变更的记录。`}
        </p>
        {jobId && (
          <p className="preview-job">
            预览任务：{jobId} ·{" "}
            {running
              ? "运行中…"
              : failed
                ? `有失败项 ${job?.failures ?? 0} 条`
                : ready
                  ? "已完成，可执行"
                  : job
                    ? job.status
                    : "状态读取中…"}
          </p>
        )}
      </div>
      <div className="preview-stats">
        <div>
          <strong>{total}</strong>
          <span>预览结果</span>
        </div>
        <div>
          <strong>{job?.failures ?? 0}</strong>
          <span>失败</span>
        </div>
        <div>
          <strong>{rows.length}</strong>
          <span>本页</span>
        </div>
      </div>
      <div className="diff-table" role="table" aria-label="变更预览">
        <div className="diff-head" role="row">
          <span>名称</span>
          <span>旧内容</span>
          <span>新内容</span>
        </div>
        {loading && rows.length === 0 ? (
          Array.from({ length: 3 }).map((_, index) => (
            <div className="diff-row skeleton-row" role="row" key={index}>
              <span className="skeleton-line" />
              <span className="skeleton-line" />
              <span className="skeleton-line" />
            </div>
          ))
        ) : rows.length > 0 ? (
          rows.map((row) => (
            <div className="diff-row" role="row" key={row.id}>
              <span className="diff-name">
                {row.name} <em>{row.type}</em>
                {row.action !== "更新" && row.action !== "删除" && (
                  <small> · {row.action}</small>
                )}
              </span>
              <code>{row.oldContent}</code>
              <code className={row.action === "删除" ? "diff-delete" : "diff-add"}>
                {row.newContent}
              </code>
            </div>
          ))
        ) : (
          <div className="diff-row">
            <span>—</span>
            <span>{running ? "正在读取预览结果…" : "没有逐条变更"}</span>
            <span>{running ? "无需操作" : "可返回修改范围"}</span>
          </div>
        )}
      </div>
      {pages > 1 && (
        <div className="preview-pager">
          <button
            className="button ghost"
            onClick={() => onPage(page - 1)}
            disabled={page <= 1 || loading}
          >
            上一页
          </button>
          <span>
            {page} / {pages}
          </span>
          <button
            className="button ghost"
            onClick={() => onPage(page + 1)}
            disabled={page >= pages || loading}
          >
            下一页
          </button>
        </div>
      )}
      <div className="inline-warning">
        <AlertTriangle size={16} />
        预览任务不会写入 Cloudflare。Diff 来自预览任务结果；执行后会生成新的任务记录。
      </div>
      {job && !ready && (
        <p className="form-hint">
          {running
            ? "预览任务仍在运行，完成后才能执行。"
            : "预览任务有失败项或未完成，请先处理失败或重新预览。"}
        </p>
      )}
      <div className="form-actions">
        <button className="button ghost" onClick={onBack}>
          返回修改
        </button>
        <button
          className="button primary"
          onClick={onExecute}
          disabled={!ready || loading}
        >
          <Play size={15} /> {running ? "等待预览完成…" : "执行变更"}
        </button>
      </div>
    </div>
  );
}

function TaskPanel({
  jobs,
  jobsLoading,
  jobsError,
  selectedJob,
  onSelectJob,
  onRerun,
  onCancel,
  onDownload,
  onExecutePreview,
  onRetryJobs,
}: {
  jobs: Job[];
  jobsLoading: boolean;
  jobsError: string | null;
  selectedJob: Job | null;
  onSelectJob: (job: Job | null) => void;
  onRerun: (jobId: string) => Promise<void>;
  onCancel: (jobId: string) => Promise<void>;
  onDownload: (jobId: string, kind: "failures" | "anomalies") => Promise<void>;
  onExecutePreview: (jobId: string) => Promise<void>;
  onRetryJobs: () => void;
}) {
  const selectedJobId = selectedJob?.id ?? null;
  const logsQuery = useJobLogs(
    selectedJobId,
    Boolean(
      selectedJob &&
        ["pending", "running"].includes(selectedJob.status),
    ),
  );
  const exportQuery = useJobExports(
    selectedJobId,
    Boolean(
      selectedJob &&
        selectedJob.mode === "export" &&
        ["done", "failed", "cancelled"].includes(selectedJob.status),
    ),
  );

  if (!selectedJob) {
    return (
      <div className="task-list">
        <div className="inspector-intro">
          <span className="eyebrow">TASKS</span>
          <h2>任务</h2>
          <p>预览、执行、失败重跑都在这里闭环。</p>
        </div>
        {jobsLoading && jobs.length === 0 && (
          <p className="nav-empty">正在读取任务…</p>
        )}
        {jobsError && (
          <div className="error-inline">
            <span>任务读取失败：{jobsError}</span>
            <button className="link-button" onClick={onRetryJobs}>
              重试
            </button>
          </div>
        )}
        {!jobsLoading && !jobsError && jobs.length === 0 && (
          <p className="nav-empty">暂无任务。提交预览后会出现在这里。</p>
        )}
        {jobs.map((job) => (
          <button key={job.id} className="task-row" onClick={() => onSelectJob(job)}>
            <span className={`task-status ${job.status}`} />
            <span className="task-copy">
              <strong>
                {job.id} · {job.mode}
              </strong>
              <small>
                {job.kind === "preview" ? "预览" : "执行"} · {job.scope}
              </small>
            </span>
            <span className="task-meta">{job.status}</span>
          </button>
        ))}
      </div>
    );
  }

  const logs = logsQuery.data?.logs ?? [];
  return (
    <div className="task-detail">
      <button className="back-link" onClick={() => onSelectJob(null)}>
        任务列表
      </button>
      <div className="inspector-intro">
        <span className="eyebrow">TASK DETAIL</span>
        <h2>
          {selectedJob.id} · {selectedJob.mode}
        </h2>
        <p>
          {selectedJob.kind === "preview" ? "预览任务" : "执行任务"} · {selectedJob.scope}
        </p>
      </div>
      <div className="task-progress">
        <div className="task-progress-head">
          <span className={`status-pill ${selectedJob.status}`}>{selectedJob.status}</span>
          <span>{selectedJob.progress}%</span>
        </div>
        <div className="progress-track">
          <span style={{ width: `${selectedJob.progress}%` }} />
        </div>
        <div className="task-facts">
          <span>账号 {selectedJob.accounts}</span>
          <span>域名 {selectedJob.zones}</span>
          <span>记录 {selectedJob.records}</span>
          <span>失败 {selectedJob.failures}</span>
          {selectedJob.anomalies > 0 && <span>异常 {selectedJob.anomalies}</span>}
        </div>
      </div>
      <div className="verdict-box">
        <div className="verdict-title">
          {selectedJob.status === "failed" ? <XCircle size={16} /> : <CheckCircle2 size={16} />}
          结论
        </div>
        <p>{selectedJob.verdict}</p>
        {selectedJob.causes.map((cause) => (
          <p className="cause-line" key={cause}>
            {cause}
          </p>
        ))}
      </div>
      <div className="task-actions">
        {selectedJob.failures > 0 && (
          <button
            className="button ghost"
            onClick={() => void onDownload(selectedJob.id, "failures")}
          >
            <Download size={15} /> 失败清单
          </button>
        )}
        {selectedJob.anomalies > 0 && (
          <button
            className="button ghost"
            onClick={() => void onDownload(selectedJob.id, "anomalies")}
          >
            <Download size={15} /> 异常 CSV
          </button>
        )}
        {selectedJob.failures > 0 &&
          !["pending", "running"].includes(selectedJob.status) && (
            <button className="button" onClick={() => void onRerun(selectedJob.id)}>
              <RotateCcw size={15} /> 重跑失败域
            </button>
          )}
        {selectedJob.kind === "preview" &&
          selectedJob.mode !== "export" &&
          selectedJob.status === "done" &&
          selectedJob.failures === 0 && (
            <button
              className="button primary"
              onClick={() => void onExecutePreview(selectedJob.id)}
            >
              <Play size={15} /> 执行此预览
            </button>
          )}
        {["running", "pending"].includes(selectedJob.status) && (
          <button
            className="button danger"
            onClick={() => void onCancel(selectedJob.id)}
          >
            取消任务
          </button>
        )}
      </div>
      {selectedJob.mode === "export" && (
        <div className="export-list">
          <div className="task-progress-head">
            <span>导出文件</span>
            <span className="muted">
              {exportQuery.data?.total ?? 0} 个
            </span>
          </div>
          {exportQuery.isFetching && (
            <p className="form-hint">正在读取导出文件…</p>
          )}
          {exportQuery.error && (
            <div className="error-inline">
              导出文件读取失败：{exportQuery.error.message}
            </div>
          )}
          {exportQuery.data?.items.map((item) => (
            <button
              key={item.index}
              className="export-row"
              onClick={() =>
                void downloadJobExport(selectedJob.id, item.index, item.zone)
              }
            >
              <span>{item.zone || `导出 ${item.index + 1}`}</span>
              <small title={item.path}>{item.path}</small>
              <Download size={14} />
            </button>
          ))}
          {!exportQuery.isFetching && exportQuery.data?.total === 0 && (
            <p className="form-hint">任务尚未产生导出文件。</p>
          )}
        </div>
      )}
      <div className="log-block">
        <div className="log-head">
          <span>日志</span>
          <span className="muted">
            {logsQuery.isFetching ? (
              <span className="inline-loading">
                <Loader2 size={12} className="spin" /> 读取中
              </span>
            ) : (
              `${logsQuery.data?.total ?? 0} 行 · 最近 500 行`
            )}
          </span>
        </div>
        <pre>
          {logsQuery.error
            ? `日志读取失败：${logsQuery.error.message}`
            : logs.length
              ? logs.join("\n")
              : logsQuery.isLoading
                ? "正在读取日志…"
                : "暂无日志输出。"}
        </pre>
      </div>
    </div>
  );
}
