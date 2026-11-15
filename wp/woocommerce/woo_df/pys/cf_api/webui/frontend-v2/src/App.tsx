import { useEffect, useMemo, useState } from "react";
import { Route, Routes } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import type { ActionDraft, DnsRecord, InspectorTab, RecordPatchValues } from "./types";
import { buildJobPayload } from "./lib/actions";
import {
  downloadAnomaliesCsv,
  downloadFailuresCsv,
  useAccounts,
  useBulkUpdateRecords,
  useCancelJob,
  useExecuteJob,
  useJob,
  useJobs,
  useMeta,
  usePatchRecord,
  useRecords,
  useRerunJob,
  useSubmitJob,
  useZones,
} from "./api/hooks";
import Topbar from "./components/Topbar";
import Navigator from "./components/Navigator";
import Workspace from "./pages/Workspace";
import Advanced from "./pages/Advanced";

type Theme = "light" | "dark";

function messageOf(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error);
  if (/invalid request headers|invalid format for authorization|6003|6111/i.test(raw)) {
    return "Cloudflare 认证失败：检查 API Token / Global API Key 是否有效，以及 Zone:Read、DNS:Edit 权限";
  }
  if (/401|unauthorized/i.test(raw)) {
    return "未授权：检查 WebUI 口令或账号凭据";
  }
  if (/429|rate limit|限流/i.test(raw)) {
    return "Cloudflare 限流：稍后重试，或在高级页降低速度档位";
  }
  if (/timeout|timed out|超时/i.test(raw)) {
    return "请求超时：检查网络或代理后重试";
  }
  return raw;
}

export default function App() {
  const queryClient = useQueryClient();
  const [theme, setTheme] = useState<Theme>(() => {
    const saved = localStorage.getItem("cfv2-theme");
    return saved === "dark" ? "dark" : "light";
  });
  const [navOpen, setNavOpen] = useState(false);
  const [account, setAccount] = useState("");
  const [zone, setZone] = useState("");
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [inspectorTab, setInspectorTab] = useState<InspectorTab>("action");
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  const metaQuery = useMeta();
  const accountsQuery = useAccounts();
  const zonesQuery = useZones(account);
  const recordsQuery = useRecords(account, zone);
  const jobsQuery = useJobs();
  const jobQuery = useJob(selectedJobId);
  const submitJob = useSubmitJob();
  const executeJob = useExecuteJob();
  const rerunJob = useRerunJob();
  const cancelJob = useCancelJob();
  const bulkUpdateRecords = useBulkUpdateRecords();
  const patchRecord = usePatchRecord();

  const accounts = accountsQuery.data ?? [];
  const zones = zonesQuery.data ?? [];
  const records = recordsQuery.data ?? [];
  const jobs = jobsQuery.data ?? [];
  const selectedJob = selectedJobId
    ? jobQuery.data ?? jobs.find((job) => job.id === selectedJobId) ?? null
    : null;
  const selectedRecords = useMemo(
    () => records.filter((record) => selectedIds.has(record.id)),
    [records, selectedIds],
  );

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem("cfv2-theme", theme);
  }, [theme]);

  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setToast(null), 3600);
    return () => window.clearTimeout(timer);
  }, [toast]);

  useEffect(() => {
    if (accounts.length === 0) return;
    if (!account || !accounts.some((item) => item.name === account)) {
      setAccount(accounts[0].name);
      setZone("");
    }
  }, [accounts, account]);

  useEffect(() => {
    if (zones.length === 0) {
      if (zone) setZone("");
      return;
    }
    if (!zones.some((item) => item.name === zone)) {
      setZone(zones[0].name);
    }
  }, [zones, zone]);

  useEffect(() => {
    setSelectedIds(new Set());
  }, [account, zone]);

  function notify(message: string) {
    setToast(message);
  }

  function chooseAccount(name: string) {
    setAccount(name);
    setZone("");
    setSelectedIds(new Set());
    setNavOpen(false);
  }

  function chooseZone(name: string) {
    setZone(name);
    setSelectedIds(new Set());
    setNavOpen(false);
  }

  function toggleRecord(id: string) {
    setSelectedIds((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleAll(items: DnsRecord[]) {
    setSelectedIds((current) => {
      const allSelected = items.length > 0 && items.every((item) => current.has(item.id));
      return allSelected ? new Set() : new Set(items.map((item) => item.id));
    });
  }

  async function handlePreview(draft: ActionDraft): Promise<string | null> {
    try {
      const result = await submitJob.mutateAsync(buildJobPayload(draft, account, zone));
      notify("预览任务已提交：" + result.job_id);
      return result.job_id;
    } catch (error) {
      notify("提交预览失败：" + messageOf(error));
      return null;
    }
  }

  async function handleExecutePreview(jobId: string) {
    try {
      const result = await executeJob.mutateAsync(jobId);
      setSelectedJobId(result.job_id);
      setInspectorTab("tasks");
      notify("已提交执行任务：" + result.job_id);
    } catch (error) {
      notify("执行失败：" + messageOf(error));
    }
  }

  async function handleRerun(jobId: string) {
    try {
      const result = await rerunJob.mutateAsync({ jobId, failedOnly: true });
      setSelectedJobId(result.job_id);
      setInspectorTab("tasks");
      notify("已提交失败域重跑：" + result.job_id);
    } catch (error) {
      notify("重跑失败：" + messageOf(error));
    }
  }

  async function handleCancel(jobId: string) {
    try {
      await cancelJob.mutateAsync(jobId);
      notify("已请求取消：" + jobId);
    } catch (error) {
      notify("取消失败：" + messageOf(error));
    }
  }

  async function handleDownload(jobId: string, kind: "failures" | "anomalies") {
    try {
      if (kind === "failures") await downloadFailuresCsv(jobId);
      else await downloadAnomaliesCsv(jobId);
      notify(kind === "failures" ? "已下载失败清单" : "已下载请求异常 CSV");
    } catch (error) {
      notify("下载失败：" + messageOf(error));
    }
  }

  async function handleBulkProxy(proxied: boolean) {
    const ids = [...selectedIds];
    if (!ids.length) return;
    try {
      await bulkUpdateRecords.mutateAsync({ account, zone, ids, proxied });
      notify(`已设置 ${ids.length} 条记录为${proxied ? "已代理" : "仅 DNS"}`);
      setSelectedIds(new Set());
    } catch (error) {
      notify("批量设置失败：" + messageOf(error));
    }
  }

  async function handleSaveRecord(
    recordId: string,
    patch: RecordPatchValues,
  ): Promise<boolean> {
    try {
      await patchRecord.mutateAsync({
        account,
        zone,
        id: recordId,
        ...patch,
      });
      notify("记录已保存");
      return true;
    } catch (error) {
      notify("保存失败：" + messageOf(error));
      return false;
    }
  }

  async function handleRefresh() {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["records", account, zone] }),
      queryClient.invalidateQueries({ queryKey: ["zones", account] }),
    ]);
    notify("已刷新当前范围");
  }

  const dataError =
    accountsQuery.error ??
    zonesQuery.error ??
    recordsQuery.error ??
    jobsQuery.error ??
    metaQuery.error;

  return (
    <div className="app">
      <Topbar
        theme={theme}
        onToggleTheme={() => setTheme(theme === "light" ? "dark" : "light")}
        onMenu={() => setNavOpen((open) => !open)}
        onTasks={() => setInspectorTab("tasks")}
        runningJobs={jobs.filter((job) => job.status === "running").length}
        configPath={metaQuery.data?.config_path}
        proxyCount={metaQuery.data?.proxy.count}
      />
      <div className={`shell ${navOpen ? "nav-open" : ""}`}>
        <Navigator
          accounts={accounts}
          zones={zones}
          account={account}
          zone={zone}
          onAccount={chooseAccount}
          onZone={chooseZone}
          onAdvanced={() => setNavOpen(false)}
        />
        {navOpen && (
          <button
            className="nav-backdrop"
            aria-label="关闭导航"
            onClick={() => setNavOpen(false)}
          />
        )}
        <main className="main">
          {dataError && (
            <div className="data-banner" role="alert">
              数据加载失败：{messageOf(dataError)}
            </div>
          )}
          <Routes>
            <Route
              path="/"
              element={
                <Workspace
                  account={account}
                  zone={zone}
                  records={records}
                  selectedIds={selectedIds}
                  selectedRecords={selectedRecords}
                  selectedJob={selectedJob}
                  jobs={jobs}
                  inspectorTab={inspectorTab}
                  loading={recordsQuery.isLoading || zonesQuery.isLoading}
                  onTab={setInspectorTab}
                  onToggleRecord={toggleRecord}
                  onToggleAll={toggleAll}
                  onClearSelection={() => setSelectedIds(new Set())}
                  onSelectJob={(job) => {
                    setSelectedJobId(job?.id ?? null);
                    setInspectorTab("tasks");
                  }}
                  onRefresh={handleRefresh}
                  onPreview={handlePreview}
                  onExecutePreview={handleExecutePreview}
                  onRerun={handleRerun}
                  onCancel={handleCancel}
                  onDownload={handleDownload}
                  onBulkProxy={handleBulkProxy}
                  onSaveRecord={handleSaveRecord}
                  onNotify={notify}
                />
              }
            />
            <Route path="/advanced" element={<Advanced onNotify={notify} />} />
          </Routes>
        </main>
      </div>
      {toast && (
        <div className="toast" role="status">
          {toast}
        </div>
      )}
    </div>
  );
}
