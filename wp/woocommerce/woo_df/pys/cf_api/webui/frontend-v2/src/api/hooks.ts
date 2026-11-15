import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { Account, DnsRecord, Job, Zone } from "../types";
import { accounts as mockAccounts, jobs as mockJobs, recordsForZone, zonesByAccount } from "../data/mock";
import {
  apiGet,
  apiPatch,
  apiPost,
  downloadFile,
  USE_MOCK,
} from "./client";
import type {
  ApiAccount,
  ApiJob,
  ApiMeta,
  ApiPage,
  ApiRecord,
  ApiZone,
  JobSubmitPayload,
} from "./types";

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
    return domains.length > 2 ? `${domains.slice(0, 2).join(", ")} +${domains.length - 2}` : domains.join(", ");
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

async function fetchAll<T>(path: string, params: Record<string, string>): Promise<T[]> {
  let page = 1;
  const items: T[] = [];
  while (true) {
    const search = new URLSearchParams({ ...params, page: String(page), per_page: "200" });
    const data = await apiGet<ApiPage<T>>(`${path}?${search.toString()}`);
    items.push(...(data.items ?? []));
    if (items.length >= data.total || (data.items ?? []).length === 0) break;
    page += 1;
  }
  return items;
}

export function useMeta() {
  return useQuery({
    queryKey: ["meta"] as const,
    queryFn: async (): Promise<ApiMeta | null> => {
      if (USE_MOCK) {
        return {
          version: "mock",
          speed_presets: {},
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
    staleTime: 60_000,
  });
}

export function useAccounts() {
  return useQuery({
    queryKey: ["accounts"] as const,
    queryFn: async (): Promise<Account[]> => {
      if (USE_MOCK) return mockAccounts;
      const data = await apiGet<{ items: ApiAccount[] }>("/api/v1/accounts");
      return (data.items ?? []).map(mapAccount);
    },
    staleTime: 60_000,
  });
}

export function useZones(account: string) {
  return useQuery({
    queryKey: ["zones", account] as const,
    queryFn: async (): Promise<Zone[]> => {
      if (!account) return [];
      if (USE_MOCK) return zonesByAccount[account] ?? [];
      const items = await fetchAll<ApiZone>("/api/v1/zones", {
        account,
        status: "all",
      });
      return items.map(mapZone);
    },
    enabled: Boolean(account),
    staleTime: 30_000,
  });
}

export function useRecords(account: string, zone: string) {
  return useQuery({
    queryKey: ["records", account, zone] as const,
    queryFn: async (): Promise<DnsRecord[]> => {
      if (!account || !zone) return [];
      if (USE_MOCK) return recordsForZone(zone);
      const items = await fetchAll<ApiRecord>("/api/v1/records", {
        account,
        zone,
        type: "ALL",
      });
      return items.map(mapRecord);
    },
    enabled: Boolean(account && zone),
    staleTime: 10_000,
  });
}

export function useJobs() {
  return useQuery({
    queryKey: ["jobs"] as const,
    queryFn: async (): Promise<Job[]> => {
      if (USE_MOCK) return mockJobs;
      const data = await apiGet<{ jobs: ApiJob[] }>("/api/v1/jobs");
      return (data.jobs ?? []).map(mapJob);
    },
    refetchInterval: 4_000,
  });
}

export function useJob(jobId: string | null) {
  return useQuery({
    queryKey: ["job", jobId] as const,
    queryFn: async (): Promise<Job | null> => {
      if (!jobId) return null;
      if (USE_MOCK) return mockJobs.find((job) => job.id === jobId) ?? null;
      const data = await apiGet<ApiJob>(`/api/v1/jobs/${jobId}`);
      return mapJob(data);
    },
    enabled: Boolean(jobId),
    refetchInterval: (query) => {
      const data = query.state.data;
      return data && (data.status === "running" || data.status === "pending")
        ? 2_000
        : false;
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
      if (USE_MOCK) return { job_id: "job-mock-execute" };
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
    mutationFn: async ({ jobId, failedOnly }: { jobId: string; failedOnly: boolean }) => {
      if (USE_MOCK) return { job_id: "job-mock-rerun" };
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
    }) => {
      if (USE_MOCK) return { updated: payload.ids, failed: [] };
      return apiPost<{ updated: string[]; failed: unknown[] }>(
        "/api/v1/records/bulk-update",
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
  await downloadFile(`/api/v1/jobs/${jobId}/failures.csv`, `failures_${jobId}.csv`);
}

export async function downloadAnomaliesCsv(jobId: string): Promise<void> {
  if (USE_MOCK) return;
  await downloadFile(`/api/v1/jobs/${jobId}/anomalies.csv`, `anomalies_${jobId}.csv`);
}
