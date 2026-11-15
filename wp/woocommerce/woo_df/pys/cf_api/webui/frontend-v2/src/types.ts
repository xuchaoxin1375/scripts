export type ZoneStatus = "active" | "pending" | "moved" | string;

export type Account = {
  name: string;
  email: string;
  auth: string;
  zoneCount?: number;
};

export type Zone = {
  id: string;
  name: string;
  status: ZoneStatus;
};

export type DnsRecord = {
  id: string;
  name: string;
  type: string;
  content: string;
  ttl: number;
  proxied: boolean;
  comment: string;
  priority?: number | null;
};

export type InspectorTab = "action" | "tasks";

export type RecordPatchValues = Omit<DnsRecord, "id">;

export type RecordFilters = {
  search: string;
  type: string;
  proxied: string;
  sort: string;
  page: number;
  perPage: number;
};

export type RecordsPage = {
  items: DnsRecord[];
  total: number;
  page: number;
  perPage: number;
};

export type WhitelistAttachment = {
  path: string;
  count: number;
  domains: string[];
};

export type ResumeAttachment = {
  path: string;
  rows: number;
  zones: string[];
};

export type Attachments = {
  whitelist: WhitelistAttachment | null;
  resume: ResumeAttachment | null;
};

export type RuntimeSettings = {
  speed: string;
  scope: string;
  maxRetries: number;
};

export type ActionMode =
  | "update"
  | "delete_wildcard"
  | "delete_ip"
  | "delete_zone"
  | "add"
  | "set_attrs"
  | "export"
  | "provision";

export type JobStatus = "pending" | "running" | "done" | "failed" | "cancelled";

export type ActionDraft = {
  mode: ActionMode;
  newContent?: string;
  oldContent?: string;
  recordType?: string;
  deleteIp?: string;
  deleteZoneMode?: string;
  backupDir?: string;
  confirm?: string;
  setProxied?: string;
  setTtl?: string;
  addDomain?: string;
  addRecords?: string;
  proxied?: boolean;
  ttl?: number;
  exportDir?: string;
  exportFormat?: string;
  serverIp?: string;
  forwardEmail?: string;
  sslMode?: string;
};

export type Job = {
  id: string;
  mode: string;
  kind: "preview" | "execute";
  status: JobStatus;
  scope: string;
  createdAt: string;
  duration: string;
  progress: number;
  accounts: number;
  zones: number;
  records: number;
  failures: number;
  cancelable: boolean;
  verdict: string;
  causes: string[];
  anomalies: number;
};

export type PreviewRow = {
  id: string;
  name: string;
  type: string;
  oldContent: string;
  newContent: string;
  action: string;
  status?: string;
  message?: string;
  account?: string;
  zone?: string;
};
