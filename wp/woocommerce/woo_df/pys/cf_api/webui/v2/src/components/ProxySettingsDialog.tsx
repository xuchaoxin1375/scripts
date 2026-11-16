import { AlertTriangle, Plus, ShieldCheck, Trash2, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import type {
  ApiProxyInput,
  ApiProxySettings,
  ApiProxyUpdate,
} from "../api/types";
import {
  DEFAULT_PROXY_MODE,
  MAX_PROXIES,
  PROXY_MODES,
  displayProxyUrl,
  parseProxyLines,
  proxyModeLabel,
} from "../shared/proxy";
import { useDialogFocus } from "../shared/useDialogFocus";

type DraftEntry = {
  id?: string;
  /** 新条目保存原始地址；已有条目留空，保存时只传 id 以保留凭据。 */
  url?: string;
  displayUrl: string;
  enabled: boolean;
};

type Props = {
  current?: ApiProxySettings;
  loading: boolean;
  loadError?: string;
  onRetry: () => void;
  onClose: () => void;
  onSave: (payload: ApiProxyUpdate) => Promise<string | null>;
};

function draftFromCurrent(current?: ApiProxySettings): DraftEntry[] {
  return (current?.proxies ?? []).map((item) => ({
    id: item.id,
    displayUrl: item.url,
    enabled: item.enabled,
  }));
}

function draftSignature(
  enabled: boolean,
  mode: string,
  entries: DraftEntry[],
): string {
  return JSON.stringify({
    enabled,
    mode,
    entries: entries.map((entry) => ({
      id: entry.id ?? null,
      url: entry.url ?? null,
      displayUrl: entry.displayUrl,
      enabled: entry.enabled,
    })),
  });
}

export default function ProxySettingsDialog({
  current,
  loading,
  loadError,
  onRetry,
  onClose,
  onSave,
}: Props) {
  const [enabled, setEnabled] = useState(current?.enabled ?? false);
  const [mode, setMode] = useState(current?.mode || DEFAULT_PROXY_MODE);
  const [entries, setEntries] = useState<DraftEntry[]>(() =>
    draftFromCurrent(current),
  );
  const [newUrl, setNewUrl] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [discardArmed, setDiscardArmed] = useState(false);
  const busyRef = useRef(false);
  busyRef.current = busy;
  const hydrated = useRef(Boolean(current));
  const initialSig = useRef(
    current
      ? draftSignature(
          current.enabled,
          current.mode || DEFAULT_PROXY_MODE,
          draftFromCurrent(current),
        )
      : "",
  );

  useEffect(() => {
    if (!current || hydrated.current) return;
    hydrated.current = true;
    const nextEntries = draftFromCurrent(current);
    const nextMode = current.mode || DEFAULT_PROXY_MODE;
    setEnabled(current.enabled);
    setMode(nextMode);
    setEntries(nextEntries);
    initialSig.current = draftSignature(
      current.enabled,
      nextMode,
      nextEntries,
    );
  }, [current]);

  useEffect(() => {
    if (loading) return;
    document.getElementById("proxy-add-url")?.focus();
  }, [loading]);

  const dirty =
    initialSig.current !== "" &&
    draftSignature(enabled, mode, entries) !== initialSig.current;
  const blockedByLoadError = Boolean(loadError) && !current;
  const canEdit = !loading && !blockedByLoadError && !busy;
  const enabledCount = entries.filter((entry) => entry.enabled).length;

  function requestClose() {
    if (busyRef.current) return;
    if (!dirty) {
      onClose();
      return;
    }
    if (discardArmed) {
      onClose();
      return;
    }
    setDiscardArmed(true);
    setError("");
  }

  const dialogRef = useDialogFocus(requestClose);

  function resetDiscard() {
    setDiscardArmed(false);
  }

  function addProxies() {
    if (!canEdit) return;
    const parsed = parseProxyLines(newUrl);
    if (parsed.error) {
      setError(parsed.error);
      document.getElementById("proxy-add-url")?.focus();
      return;
    }
    const known = new Set<string>();
    for (const entry of entries) {
      known.add(entry.displayUrl);
      if (entry.url) known.add(entry.url);
    }
    const additions = parsed.urls.filter(
      (url) => !known.has(url) && !known.has(displayProxyUrl(url)),
    );
    if (!additions.length) {
      setError("这些地址已在列表中");
      return;
    }
    if (entries.length + additions.length > MAX_PROXIES) {
      setError(`代理数量最多 ${MAX_PROXIES} 个`);
      return;
    }
    setEntries((currentEntries) => [
      ...currentEntries,
      ...additions.map((url) => ({
        url,
        displayUrl: displayProxyUrl(url),
        enabled: true,
      })),
    ]);
    setNewUrl("");
    setError("");
    resetDiscard();
    document.getElementById("proxy-add-url")?.focus();
  }

  function toggleEntry(index: number) {
    if (!canEdit) return;
    setEntries((currentEntries) =>
      currentEntries.map((entry, position) =>
        position === index ? { ...entry, enabled: !entry.enabled } : entry,
      ),
    );
    resetDiscard();
  }

  function removeEntry(index: number) {
    if (!canEdit) return;
    setEntries((currentEntries) =>
      currentEntries.filter((_, position) => position !== index),
    );
    setError("");
    resetDiscard();
    document.getElementById("proxy-add-url")?.focus();
  }

  function clearEntries() {
    if (!canEdit) return;
    setEntries([]);
    setEnabled(false);
    setNewUrl("");
    setError("");
    resetDiscard();
    document.getElementById("proxy-add-url")?.focus();
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busyRef.current || !canEdit) return;
    const proxies: ApiProxyInput[] = entries.map((entry) =>
      entry.id
        ? { id: entry.id, enabled: entry.enabled }
        : { url: entry.url ?? "", enabled: entry.enabled },
    );
    if (proxies.some((item) => !item.id && !item.url)) {
      setError("代理地址不完整，请删除后重新添加");
      return;
    }
    setError("");
    setBusy(true);
    busyRef.current = true;
    const failure = await onSave({ enabled, mode, proxies });
    if (failure) {
      setBusy(false);
      busyRef.current = false;
      setError(failure);
    }
  }

  const currentTotal = current?.total ?? 0;
  const currentCount = current?.count ?? 0;
  const currentEnabled = current?.enabled ?? false;
  const currentEnabledCount = current?.enabled_count ?? 0;

  return (
    <div className="modal-backdrop" role="presentation" onClick={requestClose}>
      <div
        className="modal proxy-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="proxy-settings-title"
        ref={dialogRef}
        onClick={(event) => event.stopPropagation()}
      >
        <header className="modal-head">
          <div className="modal-head-copy">
            <h2 id="proxy-settings-title">出口代理</h2>
            <p className="modal-subtitle">
              Cloudflare API 出口链路 · 仅本次运行有效
            </p>
          </div>
          <button
            type="button"
            className="icon-button"
            onClick={requestClose}
            disabled={busy}
            aria-label="关闭代理设置"
          >
            <X size={18} aria-hidden="true" />
          </button>
        </header>

        <form className="modal-form" onSubmit={submit} noValidate>
          <div className="modal-body">
            <div className="proxy-state" aria-live="polite">
              <span
                className={`proxy-state-dot ${currentCount > 0 ? "on" : ""}`}
                aria-hidden="true"
              />
              <div className="proxy-state-copy">
                <strong>
                  {loading
                    ? "正在读取当前代理…"
                    : currentTotal === 0
                      ? "当前直连，未保存代理"
                      : !currentEnabled
                        ? `当前关闭（已保存 ${currentTotal} 个）`
                        : `当前启用 ${currentCount}/${currentTotal} · ${proxyModeLabel(
                            current?.mode || "",
                          )}`}
                </strong>
                {!loading && currentTotal > 0 && currentEnabled && currentCount === 0 && (
                  <span className="field-hint">
                    总开关已开，但没有启用任何代理，请求仍直连。
                  </span>
                )}
                {!loading && currentTotal > 0 && !currentEnabled && (
                  <span className="field-hint">
                    配置已保存；打开下方总开关并保存后才会走代理。
                  </span>
                )}
                {dirty && (
                  <span className="field-hint">
                    下方为未保存修改，点“保存配置”后生效。
                  </span>
                )}
              </div>
            </div>

            {loadError && (
              <div className="inline-warning" role="alert">
                <AlertTriangle size={16} aria-hidden="true" />
                <span>
                  当前代理状态读取失败：{loadError}
                  <button
                    type="button"
                    className="button ghost"
                    onClick={onRetry}
                    disabled={busy}
                  >
                    重试
                  </button>
                </span>
              </div>
            )}

            {error && (
              <div className="inline-warning" role="alert">
                <AlertTriangle size={16} aria-hidden="true" />
                <span>{error}</span>
              </div>
            )}

            {discardArmed && (
              <div className="inline-warning" role="alert">
                <AlertTriangle size={16} aria-hidden="true" />
                <span>
                  有未保存修改；再次关闭或按 Esc 将丢弃。
                  <button
                    type="button"
                    className="button ghost"
                    onClick={resetDiscard}
                  >
                    继续编辑
                  </button>
                </span>
              </div>
            )}

            <label className="switch-row proxy-master">
              <span className="switch-copy">
                <strong>启用出口代理</strong>
                <small>关闭时保留列表与单项开关，但所有请求直连</small>
              </span>
              <span className="switch">
                <input
                  type="checkbox"
                  checked={enabled}
                  disabled={!canEdit}
                  onChange={(event) => {
                    setEnabled(event.target.checked);
                    resetDiscard();
                  }}
                  aria-label="启用出口代理"
                />
                <span aria-hidden="true" />
              </span>
            </label>

            <div className="field">
              <label htmlFor="proxy-mode">调度模式</label>
              <select
                id="proxy-mode"
                value={mode}
                disabled={!canEdit}
                onChange={(event) => {
                  setMode(event.target.value);
                  resetDiscard();
                }}
              >
                {PROXY_MODES.map((item) => (
                  <option key={item.value} value={item.value}>
                    {item.label}（{item.hint}）
                  </option>
                ))}
              </select>
              <span className="field-hint">
                仅启用项参与调度；单项关闭不会删除已保存地址。
              </span>
            </div>

            <div className="proxy-list-head">
              <span>代理列表</span>
              <span>
                {entries.length}/{MAX_PROXIES}
              </span>
            </div>
            {entries.length > 0 ? (
              <ul className="proxy-edit-list">
                {entries.map((entry, index) => (
                  <li className="proxy-edit-item" key={entry.id ?? `new-${index}`}>
                    <label className="switch" title="启用此代理">
                      <input
                        type="checkbox"
                        checked={entry.enabled}
                        disabled={!canEdit}
                        onChange={() => toggleEntry(index)}
                        aria-label={`启用代理 ${entry.displayUrl}`}
                      />
                      <span aria-hidden="true" />
                    </label>
                    <code title={entry.displayUrl}>{entry.displayUrl}</code>
                    <button
                      type="button"
                      className="icon-button"
                      onClick={() => removeEntry(index)}
                      disabled={!canEdit}
                      aria-label={`删除代理 ${entry.displayUrl}`}
                      title="删除此代理"
                    >
                      <Trash2 size={15} aria-hidden="true" />
                    </button>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="proxy-empty">
                还没有保存的代理。添加后保存在当前进程，重启 WebUI 后失效。
              </p>
            )}

            <div className="proxy-add-row">
              <textarea
                id="proxy-add-url"
                rows={2}
                value={newUrl}
                onChange={(event) => {
                  setNewUrl(event.target.value);
                  if (error) setError("");
                }}
                placeholder="http://127.0.0.1:7897"
                spellCheck={false}
                autoComplete="off"
                disabled={!canEdit}
                data-dialog-initial
                aria-label="新增代理地址"
                aria-describedby="proxy-add-hint"
              />
              <button
                type="button"
                className="button"
                onClick={addProxies}
                disabled={!canEdit || !newUrl.trim()}
              >
                <Plus size={14} aria-hidden="true" />
                添加
              </button>
            </div>
            <span className="field-hint" id="proxy-add-hint">
              每行一个，支持 http:// 或 https:// 与 user:pass@host:port；添加后仍可单独开关。已有地址修改需删除后重新添加（凭据不回显）。
            </span>

            {enabled && enabledCount === 0 && (
              <p className="proxy-note">
                <AlertTriangle size={15} aria-hidden="true" />
                <span>
                  总开关已开，但没有任何启用的代理；保存后请求仍直连。
                </span>
              </p>
            )}

            <div className="proxy-note">
              <ShieldCheck size={15} aria-hidden="true" />
              <span>
                代理与凭据只保存在当前进程，不写配置文件；重启 WebUI 后恢复启动参数或直连。保存对之后发起的请求生效，正在运行的任务继续使用原代理。
              </span>
            </div>
          </div>

          <footer className="modal-actions proxy-actions">
            <button
              type="button"
              className="button ghost danger-text"
              onClick={clearEntries}
              disabled={!canEdit || entries.length === 0}
              title="只清空弹窗草稿，仍需点“保存配置”"
            >
              清空列表
            </button>
            <span className="strip-spacer" />
            <span className="proxy-dirty-note" aria-live="polite">
              {dirty ? "有未保存修改" : "无未保存修改"}
            </span>
            <button
              type="button"
              className="button ghost"
              onClick={requestClose}
              disabled={busy}
            >
              {discardArmed ? "放弃并关闭" : "取消"}
            </button>
            <button
              type="submit"
              className="button primary"
              disabled={
                busy || loading || blockedByLoadError || !dirty || !canEdit
              }
            >
              {busy ? "保存中…" : "保存配置"}
            </button>
          </footer>
        </form>
      </div>
    </div>
  );
}
