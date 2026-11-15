import type { RuntimeSettings } from "../types";

const RUNTIME_KEY = "cfv2-runtime";

const DEFAULTS: RuntimeSettings = {
  speed: "eco",
  scope: "account",
  maxRetries: 5,
};

export function loadRuntime(): RuntimeSettings {
  try {
    const raw = localStorage.getItem(RUNTIME_KEY);
    if (!raw) return DEFAULTS;
    const parsed = JSON.parse(raw) as Partial<RuntimeSettings>;
    return {
      speed: typeof parsed.speed === "string" ? parsed.speed : DEFAULTS.speed,
      scope: parsed.scope === "global" ? "global" : "account",
      maxRetries:
        typeof parsed.maxRetries === "number" && parsed.maxRetries >= 0
          ? parsed.maxRetries
          : DEFAULTS.maxRetries,
    };
  } catch {
    return DEFAULTS;
  }
}

export function saveRuntime(settings: RuntimeSettings): void {
  try {
    localStorage.setItem(RUNTIME_KEY, JSON.stringify(settings));
  } catch {
    // 隐私模式下 localStorage 可能不可写，保持内存值即可
  }
}
