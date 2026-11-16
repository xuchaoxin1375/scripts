import { AlertTriangle, X } from "lucide-react";
import { useRef, useState } from "react";
import type { FormEvent } from "react";
import type { DnsRecord, RecordCreateValues, RecordPatchValues } from "../types";
import { shortName } from "../shared/names";
import { useDialogFocus } from "../shared/useDialogFocus";

const PROXIABLE = new Set(["A", "AAAA", "CNAME"]);
const RECORD_TYPES = ["A", "AAAA", "CNAME", "TXT", "MX"];

type FieldErrors = {
  name?: string;
  content?: string;
  ttl?: string;
  priority?: string;
};

function FieldError({ id, message }: { id: string; message?: string }) {
  if (!message) return null;
  return (
    <span className="field-error" id={id}>
      {message}
    </span>
  );
}

function describedBy(
  hintId: string,
  errorId: string,
  hasError: boolean,
): string | undefined {
  return [hintId, hasError ? errorId : null].filter(Boolean).join(" ") || undefined;
}

export function RecordEditDialog({
  record,
  zone,
  onClose,
  onSave,
}: {
  record: DnsRecord;
  zone: string;
  onClose: () => void;
  onSave: (recordId: string, patch: RecordPatchValues) => Promise<boolean>;
}) {
  const [name, setName] = useState(shortName(record.name, zone));
  const [type, setType] = useState(record.type);
  const [content, setContent] = useState(record.content);
  const [proxied, setProxied] = useState(record.proxied);
  const [ttl, setTtl] = useState(String(record.ttl || 1));
  const [comment, setComment] = useState(record.comment || "");
  const [priority, setPriority] = useState(
    record.priority == null ? "" : String(record.priority),
  );
  const [errors, setErrors] = useState<FieldErrors>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const busyRef = useRef(false);
  busyRef.current = busy;

  const proxiable = PROXIABLE.has(type);
  const typeOptions = RECORD_TYPES.includes(type)
    ? RECORD_TYPES
    : [type, ...RECORD_TYPES];
  const showSuffix =
    Boolean(zone) && name.trim() !== "@" && !name.trim().includes(".");

  function closeIfIdle() {
    if (!busyRef.current) onClose();
  }
  const dialogRef = useDialogFocus(closeIfIdle);

  function changeType(nextType: string) {
    setType(nextType);
    if (!PROXIABLE.has(nextType)) setProxied(false);
  }

  function changeProxied(checked: boolean) {
    setProxied(checked);
    if (checked) setTtl("1");
  }

  function updateName(value: string) {
    setName(value);
    if (errors.name) setErrors((current) => ({ ...current, name: undefined }));
  }

  function updateContent(value: string) {
    setContent(value);
    if (errors.content) {
      setErrors((current) => ({ ...current, content: undefined }));
    }
  }

  function updateTtl(value: string) {
    setTtl(value);
    if (errors.ttl) setErrors((current) => ({ ...current, ttl: undefined }));
  }

  function updatePriority(value: string) {
    setPriority(value);
    if (errors.priority) {
      setErrors((current) => ({ ...current, priority: undefined }));
    }
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busyRef.current) return;
    const nextErrors: FieldErrors = {};
    const trimmedName = name.trim();
    const trimmedContent = content.trim();
    const ttlValue = Number(ttl);
    const priorityValue = type === "MX" ? Number(priority) : null;

    if (!trimmedName) nextErrors.name = "请输入记录名称";
    else if (trimmedName.includes(":")) nextErrors.name = "名称不能包含冒号";
    if (!trimmedContent) nextErrors.content = "请输入记录内容";
    if (!proxiable || !proxied) {
      if (!Number.isFinite(ttlValue) || ttlValue < 1) {
        nextErrors.ttl = "TTL 必须是大于 0 的整数";
      }
    }
    if (
      type === "MX" &&
      (priority.trim() === "" ||
        !Number.isFinite(priorityValue) ||
        (priorityValue ?? 0) < 0 ||
        (priorityValue ?? 0) > 65535)
    ) {
      nextErrors.priority = "优先级需在 0–65535";
    }

    setErrors(nextErrors);
    if (Object.keys(nextErrors).length > 0) {
      const firstId = nextErrors.name
        ? "edit-record-name"
        : nextErrors.content
          ? "edit-record-content"
          : nextErrors.ttl
            ? "edit-record-ttl"
            : "edit-record-priority";
      document.getElementById(firstId)?.focus();
      return;
    }

    setBusy(true);
    busyRef.current = true;
    setError("");
    const ok = await onSave(record.id, {
      name: trimmedName,
      type,
      content: trimmedContent,
      proxied: proxiable ? proxied : false,
      ttl: proxiable && proxied ? 1 : ttlValue,
      comment: comment.trim(),
      priority: type === "MX" ? priorityValue : null,
    });
    setBusy(false);
    busyRef.current = false;
    if (ok) {
      onClose();
    } else {
      setError("保存失败，请查看提示后重试");
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onClick={closeIfIdle}>
      <div
        className="modal record-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="edit-record-title"
        ref={dialogRef}
        onClick={(event) => event.stopPropagation()}
      >
        <header className="modal-head">
          <div className="modal-head-copy">
            <h2 id="edit-record-title">编辑记录</h2>
            <p className="modal-subtitle">
              {record.type} · {record.name}
            </p>
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

        <form className="modal-form" onSubmit={submit} noValidate>
          <div className="modal-body">
            <div className="form-grid">
              <div className="field">
                <label htmlFor="edit-record-type">类型</label>
                <select
                  id="edit-record-type"
                  value={type}
                  onChange={(event) => changeType(event.target.value)}
                >
                  {typeOptions.map((item) => (
                    <option key={item} value={item}>
                      {item}
                    </option>
                  ))}
                </select>
              </div>
              <div className={`field ${errors.name ? "invalid" : ""}`}>
                <label htmlFor="edit-record-name">名称</label>
                <div className="input-group">
                  <input
                    id="edit-record-name"
                    value={name}
                    onChange={(event) => updateName(event.target.value)}
                    data-dialog-initial
                    autoComplete="off"
                    spellCheck={false}
                    aria-invalid={Boolean(errors.name)}
                    aria-describedby={describedBy(
                      "edit-record-name-hint",
                      "edit-record-name-error",
                      Boolean(errors.name),
                    )}
                  />
                  {showSuffix && <span className="suffix">.{zone}</span>}
                </div>
                <span className="field-hint" id="edit-record-name-hint">
                  短名自动补全当前域名；@ 表示根域名。
                </span>
                <FieldError
                  id="edit-record-name-error"
                  message={errors.name}
                />
              </div>
            </div>

            <div className={`field ${errors.content ? "invalid" : ""}`}>
              <label htmlFor="edit-record-content">内容</label>
              <input
                id="edit-record-content"
                value={content}
                onChange={(event) => updateContent(event.target.value)}
                autoComplete="off"
                spellCheck={false}
                aria-invalid={Boolean(errors.content)}
                aria-describedby={
                  errors.content ? "edit-record-content-error" : undefined
                }
              />
              <FieldError
                id="edit-record-content-error"
                message={errors.content}
              />
            </div>

            <label className="switch-row">
              <span className="switch-copy">
                <strong>通过 Cloudflare 代理</strong>
                <small>
                  {proxiable
                    ? "A / AAAA / CNAME 可用；开启后 TTL 固定自动"
                    : `${type} 记录不可代理`}
                </small>
              </span>
              <span className="switch">
                <input
                  type="checkbox"
                  checked={proxiable && proxied}
                  disabled={!proxiable}
                  onChange={(event) => changeProxied(event.target.checked)}
                  aria-label="通过 Cloudflare 代理"
                />
                <span aria-hidden="true" />
              </span>
            </label>

            <div className="form-grid">
              <div className={`field ${errors.ttl ? "invalid" : ""}`}>
                <label htmlFor="edit-record-ttl">TTL</label>
                <input
                  id="edit-record-ttl"
                  type="number"
                  min={1}
                  value={proxiable && proxied ? "1" : ttl}
                  disabled={proxiable && proxied}
                  onChange={(event) => updateTtl(event.target.value)}
                  aria-invalid={Boolean(errors.ttl)}
                  aria-describedby={describedBy(
                    "edit-record-ttl-hint",
                    "edit-record-ttl-error",
                    Boolean(errors.ttl),
                  )}
                />
                <span className="field-hint" id="edit-record-ttl-hint">
                  {proxiable && proxied
                    ? "代理开启时固定自动"
                    : "1 = 自动；其余为秒"}
                </span>
                <FieldError id="edit-record-ttl-error" message={errors.ttl} />
              </div>
              {type === "MX" && (
                <div className={`field ${errors.priority ? "invalid" : ""}`}>
                  <label htmlFor="edit-record-priority">优先级</label>
                  <input
                    id="edit-record-priority"
                    type="number"
                    min={0}
                    max={65535}
                    value={priority}
                    onChange={(event) => updatePriority(event.target.value)}
                    aria-invalid={Boolean(errors.priority)}
                    aria-describedby={describedBy(
                      "edit-record-priority-hint",
                      "edit-record-priority-error",
                      Boolean(errors.priority),
                    )}
                  />
                  <span
                    className="field-hint"
                    id="edit-record-priority-hint"
                  >
                    0–65535
                  </span>
                  <FieldError
                    id="edit-record-priority-error"
                    message={errors.priority}
                  />
                </div>
              )}
            </div>

            <div className="field">
              <label htmlFor="edit-record-comment">备注</label>
              <input
                id="edit-record-comment"
                value={comment}
                maxLength={100}
                onChange={(event) => setComment(event.target.value)}
              />
              <span className="field-hint">{comment.length}/100</span>
            </div>

            <div className="inline-warning">
              <AlertTriangle size={16} aria-hidden="true" />
              <span>
                保存会直接 PATCH 当前记录；名称、内容、代理、TTL、备注与 MX
                优先级按字段写入。
              </span>
            </div>
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
            <button type="submit" className="button primary" disabled={busy}>
              {busy ? "保存中…" : "保存记录"}
            </button>
          </footer>
        </form>
      </div>
    </div>
  );
}

export function AddRecordDialog({
  zone,
  onClose,
  onSave,
}: {
  zone: string;
  onClose: () => void;
  onSave: (values: RecordCreateValues) => Promise<boolean>;
}) {
  const [type, setType] = useState("A");
  const [name, setName] = useState("");
  const [content, setContent] = useState("");
  const [proxied, setProxied] = useState(true);
  const [ttl, setTtl] = useState("1");
  const [comment, setComment] = useState("");
  const [priority, setPriority] = useState("");
  const [errors, setErrors] = useState<FieldErrors>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const busyRef = useRef(false);
  busyRef.current = busy;

  const proxiable = PROXIABLE.has(type);
  const showSuffix =
    Boolean(zone) && name.trim() !== "@" && !name.trim().includes(".");
  const contentPlaceholder =
    type === "A"
      ? "203.0.113.10"
      : type === "AAAA"
        ? "2001:db8::10"
        : type === "CNAME"
          ? "target.example.net"
          : type === "MX"
            ? "mail.example.net"
            : "v=spf1 include:_spf.example.net ~all";

  function closeIfIdle() {
    if (!busyRef.current) onClose();
  }
  const dialogRef = useDialogFocus(closeIfIdle);

  function changeType(nextType: string) {
    setType(nextType);
    if (!PROXIABLE.has(nextType)) setProxied(false);
  }

  function changeProxied(checked: boolean) {
    setProxied(checked);
    if (checked) setTtl("1");
  }

  function updateName(value: string) {
    setName(value);
    if (errors.name) setErrors((current) => ({ ...current, name: undefined }));
  }

  function updateContent(value: string) {
    setContent(value);
    if (errors.content) {
      setErrors((current) => ({ ...current, content: undefined }));
    }
  }

  function updateTtl(value: string) {
    setTtl(value);
    if (errors.ttl) setErrors((current) => ({ ...current, ttl: undefined }));
  }

  function updatePriority(value: string) {
    setPriority(value);
    if (errors.priority) {
      setErrors((current) => ({ ...current, priority: undefined }));
    }
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busyRef.current) return;
    const nextErrors: FieldErrors = {};
    const trimmedName = name.trim();
    const trimmedContent = content.trim();
    const ttlValue = Number(ttl);
    const priorityValue = type === "MX" ? Number(priority) : null;

    if (!trimmedName) nextErrors.name = "请输入记录名称";
    else if (trimmedName.includes(":")) nextErrors.name = "名称不能包含冒号";
    if (!trimmedContent) nextErrors.content = "请输入记录内容";
    if (!proxiable || !proxied) {
      if (!Number.isFinite(ttlValue) || ttlValue < 1) {
        nextErrors.ttl = "TTL 必须是大于 0 的整数";
      }
    }
    if (
      type === "MX" &&
      (priority.trim() === "" ||
        !Number.isFinite(priorityValue) ||
        (priorityValue ?? 0) < 0 ||
        (priorityValue ?? 0) > 65535)
    ) {
      nextErrors.priority = "优先级需在 0–65535";
    }

    setErrors(nextErrors);
    if (Object.keys(nextErrors).length > 0) {
      const firstId = nextErrors.name
        ? "add-record-name"
        : nextErrors.content
          ? "add-record-content"
          : nextErrors.ttl
            ? "add-record-ttl"
            : "add-record-priority";
      document.getElementById(firstId)?.focus();
      return;
    }

    setBusy(true);
    busyRef.current = true;
    setError("");
    const ok = await onSave({
      name: trimmedName,
      type,
      content: trimmedContent,
      proxied: proxiable ? proxied : false,
      ttl: proxiable && proxied ? 1 : ttlValue,
      comment: comment.trim(),
      priority: type === "MX" ? priorityValue : null,
    });
    setBusy(false);
    busyRef.current = false;
    if (ok) {
      onClose();
    } else {
      setError("保存失败，请查看提示后重试");
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onClick={closeIfIdle}>
      <div
        className="modal record-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="add-record-title"
        ref={dialogRef}
        onClick={(event) => event.stopPropagation()}
      >
        <header className="modal-head">
          <div className="modal-head-copy">
            <h2 id="add-record-title">新增记录</h2>
            <p className="modal-subtitle">{zone || "未选择域名"} · 直接写入</p>
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

        <form className="modal-form" onSubmit={submit} noValidate>
          <div className="modal-body">
            <div className="form-grid">
              <div className="field">
                <label htmlFor="add-record-type">类型</label>
                <select
                  id="add-record-type"
                  value={type}
                  onChange={(event) => changeType(event.target.value)}
                >
                  {RECORD_TYPES.map((item) => (
                    <option key={item} value={item}>
                      {item}
                    </option>
                  ))}
                </select>
              </div>
              <div className={`field ${errors.name ? "invalid" : ""}`}>
                <label htmlFor="add-record-name">名称</label>
                <div className="input-group">
                  <input
                    id="add-record-name"
                    value={name}
                    onChange={(event) => updateName(event.target.value)}
                    placeholder="www"
                    data-dialog-initial
                    autoComplete="off"
                    spellCheck={false}
                    aria-invalid={Boolean(errors.name)}
                    aria-describedby={describedBy(
                      "add-record-name-hint",
                      "add-record-name-error",
                      Boolean(errors.name),
                    )}
                  />
                  {showSuffix && <span className="suffix">.{zone}</span>}
                </div>
                <span className="field-hint" id="add-record-name-hint">
                  短名自动补全当前域名；@ 表示根域名。
                </span>
                <FieldError id="add-record-name-error" message={errors.name} />
              </div>
            </div>

            <div className={`field ${errors.content ? "invalid" : ""}`}>
              <label htmlFor="add-record-content">内容</label>
              <input
                id="add-record-content"
                value={content}
                onChange={(event) => updateContent(event.target.value)}
                placeholder={contentPlaceholder}
                autoComplete="off"
                spellCheck={false}
                aria-invalid={Boolean(errors.content)}
                aria-describedby={
                  errors.content ? "add-record-content-error" : undefined
                }
              />
              <FieldError
                id="add-record-content-error"
                message={errors.content}
              />
            </div>

            <label className="switch-row">
              <span className="switch-copy">
                <strong>通过 Cloudflare 代理</strong>
                <small>
                  {proxiable
                    ? "A / AAAA / CNAME 可用；开启后 TTL 固定自动"
                    : `${type} 记录不可代理`}
                </small>
              </span>
              <span className="switch">
                <input
                  type="checkbox"
                  checked={proxiable && proxied}
                  disabled={!proxiable}
                  onChange={(event) => changeProxied(event.target.checked)}
                  aria-label="通过 Cloudflare 代理"
                />
                <span aria-hidden="true" />
              </span>
            </label>

            <div className="form-grid">
              <div className={`field ${errors.ttl ? "invalid" : ""}`}>
                <label htmlFor="add-record-ttl">TTL</label>
                <input
                  id="add-record-ttl"
                  type="number"
                  min={1}
                  value={proxiable && proxied ? "1" : ttl}
                  disabled={proxiable && proxied}
                  onChange={(event) => updateTtl(event.target.value)}
                  aria-invalid={Boolean(errors.ttl)}
                  aria-describedby={describedBy(
                    "add-record-ttl-hint",
                    "add-record-ttl-error",
                    Boolean(errors.ttl),
                  )}
                />
                <span className="field-hint" id="add-record-ttl-hint">
                  {proxiable && proxied
                    ? "代理开启时固定自动"
                    : "1 = 自动；其余为秒"}
                </span>
                <FieldError id="add-record-ttl-error" message={errors.ttl} />
              </div>
              {type === "MX" && (
                <div className={`field ${errors.priority ? "invalid" : ""}`}>
                  <label htmlFor="add-record-priority">优先级</label>
                  <input
                    id="add-record-priority"
                    type="number"
                    min={0}
                    max={65535}
                    value={priority}
                    onChange={(event) => updatePriority(event.target.value)}
                    aria-invalid={Boolean(errors.priority)}
                    aria-describedby={describedBy(
                      "add-record-priority-hint",
                      "add-record-priority-error",
                      Boolean(errors.priority),
                    )}
                  />
                  <span
                    className="field-hint"
                    id="add-record-priority-hint"
                  >
                    0–65535
                  </span>
                  <FieldError
                    id="add-record-priority-error"
                    message={errors.priority}
                  />
                </div>
              )}
            </div>

            <div className="field">
              <label htmlFor="add-record-comment">备注</label>
              <input
                id="add-record-comment"
                value={comment}
                maxLength={100}
                onChange={(event) => setComment(event.target.value)}
              />
              <span className="field-hint">{comment.length}/100</span>
            </div>

            <div className="inline-warning">
              <AlertTriangle size={16} aria-hidden="true" />
              <span>
                保存会直接写入 Cloudflare，不再生成预览任务。需要先预览或一次加多条时，用右侧批量抽屉的“添加域名或记录”（等同命令行
                dry-run）。
              </span>
            </div>
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
            <button type="submit" className="button primary" disabled={busy}>
              {busy ? "保存中…" : "保存记录"}
            </button>
          </footer>
        </form>
      </div>
    </div>
  );
}
