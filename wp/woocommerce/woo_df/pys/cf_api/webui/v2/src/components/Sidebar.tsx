import { Activity, ListTree, Settings2, X } from "lucide-react";
import { useEffect, useRef } from "react";
import { NavLink } from "react-router-dom";

type Props = {
  mobileOpen: boolean;
  onClose: () => void;
  onTasks: () => void;
  tasksActive: boolean;
  runningJobs: number;
  recordCount?: number;
  configPath?: string;
  proxyCount?: number;
};

const FOCUSABLE =
  'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export default function Sidebar({
  mobileOpen,
  onClose,
  onTasks,
  tasksActive,
  runningJobs,
  recordCount,
  configPath,
  proxyCount,
}: Props) {
  const sidebarRef = useRef<HTMLElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const previousRef = useRef<HTMLElement | null>(null);
  const closeCallback = useRef(onClose);
  closeCallback.current = onClose;

  useEffect(() => {
    if (!mobileOpen) return;
    previousRef.current = document.activeElement as HTMLElement | null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const timer = window.setTimeout(() => closeRef.current?.focus(), 20);

    function focusables(): HTMLElement[] {
      const root = sidebarRef.current;
      if (!root) return [];
      return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
        (element) =>
          element.getClientRects().length > 0 &&
          getComputedStyle(element).visibility !== "hidden",
      );
    }

    function onKeyDown(event: globalThis.KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        closeCallback.current();
        return;
      }
      if (event.key !== "Tab") return;
      const items = focusables();
      if (!items.length) return;
      const first = items[0];
      const last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }

    document.addEventListener("keydown", onKeyDown);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previousOverflow;
      if (document.querySelector(".drawer.open, .modal-backdrop")) return;
      const previous = previousRef.current;
      if (
        previous &&
        previous !== document.body &&
        document.contains(previous) &&
        previous.getClientRects().length > 0
      ) {
        previous.focus();
      }
    };
  }, [mobileOpen]);

  function handleTasks() {
    closeCallback.current();
    onTasks();
  }

  return (
    <>
      <aside
        ref={sidebarRef}
        className="sidebar"
        aria-label="主导航"
        role={mobileOpen ? "dialog" : undefined}
        aria-modal={mobileOpen ? true : undefined}
      >
        <div className="sidebar-mobile-head">
          <span className="brand-mark" aria-hidden="true">
            C
          </span>
          <span className="sidebar-mobile-title">Cloudflare DNS 控制台</span>
          <button
            type="button"
            className="icon-button"
            ref={closeRef}
            onClick={onClose}
            aria-label="关闭导航"
          >
            <X size={18} aria-hidden="true" />
          </button>
        </div>

        <div className="sidebar-inner">
          <nav aria-label="主要导航">
            <div className="nav-group">
              <div className="nav-group-title">工作区</div>
              <NavLink
                to="/"
                end
                className={({ isActive }) =>
                  `nav-link ${isActive ? "active" : ""}`
                }
                aria-label="DNS 记录"
                title="DNS 记录"
                onClick={onClose}
              >
                <ListTree size={18} className="nav-icon" aria-hidden="true" />
                <span className="nav-label">DNS 记录</span>
                {typeof recordCount === "number" && recordCount > 0 && (
                  <span className="nav-badge">{recordCount}</span>
                )}
              </NavLink>
              <NavLink
                to="/advanced"
                className={({ isActive }) =>
                  `nav-link ${isActive ? "active" : ""}`
                }
                aria-label="高级工具"
                title="高级工具"
                onClick={onClose}
              >
                <Settings2 size={18} className="nav-icon" aria-hidden="true" />
                <span className="nav-label">高级工具</span>
              </NavLink>
            </div>

            <div className="nav-group">
              <div className="nav-group-title">任务</div>
              <button
                type="button"
                className={`nav-link ${tasksActive ? "active" : ""}`}
                onClick={handleTasks}
                aria-pressed={tasksActive}
                aria-label="任务与日志"
                title="任务与日志"
              >
                <Activity size={18} className="nav-icon" aria-hidden="true" />
                <span className="nav-label">任务与日志</span>
                {runningJobs > 0 && (
                  <span className="nav-badge">{runningJobs}</span>
                )}
              </button>
            </div>
          </nav>

          <div className="sidebar-footer">
            <span className="sidebar-footer-text">
              <span className="sidebar-config">
                配置{" "}
                <code title={configPath || "当前账号配置"}>
                  {configPath || "—"}
                </code>
              </span>
              <span>代理 {proxyCount ?? 0} · 本机模式</span>
            </span>
          </div>
        </div>
      </aside>

      <button
        type="button"
        className="sidebar-backdrop"
        onClick={onClose}
        aria-label="关闭导航遮罩"
        tabIndex={-1}
      />
    </>
  );
}
