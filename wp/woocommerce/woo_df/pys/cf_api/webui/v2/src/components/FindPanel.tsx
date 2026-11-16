import { useQueryClient } from "@tanstack/react-query";
import {
  AlertTriangle,
  CheckCircle2,
  Clock3,
  Info,
  Loader2,
  Play,
  RotateCcw,
  Search,
  XCircle,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import type { Account, RuntimeSettings } from "../types";
import type { ApiFindScan, ApiFindEvent } from "../api/types";
import { ApiError } from "../api/client";
import {
  useCancelFindScan,
  useContinueFindScan,
  useFindScan,
  useStartFindScan,
} from "../api/hooks";

const SCAN_STORAGE_KEY = "cfv2-find-scan";
const STOP_ON_FIRST_KEY = "cfv2-find-stop-on-first";
const RUNNING = new Set(["pending", "running", "cancelling"]);

const ZONE_STATUS: Record<string, { label: string; tone: string }> = {
  active: { label: "已激活", tone: "done" },
  pending: { label: "待激活", tone: "warning" },
  initializing: { label: "初始化中", tone: "running" },
  moved: { label: "已移出", tone: "failed" },
  deactivated: { label: "已停用", tone: "muted" },
  deleted: { label: "已删除", tone: "muted" },
};

function zoneStatus(status: string) {
  const key = (status || "").toLowerCase();
  return ZONE_STATUS[key] ?? { label: status || "未知", tone: "muted" };
}

function formatElapsed(ms: number): string {
  if (!ms) return "0 秒";
  return ms >= 1000 ? `${(ms / 1000).toFixed(1)} 秒` : `${ms} 毫秒`;
}

function formatTime(value: string): string {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleTimeString("zh-CN", { hour12: false });
}

function errorText(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.status === 404) {
      return "扫描记录已失效（WebUI 服务可能已重启），请重新查找";
    }
    return error.message;
  }
  if (error instanceof TypeError) {
    return "无法连接后端，请确认 WebUI 服务正在运行（可能已停止或重启）";
  }
  if (error instanceof DOMException && error.name === "AbortError") {
    return "请求已取消";
  }
  const message = error instanceof Error ? error.message : String(error);
  return /failed to fetch|networkerror|load failed/i.test(message)
    ? "无法连接后端，请确认 WebUI 服务正在运行（可能已停止或重启）"
    : message;
}

function isScanExpired(error: unknown): boolean {
  return error instanceof ApiError && error.status === 404;
}

function readStoredScan(): string | null {
  try {
    return sessionStorage.getItem(SCAN_STORAGE_KEY);
  } catch {
    return null;
  }
}

function readStopOnFirst(): boolean {
  try {
    return localStorage.getItem(STOP_ON_FIRST_KEY) !== "false";
  } catch {
    return true;
  }
}

function EventIcon({ level }: { level: string }) {
  if (level === "success") return <CheckCircle2 size={13} />;
  if (level === "warning") return <AlertTriangle size={13} />;
  if (level === "error") return <XCircle size={13} />;
  return <Info size={13} />;
}

function SummaryText({ scan }: { scan: ApiFindScan }) {
  if (scan.stopped_early) {
    return (
      <>
        {scan.domain} · 已找到，提前停止：已检查 {scan.checked}/{scan.total}{" "}
        个账号 · 命中 {scan.hits} 个账号 · 未找到 {scan.misses} 个账号
        {scan.failed > 0 ? ` · ${scan.failed} 个读取失败` : ""} ·{" "}
        {scan.unchecked} 个未检查
      </>
    );
  }
  if (scan.status === "failed") {
    return (
      <>
        {scan.domain} · 查询失败：{scan.failed} 个账号均未能读取
      </>
    );
  }
  if (scan.status === "partial") {
    return (
      <>
        {scan.domain} · 已检查 {scan.checked}/{scan.total} 个账号 · 命中{" "}
        {scan.hits} 个账号 · 未找到 {scan.misses} 个账号 · {scan.failed}{" "}
        个读取失败
      </>
    );
  }
  if (scan.status === "cancelled") {
    return (
      <>
        {scan.domain} · 已取消：已检查 {scan.checked}/{scan.total} · 命中{" "}
        {scan.hits} 个账号 · 未找到 {scan.misses} 个账号 ·{" "}
        {scan.unchecked} 个未检查
      </>
    );
  }
  if (scan.status === "done") {
    return (
      <>
        {scan.domain} · 已检查 {scan.checked}/{scan.total} 个账号 · 命中{" "}
        {scan.hits} 个账号 · 未找到 {scan.misses} 个账号
      </>
    );
  }
  if (scan.status === "cancelling") {
    return (
      <>
        {scan.domain} · 正在取消：已检查 {scan.checked}/{scan.total} 个账号
      </>
    );
  }
  return (
    <>
      {scan.domain} · 正在检查 {scan.checked}/{scan.total} 个账号 · 命中{" "}
      {scan.hits} 个账号 · 未找到 {scan.misses} 个账号
    </>
  );
}

export default function FindPanel({
  accounts,
  runtime,
  onOpenScope,
  onNotify,
}: {
  accounts: Account[];
  runtime: RuntimeSettings;
  onOpenScope: (account: string, zone: string) => void;
  onNotify: (message: string) => void;
}) {
  const [domain, setDomain] = useState("");
  const [scanId, setScanId] = useState<string | null>(readStoredScan);
  const [stopOnFirst, setStopOnFirst] = useState(readStopOnFirst);
  const [error, setError] = useState("");
  const [scanExpired, setScanExpired] = useState(false);
  const queryClient = useQueryClient();
  const startScan = useStartFindScan();
  const cancelScan = useCancelFindScan();
  const continueScan = useContinueFindScan();
  const scanQuery = useFindScan(scanId);
  const scan =
    scanQuery.data ??
    (startScan.data?.scan_id === scanId ? startScan.data : null);
  const running = Boolean(scan && RUNNING.has(scan.status) && !scanExpired);
  const busy =
    startScan.isPending ||
    running ||
    cancelScan.isPending ||
    continueScan.isPending;
  const percent = useMemo(() => {
    if (!scan || scan.total <= 0) return 0;
    return Math.min(100, Math.round((scan.checked / scan.total) * 100));
  }, [scan]);
  const final = Boolean(
    scan && ["done", "partial", "failed", "cancelled"].includes(scan.status),
  );
  const barPercent = final ? 100 : percent;
  const progressTone = scan
    ? scan.stopped_early
      ? "stopped"
      : scan.status === "cancelled"
        ? "cancelled"
        : scan.status === "failed"
          ? "failed"
          : scan.status === "partial"
            ? "partial"
            : scan.status === "done"
              ? "done"
              : ""
    : "";
  const progressLabel = scan
    ? scan.stopped_early
      ? "提前停止"
      : scan.status === "cancelled"
        ? "已取消"
        : scan.status === "failed"
          ? "失败"
          : scan.status === "partial"
            ? "已完成（部分失败）"
            : scan.status === "done"
              ? "100%"
              : `${percent}%`
    : "0%";

  function markScanExpired() {
    try {
      sessionStorage.removeItem(SCAN_STORAGE_KEY);
    } catch {
      // 本机浏览器禁用 sessionStorage 时不影响页面提示。
    }
    setScanExpired(true);
    setError("");
  }

  useEffect(() => {
    if (!scanId || !isScanExpired(scanQuery.error)) return;
    // 服务重启后内存中的扫描已丢失：保留最后一次进度供查看，
    // 但清掉本地记录，避免刷新后再次请求失效 ID。
    markScanExpired();
  }, [scanId, scanQuery.error]);

  useEffect(() => {
    try {
      if (scanId) sessionStorage.setItem(SCAN_STORAGE_KEY, scanId);
      else sessionStorage.removeItem(SCAN_STORAGE_KEY);
    } catch {
      // 本机浏览器禁用 sessionStorage 时不影响扫描本身。
    }
  }, [scanId]);

  useEffect(() => {
    try {
      localStorage.setItem(STOP_ON_FIRST_KEY, String(stopOnFirst));
    } catch {
      // 偏好保存失败不影响本次扫描。
    }
  }, [stopOnFirst]);

  async function submit() {
    if (busy) return;
    const target = domain.trim();
    if (!target) {
      setError("请输入域名，例如 example.com");
      return;
    }
    setError("");
    setScanExpired(false);
    try {
      const data = await startScan.mutateAsync({
        domain: target,
        speed: runtime.speed,
        max_retries: runtime.maxRetries,
        stop_on_first: stopOnFirst,
      });
      queryClient.setQueryData(["find-scan", data.scan_id], data);
      setScanId(data.scan_id);
      onNotify(`开始扫描 ${data.total} 个账号`);
    } catch (err) {
      setError(errorText(err));
    }
  }

  async function cancel() {
    if (!scanId) return;
    setError("");
    try {
      const data = await cancelScan.mutateAsync(scanId);
      queryClient.setQueryData(["find-scan", scanId], data);
      onNotify("已请求取消扫描");
    } catch (err) {
      if (isScanExpired(err)) markScanExpired();
      else setError(errorText(err));
    }
  }

  async function continueScanNow() {
    if (!scanId || !scan || scan.unchecked <= 0) return;
    setError("");
    try {
      const data = await continueScan.mutateAsync(scanId);
      queryClient.setQueryData(["find-scan", scanId], data);
      onNotify(`继续查询剩余 ${scan.unchecked} 个账号`);
    } catch (err) {
      if (isScanExpired(err)) markScanExpired();
      else setError(errorText(err));
    }
  }

  function reset() {
    if (busy) return;
    setScanId(null);
    setScanExpired(false);
    setError("");
  }

  return (
    <section className="panel wide find-panel">
      <div className="panel-head">
        <Search size={17} />
        <div>
          <h2>查找域名</h2>
          <p>
            输入 Cloudflare zone 名（根域名），扫描全部 {accounts.length}{" "}
            个账号；使用运行参数 {runtime.speed} 的账号并发与重试次数。
          </p>
        </div>
      </div>
      <div className="inline-form">
        <input
          value={domain}
          onChange={(event) => setDomain(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter" && !busy) {
              event.preventDefault();
              void submit();
            }
          }}
          placeholder="example.com"
          aria-label="要查找的域名"
          aria-describedby="find-domain-hint"
          disabled={busy}
        />
        <button
          className="button primary"
          onClick={() => void submit()}
          disabled={busy}
        >
          {startScan.isPending || running ? (
            <>
              <Loader2 size={15} className="spin" /> 查找中
            </>
          ) : (
            <>
              <Search size={15} /> 查找
            </>
          )}
        </button>
        {running && (
          <button
            className="button ghost"
            onClick={() => void cancel()}
            disabled={cancelScan.isPending || scan?.status === "cancelling"}
          >
            {cancelScan.isPending || scan?.status === "cancelling"
              ? "取消中…"
              : "取消"}
          </button>
        )}
      </div>
      <div className="find-options">
        <label className="checkbox-line">
          <input
            type="checkbox"
            checked={stopOnFirst}
            onChange={(event) => setStopOnFirst(event.target.checked)}
            disabled={busy}
          />
          找到第一个就停止（推荐）
        </label>
        <span className="form-hint">
          {stopOnFirst
            ? "命中一个账号后停止；剩余账号显示为未检查。"
            : "扫描全部账号；结果更完整，耗时更长。"}
        </span>
      </div>
      <p id="find-domain-hint" className="form-hint">
        填根域名，不要填子域名；扫描只检查 zone 是否存在，不读取 DNS
        记录，记录数在打开工作台后查看。
      </p>
      {error && <div className="error-inline">{error}</div>}
      {scanExpired && (
        <div className="inline-warning">
          {scan
            ? "上次扫描记录已失效（WebUI 服务可能已重启）。下方保留最后一次进度，可重新查找。"
            : "上次扫描记录已失效（WebUI 服务可能已重启），请重新查找。"}
          <button className="link-button" onClick={reset}>
            重新查找
          </button>
        </div>
      )}
      {scanId && scanQuery.isError && !isScanExpired(scanQuery.error) && (
        <div className="error-inline">
          读取扫描进度失败：{errorText(scanQuery.error)}
          <button
            className="link-button"
            onClick={() => void scanQuery.refetch()}
          >
            重试
          </button>
          <button className="link-button" onClick={reset}>
            清除
          </button>
        </div>
      )}
      {accounts.length === 0 && (
        <div className="inline-warning">
          当前没有可用账号。先检查账号配置文件，再回来扫描。
        </div>
      )}

      {scan && (
        <>
          <div className="scan-progress" aria-live="polite">
            <div className="scan-progress-head">
              <span>
                <SummaryText scan={scan} />
              </span>
              <span>{progressLabel}</span>
            </div>
            <div
              className={`progress-track ${progressTone}`}
              role="progressbar"
              aria-label="扫描进度"
              aria-valuemin={0}
              aria-valuemax={scan.total}
              aria-valuenow={scan.checked}
              aria-valuetext={`${progressLabel}，已检查 ${scan.checked}/${scan.total} 个账号`}
            >
              <span style={{ width: `${barPercent}%` }} />
            </div>
            <div className="scan-counts">
              <span>
                <strong>{scan.checked}</strong> / {scan.total} 已检查
              </span>
              <span className="ok">
                <strong>{scan.hits}</strong> 命中
              </span>
              <span>
                <strong>{scan.misses}</strong> 未找到
              </span>
              {scan.failed > 0 && (
                <span className="bad">
                  <strong>{scan.failed}</strong> 失败
                </span>
              )}
              {scan.unchecked > 0 && (
                <span className="muted">
                  <strong>{scan.unchecked}</strong> 未检查
                </span>
              )}
              <span className="muted">
                <Clock3 size={12} /> 本次 {formatElapsed(scan.elapsed_ms)}
              </span>
            </div>
            {running && scan.in_flight.length > 0 && (
              <p className="form-hint">
                正在检查：{scan.in_flight.join("、")}
                {scan.in_flight.length >= 4 ? " …" : ""}
              </p>
            )}
          </div>

          {scan.results.length > 0 && (
            <div
              className="data-table-wrap"
              role="region"
              aria-label="跨账号查找结果"
              tabIndex={0}
            >
              <table className="data-table">
                <thead>
                  <tr>
                    <th scope="col">账号</th>
                    <th scope="col">域名</th>
                    <th scope="col">状态</th>
                    <th scope="col">耗时</th>
                    <th scope="col">操作</th>
                  </tr>
                </thead>
                <tbody>
                  {scan.results.map((item) => {
                    const state = zoneStatus(item.status);
                    return (
                      <tr key={`${item.account}-${item.zone_id || item.zone}`}>
                        <td>{item.account}</td>
                        <td>{item.zone || scan.domain}</td>
                        <td>
                          <span className={`status-pill ${state.tone}`}>
                            {state.label}
                          </span>
                        </td>
                        <td>{formatElapsed(item.elapsed_ms)}</td>
                        <td>
                          <button
                            className="button ghost"
                            aria-label={`在 ${item.account} 的 ${
                              item.zone || scan.domain
                            } 工作台打开`}
                            onClick={() =>
                              onOpenScope(
                                item.account,
                                item.zone || scan.domain,
                              )
                            }
                          >
                            在工作台打开
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          {final && scan.results.length === 0 && (
            <div
              className={
                scan.status === "failed"
                  ? "find-empty find-empty-error"
                  : "find-empty"
              }
            >
              {scan.status === "failed" ? (
                <>
                  <strong>查询失败：所有账号都未能读取。</strong>
                  <span>
                    这不能判定为“域名不存在”。请检查网络/代理、账号 Token 的
                    Zone:Read 权限后重试。
                  </span>
                </>
              ) : scan.status === "cancelled" ? (
                <>
                  <strong>扫描已取消。</strong>
                  <span>
                    已检查 {scan.checked}/{scan.total} 个账号，结果不完整；可重新扫描。
                  </span>
                </>
              ) : scan.failed > 0 ? (
                <>
                  <strong>未找到，但结果不完整。</strong>
                  <span>
                    {scan.failed} 个账号读取失败；先处理失败账号，再重新扫描。
                  </span>
                </>
              ) : (
                <>
                  <strong>未找到 {scan.domain}。</strong>
                  <span>
                    确认它是 Cloudflare zone 名（根域名），并确认账号 Token 具备
                    Zone:Read 权限；子域名不能直接匹配根 zone。
                  </span>
                </>
              )}
            </div>
          )}

          {scan.errors.length > 0 && (
            <div className="inline-warning find-warning">
              <strong>{scan.errors.length} 个账号读取失败</strong>
              <span>
                这些账号没有被判定为“未找到”，命中结果可能不完整。
              </span>
              <details className="find-details">
                <summary>查看失败账号</summary>
                <ul className="scan-error-list">
                  {scan.errors.map((item) => (
                    <li key={item.account}>
                      <strong>{item.account}</strong>
                      <span>{item.error}</span>
                    </li>
                  ))}
                </ul>
              </details>
            </div>
          )}

          {final && scan.missed_accounts.length > 0 && (
            <details className="find-details">
              <summary>
                未找到的账号（{scan.missed_accounts.length}）
              </summary>
              <div className="chip-row">
                {scan.missed_accounts.slice(0, 200).map((account) => (
                  <span className="step-chip" key={account}>
                    {account}
                  </span>
                ))}
              </div>
            </details>
          )}

          {final && scan.unchecked_accounts.length > 0 && (
            <details className="find-details">
              <summary>
                未检查的账号（{scan.unchecked_accounts.length}）
              </summary>
              <div className="chip-row">
                {scan.unchecked_accounts.slice(0, 200).map((account) => (
                  <span className="step-chip" key={account}>
                    {account}
                  </span>
                ))}
              </div>
            </details>
          )}

          {scan.events.length > 0 && (
            <details className="find-details">
              <summary>扫描记录（{scan.events.length}）</summary>
              <ol className="scan-events">
                {scan.events.map((event: ApiFindEvent, index) => (
                  <li
                    className={`scan-event ${event.level}`}
                    key={`${event.ts}-${index}`}
                  >
                    <span className="scan-event-icon">
                      <EventIcon level={event.level} />
                    </span>
                    <time>{formatTime(event.ts)}</time>
                    {event.account && (
                      <span className="step-chip">{event.account}</span>
                    )}
                    <span>{event.message}</span>
                  </li>
                ))}
              </ol>
            </details>
          )}

          {final && !scanExpired && (
            <div className="button-row">
              {scan.unchecked > 0 && (
                <button
                  className="button primary"
                  onClick={() => void continueScanNow()}
                  disabled={continueScan.isPending}
                  title="扫描剩余账号，直到全部完成"
                >
                  <Play size={14} />
                  {continueScan.isPending
                    ? "提交中…"
                    : `继续查询剩余 ${scan.unchecked} 个账号`}
                </button>
              )}
              <button
                className="button ghost"
                onClick={reset}
                disabled={continueScan.isPending}
              >
                <RotateCcw size={14} /> 重新扫描
              </button>
            </div>
          )}
        </>
      )}
    </section>
  );
}
