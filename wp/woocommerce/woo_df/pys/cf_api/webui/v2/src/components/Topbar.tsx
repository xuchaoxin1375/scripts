import {
  Activity,
  Moon,
  PanelLeft,
  ShieldCheck,
  Sun,
} from "lucide-react";

type Props = {
  theme: "light" | "dark";
  onToggleTheme: () => void;
  onMenu: () => void;
  onTasks: () => void;
  runningJobs: number;
  configPath?: string;
  proxyCount?: number;
};

export default function Topbar({
  theme,
  onToggleTheme,
  onMenu,
  onTasks,
  runningJobs,
  configPath,
  proxyCount,
}: Props) {
  return (
    <header className="topbar">
      <h1 className="sr-only">Cloudflare DNS 控制台</h1>
      <button className="icon-button menu-button" onClick={onMenu} aria-label="打开导航">
        <PanelLeft size={18} />
      </button>
      <div className="brand">
        <span className="brand-mark">C</span>
        <span className="brand-name">Cloudflare DNS 控制台</span>
      </div>
      <span className="config-path" title={configPath || "当前账号配置"}>
        config: {configPath || "—"}
      </span>
      <span className="topbar-spacer" />
      <span className="badge subtle">
        <ShieldCheck size={14} /> 本机模式
      </span>
      <span className="badge subtle">代理 {proxyCount ?? 0}</span>
      <button className="topbar-action" onClick={onTasks}>
        <Activity size={16} />
        任务
        {runningJobs > 0 && <span className="count-badge">{runningJobs}</span>}
      </button>
      <button className="icon-button" onClick={onToggleTheme} aria-label="切换主题">
        {theme === "light" ? <Moon size={17} /> : <Sun size={17} />}
      </button>
    </header>
  );
}
