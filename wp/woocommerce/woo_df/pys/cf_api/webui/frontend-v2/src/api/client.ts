const TOKEN_KEY = "cf_token";

export const USE_MOCK = import.meta.env.VITE_USE_MOCK === "true";

export class ApiError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

type RequestOptions = Omit<RequestInit, "body"> & {
  json?: unknown;
  body?: BodyInit | null;
};

function authHeaders(): HeadersInit {
  const token = localStorage.getItem(TOKEN_KEY);
  return token ? { "X-Auth-Token": token } : {};
}

export async function apiRequest<T>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const headers = new Headers(options.headers);
  const token = localStorage.getItem(TOKEN_KEY);
  if (token) headers.set("X-Auth-Token", token);
  let body = options.body ?? null;
  if (options.json !== undefined) {
    headers.set("Content-Type", "application/json");
    body = JSON.stringify(options.json);
  }
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), 30000);
  try {
    const response = await fetch(path, {
      ...options,
      headers,
      body,
      signal: controller.signal,
    });
    if (response.status === 401) {
      throw new ApiError("需要口令：请设置 X-Auth-Token 后重试", 401);
    }
    if (!response.ok) {
      let detail = `HTTP ${response.status}`;
      try {
        const data = (await response.json()) as { detail?: unknown };
        if (data?.detail) {
          detail =
            typeof data.detail === "string"
              ? data.detail
              : JSON.stringify(data.detail);
        }
      } catch {
        // 非 JSON 错误体保留状态码
      }
      throw new ApiError(detail, response.status);
    }
    const contentType = response.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
      return (await response.json()) as T;
    }
    return (await response.text()) as T;
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new ApiError("请求超时（30 秒），请重试", 0);
    }
    throw error;
  } finally {
    window.clearTimeout(timer);
  }
}

export async function apiGet<T>(path: string): Promise<T> {
  return apiRequest<T>(path);
}

export async function apiPost<T>(path: string, json?: unknown): Promise<T> {
  return apiRequest<T>(path, { method: "POST", json });
}

export async function apiPatch<T>(path: string, json?: unknown): Promise<T> {
  return apiRequest<T>(path, { method: "PATCH", json });
}

export async function apiDelete<T>(path: string): Promise<T> {
  return apiRequest<T>(path, { method: "DELETE" });
}

export async function downloadFile(
  path: string,
  filename: string,
): Promise<void> {
  const response = await fetch(path, { headers: authHeaders() });
  if (!response.ok) {
    throw new ApiError(`下载失败：HTTP ${response.status}`, response.status);
  }
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 5000);
}
