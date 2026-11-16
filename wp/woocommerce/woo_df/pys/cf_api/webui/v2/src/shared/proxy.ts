export const PROXY_MODES = [
  { value: "round-robin", label: "轮转", hint: "每个请求换一个代理" },
  { value: "sticky", label: "粘性", hint: "每个线程固定一个代理" },
  { value: "failover", label: "故障切换", hint: "优先用第一个，失败后切换" },
] as const;

export const DEFAULT_PROXY_MODE = "round-robin";
export const MAX_PROXIES = 50;

type ParseResult = {
  urls: string[];
  error: string;
};

export function proxyModeLabel(mode: string): string {
  return PROXY_MODES.find((item) => item.value === mode)?.label ?? mode;
}

/** 界面展示用：去掉代理 URL 中的 userinfo，保留 scheme://host:port。 */
export function displayProxyUrl(raw: string): string {
  try {
    const parsed = new URL(raw);
    const host = parsed.hostname.includes(":")
      ? `[${parsed.hostname}]`
      : parsed.hostname;
    return `${parsed.protocol}//${host}${parsed.port ? `:${parsed.port}` : ""}`;
  } catch {
    return raw;
  }
}

export function parseProxyLines(text: string): ParseResult {
  const urls: string[] = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    let parsed: URL;
    try {
      parsed = new URL(line);
    } catch {
      return { urls: [], error: `代理地址格式错误：${line}` };
    }
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return {
        urls: [],
        error: `仅支持 http:// 或 https:// 代理，收到：${line}`,
      };
    }
    if (!parsed.hostname) {
      return { urls: [], error: `代理地址缺少主机名：${line}` };
    }
    urls.push(line);
  }
  const unique = [...new Set(urls)];
  if (!unique.length) {
    return {
      urls: [],
      error: "请至少填一个代理地址；要恢复直连请点“清除代理”。",
    };
  }
  if (unique.length > MAX_PROXIES) {
    return {
      urls: [],
      error: `代理数量最多 ${MAX_PROXIES} 个，当前 ${unique.length} 个。`,
    };
  }
  return { urls: unique, error: "" };
}
