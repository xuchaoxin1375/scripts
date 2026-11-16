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
  timeoutMs?: number;
};

type FetchOptions = {
  signal?: AbortSignal;
  timeoutMs?: number;
};

function linkSignal(signal: AbortSignal | undefined): {
  controller: AbortController;
  cleanup: () => void;
} {
  const controller = new AbortController();
  if (!signal) return { controller, cleanup: () => undefined };
  if (signal.aborted) {
    controller.abort();
    return { controller, cleanup: () => undefined };
  }
  const onAbort = () => controller.abort();
  signal.addEventListener("abort", onAbort, { once: true });
  return {
    controller,
    cleanup: () => signal.removeEventListener("abort", onAbort),
  };
}

async function request(
  path: string,
  options: RequestOptions = {},
): Promise<Response> {
  const headers = new Headers(options.headers);
  const token = localStorage.getItem(TOKEN_KEY);
  if (token) headers.set("X-Auth-Token", token);
  let body = options.body ?? null;
  if (options.json !== undefined) {
    headers.set("Content-Type", "application/json");
    body = JSON.stringify(options.json);
  }
  const { controller, cleanup } = linkSignal(options.signal ?? undefined);
  const timeoutMs = options.timeoutMs ?? 30_000;
  const timer =
    timeoutMs > 0 ? window.setTimeout(() => controller.abort(), timeoutMs) : 0;
  const { json: _json, timeoutMs: _timeout, ...init } = options;
  try {
    const response = await fetch(path, {
      ...init,
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
    return response;
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      if (options.signal?.aborted) throw error;
      throw new ApiError(`请求超时（${Math.round(timeoutMs / 1000)} 秒），请重试`, 0);
    }
    throw error;
  } finally {
    if (timer) window.clearTimeout(timer);
    cleanup();
  }
}

export async function apiRequest<T>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const response = await request(path, options);
  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    return (await response.json()) as T;
  }
  return (await response.text()) as T;
}

export async function apiGet<T>(path: string, options: FetchOptions = {}): Promise<T> {
  return apiRequest<T>(path, {
    signal: options.signal,
    timeoutMs: options.timeoutMs,
  });
}

export async function apiPost<T>(
  path: string,
  json?: unknown,
  options: FetchOptions = {},
): Promise<T> {
  return apiRequest<T>(path, {
    method: "POST",
    json,
    signal: options.signal,
    timeoutMs: options.timeoutMs,
  });
}

export async function apiPatch<T>(
  path: string,
  json?: unknown,
  options: FetchOptions = {},
): Promise<T> {
  return apiRequest<T>(path, {
    method: "PATCH",
    json,
    signal: options.signal,
    timeoutMs: options.timeoutMs,
  });
}

export async function apiPut<T>(
  path: string,
  json?: unknown,
  options: FetchOptions = {},
): Promise<T> {
  return apiRequest<T>(path, {
    method: "PUT",
    json,
    signal: options.signal,
    timeoutMs: options.timeoutMs,
  });
}

export async function apiDelete<T>(
  path: string,
  options: FetchOptions = {},
): Promise<T> {
  return apiRequest<T>(path, {
    method: "DELETE",
    signal: options.signal,
    timeoutMs: options.timeoutMs,
  });
}

export async function apiUpload<T>(
  path: string,
  file: File,
  options: FetchOptions = {},
): Promise<T> {
  const form = new FormData();
  form.append("file", file);
  return apiRequest<T>(path, {
    method: "POST",
    body: form,
    signal: options.signal,
    timeoutMs: options.timeoutMs ?? 60_000,
  });
}

function saveBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 5000);
}

export async function downloadFile(
  path: string,
  filename: string,
  options: FetchOptions = {},
): Promise<void> {
  const response = await request(path, {
    signal: options.signal,
    timeoutMs: options.timeoutMs ?? 120_000,
  });
  saveBlob(await response.blob(), filename);
}

export async function downloadPostFile(
  path: string,
  filename: string,
  json: unknown,
  options: FetchOptions = {},
): Promise<void> {
  const response = await request(path, {
    method: "POST",
    json,
    signal: options.signal,
    timeoutMs: options.timeoutMs ?? 120_000,
  });
  saveBlob(await response.blob(), filename);
}
