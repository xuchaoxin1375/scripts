import {
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  Asterisk,
  CheckCircle2,
  Download,
  FileJson,
  Globe2,
  Layers,
  ListFilter,
  Play,
  Plus,
  RefreshCw,
  RotateCcw,
  ShieldAlert,
  SlidersHorizontal,
  Trash2,
  Upload,
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

type Props = {
  tab: InspectorTab;
  onTab: (tab: InspectorTab) => void;
  account: string;
  zone: string;
  selectedRecords: DnsRecord[];
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
  previewJobId: string | null;
  previewJob: Job | null;
  submitting: boolean;
  onPreview: (draft: ActionDraft) => void;
  onBack: () => void;
  onExecute: () => void;
  jobs: Job[];
  selectedJob: Job | null;
  onSelectJob: (job: Job | null) => void;
  onRerun: (jobId: string) => Promise<void>;
  onCancel: (jobId: string) => Promise<void>;
  onDownload: (jobId: string, kind: "failures" | "anomalies") => Promise<void>;
  onExecutePreview: (jobId: string) => Promise<void>;
  onNotify: (message: string) => void;
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

function ActionIcon({ mode }: { mode: ActionMode }) {
  const card = ACTION_CARDS.find((item) => item.mode === mode);
  const Icon = card?.icon ?? Layers;
  return <Icon size={16} />;
}

export default function Inspector(props: Props) {
  const {
    tab,
    onTab,
    account,
    zone,
    selectedRecords,
    editingRecord,
    onCancelEdit,
    onSaveRecord,
    actionMode,
    onActionMode,
    previewOpen,
    previewRows,
    previewJobId,
    previewJob,
    submitting,
    onPreview,
    onBack,
    onExecute,
    jobs,
    selectedJob,
    onSelectJob,
    onRerun,
    onCancel,
    onDownload,
    onExecutePreview,
    onNotify,
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
              zone={zone}
              jobId={previewJobId}
              job={previewJob}
              onBack={onBack}
              onExecute={onExecute}
            />
          ) : actionMode ? (
            <ActionForm
              mode={actionMode}
              account={account}
              zone={zone}
              selectedCount={selectedRecords.length}
              selectedRecords={selectedRecords}
              submitting={submitting}
              onBack={() => onActionMode(null)}
              onPreview={onPreview}
              onNotify={onNotify}
            />
          ) : (
            <ActionPicker
              selectedCount={selectedRecords.length}
              zone={zone}
              onPick={onActionMode}
            />
          )}
        </div>
      ) : (
        <div className="inspector-body">
          <TaskPanel
            jobs={jobs}
            selectedJob={selectedJob}
            onSelectJob={onSelectJob}
            onRerun={onRerun}
            onCancel={onCancel}
            onDownload={onDownload}
            onExecutePreview={onExecutePreview}
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
  onBack,
  onPreview,
  onNotify,
}: {
  mode: ActionMode;
  account: string;
  zone: string;
  selectedCount: number;
  selectedRecords: DnsRecord[];
  submitting: boolean;
  onBack: () => void;
  onPreview: (draft: ActionDraft) => void;
  onNotify: (message: string) => void;
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
  const [backupDir, setBackupDir] = useState("C:/Users/Administrator/Desktop/deploy_configs/cf_backup");
  const [proxy, setProxy] = useState("keep");
  const [ttl, setTtl] = useState("");
  const [domain, setDomain] = useState("");
  const [recordsText, setRecordsText] = useState("www:A:198.51.100.10");
  const [addProxied, setAddProxied] = useState("on");
  const [addTtl, setAddTtl] = useState("1");
  const [exportDir, setExportDir] = useState("C:/Users/Administrator/Desktop/deploy_configs/cf_export");
  const [exportFormat, setExportFormat] = useState("json");
  const [serverIp, setServerIp] = useState("");
  const [forwardEmail, setForwardEmail] = useState("");

  const card = ACTION_CARDS.find((item) => item.mode === mode);
  const title = card?.title ?? "批量操作";
  const isDanger = card?.tone === "danger";
  const scopeText = "当前域名下匹配记录";

  function submitPreview() {
    if (mode === "update" && !newContent.trim()) {
      onNotify("请填写新内容，例如 198.51.100.10 或目标域名");
      return;
    }
    if (mode === "delete_ip" && !deleteIp.trim()) {
      onNotify("请填写要删除的 IP");
      return;
    }
    if (mode === "delete_zone" && confirm.trim() !== "DELETE") {
      onNotify("删除域名需输入 DELETE 确认");
      return;
    }
    if (mode === "set_attrs" && proxy === "keep" && !ttl.trim()) {
      onNotify("属性设置至少改一项：代理或 TTL");
      return;
    }
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
  zone,
  jobId,
  job,
  onBack,
  onExecute,
}: {
  rows: PreviewRow[];
  zone: string;
  jobId: string | null;
  job: Job | null;
  onBack: () => void;
  onExecute: () => void;
}) {
  const updates = rows.filter((row) => row.action === "更新").length;
  const deletes = rows.filter((row) => row.action === "删除").length;
  const running = job ? ["pending", "running"].includes(job.status) : false;
  const failed = job ? job.status === "failed" || job.failures > 0 : false;
  const ready = job ? job.status === "done" && job.failures === 0 : false;
  return (
    <div className="preview-panel">
      <button className="back-link" onClick={onBack}>
        <ArrowLeft size={15} /> 返回修改
      </button>
      <div className="inspector-intro">
        <span className="eyebrow">PREVIEW</span>
        <h2>预览 · 尚未执行</h2>
        <p>
          {rows.length > 0
            ? `${zone} · 将更新 ${updates} 条、删除 ${deletes} 条。确认后才写入 Cloudflare。`
            : "该动作没有逐条 diff，提交后以任务日志与结果为准。"}
        </p>
        {jobId && (
          <p className="preview-job">
            预览任务：{jobId} ·{" "}
            {running
              ? "运行中…"
              : failed
                ? "有失败项"
                : ready
                  ? "已完成，可执行"
                  : "状态读取中…"}
          </p>
        )}
      </div>
      <div className="preview-stats">
        <div>
          <strong>{rows.length}</strong>
          <span>涉及记录</span>
        </div>
        <div>
          <strong>{updates}</strong>
          <span>更新</span>
        </div>
        <div>
          <strong>{deletes}</strong>
          <span>删除</span>
        </div>
      </div>
      <div className="diff-table" role="table" aria-label="变更预览">
        <div className="diff-head" role="row">
          <span>名称</span>
          <span>旧内容</span>
          <span>新内容</span>
        </div>
        {rows.length > 0 ? (
          rows.map((row) => (
            <div className="diff-row" role="row" key={row.id}>
              <span className="diff-name">
                {row.name} <em>{row.type}</em>
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
            <span>该动作无逐条差异</span>
            <span>执行前请以任务日志为准</span>
          </div>
        )}
      </div>
      <div className="inline-warning">
        <AlertTriangle size={16} />
        预览任务不会写入 Cloudflare。Diff 为本地预估，最终以预览任务结果为准；执行后会生成新的任务记录。
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
          disabled={!ready}
        >
          <Play size={15} /> {running ? "等待预览完成…" : "执行变更"}
        </button>
      </div>
    </div>
  );
}

function TaskPanel({
  jobs,
  selectedJob,
  onSelectJob,
  onRerun,
  onCancel,
  onDownload,
  onExecutePreview,
}: {
  jobs: Job[];
  selectedJob: Job | null;
  onSelectJob: (job: Job | null) => void;
  onRerun: (jobId: string) => Promise<void>;
  onCancel: (jobId: string) => Promise<void>;
  onDownload: (jobId: string, kind: "failures" | "anomalies") => Promise<void>;
  onExecutePreview: (jobId: string) => Promise<void>;
}) {
  if (!selectedJob) {
    return (
      <div className="task-list">
        <div className="inspector-intro">
          <span className="eyebrow">TASKS</span>
          <h2>任务</h2>
          <p>预览、执行、失败重跑都在这里闭环。</p>
        </div>
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
        <button
          className="button ghost"
          onClick={() => void onDownload(selectedJob.id, "failures")}
        >
          <Download size={15} /> 失败清单
        </button>
        <button
          className="button ghost"
          onClick={() => void onDownload(selectedJob.id, "anomalies")}
        >
          <Download size={15} /> 异常 CSV
        </button>
        <button className="button" onClick={() => void onRerun(selectedJob.id)}>
          <RotateCcw size={15} /> 重跑失败域
        </button>
        {selectedJob.kind === "preview" &&
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
      <div className="log-block">
        <div className="log-head">
          <span>日志</span>
          <span className="muted">原始输出折叠</span>
        </div>
        <pre>[job] {selectedJob.id} 已创建{"\n"}[account] 正在读取 zone…{"\n"}[progress] 6/10</pre>
      </div>
    </div>
  );
}
