import type {
  ActionDraft,
  Attachments,
  RuntimeSettings,
} from "../types";

type BuildOptions = {
  attachments?: Attachments;
  runtime?: RuntimeSettings;
};

function basePayload(
  draft: ActionDraft,
  account: string,
  zone: string,
  options: BuildOptions,
): Record<string, unknown> {
  const runtime = options.runtime ?? {
    speed: "eco",
    scope: "account",
    maxRetries: 5,
  };
  const whitelistFile = options.attachments?.whitelist?.path ?? null;
  const resumeCsv = options.attachments?.resume?.path ?? null;
  return {
    accounts: [account],
    domains: [zone],
    dry_run: true,
    mode: draft.mode,
    record_type: draft.recordType || "auto",
    speed: runtime.speed,
    scope: runtime.scope,
    max_retries: runtime.maxRetries,
    ...(whitelistFile ? { whitelist_file: whitelistFile } : {}),
    ...(resumeCsv ? { resume_csv: resumeCsv } : {}),
  };
}

export function buildJobPayload(
  draft: ActionDraft,
  account: string,
  zone: string,
  options: BuildOptions = {},
): Record<string, unknown> {
  const base = basePayload(draft, account, zone, options);
  if (draft.mode === "update") {
    return {
      ...base,
      new_content: draft.newContent?.trim() || null,
      old_content: draft.oldContent?.trim() || null,
    };
  }
  if (draft.mode === "delete_wildcard") {
    return base;
  }
  if (draft.mode === "delete_ip") {
    return {
      ...base,
      delete_ip: draft.deleteIp?.trim() || null,
    };
  }
  if (draft.mode === "delete_zone") {
    return {
      ...base,
      delete_zone_mode: draft.deleteZoneMode || "dns",
      backup_dir: draft.backupDir?.trim() || null,
      confirm: draft.confirm?.trim() || null,
    };
  }
  if (draft.mode === "set_attrs") {
    return {
      ...base,
      set_proxied:
        draft.setProxied === "on"
          ? "on"
          : draft.setProxied === "off"
            ? "off"
            : null,
      set_ttl: draft.setTtl ? Number(draft.setTtl) : null,
    };
  }
  if (draft.mode === "add") {
    return {
      ...base,
      domains: draft.addDomain?.trim() ? [] : [zone],
      add_domain: draft.addDomain?.trim() || null,
      add_records: (draft.addRecords || "")
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean),
      proxied: draft.proxied ?? true,
      ttl: draft.ttl ?? 1,
    };
  }
  if (draft.mode === "export") {
    return {
      ...base,
      export_dir: draft.exportDir?.trim() || null,
      export_fmt: draft.exportFormat || "json",
    };
  }
  if (draft.mode === "provision") {
    return {
      ...base,
      server_ip: draft.serverIp?.trim() || "",
      forward_email: draft.forwardEmail?.trim() || "",
      ssl_mode: draft.sslMode || "",
    };
  }
  return base;
}
