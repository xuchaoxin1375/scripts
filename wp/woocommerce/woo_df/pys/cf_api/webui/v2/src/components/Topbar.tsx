import {
  Activity,
  Menu,
  Moon,
  PanelLeftClose,
  PanelLeftOpen,
  ShieldCheck,
  Sun,
} from "lucide-react";
import type { ReactNode } from "react";
import { Link } from "react-router-dom";

type Props = {
  theme: "light" | "dark";
  onToggleTheme: () => void;
  onMenu: () => void;
  onRailToggle: () => void;
  rail: boolean;
  onTasks: () => void;
  runningJobs: number;
  proxyCount?: number;
  resource: ReactNode;
};

export default function Topbar({
  theme,
  onToggleTheme,
  onMenu,
  onRailToggle,
  rail,
  onTasks,
  runningJobs,
  proxyCount,
  resource,
}: Props) {
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
      <span className="badge subtle proxy-badge">
        <ShieldCheck size={14} aria-hidden="true" />
        代理 {proxyCount ?? 0}
      </span>
      <button
        type="button"
        className="icon-button rail-toggle"
        onClick={onRailToggle}
        aria-label={rail ? "展开侧栏" : "收起侧栏"}
        aria-pressed={rail}
        title={rail ? "展开侧栏" : "收起侧栏"}
      >
        {rail ? (
          <PanelLeftOpen size={18} aria-hidden="true" />
        ) : (
          <PanelLeftClose size={18} aria-hidden="true" />
        )}
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
