import { useCallback, useEffect, useMemo, useState } from "react";
import { Route, Routes, useLocation, useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import type {
  ActionDraft,
  Attachments,
  DnsRecord,
  InspectorTab,
  RecordFilters,
  RecordPatchValues,
  RuntimeSettings,
} from "./types";
import { buildJobPayload } from "./shared/actions";
import { loadRuntime, saveRuntime } from "./shared/runtime";
import {
  downloadAnomaliesCsv,
  downloadFailuresCsv,
  downloadRecordsJson,
  useAccounts,
  useBulkDeleteRecords,
  useBulkUpdateRecords,
  useCancelJob,
  useExecuteJob,
  useJob,
  useJobs,
  useMeta,
  usePatchRecord,
  useRecordsPage,
  useRerunJob,
  useSubmitJob,
  useZones,
} from "./api/hooks";
import Topbar from "./components/Topbar";
import Sidebar from "./components/Sidebar";
import ResourceSwitcher from "./components/ResourceSwitcher";
import Workspace from "./pages/Workspace";
import Advanced from "./pages/Advanced";

type Theme = "light" | "dark";

const DEFAULT_FILTERS: RecordFilters = {
  search: "",
  type: "ALL",
  proxied: "all",
  sort: "",
  page: 1,
  perPage: 50,
};

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
  const navigate = useNavigate();
  const location = useLocation();
  const workspaceActive = location.pathname !== "/advanced";
  const [theme, setTheme] = useState<Theme>(() => {
    const saved = localStorage.getItem("cfv2-theme");
    return saved === "dark" ? "dark" : "light";
  });
  const [navOpen, setNavOpen] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [rail, setRail] = useState(() => {
    const saved = localStorage.getItem("cfv2-sidebar-rail");
    return saved === null ? true : saved === "1";
  });
  const [account, setAccount] = useState("");
  const [zone, setZone] = useState("");
  const [pendingZone, setPendingZone] = useState<string | null>(null);
  const [filters, setFilters] = useState<RecordFilters>(DEFAULT_FILTERS);
  const [selected, setSelected] = useState<Map<string, DnsRecord>>(new Map());
  const [inspectorTab, setInspectorTab] = useState<InspectorTab>("action");
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);
  const [attachments, setAttachments] = useState<Attachments>({
    whitelist: null,
    resume: null,
  });
  const [runtime, setRuntime] = useState<RuntimeSettings>(() => loadRuntime());
  const [toast, setToast] = useState<string | null>(null);

  const effectiveFilters = filters;

  const metaQuery = useMeta();
  const accountsQuery = useAccounts();
  const zonesQuery = useZones(account);
  const recordsQuery = useRecordsPage(
    account,
    zone,
    effectiveFilters,
    workspaceActive,
  );
  const jobsQuery = useJobs();
  const jobQuery = useJob(
    selectedJobId,
    drawerOpen && inspectorTab === "tasks",
  );
  const submitJob = useSubmitJob();
  const executeJob = useExecuteJob();
  const rerunJob = useRerunJob();
  const cancelJob = useCancelJob();
  const bulkUpdateRecords = useBulkUpdateRecords();
  const bulkDeleteRecords = useBulkDeleteRecords();
  const patchRecord = usePatchRecord();

  const accounts = accountsQuery.data ?? [];
  const zones = zonesQuery.data ?? [];
  const recordPage = recordsQuery.data ?? {
    items: [] as DnsRecord[],
    total: 0,
    page: effectiveFilters.page,
    perPage: effectiveFilters.perPage,
  };
  const jobs = jobsQuery.data ?? [];
  const selectedIds = useMemo(() => new Set(selected.keys()), [selected]);
  const selectedRecords = useMemo(() => [...selected.values()], [selected]);
  const selectedJob = selectedJobId
    ? jobQuery.data ?? jobs.find((job) => job.id === selectedJobId) ?? null
    : null;

  const accountsError = accountsQuery.error ? messageOf(accountsQuery.error) : null;
  const zonesError = zonesQuery.error ? messageOf(zonesQuery.error) : null;
  const recordsError = recordsQuery.error ? messageOf(recordsQuery.error) : null;
  const jobsError = jobsQuery.error ? messageOf(jobsQuery.error) : null;

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem("cfv2-theme", theme);
  }, [theme]);

  useEffect(() => {
    localStorage.setItem("cfv2-sidebar-rail", rail ? "1" : "0");
  }, [rail]);

  useEffect(() => {
    setNavOpen(false);
    if (!workspaceActive) setDrawerOpen(false);
  }, [location.pathname, workspaceActive]);

  useEffect(() => {
    saveRuntime(runtime);
  }, [runtime]);

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
      setPendingZone(null);
    }
  }, [accounts, account]);

  useEffect(() => {
    if (zones.length === 0) {
      if (zone) setZone("");
      return;
    }
    if (pendingZone && zones.some((item) => item.name === pendingZone)) {
      setZone(pendingZone);
      setPendingZone(null);
      return;
    }
    if (pendingZone) setPendingZone(null);
    if (!zones.some((item) => item.name === zone)) {
      setZone(zones[0].name);
    }
  }, [zones, zone, pendingZone]);

  useEffect(() => {
    setSelected(new Map());
    setFilters(DEFAULT_FILTERS);
    setInspectorTab("action");
    setDrawerOpen(false);
  }, [account, zone]);

  useEffect(() => {
    if (!workspaceActive || !recordsQuery.data) return;
    const maxPage = Math.max(
      1,
      Math.ceil(recordsQuery.data.total / effectiveFilters.perPage),
    );
    if (filters.page > maxPage) {
      setFilters((current) => ({ ...current, page: maxPage }));
    }
  }, [
    workspaceActive,
    recordsQuery.data,
    filters.page,
    effectiveFilters.perPage,
  ]);

  function notify(message: string) {
    setToast(message);
  }

  const updateFilters = useCallback((patch: Partial<RecordFilters>) => {
    setFilters((current) => ({
      ...current,
      ...patch,
      page: patch.page ?? 1,
    }));
  }, []);

  function chooseAccount(name: string) {
    setAccount(name);
    setZone("");
    setPendingZone(null);
    setSelected(new Map());
    setFilters(DEFAULT_FILTERS);
    setNavOpen(false);
    setDrawerOpen(false);
  }

  function chooseZone(name: string) {
    setZone(name);
    setSelected(new Map());
    setFilters(DEFAULT_FILTERS);
    setNavOpen(false);
    setDrawerOpen(false);
  }

  function toggleRecord(record: DnsRecord) {
    setSelected((current) => {
      const next = new Map(current);
      if (next.has(record.id)) next.delete(record.id);
      else next.set(record.id, record);
      return next;
    });
  }

  function toggleAll(items: DnsRecord[]) {
    setSelected((current) => {
      const next = new Map(current);
      const allSelected =
        items.length > 0 && items.every((item) => current.has(item.id));
      if (allSelected) {
        items.forEach((item) => next.delete(item.id));
      } else {
        items.forEach((item) => next.set(item.id, item));
      }
      return next;
    });
  }

  function clearSelection() {
    setSelected(new Map());
  }

  function openDrawer(tab?: InspectorTab) {
    if (tab) setInspectorTab(tab);
    setDrawerOpen(true);
    setNavOpen(false);
  }

  function closeDrawer() {
    setDrawerOpen(false);
  }

  function openTasks() {
    setInspectorTab("tasks");
    setSelectedJobId(null);
    setDrawerOpen(true);
    setNavOpen(false);
    if (!workspaceActive) navigate("/");
  }

  function openScope(nextAccount: string, nextZone: string) {
    if (nextAccount !== account) {
      setAccount(nextAccount);
      setZone("");
      setPendingZone(nextZone);
    } else {
      setZone(nextZone);
      setPendingZone(null);
    }
    setSelected(new Map());
    setFilters(DEFAULT_FILTERS);
    setInspectorTab("action");
    setSelectedJobId(null);
    setNavOpen(false);
    setDrawerOpen(false);
    navigate("/");
  }

  function openJob(jobId: string) {
    setSelectedJobId(jobId);
    setInspectorTab("tasks");
    setDrawerOpen(true);
    setNavOpen(false);
    navigate("/");
  }

  async function handlePreview(draft: ActionDraft): Promise<string | null> {
    try {
      const result = await submitJob.mutateAsync(
        buildJobPayload(draft, account, zone, { attachments, runtime }),
      );
      notify("预览任务已提交：" + result.job_id);
      return result.job_id;
    } catch (error) {
      notify("提交预览失败：" + messageOf(error));
      return null;
    }
  }

  async function handleExecutePreview(jobId: string): Promise<boolean> {
    try {
      const result = await executeJob.mutateAsync(jobId);
      setSelectedJobId(result.job_id);
      setInspectorTab("tasks");
      setDrawerOpen(true);
      notify("已提交执行任务：" + result.job_id);
      return true;
    } catch (error) {
      notify("执行失败：" + messageOf(error));
      return false;
    }
  }

  async function handleRerun(jobId: string) {
    try {
      const result = await rerunJob.mutateAsync({ jobId, failedOnly: true });
      setSelectedJobId(result.job_id);
      setInspectorTab("tasks");
      setDrawerOpen(true);
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
    if (ids.length > 200) {
      notify("单次批量更新至多 200 条，请减少选择");
      return;
    }
    try {
      await bulkUpdateRecords.mutateAsync({ account, zone, ids, proxied });
      notify(`已设置 ${ids.length} 条记录为${proxied ? "已代理" : "仅 DNS"}`);
      clearSelection();
    } catch (error) {
      notify("批量设置失败：" + messageOf(error));
    }
  }

  async function handleBulkContent(
    ids: string[],
    content: string,
  ): Promise<boolean> {
    if (!ids.length) return false;
    if (ids.length > 200) {
      notify("单次批量更新至多 200 条，请减少选择");
      return false;
    }
    try {
      const result = await bulkUpdateRecords.mutateAsync({
        account,
        zone,
        ids,
        content,
      });
      const failed = result.failed?.length ?? 0;
      notify(
        failed
          ? `已更新 ${result.updated?.length ?? 0} 条，失败 ${failed} 条`
          : `已更新 ${result.updated?.length ?? 0} 条记录内容`,
      );
      clearSelection();
      return true;
    } catch (error) {
      notify("批量更新失败：" + messageOf(error));
      return false;
    }
  }

  async function handleBulkDelete(ids: string[]): Promise<boolean> {
    if (!ids.length) return false;
    if (ids.length > 200) {
      notify("单次批量删除至多 200 条，请减少选择");
      return false;
    }
    try {
      const result = await bulkDeleteRecords.mutateAsync({ account, zone, ids });
      const failed = result.failed?.length ?? 0;
      notify(
        failed
          ? `已删除 ${result.deleted?.length ?? 0} 条，失败 ${failed} 条`
          : `已删除 ${result.deleted?.length ?? 0} 条记录`,
      );
      clearSelection();
      return true;
    } catch (error) {
      notify("批量删除失败：" + messageOf(error));
      return false;
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
      setSelected((current) => {
        const next = new Map(current);
        next.delete(recordId);
        return next;
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
      queryClient.invalidateQueries({
        queryKey: ["records", account, zone],
      }),
      queryClient.invalidateQueries({ queryKey: ["zones", account] }),
    ]);
    notify("已刷新当前范围");
  }

  function handleExportRecords() {
    if (!account || !zone) {
      notify("先选择账号与域名");
      return;
    }
    const ids = [...selectedIds];
    downloadRecordsJson({
      account,
      zone,
      ids: ids.length ? ids : undefined,
      type: ids.length ? "ALL" : effectiveFilters.type,
      search: ids.length ? "" : effectiveFilters.search,
      proxied: ids.length ? "all" : effectiveFilters.proxied,
    })
      .then(() =>
        notify(ids.length ? `已导出 ${ids.length} 条选中记录` : "已导出当前筛选范围"),
      )
      .catch((error) => notify("导出失败：" + messageOf(error)));
  }

  const runningJobs = jobs.filter(
    (job) => job.status === "running" || job.status === "pending",
  ).length;
  const zoneStatus = zones.find((item) => item.name === zone)?.status;

  return (
    <div
      className={`app ${rail ? "rail" : ""} ${navOpen ? "nav-open" : ""} ${
        drawerOpen ? "drawer-open" : ""
      } ${selected.size > 0 ? "has-bulk" : ""}`}
    >
      <a
        className="skip-link"
        href="#main"
        onClick={(event) => {
          event.preventDefault();
          document.getElementById("main")?.focus();
        }}
      >
        跳到主要内容
      </a>

      <Topbar
        theme={theme}
        onToggleTheme={() => setTheme(theme === "light" ? "dark" : "light")}
        onMenu={() => {
          setNavOpen((open) => !open);
          setDrawerOpen(false);
        }}
        onRailToggle={() => setRail((value) => !value)}
        rail={rail}
        onTasks={openTasks}
        runningJobs={runningJobs}
        proxyCount={metaQuery.data?.proxy.count}
        resource={
          <ResourceSwitcher
            accounts={accounts}
            zones={zones}
            account={account}
            zone={zone}
            accountsLoading={accountsQuery.isPending}
            zonesLoading={Boolean(account) && zonesQuery.isPending}
            accountsError={accountsError}
            zonesError={zonesError}
            onAccount={chooseAccount}
            onZone={chooseZone}
            onRetryAccounts={() => void accountsQuery.refetch()}
            onRetryZones={() => void zonesQuery.refetch()}
          />
        }
      />

      <Sidebar
        mobileOpen={navOpen}
        onClose={() => setNavOpen(false)}
        onTasks={openTasks}
        tasksActive={drawerOpen && inspectorTab === "tasks"}
        runningJobs={runningJobs}
        recordCount={workspaceActive ? recordPage.total : undefined}
        configPath={metaQuery.data?.config_path}
        proxyCount={metaQuery.data?.proxy.count}
      />

      <main className="main" id="main" tabIndex={-1}>
        <Routes>
          <Route
            path="/"
            element={
              <Workspace
                account={account}
                zone={zone}
                zoneStatus={zoneStatus}
                records={recordPage.items}
                total={recordPage.total}
                page={recordPage.page}
                perPage={recordPage.perPage}
                loading={
                  workspaceActive &&
                  Boolean(account && zone) &&
                  recordsQuery.isPending
                }
                fetching={recordsQuery.isFetching}
                recordsError={recordsError}
                filters={effectiveFilters}
                selectedIds={selectedIds}
                selectedRecords={selectedRecords}
                selectedJob={selectedJob}
                jobs={jobs}
                jobsLoading={jobsQuery.isPending}
                jobsError={jobsError}
                inspectorTab={inspectorTab}
                attachments={attachments}
                defaultBackupDir={metaQuery.data?.dirs.backup_dir ?? ""}
                defaultExportDir={metaQuery.data?.dirs.export_dir ?? ""}
                refreshing={recordsQuery.isFetching || zonesQuery.isFetching}
                drawerOpen={drawerOpen}
                onDrawerOpen={openDrawer}
                onDrawerClose={closeDrawer}
                onTab={setInspectorTab}
                onToggleRecord={toggleRecord}
                onToggleAll={toggleAll}
                onClearSelection={clearSelection}
                onFilters={updateFilters}
                onPage={(page) => updateFilters({ page })}
                onRetryRecords={() => void recordsQuery.refetch()}
                onRetryJobs={() => void jobsQuery.refetch()}
                onSelectJob={(job) => {
                  setSelectedJobId(job?.id ?? null);
                  setInspectorTab("tasks");
                  setDrawerOpen(true);
                }}
                onRefresh={handleRefresh}
                onPreview={handlePreview}
                onExecutePreview={handleExecutePreview}
                onRerun={handleRerun}
                onCancel={handleCancel}
                onDownload={handleDownload}
                onBulkProxy={handleBulkProxy}
                onBulkDelete={handleBulkDelete}
                onBulkContent={handleBulkContent}
                onSaveRecord={handleSaveRecord}
                onExportRecords={handleExportRecords}
                onClearAttachment={(kind) =>
                  setAttachments((current) => ({
                    ...current,
                    [kind]: null,
                  }))
                }
                onNotify={notify}
              />
            }
          />
          <Route
            path="/advanced"
            element={
              <Advanced
                accounts={accounts}
                account={account}
                zone={zone}
                attachments={attachments}
                runtime={runtime}
                onOpenScope={openScope}
                onOpenJob={openJob}
                onAttachmentChange={(kind, value) =>
                  setAttachments((current) => ({
                    ...current,
                    [kind]: value,
                  }))
                }
                onRuntimeChange={setRuntime}
                onNotify={notify}
              />
            }
          />
        </Routes>
      </main>

      {toast && (
        <div className="toast" role="status">
          {toast}
        </div>
      )}
    </div>
  );
}
