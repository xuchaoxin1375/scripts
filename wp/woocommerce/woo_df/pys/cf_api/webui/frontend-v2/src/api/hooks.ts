import {
  keepPreviousData,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import type {
  Account,
  DnsRecord,
  Job,
  PreviewRow,
  RecordFilters,
  RecordsPage,
  Zone,
} from "../types";
import {
  accounts as mockAccounts,
  jobs as mockJobs,
  recordsForZone,
  zonesByAccount,
} from "../data/mock";
import {
  apiGet,
  apiPatch,
  apiPost,
  apiUpload,
  downloadFile,
  downloadPostFile,
  USE_MOCK,
} from "./client";
import type {
  ApiAccount,
  ApiAuditRow,
  ApiBulkResult,
  ApiFindResponse,
  ApiHistoryRow,
  ApiImportItem,
  ApiImportResult,
  ApiJob,
  ApiJobExports,
  ApiJobLogs,
  ApiJobResult,
  ApiMeta,
  ApiPage,
  ApiPageResult,
  ApiRecord,
  ApiResumeUpload,
  ApiWhitelistUpload,
  ApiZone,
  JobSubmitPayload,
} from "./types";

const ZONE_MAX_ITEMS = 3000;

function mapAccount(item: ApiAccount): Account {
  return {
    name: item.name,
    email: item.email,
    auth: item.auth,
  };
}

function mapZone(item: ApiZone): Zone {
  return { id: item.id, name: item.name, status: item.status };
}

function mapRecord(item: ApiRecord): DnsRecord {
  return {
    id: item.id,
    name: item.name,
    type: item.type,
    content: item.content,
    ttl: item.ttl,
    proxied: item.proxied,
    comment: item.comment ?? "",
    priority: item.priority,
  };
}

function mapRecordPage(data: ApiPage<ApiRecord>): RecordsPage {
  return {
    items: (data.items ?? []).map(mapRecord),
    total: data.total ?? 0,
    page: data.page ?? 1,
    perPage: data.per_page ?? 50,
  };
}

function progressOf(api: ApiJob): number {
  const zones = Object.values(api.zone_summary ?? {});
  const total = zones.reduce((sum, item) => sum + item.total, 0);
  const done = zones.reduce((sum, item) => sum + item.done, 0);
  if (total > 0) return Math.min(100, Math.round((done / total) * 100));
  if (api.accounts_total > 0) {
    return Math.min(100, Math.round((api.accounts_done / api.accounts_total) * 100));
  }
  return 0;
}

function durationOf(api: ApiJob): string {
  if (!api.created_at) return "—";
  const start = Date.parse(api.created_at);
  const end = api.finished_at ? Date.parse(api.finished_at) : Date.now();
  if (Number.isNaN(start) || Number.isNaN(end)) return "—";
  const seconds = Math.max(0, Math.round((end - start) / 1000));
  return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}

function scopeText(api: ApiJob): string {
  const domains = api.scope?.domains ?? [];
  if (domains.length > 0) {
    return domains.length > 2
      ? `${domains.slice(0, 2).join(", ")} +${domains.length - 2}`
      : domains.join(", ");
  }
  if (api.scope?.add_domain) return api.scope.add_domain;
  if (api.scope?.delete_ip) return `IP ${api.scope.delete_ip}`;
  const accounts = api.scope?.accounts ?? [];
  return accounts.join(", ") || "—";
}

export function mapJob(api: ApiJob): Job {
  const verdict = (api.verdict ?? []).join("\n").trim();
  const causes = (api.verdict ?? [])
    .filter((line) => line.trim().startsWith("- ["))
    .slice(0, 3);
  return {
    id: api.job_id || api.id,
    mode: api.mode,
    kind: api.kind,
    status: api.status as Job["status"],
    scope: scopeText(api),
    createdAt: api.created_at
      ? new Date(api.created_at).toLocaleTimeString("zh-CN", {
          hour: "2-digit",
          minute: "2-digit",
        })
      : "—",
    duration: durationOf(api),
    progress: progressOf(api),
    accounts: api.accounts_total,
    zones: Object.values(api.zone_summary ?? {}).reduce(
      (sum, item) => sum + item.total,
      0,
    ),
    records: api.result_count,
    failures: api.failure_count,
    cancelable: api.status === "pending" || api.status === "running",
    verdict:
      verdict ||
      (api.status === "running" || api.status === "pending"
        ? "任务正在执行…"
        : api.error || "—"),
    causes,
    anomalies: api.anomaly_count ?? 0,
  };
}

function actionOfResult(api: ApiJobResult, mode: string): string {
  const status = (api.status || "").toLowerCase();
  if (status.includes("delete") || status.includes("clear")) return "删除";
  if (status.includes("add") || status.includes("create")) return "新增";
  if (
    status.includes("update") ||
    status.includes("migrate") ||
    status.includes("merge") ||
    status.includes("replace")
  ) {
    return "更新";
  }
  if (status.includes("export")) return "导出";
  if (mode.startsWith("delete") || mode === "delete_zone") return "删除";
  if (mode === "add") return "新增";
  return "变更";
}

function mapJobResult(api: ApiJobResult, index: number, mode: string): PreviewRow {
  return {
    id: `${api.account}:${api.zone}:${api.name}:${api.type}:${index}`,
    name: api.name || api.zone || "—",
    type: api.type || "ZONE",
    oldContent: api.old ?? "—",
    newContent: api.new ?? "—",
    action: actionOfResult(api, mode),
    status: api.status,
    message: api.message,
    account: api.account,
    zone: api.zone,
  };
}

async function fetchAll<T>(
  path: string,
  params: Record<string, string>,
  signal?: AbortSignal,
): Promise<T[]> {
  let page = 1;
  const items: T[] = [];
  while (items.length < ZONE_MAX_ITEMS) {
    const search = new URLSearchParams({
      ...params,
      page: String(page),
      per_page: "200",
    });
    const data = await apiGet<ApiPage<T>>(`${path}?${search.toString()}`, {
      signal,
    });
    const batch = data.items ?? [];
    items.push(...batch);
    if (items.length >= (data.total ?? 0) || batch.length === 0) break;
    page += 1;
  }
  return items.slice(0, ZONE_MAX_ITEMS);
}

function mockRecordPage(
  zone: string,
  filters: RecordFilters,
): RecordsPage {
  let items = recordsForZone(zone);
  const query = filters.search.trim().toLowerCase();
  if (filters.type !== "ALL") {
    items = items.filter((item) => item.type === filters.type);
  }
  if (filters.proxied === "proxied") {
    items = items.filter((item) => item.proxied);
  } else if (filters.proxied === "dnsonly") {
    items = items.filter((item) => !item.proxied);
  }
  if (query) {
    items = items.filter(
      (item) =>
        item.name.toLowerCase().includes(query) ||
        item.content.toLowerCase().includes(query),
    );
  }
  if (filters.sort) {
    const desc = filters.sort.startsWith("-");
    const key = filters.sort.replace(/^-/, "") as keyof DnsRecord;
    items = [...items].sort((left, right) => {
      const result = String(left[key] ?? "").localeCompare(
        String(right[key] ?? ""),
        "zh-CN",
      );
      return desc ? -result : result;
    });
  }
  const total = items.length;
  const start = (filters.page - 1) * filters.perPage;
  return {
    items: items.slice(start, start + filters.perPage),
    total,
    page: filters.page,
    perPage: filters.perPage,
  };
}

export function useMeta() {
  return useQuery({
    queryKey: ["meta"] as const,
    queryFn: async (): Promise<ApiMeta | null> => {
      if (USE_MOCK) {
        return {
          version: "mock",
          speed_presets: {
            eco: { account_workers: 3, workers: 2, request_interval: 0.5 },
            balanced: { account_workers: 5, workers: 4, request_interval: 0.2 },
            fast: { account_workers: 8, workers: 6, request_interval: 0.1 },
            turbo: { account_workers: 20, workers: 20, request_interval: 0 },
          },
          defaults: {},
          dirs: {
            backup_dir: "C:/Users/Administrator/Desktop/deploy_configs/cf_backup",
            export_dir: "C:/Users/Administrator/Desktop/deploy_configs/cf_export",
          },
          requires_auth: false,
          config_path: "C:/Users/Administrator/Desktop/deploy_configs/cf_config.csv",
          proxy: { mode: "", count: 0 },
        };
      }
      return apiGet<ApiMeta>("/api/v1/meta");
    },
    staleTime: 5 * 60_000,
  });
}

export function useAccounts() {
  return useQuery({
    queryKey: ["accounts"] as const,
    queryFn: async ({ signal }): Promise<Account[]> => {
      if (USE_MOCK) return mockAccounts;
      const data = await apiGet<{ items: ApiAccount[] }>("/api/v1/accounts", {
        signal,
      });
      return (data.items ?? []).map(mapAccount);
    },
    staleTime: 5 * 60_000,
  });
}

export function useZones(account: string) {
  return useQuery({
    queryKey: ["zones", account] as const,
    queryFn: async ({ signal }): Promise<Zone[]> => {
      if (!account) return [];
      if (USE_MOCK) return zonesByAccount[account] ?? [];
      const items = await fetchAll<ApiZone>(
        "/api/v1/zones",
        { account, status: "all" },
        signal,
      );
      return items.map(mapZone);
    },
    enabled: Boolean(account),
    staleTime: 60_000,
  });
}

export function useRecordsPage(
  account: string,
  zone: string,
  filters: RecordFilters,
  enabled: boolean,
) {
  return useQuery({
    queryKey: ["records", account, zone, filters] as const,
    queryFn: async ({ signal }): Promise<RecordsPage> => {
      if (!account || !zone) {
        return { items: [], total: 0, page: 1, perPage: filters.perPage };
      }
      if (USE_MOCK) return mockRecordPage(zone, filters);
      const params = new URLSearchParams({
        account,
        zone,
        type: filters.type,
        search: filters.search,
        proxied: filters.proxied,
        page: String(filters.page),
        per_page: String(filters.perPage),
      });
      if (filters.sort) params.set("sort", filters.sort);
      const data = await apiGet<ApiPage<ApiRecord>>(
        `/api/v1/records?${params.toString()}`,
        { signal },
      );
      return mapRecordPage(data);
    },
    enabled: enabled && Boolean(account && zone),
    staleTime: 15_000,
  });
}

export function useJobs() {
  return useQuery({
    queryKey: ["jobs"] as const,
    queryFn: async ({ signal }): Promise<Job[]> => {
      if (USE_MOCK) return mockJobs;
      const data = await apiGet<{ jobs: ApiJob[] }>("/api/v1/jobs", { signal });
      return (data.jobs ?? []).map(mapJob);
    },
    refetchInterval: (query) => {
      const jobs = query.state.data;
      if (!jobs) return false;
      return jobs.some(
        (job) => job.status === "running" || job.status === "pending",
      )
        ? 3_000
        : 20_000;
    },
    refetchIntervalInBackground: false,
    refetchOnWindowFocus: true,
    staleTime: 3_000,
  });
}

export function useJob(jobId: string | null, enabled = true) {
  return useQuery({
    queryKey: ["job", jobId] as const,
    queryFn: async ({ signal }): Promise<Job | null> => {
      if (!jobId) return null;
      if (USE_MOCK) return mockJobs.find((job) => job.id === jobId) ?? null;
      const data = await apiGet<ApiJob>(`/api/v1/jobs/${jobId}`, { signal });
      return mapJob(data);
    },
    enabled: Boolean(jobId) && enabled,
    refetchInterval: (query) => {
      const data = query.state.data;
      return data && (data.status === "running" || data.status === "pending")
        ? 2_000
        : false;
    },
    refetchIntervalInBackground: false,
    refetchOnWindowFocus: true,
  });
}

export function useJobResults(
  jobId: string | null,
  page: number,
  perPage: number,
  enabled: boolean,
  mode = "",
) {
  return useQuery({
    queryKey: ["job-results", jobId, page, perPage] as const,
    queryFn: async ({ signal }): Promise<{ rows: PreviewRow[]; total: number }> => {
      if (!jobId) return { rows: [], total: 0 };
      if (USE_MOCK) {
        const rows = recordsForZone("example.com")
          .slice((page - 1) * perPage, page * perPage)
          .map((record, index) => ({
            id: `${record.id}-${index}`,
            name: record.name,
            type: record.type,
            oldContent: record.content,
            newContent:
              record.type === "CNAME" ? "origin.example.net" : "198.51.100.77",
            action: "更新",
            status: "dry_run_update",
            message: "预览",
          }));
        return { rows, total: rows.length };
      }
      const data = await apiGet<ApiPage<ApiJobResult>>(
        `/api/v1/jobs/${jobId}/results?page=${page}&per_page=${perPage}`,
        { signal },
      );
      return {
        rows: (data.items ?? []).map((item, index) =>
          mapJobResult(item, index, mode),
        ),
        total: data.total ?? 0,
      };
    },
    enabled: Boolean(jobId) && enabled,
    placeholderData: keepPreviousData,
    staleTime: Infinity,
  });
}

export function useJobLogs(jobId: string | null, live: boolean) {
  return useQuery({
    queryKey: ["job-logs", jobId] as const,
    queryFn: async ({ signal }): Promise<ApiJobLogs> => {
      if (!jobId) return { job_id: "", total: 0, offset: 0, logs: [] };
      if (USE_MOCK) {
        return {
          job_id: jobId,
          total: 3,
          offset: 0,
          logs: [
            `[job] ${jobId} 已创建`,
            "[account] 正在读取 zone…",
            "[progress] 6/10",
          ],
        };
      }
      return apiGet<ApiJobLogs>(`/api/v1/jobs/${jobId}/logs?offset=0&limit=500`, {
        signal,
      });
    },
    enabled: Boolean(jobId),
    refetchInterval: live ? 3_000 : false,
    refetchIntervalInBackground: false,
    staleTime: 1_000,
  });
}

export function useJobExports(jobId: string | null, enabled: boolean) {
  return useQuery({
    queryKey: ["job-exports", jobId] as const,
    queryFn: async ({ signal }): Promise<ApiJobExports> => {
      if (!jobId) return { job_id: "", total: 0, items: [] };
      if (USE_MOCK) {
        return {
          job_id: jobId,
          total: 1,
          items: [{ index: 0, zone: "example.com", path: "example.com.json" }],
        };
      }
      return apiGet<ApiJobExports>(`/api/v1/jobs/${jobId}/exports`, { signal });
    },
    enabled: Boolean(jobId) && enabled,
    staleTime: 10_000,
  });
}

export function useHistory(enabled: boolean, limit = 50, offset = 0) {
  return useQuery({
    queryKey: ["history", limit, offset] as const,
    queryFn: async ({ signal }): Promise<ApiPageResult<ApiHistoryRow>> => {
      if (USE_MOCK) {
        return {
          items: [
            {
              id: "job-9002",
              mode: "update",
              status: "done",
              label: "预览 update x1账号",
              accounts: "cf00",
              exit_code: 0,
              created_at: new Date().toISOString(),
              finished_at: new Date().toISOString(),
            },
          ],
          total: 1,
          limit,
          offset,
        };
      }
      return apiGet<ApiPageResult<ApiHistoryRow>>(
        `/api/v1/history?limit=${limit}&offset=${offset}`,
        { signal },
      );
    },
    enabled,
    staleTime: 30_000,
  });
}

export function useAudit(enabled: boolean, limit = 50, offset = 0) {
  return useQuery({
    queryKey: ["audit", limit, offset] as const,
    queryFn: async ({ signal }): Promise<ApiPageResult<ApiAuditRow>> => {
      if (USE_MOCK) {
        return {
          items: [
            {
              id: 1,
              ts: new Date().toISOString(),
              kind: "bulk_update",
              account: "cf00",
              detail: "example.com 更新 2 条，失败 0 条",
            },
          ],
          total: 1,
          limit,
          offset,
        };
      }
      return apiGet<ApiPageResult<ApiAuditRow>>(
        `/api/v1/audit?limit=${limit}&offset=${offset}`,
        { signal },
      );
    },
    enabled,
    staleTime: 30_000,
  });
}

export function useFindDomain() {
  return useMutation({
    mutationFn: async (domain: string): Promise<ApiFindResponse> => {
      if (USE_MOCK) {
        const target = domain.trim().toLowerCase();
        const results = Object.entries(zonesByAccount)
          .filter(([, zones]) => zones.some((zone) => zone.name === target))
          .map(([account, zones]) => {
            const zone = zones.find((item) => item.name === target)!;
            return {
              account,
              zone: zone.name,
              zone_id: zone.id,
              status: zone.status,
              record_count: recordsForZone(zone.name).length,
            };
          });
        return { domain: target, found: results.length, results };
      }
      return apiGet<ApiFindResponse>(
        `/api/v1/find?domain=${encodeURIComponent(domain.trim())}`,
        { timeoutMs: 120_000 },
      );
    },
  });
}

export function useUploadWhitelist() {
  return useMutation({
    mutationFn: async (file: File): Promise<ApiWhitelistUpload> => {
      if (USE_MOCK) {
        return { path: "mock-whitelist.txt", count: 2, domains: ["example.com", "example.net"] };
      }
      return apiUpload<ApiWhitelistUpload>("/api/v1/whitelist-upload", file);
    },
  });
}

export function useUploadResume() {
  return useMutation({
    mutationFn: async (file: File): Promise<ApiResumeUpload> => {
      if (USE_MOCK) {
        return { path: "mock-resume.csv", rows: 2, zones: ["example.com", "shop.example.net"] };
      }
      return apiUpload<ApiResumeUpload>("/api/v1/resume-upload", file);
    },
  });
}

export function useImportRecords() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (payload: {
      account: string;
      zone: string;
      records: ApiImportItem[];
      dry_run: boolean;
    }): Promise<ApiImportResult> => {
      if (USE_MOCK) {
        return payload.dry_run
          ? { checked: payload.records.length, errors: [], failed: [], total: payload.records.length }
          : {
              added: payload.records.length,
              updated: 0,
              unchanged: 0,
              errors: [],
              failed: [],
              total: payload.records.length,
            };
      }
      return apiPost<ApiImportResult>("/api/v1/records/import", payload, {
        timeoutMs: 120_000,
      });
    },
    onSuccess: (_data, variables) => {
      if (variables.dry_run) return;
      void queryClient.invalidateQueries({
        queryKey: ["records", variables.account, variables.zone],
      });
    },
  });
}

export function useSubmitJob() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (payload: JobSubmitPayload) => {
      if (USE_MOCK) return { job_id: "job-9002" };
      return apiPost<{ job_id: string }>("/api/v1/jobs", payload);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["jobs"] });
    },
  });
}

export function useExecuteJob() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (jobId: string) => {
      if (USE_MOCK) return { job_id: "job-9003" };
      return apiPost<{ job_id: string }>(`/api/v1/jobs/${jobId}/execute`);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["jobs"] });
    },
  });
}

export function useRerunJob() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      jobId,
      failedOnly,
    }: {
      jobId: string;
      failedOnly: boolean;
    }) => {
      if (USE_MOCK) return { job_id: "job-9004" };
      return apiPost<{ job_id: string }>(
        `/api/v1/jobs/${jobId}/rerun?failed_only=${failedOnly ? "true" : "false"}`,
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["jobs"] });
    },
  });
}

export function useCancelJob() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (jobId: string) => {
      if (USE_MOCK) return { cancelled: true };
      return apiPost<{ cancelled: boolean }>(`/api/v1/jobs/${jobId}/cancel`);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["jobs"] });
    },
  });
}

export function useBulkUpdateRecords() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (payload: {
      account: string;
      zone: string;
      ids: string[];
      proxied?: boolean;
      ttl?: number;
      content?: string;
    }) => {
      if (USE_MOCK) {
        return {
          updated: payload.ids,
          failed: [],
          total: payload.ids.length,
        } satisfies ApiBulkResult;
      }
      return apiPost<ApiBulkResult>("/api/v1/records/bulk-update", payload, {
        timeoutMs: 120_000,
      });
    },
    onSuccess: (_data, variables) => {
      void queryClient.invalidateQueries({
        queryKey: ["records", variables.account, variables.zone],
      });
    },
  });
}

export function useBulkDeleteRecords() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (payload: {
      account: string;
      zone: string;
      ids: string[];
    }) => {
      if (USE_MOCK) {
        return {
          deleted: payload.ids.map((id) => ({ id })),
          failed: [],
          total: payload.ids.length,
        } satisfies ApiBulkResult;
      }
      return apiPost<ApiBulkResult>("/api/v1/records/bulk-delete", payload, {
        timeoutMs: 120_000,
      });
    },
    onSuccess: (_data, variables) => {
      void queryClient.invalidateQueries({
        queryKey: ["records", variables.account, variables.zone],
      });
    },
  });
}

export function usePatchRecord() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (payload: {
      account: string;
      zone: string;
      id: string;
      name: string;
      type: string;
      content: string;
      proxied: boolean;
      ttl: number;
      comment: string;
      priority?: number | null;
    }) => {
      if (USE_MOCK) return { status: "updated", message: "已更新" };
      return apiPatch<{ status: string; message: string }>(
        "/api/v1/records",
        payload,
      );
    },
    onSuccess: (_data, variables) => {
      void queryClient.invalidateQueries({
        queryKey: ["records", variables.account, variables.zone],
      });
    },
  });
}

export async function downloadFailuresCsv(jobId: string): Promise<void> {
  if (USE_MOCK) return;
  await downloadFile(
    `/api/v1/jobs/${jobId}/failures.csv`,
    `failures_${jobId}.csv`,
  );
}

export async function downloadAnomaliesCsv(jobId: string): Promise<void> {
  if (USE_MOCK) return;
  await downloadFile(
    `/api/v1/jobs/${jobId}/anomalies.csv`,
    `anomalies_${jobId}.csv`,
  );
}

export async function downloadJobExport(
  jobId: string,
  index: number,
  zone: string,
): Promise<void> {
  if (USE_MOCK) return;
  await downloadFile(
    `/api/v1/jobs/${jobId}/exports/${index}`,
    `export_${jobId}_${zone || index}.json`,
  );
}

export async function downloadZoneCsv(account: string): Promise<void> {
  if (USE_MOCK) return;
  await downloadFile(
    `/api/v1/zones.csv?account=${encodeURIComponent(account)}&status=all`,
    `zones_${account}.csv`,
  );
}

export async function downloadRecordsJson(payload: {
  account: string;
  zone: string;
  ids?: string[];
  type?: string;
  search?: string;
  proxied?: string;
}): Promise<void> {
  if (USE_MOCK) return;
  await downloadPostFile(
    "/api/v1/records/export",
    `records_${payload.zone}.json`,
    {
      account: payload.account,
      zone: payload.zone,
      ids: payload.ids ?? [],
      type: payload.type ?? "ALL",
      search: payload.search ?? "",
      proxied: payload.proxied ?? "all",
    },
  );
}
