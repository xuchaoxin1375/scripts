export type ApiAccount = {
  name: string;
  auth: string;
  email: string;
  secret: string;
  has_secret: boolean;
};

export type ApiZone = {
  id: string;
  name: string;
  status: string;
};

export type ApiRecord = {
  id: string;
  type: string;
  name: string;
  content: string;
  ttl: number;
  proxied: boolean;
  comment: string;
  priority: number | null;
};

export type ApiPage<T> = {
  total: number;
  page: number;
  per_page: number;
  items: T[];
};

export type ApiJobScope = {
  accounts?: string[];
  domains?: string[];
  whitelist_count?: number;
  add_domain?: string | null;
  delete_ip?: string | null;
};

export type ApiJob = {
  job_id: string;
  id: string;
  label: string;
  kind: "preview" | "execute";
  mode: string;
  status: string;
  accounts_done: number;
  accounts_total: number;
  current_account: string;
  account_status: Record<string, string>;
  zone_summary: Record<string, { total: number; done: number }>;
  result_count: number;
  failure_count: number;
  anomaly_count: number;
  dry_run: boolean;
  scope: ApiJobScope;
  exit_code: number | null;
  error: string;
  created_at: string;
  finished_at: string;
  verdict: string[];
};

export type ApiJobResult = {
  account: string;
  zone: string;
  name: string;
  type: string;
  old: string | null;
  new: string | null;
  status: string;
  message: string;
};

export type ApiFailure = {
  account: string;
  zone: string;
  name: string;
  type: string;
  status: string;
  error: string;
};

export type ApiAnomaly = {
  account: string;
  zone: string;
  zone_id: string;
  method: string;
  endpoint: string;
  kind: string;
  http_status: string;
  attempts: number;
  resolved: string;
  error: string;
  timestamp: string;
};

export type ApiMeta = {
  version: string;
  speed_presets: Record<string, Record<string, number>>;
  defaults: Record<string, unknown>;
  dirs: { backup_dir: string; export_dir: string };
  requires_auth: boolean;
  config_path: string;
  proxy: { mode: string; count: number };
};

export type ApiHistoryRow = {
  id: string;
  mode: string;
  status: string;
  label: string;
  accounts: string;
  exit_code: number | null;
  created_at: string;
  finished_at: string;
};

export type ApiAuditRow = {
  id: number;
  ts: string;
  kind: string;
  account: string;
  detail: string;
};

export type ApiPageResult<T> = {
  total: number;
  limit: number;
  offset: number;
  items: T[];
};

export type ApiFindResult = {
  account: string;
  zone?: string;
  zone_id?: string;
  status?: string;
  record_count?: number | string;
  error?: string;
};

export type ApiFindResponse = {
  domain: string;
  found: number;
  results: ApiFindResult[];
};

export type ApiWhitelistUpload = {
  path: string;
  count: number;
  domains: string[];
};

export type ApiResumeUpload = {
  path: string;
  rows: number;
  zones: string[];
};

export type ApiImportItem = {
  name: string;
  type: string;
  content: string;
  proxied?: boolean;
  ttl?: number;
  comment?: string;
  priority?: number | null;
};

export type ApiImportResult = {
  added?: number;
  updated?: number;
  unchanged?: number;
  checked?: number;
  errors: unknown[];
  failed: unknown[];
  total: number;
};

export type ApiBulkResult = {
  updated?: string[];
  deleted?: unknown[];
  failed: unknown[];
  total: number;
};

export type ApiEmailRoutingAddress = {
  id: string;
  email: string;
  verified: boolean;
  created: string;
  modified: string;
};

export type ApiEmailRoutingAddresses = {
  account: string;
  total: number;
  items: ApiEmailRoutingAddress[];
  target?: ApiEmailRoutingAddress | null;
};

export type ApiEmailRoutingCatchAll = {
  enabled: boolean;
  forward_to: string[];
  name: string;
};

export type ApiEmailRoutingRequiredRecord = {
  type: string;
  name: string;
  content: string;
  priority?: number | null;
};

export type ApiEmailRoutingMxRecord = {
  name: string;
  content: string;
  priority?: number | null;
};

export type ApiEmailRoutingStatus = {
  account: string;
  zone: string;
  zone_id: string;
  zone_status: string;
  routing_enabled: boolean;
  catch_all: ApiEmailRoutingCatchAll;
  required_records: ApiEmailRoutingRequiredRecord[];
  mx_records: ApiEmailRoutingMxRecord[];
  non_cloudflare_mx: string[];
  records_error: string;
};

export type ApiEmailRoutingAddressResult = {
  account: string;
  email: string;
  found: boolean;
  verified: boolean;
  created: boolean;
  message: string;
};

export type ApiEmailRoutingCompleteResult = {
  account: string;
  zone: string;
  email: string;
  status: string;
  message: string;
  records: string[];
};

export type ApiJobLogs = {
  job_id: string;
  total: number;
  offset: number;
  logs: string[];
};

export type ApiJobExportItem = {
  index: number;
  zone: string;
  path: string;
};

export type ApiJobExports = {
  job_id: string;
  total: number;
  items: ApiJobExportItem[];
};

export type JobSubmitPayload = Record<string, unknown>;
