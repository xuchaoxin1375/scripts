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

export type JobSubmitPayload = Record<string, unknown>;
