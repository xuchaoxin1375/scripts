import {
  ChevronLeft,
  ChevronRight,
  Download,
  FileJson,
  Gauge,
  History,
  Loader2,
  RefreshCw,
  Search,
  Upload,
  Wand2,
  X,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import type { ChangeEvent } from "react";
import type {
  Account,
  Attachments,
  ResumeAttachment,
  RuntimeSettings,
  WhitelistAttachment,
} from "../types";
import type { ApiImportItem } from "../api/types";
import {
  downloadJobExport,
  downloadRecordsJson,
  downloadZoneCsv,
  useAudit,
  useExecuteJob,
  useFindDomain,
  useHistory,
  useImportRecords,
  useJob,
  useJobExports,
  useMeta,
  useSubmitJob,
  useUploadResume,
  useUploadWhitelist,
} from "../api/hooks";

type Props = {
  accounts: Account[];
  account: string;
  zone: string;
  attachments: Attachments;
  runtime: RuntimeSettings;
  onOpenScope: (account: string, zone: string) => void;
  onOpenJob: (jobId: string) => void;
  onAttachmentChange: (
    kind: "whitelist" | "resume",
    value: WhitelistAttachment | ResumeAttachment | null,
  ) => void;
  onRuntimeChange: (settings: RuntimeSettings) => void;
  onNotify: (message: string) => void;
};

function linesOf(text: string): string[] {
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function formatWhen(value: string): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString("zh-CN", { hour12: false });
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export default function Advanced({
  accounts,
  account,
  zone,
  attachments,
  runtime,
  onOpenScope,
  onOpenJob,
  onAttachmentChange,
  onRuntimeChange,
  onNotify,
}: Props) {
  return (
    <div className="advanced-page">
      <header className="page-head">
        <span className="eyebrow">ADVANCED</span>
        <h1>高级</h1>
        <p>低频能力集中在这里：跨账号查找、配置向导、导入导出、范围附件与历史审计。</p>
      </header>

      <div className="advanced-context">
        <span>当前范围</span>
        <strong>
          {account || "未选择账号"} / {zone || "未选择域名"}
        </strong>
        <button
          className="button ghost"
          disabled={!account || !zone}
          onClick={() => onOpenScope(account, zone)}
        >
          回到工作台
        </button>
      </div>

      <div className="advanced-grid">
        <FindPanel onOpenScope={onOpenScope} onNotify={onNotify} />
        <ProvisionPanel
          accounts={accounts}
          defaultAccount={account}
          defaultZone={zone}
          runtime={runtime}
          onOpenJob={onOpenJob}
          onNotify={onNotify}
        />
        <TransferPanel
          account={account}
          zone={zone}
          runtime={runtime}
          onOpenJob={onOpenJob}
          onNotify={onNotify}
        />
        <AttachmentPanel
          account={account}
          zone={zone}
          attachments={attachments}
          onAttachmentChange={onAttachmentChange}
          onNotify={onNotify}
        />
        <HistoryPanel onNotify={onNotify} />
        <RuntimePanel runtime={runtime} onRuntimeChange={onRuntimeChange} />
      </div>
    </div>
  );
}

function FindPanel({
  onOpenScope,
  onNotify,
}: {
  onOpenScope: (account: string, zone: string) => void;
  onNotify: (message: string) => void;
}) {
  const [domain, setDomain] = useState("");
  const [error, setError] = useState("");
  const find = useFindDomain();
  const results = find.data?.results ?? [];
  const success = results.filter((item) => !item.error);
  const failed = results.filter((item) => item.error);

  async function submit() {
    const target = domain.trim();
    if (!target) {
      setError("请输入域名，例如 example.com");
      return;
    }
    setError("");
    try {
      const data = await find.mutateAsync(target);
      if (data.found === 0) {
        onNotify(`未在任何账号中找到 ${data.domain}`);
      } else {
        onNotify(`找到 ${data.found} 个账号包含 ${data.domain}`);
      }
    } catch (err) {
      setError(errorText(err));
    }
  }

  return (
    <section className="panel wide">
      <div className="panel-head">
        <Search size={17} />
        <div>
          <h2>跨账号查找域名</h2>
          <p>逐个账号检查 zone 是否存在；账号较多时会较慢，结果按账号列出。</p>
        </div>
      </div>
      <div className="inline-form">
        <input
          value={domain}
          onChange={(event) => setDomain(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") void submit();
          }}
          placeholder="example.com"
          aria-label="要查找的域名"
        />
        <button
          className="button primary"
          onClick={() => void submit()}
          disabled={find.isPending}
        >
          {find.isPending ? (
            <>
              <Loader2 size={15} className="spin" /> 查找中
            </>
          ) : (
            <>
              <Search size={15} /> 查找
            </>
          )}
        </button>
      </div>
      {error && <div className="error-inline">{error}</div>}
      {find.data && (
        <>
          <p className="form-hint result-summary">
            {find.data.domain} · 命中 {find.data.found} 个账号
            {failed.length ? ` · ${failed.length} 个账号读取失败` : ""}
          </p>
          {success.length > 0 && (
            <div
              className="data-table-wrap"
              role="region"
              aria-label="跨账号查找结果"
              tabIndex={0}
            >
              <table className="data-table">
                <thead>
                  <tr>
                    <th>账号</th>
                    <th>域名</th>
                    <th>状态</th>
                    <th>记录数</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {success.map((item) => (
                    <tr key={`${item.account}-${item.zone}`}>
                      <td>{item.account}</td>
                      <td>{item.zone || find.data?.domain}</td>
                      <td>
                        <span className={`status-pill ${item.status === "active" ? "done" : "running"}`}>
                          {item.status || "—"}
                        </span>
                      </td>
                      <td>{item.record_count ?? "—"}</td>
                      <td>
                        <button
                          className="button ghost"
                          onClick={() =>
                            onOpenScope(item.account, item.zone || find.data!.domain)
                          }
                        >
                          打开
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {failed.length > 0 && (
            <div className="error-inline">
              {failed.map((item) => (
                <div key={item.account}>
                  {item.account}：{item.error}
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </section>
  );
}

function ProvisionPanel({
  accounts,
  defaultAccount,
  defaultZone,
  runtime,
  onOpenJob,
  onNotify,
}: {
  accounts: Account[];
  defaultAccount: string;
  defaultZone: string;
  runtime: RuntimeSettings;
  onOpenJob: (jobId: string) => void;
  onNotify: (message: string) => void;
}) {
  const [account, setAccount] = useState(defaultAccount);
  const [domainsText, setDomainsText] = useState(defaultZone);
  const [serverIp, setServerIp] = useState("");
  const [forwardEmail, setForwardEmail] = useState("");
  const [sslMode, setSslMode] = useState("");
  const [createZone, setCreateZone] = useState(false);
  const [steps, setSteps] = useState({
    dns: true,
    activation: true,
    email: true,
    ssl: true,
    security: true,
    optimize: true,
  });
  const [jobId, setJobId] = useState<string | null>(null);
  const [error, setError] = useState("");
  const submit = useSubmitJob();
  const execute = useExecuteJob();
  const jobQuery = useJob(jobId);
  const job = jobQuery.data ?? null;

  useEffect(() => {
    if (!account && defaultAccount) setAccount(defaultAccount);
  }, [account, defaultAccount]);

  useEffect(() => {
    if (!domainsText && defaultZone) setDomainsText(defaultZone);
  }, [domainsText, defaultZone]);

  const domains = useMemo(() => linesOf(domainsText), [domainsText]);

  async function submitPreview() {
    if (!account) {
      setError("先选择账号");
      return;
    }
    if (!domains.length) {
      setError("至少填写一个域名");
      return;
    }
    setError("");
    try {
      const result = await submit.mutateAsync({
        mode: "provision",
        accounts: [account],
        domains,
        server_ip: serverIp.trim(),
        forward_email: forwardEmail.trim(),
        ssl_mode: sslMode,
        create_zone: createZone,
        do_dns: steps.dns,
        do_activation: steps.activation,
        do_email: steps.email,
        do_ssl: steps.ssl,
        do_security: steps.security,
        do_optimize: steps.optimize,
        speed: runtime.speed,
        scope: runtime.scope,
        max_retries: runtime.maxRetries,
        dry_run: true,
        label: `provision 预览 x${domains.length}域名`,
      });
      setJobId(result.job_id);
      onNotify("provision 预览已提交：" + result.job_id);
    } catch (err) {
      setError(errorText(err));
    }
  }

  async function executePreview() {
    if (!jobId) return;
    try {
      const result = await execute.mutateAsync(jobId);
      onNotify("provision 执行已提交：" + result.job_id);
      onOpenJob(result.job_id);
    } catch (err) {
      setError(errorText(err));
    }
  }

  function toggleStep(key: keyof typeof steps) {
    setSteps((current) => ({ ...current, [key]: !current[key] }));
  }

  const ready = job
    ? job.status === "done" && job.failures === 0
    : false;

  return (
    <section className="panel wide">
      <div className="panel-head">
        <Wand2 size={17} />
        <div>
          <h2>域名配置向导</h2>
          <p>DNS → 等激活 → 邮箱 → SSL → 安全 / 加速；默认先预览再执行。</p>
        </div>
      </div>
      <div className="form-grid">
        <label className="field">
          <span className="field-label">账号</span>
          <select
            value={account}
            onChange={(event) => setAccount(event.target.value)}
          >
            <option value="">选择账号</option>
            {accounts.map((item) => (
              <option key={item.name} value={item.name}>
                {item.name}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span className="field-label">SSL 模式</span>
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
        </label>
      </div>
      <label className="field">
        <span className="field-label">域名（每行一个）</span>
        <textarea
          rows={3}
          value={domainsText}
          onChange={(event) => setDomainsText(event.target.value)}
          placeholder="example.com"
        />
      </label>
      <div className="form-grid">
        <label className="field">
          <span className="field-label">默认服务器 IP</span>
          <input
            value={serverIp}
            onChange={(event) => setServerIp(event.target.value)}
            placeholder="198.51.100.10"
          />
        </label>
        <label className="field">
          <span className="field-label">邮箱转发目标</span>
          <input
            value={forwardEmail}
            onChange={(event) => setForwardEmail(event.target.value)}
            placeholder="admin@example.com"
          />
        </label>
      </div>
      <div className="step-toggle-row">
        {(
          [
            ["dns", "DNS"],
            ["activation", "等激活"],
            ["email", "邮箱"],
            ["ssl", "SSL"],
            ["security", "安全"],
            ["optimize", "加速"],
          ] as const
        ).map(([key, label]) => (
          <label className="checkbox-line" key={key}>
            <input
              type="checkbox"
              checked={steps[key]}
              onChange={() => toggleStep(key)}
            />
            {label}
          </label>
        ))}
        <label className="checkbox-line">
          <input
            type="checkbox"
            checked={createZone}
            onChange={(event) => setCreateZone(event.target.checked)}
          />
          不存在时创建 zone
        </label>
      </div>
      {error && <div className="error-inline">{error}</div>}
      <div className="button-row">
        <button
          className="button primary"
          onClick={() => void submitPreview()}
          disabled={submit.isPending}
        >
          {submit.isPending ? "提交中…" : "预览配置"}
        </button>
        {jobId && (
          <button className="button ghost" onClick={() => onOpenJob(jobId)}>
            在任务中查看
          </button>
        )}
        {ready && (
          <button
            className="button"
            onClick={() => void executePreview()}
            disabled={execute.isPending}
          >
            {execute.isPending ? "提交中…" : "执行此预览"}
          </button>
        )}
      </div>
      {job && (
        <div className="job-inline">
          <span className={`status-pill ${job.status}`}>{job.status}</span>
          <span>
            预览 {job.id} · 账号 {job.accounts} · 域名 {job.zones} · 结果 {job.records} ·
            失败 {job.failures}
          </span>
        </div>
      )}
    </section>
  );
}

function TransferPanel({
  account,
  zone,
  runtime,
  onOpenJob,
  onNotify,
}: {
  account: string;
  zone: string;
  runtime: RuntimeSettings;
  onOpenJob: (jobId: string) => void;
  onNotify: (message: string) => void;
}) {
  const meta = useMeta();
  const importRecords = useImportRecords();
  const submit = useSubmitJob();
  const fileRef = useRef<HTMLInputElement>(null);
  const [items, setItems] = useState<ApiImportItem[] | null>(null);
  const [fileName, setFileName] = useState("");
  const [prechecked, setPrechecked] = useState(false);
  const [importResult, setImportResult] = useState("");
  const [error, setError] = useState("");
  const [exportDir, setExportDir] = useState("");
  const [exportFormat, setExportFormat] = useState("json");
  const [exportJobId, setExportJobId] = useState<string | null>(null);
  const exportJobQuery = useJob(exportJobId);
  const exportJob = exportJobQuery.data ?? null;
  const exportsQuery = useJobExports(
    exportJobId,
    Boolean(
      exportJob &&
        ["done", "failed", "cancelled"].includes(exportJob.status),
    ),
  );

  useEffect(() => {
    if (!exportDir && meta.data?.dirs.export_dir) {
      setExportDir(meta.data.dirs.export_dir);
    }
  }, [exportDir, meta.data?.dirs.export_dir]);

  useEffect(() => {
    setItems(null);
    setPrechecked(false);
    setImportResult("");
    setFileName("");
    setError("");
    if (fileRef.current) fileRef.current.value = "";
  }, [account, zone]);

  const scopeReady = Boolean(account && zone);

  async function chooseFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setPrechecked(false);
    setImportResult("");
    setError("");
    if (file.size > 1024 * 1024) {
      setError("JSON 文件超过 1MB 上限");
      return;
    }
    try {
      const parsed = JSON.parse(await file.text()) as unknown;
      if (!Array.isArray(parsed)) {
        setError("文件顶层须为数组");
        return;
      }
      if (parsed.length > 200) {
        setError("单次导入至多 200 条");
        return;
      }
      const records = parsed.map((raw) => {
        const item = raw as Record<string, unknown>;
        return {
          name: String(item.name ?? ""),
          type: String(item.type ?? "A"),
          content: String(item.content ?? ""),
          proxied: Boolean(item.proxied),
          ttl: Number(item.ttl ?? 1) || 1,
          comment: String(item.comment ?? ""),
          priority:
            item.priority === undefined || item.priority === null
              ? null
              : Number(item.priority),
        } satisfies ApiImportItem;
      });
      setItems(records);
      setFileName(file.name);
    } catch (err) {
      setError("JSON 解析失败：" + errorText(err));
      setItems(null);
    }
  }

  async function precheck() {
    if (!items || !scopeReady) return;
    setError("");
    try {
      const result = await importRecords.mutateAsync({
        account,
        zone,
        records: items,
        dry_run: true,
      });
      setPrechecked(true);
      onNotify(`预检通过：${result.checked ?? items.length} 条可写`);
    } catch (err) {
      setPrechecked(false);
      setError(errorText(err));
    }
  }

  async function runImport() {
    if (!items || !prechecked || !scopeReady) return;
    setError("");
    try {
      const result = await importRecords.mutateAsync({
        account,
        zone,
        records: items,
        dry_run: false,
      });
      setImportResult(
        `导入完成：新增 ${result.added ?? 0}，更新 ${result.updated ?? 0}，未变 ${result.unchanged ?? 0}，失败 ${result.failed?.length ?? 0}`,
      );
      setItems(null);
      setPrechecked(false);
      if (fileRef.current) fileRef.current.value = "";
      onNotify("记录导入完成");
    } catch (err) {
      setError(errorText(err));
    }
  }

  async function runExportJob() {
    if (!scopeReady) return;
    setError("");
    try {
      const result = await submit.mutateAsync({
        mode: "export",
        accounts: [account],
        domains: [zone],
        export_dir: exportDir || meta.data?.dirs.export_dir || "",
        export_fmt: exportFormat,
        speed: runtime.speed,
        scope: runtime.scope,
        max_retries: runtime.maxRetries,
        dry_run: false,
        label: `导出 ${zone}`,
      });
      setExportJobId(result.job_id);
      onNotify("导出任务已提交：" + result.job_id);
    } catch (err) {
      setError(errorText(err));
    }
  }

  function downloadRecords() {
    if (!scopeReady) return;
    downloadRecordsJson({ account, zone })
      .then(() => onNotify("已导出当前域名记录 JSON"))
      .catch((err) => setError(errorText(err)));
  }

  function downloadZones() {
    if (!account) return;
    downloadZoneCsv(account)
      .then(() => onNotify("已导出 zone CSV"))
      .catch((err) => setError(errorText(err)));
  }

  return (
    <section className="panel">
      <div className="panel-head">
        <FileJson size={17} />
        <div>
          <h2>导入 / 导出</h2>
          <p>导入先预检后写入；导出支持当前域名 JSON、zone CSV 与服务器目录任务。</p>
        </div>
      </div>
      {!scopeReady && (
        <div className="form-hint">
          先在左侧选择账号与域名，导入导出会使用当前范围。
        </div>
      )}
      <div className="subsection">
        <h3>导入记录 JSON</h3>
        <input
          ref={fileRef}
          type="file"
          accept=".json,application/json"
          aria-label="导入记录 JSON 文件"
          onChange={(event) => void chooseFile(event)}
          disabled={!scopeReady}
        />
        <p className="form-hint">
          数组，每项含 name/type/content，可含 ttl/proxied/comment/priority；上限 200 条、1MB。
        </p>
        {fileName && (
          <p className="form-hint">
            {fileName} · {items?.length ?? 0} 条
          </p>
        )}
        <div className="button-row">
          <button
            className="button ghost"
            onClick={() => void precheck()}
            disabled={!items || !scopeReady || importRecords.isPending}
          >
            {importRecords.isPending && !prechecked ? "预检中…" : "预检记录"}
          </button>
          <button
            className="button primary"
            onClick={() => void runImport()}
            disabled={!prechecked || importRecords.isPending}
          >
            确认导入
          </button>
        </div>
        {importResult && <p className="success-inline">{importResult}</p>}
      </div>
      <div className="subsection">
        <h3>导出</h3>
        <div className="button-row">
          <button className="button ghost" onClick={downloadRecords} disabled={!scopeReady}>
            <Download size={15} /> 当前域名 JSON
          </button>
          <button className="button ghost" onClick={downloadZones} disabled={!account}>
            <Download size={15} /> zone CSV
          </button>
        </div>
        <div className="form-grid">
          <label className="field">
            <span className="field-label">服务器导出目录</span>
            <input
              value={exportDir}
              onChange={(event) => setExportDir(event.target.value)}
              placeholder={meta.data?.dirs.export_dir || "./cf_export"}
            />
          </label>
          <label className="field">
            <span className="field-label">格式</span>
            <select
              value={exportFormat}
              onChange={(event) => setExportFormat(event.target.value)}
            >
              <option value="json">json</option>
              <option value="bind">bind</option>
            </select>
          </label>
        </div>
        <button
          className="button"
          onClick={() => void runExportJob()}
          disabled={!scopeReady || submit.isPending}
        >
          {submit.isPending ? "提交中…" : "生成导出任务"}
        </button>
        {exportJob && (
          <div className="job-inline">
            <span className={`status-pill ${exportJob.status}`}>{exportJob.status}</span>
            <span>
              导出 {exportJob.id} · 失败 {exportJob.failures} · 文件{" "}
              {exportsQuery.data?.total ?? 0}
            </span>
            <button className="link-button" onClick={() => onOpenJob(exportJob.id)}>
              查看任务
            </button>
          </div>
        )}
        {exportsQuery.data?.items.map((item) => (
          <button
            key={item.index}
            className="export-row"
            onClick={() => void downloadJobExport(exportJobId!, item.index, item.zone)}
          >
            <span>{item.zone || `导出 ${item.index + 1}`}</span>
            <small title={item.path}>{item.path}</small>
            <Download size={14} />
          </button>
        ))}
      </div>
      {error && <div className="error-inline">{error}</div>}
    </section>
  );
}

function AttachmentPanel({
  account,
  zone,
  attachments,
  onAttachmentChange,
  onNotify,
}: {
  account: string;
  zone: string;
  attachments: Attachments;
  onAttachmentChange: (
    kind: "whitelist" | "resume",
    value: WhitelistAttachment | ResumeAttachment | null,
  ) => void;
  onNotify: (message: string) => void;
}) {
  const whitelistUpload = useUploadWhitelist();
  const resumeUpload = useUploadResume();
  const whitelistRef = useRef<HTMLInputElement>(null);
  const resumeRef = useRef<HTMLInputElement>(null);
  const [error, setError] = useState("");

  async function uploadWhitelist(file: File) {
    setError("");
    try {
      const data = await whitelistUpload.mutateAsync(file);
      onAttachmentChange("whitelist", {
        path: data.path,
        count: data.count,
        domains: data.domains,
      });
      onNotify(`白名单已解析：${data.count} 个域名`);
    } catch (err) {
      setError(errorText(err));
    }
  }

  async function uploadResume(file: File) {
    setError("");
    try {
      const data = await resumeUpload.mutateAsync(file);
      onAttachmentChange("resume", {
        path: data.path,
        rows: data.rows,
        zones: data.zones,
      });
      onNotify(`重跑清单已解析：${data.rows} 行`);
    } catch (err) {
      setError(errorText(err));
    }
  }

  return (
    <section className="panel">
      <div className="panel-head">
        <Upload size={17} />
        <div>
          <h2>白名单 / 重跑清单</h2>
          <p>上传后附加到下一次预览/执行；不写入账号配置，服务重启后需重传。</p>
        </div>
      </div>
      <div className="drop-row">
        <div className="drop-zone">
          <div>
            <strong>白名单 .txt / .csv</strong>
            <small>
              {attachments.whitelist
                ? `已附加 ${attachments.whitelist.count} 个域名`
                : "每行一个域名/URL，2MB 内"}
            </small>
          </div>
          <div className="drop-actions">
            <input
              ref={whitelistRef}
              type="file"
              accept=".txt,.csv"
              aria-label="上传白名单文件"
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (file) {
                  void uploadWhitelist(file).finally(() => {
                    if (whitelistRef.current) whitelistRef.current.value = "";
                  });
                }
              }}
            />
            {attachments.whitelist && (
              <button
                className="icon-button"
                aria-label="移除白名单"
                onClick={() => onAttachmentChange("whitelist", null)}
              >
                <X size={14} />
              </button>
            )}
          </div>
        </div>
        <div className="drop-zone">
          <div>
            <strong>失败清单 .csv</strong>
            <small>
              {attachments.resume
                ? `已附加 ${attachments.resume.rows} 行 / ${attachments.resume.zones.length} 域名`
                : "account,zone 两列；用于限定重跑范围"}
            </small>
          </div>
          <div className="drop-actions">
            <input
              ref={resumeRef}
              type="file"
              accept=".csv"
              aria-label="上传失败清单 CSV"
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (file) {
                  void uploadResume(file).finally(() => {
                    if (resumeRef.current) resumeRef.current.value = "";
                  });
                }
              }}
            />
            {attachments.resume && (
              <button
                className="icon-button"
                aria-label="移除重跑清单"
                onClick={() => onAttachmentChange("resume", null)}
              >
                <X size={14} />
              </button>
            )}
          </div>
        </div>
      </div>
      <p className="form-hint">
        当前范围 {account || "未选账号"} / {zone || "未选域名"}；白名单会与显式域名取交集，
        重跑清单按账号与域名过滤任务。
      </p>
      {attachments.whitelist && (
        <details className="attachment-detail">
          <summary>查看白名单域名（前 200 个）</summary>
          <div className="chip-row">
            {attachments.whitelist.domains.slice(0, 200).map((item) => (
              <span className="step-chip" key={item}>
                {item}
              </span>
            ))}
          </div>
        </details>
      )}
      {attachments.resume && (
        <details className="attachment-detail">
          <summary>查看重跑域名（前 100 个）</summary>
          <div className="chip-row">
            {attachments.resume.zones.slice(0, 100).map((item) => (
              <span className="step-chip" key={item}>
                {item}
              </span>
            ))}
          </div>
        </details>
      )}
      {error && <div className="error-inline">{error}</div>}
    </section>
  );
}

function HistoryPanel({ onNotify }: { onNotify: (message: string) => void }) {
  const [tab, setTab] = useState<"history" | "audit">("history");
  const [offset, setOffset] = useState(0);
  const limit = 50;
  const history = useHistory(tab === "history", limit, offset);
  const audit = useAudit(tab === "audit", limit, offset);
  const active = tab === "history" ? history : audit;
  const historyRows = history.data?.items ?? [];
  const auditRows = audit.data?.items ?? [];
  const total = active.data?.total ?? 0;
  const pages = Math.max(1, Math.ceil(total / limit));
  const page = Math.floor(offset / limit) + 1;

  function refresh() {
    void active.refetch();
    onNotify("已刷新" + (tab === "history" ? "任务历史" : "审计日志"));
  }

  return (
    <section className="panel wide">
      <div className="panel-head">
        <History size={17} />
        <div>
          <h2>历史与审计</h2>
          <p>任务终态与单条/批量写入记录；按时间倒序分页加载。</p>
        </div>
      </div>
      <div className="tab-row">
        <button
          className={`tab-button ${tab === "history" ? "active" : ""}`}
          onClick={() => {
            setTab("history");
            setOffset(0);
          }}
        >
          任务历史
        </button>
        <button
          className={`tab-button ${tab === "audit" ? "active" : ""}`}
          onClick={() => {
            setTab("audit");
            setOffset(0);
          }}
        >
          审计日志
        </button>
        <button className="button ghost" onClick={refresh} disabled={active.isFetching}>
          <RefreshCw size={14} className={active.isFetching ? "spin" : ""} /> 刷新
        </button>
      </div>
      {active.error && (
        <div className="error-inline">
          读取失败：{errorText(active.error)}
          <button className="link-button" onClick={() => void active.refetch()}>
            重试
          </button>
        </div>
      )}
      {active.isPending ? (
        <p className="form-hint">正在读取…</p>
      ) : tab === "history" ? (
        <div
          className="data-table-wrap"
          role="region"
          aria-label="任务历史"
          tabIndex={0}
        >
          <table className="data-table">
            <thead>
              <tr>
                <th>结束时间</th>
                <th>任务</th>
                <th>账号</th>
                <th>状态</th>
              </tr>
            </thead>
            <tbody>
              {historyRows.map((row) => (
                <tr key={row.id}>
                  <td>{formatWhen(row.finished_at || row.created_at)}</td>
                  <td>
                    <strong>{row.id}</strong> · {row.mode}
                    <small>{row.label}</small>
                  </td>
                  <td>{row.accounts || "—"}</td>
                  <td>
                    <span className={`status-pill ${row.status}`}>{row.status}</span>
                  </td>
                </tr>
              ))}
              {historyRows.length === 0 && (
                <tr>
                  <td colSpan={4} className="muted">
                    暂无历史记录
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      ) : (
        <div
          className="data-table-wrap"
          role="region"
          aria-label="审计日志"
          tabIndex={0}
        >
          <table className="data-table">
            <thead>
              <tr>
                <th>时间</th>
                <th>类型</th>
                <th>账号</th>
                <th>详情</th>
              </tr>
            </thead>
            <tbody>
              {auditRows.map((row) => (
                <tr key={row.id}>
                  <td>{formatWhen(row.ts)}</td>
                  <td>{row.kind}</td>
                  <td>{row.account || "—"}</td>
                  <td>{row.detail || "—"}</td>
                </tr>
              ))}
              {auditRows.length === 0 && (
                <tr>
                  <td colSpan={4} className="muted">
                    暂无审计记录
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
      <div className="pager advanced-pager">
        <button
          className="button ghost"
          onClick={() => setOffset(Math.max(0, offset - limit))}
          disabled={page <= 1}
        >
          <ChevronLeft size={14} /> 上一页
        </button>
        <span>
          {page} / {pages} · 共 {total} 条
        </span>
        <button
          className="button ghost"
          onClick={() => setOffset(offset + limit)}
          disabled={page >= pages}
        >
          下一页 <ChevronRight size={14} />
        </button>
      </div>
    </section>
  );
}

function RuntimePanel({
  runtime,
  onRuntimeChange,
}: {
  runtime: RuntimeSettings;
  onRuntimeChange: (settings: RuntimeSettings) => void;
}) {
  const meta = useMeta();
  const presets = meta.data?.speed_presets ?? {};
  const preset = presets[runtime.speed] ?? {};
  return (
    <section className="panel">
      <div className="panel-head">
        <Gauge size={17} />
        <div>
          <h2>运行参数</h2>
          <p>保存在本机浏览器，作为工作台预览与执行的默认值。</p>
        </div>
      </div>
      <div className="form-grid">
        <label className="field">
          <span className="field-label">速度档位</span>
          <select
            value={runtime.speed}
            onChange={(event) =>
              onRuntimeChange({ ...runtime, speed: event.target.value })
            }
          >
            {Object.keys(presets).length ? (
              Object.keys(presets).map((name) => (
                <option key={name} value={name}>
                  {name}
                </option>
              ))
            ) : (
              <option value="eco">eco</option>
            )}
          </select>
        </label>
        <label className="field">
          <span className="field-label">限速范围</span>
          <select
            value={runtime.scope}
            onChange={(event) =>
              onRuntimeChange({ ...runtime, scope: event.target.value })
            }
          >
            <option value="account">账号内限速</option>
            <option value="global">全局限速</option>
          </select>
        </label>
        <label className="field">
          <span className="field-label">最大重试</span>
          <input
            type="number"
            min={0}
            value={runtime.maxRetries}
            onChange={(event) =>
              onRuntimeChange({
                ...runtime,
                maxRetries: Math.max(0, Number(event.target.value) || 0),
              })
            }
          />
        </label>
      </div>
      <p className="form-hint">
        {Object.keys(preset).length
          ? `workers=${preset.workers ?? "—"} · account_workers=${preset.account_workers ?? "—"} · interval=${preset.request_interval ?? "—"}s`
          : "档位参数由后端 meta 提供。"}
      </p>
    </section>
  );
}
