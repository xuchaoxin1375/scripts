import {
  Activity,
  Menu,
  Moon,
  ShieldCheck,
  Sun,
} from "lucide-react";
import type { ReactNode } from "react";
import { Link } from "react-router-dom";

type Props = {
  theme: "light" | "dark";
  onToggleTheme: () => void;
  onMenu: () => void;
  onTasks: () => void;
  onProxy: () => void;
  runningJobs: number;
  proxyCount?: number;
  proxyTotal?: number;
  proxyEnabled?: boolean;
  resource: ReactNode;
};

export default function Topbar({
  theme,
  onToggleTheme,
  onMenu,
  onTasks,
  onProxy,
  runningJobs,
  proxyCount,
  proxyTotal,
  proxyEnabled,
  resource,
}: Props) {
  const savedProxies = proxyTotal ?? 0;
  const activeProxies = proxyCount ?? 0;
  const proxyLabel =
    proxyEnabled === false && savedProxies > 0
      ? `关(${savedProxies})`
      : savedProxies > 0
        ? `${activeProxies}/${savedProxies}`
        : `${activeProxies}`;
  const proxyTitle =
    proxyEnabled === false && savedProxies > 0
      ? `出口代理已关闭，已保存 ${savedProxies} 个（仅本次运行）`
      : "配置出口代理（仅本次运行）";
  const proxyAria =
    proxyEnabled === false && savedProxies > 0
      ? `出口代理已关闭，已保存 ${savedProxies} 个`
      : `出口代理当前 ${activeProxies} 个启用`;
  return (
    <header className="topbar">
      <button
        type="button"
        className="icon-button menu-button"
        onClick={onMenu}
        aria-label="打开导航"
        title="打开导航"
      >
        <Menu size={18} aria-hidden="true" />
      </button>

      <Link
        className="brand"
        to="/"
        aria-label="Cloudflare DNS 控制台，返回 DNS 记录"
        title="返回 DNS 记录"
      >
        <span className="brand-mark" aria-hidden="true">
          C
        </span>
        <span className="brand-name">Cloudflare DNS 控制台</span>
      </Link>
      <span className="topbar-sep" aria-hidden="true" />
      {resource}

      <span className="topbar-spacer" />

      <span className="env-badge">
        <span className="dot" aria-hidden="true" />
        本机
      </span>
      <button
        type="button"
        className="badge subtle proxy-badge proxy-trigger"
        onClick={onProxy}
        data-proxy-trigger="topbar"
        data-active={Boolean(proxyEnabled && activeProxies > 0)}
        aria-label={`配置${proxyAria}`}
        title={proxyTitle}
      >
        <ShieldCheck size={14} aria-hidden="true" />
        代理 {proxyLabel}
      </button>
      <button
        type="button"
        className="icon-button"
        onClick={onToggleTheme}
        aria-label={
          theme === "light" ? "切换到深色主题" : "切换到浅色主题"
        }
        title={theme === "light" ? "切换到深色主题" : "切换到浅色主题"}
      >
        {theme === "light" ? (
          <Moon size={17} aria-hidden="true" />
        ) : (
          <Sun size={17} aria-hidden="true" />
        )}
      </button>
      <button
        type="button"
        className="icon-button topbar-task"
        onClick={onTasks}
        aria-label={
          runningJobs > 0
            ? `任务与日志，${runningJobs} 个运行中`
            : "任务与日志"
        }
        title="任务与日志"
        data-tasks-button
      >
        <Activity size={17} aria-hidden="true" />
        {runningJobs > 0 && (
          <span className="count-badge" aria-hidden="true">
            {runningJobs}
          </span>
        )}
      </button>
    </header>
  );
}
