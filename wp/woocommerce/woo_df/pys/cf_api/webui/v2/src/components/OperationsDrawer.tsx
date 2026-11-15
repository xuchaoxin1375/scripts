import { Activity, SlidersHorizontal, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { KeyboardEvent, ReactNode } from "react";
import type { InspectorTab } from "../types";

type Props = {
  open: boolean;
  tab: InspectorTab;
  onTab: (tab: InspectorTab) => void;
  onClose: () => void;
  modalOpen: boolean;
  account: string;
  zone: string;
  selectedCount: number;
  runningJobs: number;
  children: ReactNode;
};

const FOCUSABLE =
  'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

function focusableItems(root: HTMLElement): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
    (element) =>
      element.getClientRects().length > 0 &&
      getComputedStyle(element).visibility !== "hidden",
  );
}

export default function OperationsDrawer({
  open,
  tab,
  onTab,
  onClose,
  modalOpen,
  account,
  zone,
  selectedCount,
  runningJobs,
  children,
}: Props) {
  const drawerRef = useRef<HTMLElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const previousRef = useRef<HTMLElement | null>(null);
  const closeCallback = useRef(onClose);
  closeCallback.current = onClose;
  const modalOpenRef = useRef(modalOpen);
  modalOpenRef.current = modalOpen;
  const [overlay, setOverlay] = useState(() =>
    window.matchMedia("(max-width: 1180px)").matches,
  );
  const overlayRef = useRef(overlay);
  overlayRef.current = overlay;

  useEffect(() => {
    const query = window.matchMedia("(max-width: 1180px)");
    const update = () => setOverlay(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);

  useEffect(() => {
    if (!open) return;
    previousRef.current = document.activeElement as HTMLElement | null;
    const timer = window.setTimeout(() => closeRef.current?.focus(), 20);

    function onKeyDown(event: globalThis.KeyboardEvent) {
      if (event.key === "Escape") {
        if (modalOpenRef.current) return;
        event.preventDefault();
        event.stopPropagation();
        closeCallback.current();
        return;
      }
      if (
        event.key !== "Tab" ||
        !overlayRef.current ||
        modalOpenRef.current
      ) {
        return;
      }
      const root = drawerRef.current;
      if (!root) return;
      const items = focusableItems(root);
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
      if (document.querySelector(".modal-backdrop")) return;
      const previous = previousRef.current;
      if (
        previous &&
        previous !== document.body &&
        document.contains(previous) &&
        previous.getClientRects().length > 0
      ) {
        previous.focus();
      } else {
        document.querySelector<HTMLElement>("[data-tasks-button]")?.focus();
      }
    };
  }, [open]);

  useEffect(() => {
    if (!open || !overlay) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previous;
    };
  }, [open, overlay]);

  function handleTabKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    const next: InspectorTab = tab === "action" ? "tasks" : "action";
    onTab(next);
    window.setTimeout(
      () => document.getElementById(`drawer-tab-${next}`)?.focus(),
      0,
    );
  }

  return (
    <>
      <aside
        ref={drawerRef}
        className={`drawer ${open ? "open" : ""}`}
        role={overlay ? "dialog" : "region"}
        aria-modal={overlay && open ? true : undefined}
        aria-labelledby="drawer-title"
        aria-hidden={!open}
        inert={!open}
      >
        <header className="drawer-head">
          <div className="drawer-head-row">
            <div className="drawer-head-copy">
              <h2 id="drawer-title">
                {tab === "tasks" ? "任务与日志" : "批量操作"}
              </h2>
              <p>
                {account || "未选择账号"} / {zone || "未选择域名"} ·{" "}
                {tab === "tasks"
                  ? "预览、执行与失败重跑"
                  : selectedCount > 0
                    ? `已选 ${selectedCount} 条记录`
                    : "勾选记录或直接选择动作"}
              </p>
            </div>
            <button
              type="button"
              className="icon-button"
              ref={closeRef}
              onClick={onClose}
              aria-label="关闭面板"
              data-drawer-initial
            >
              <X size={18} aria-hidden="true" />
            </button>
          </div>
          <div
            className="drawer-tabs"
            role="tablist"
            aria-label="操作与任务"
            onKeyDown={handleTabKeyDown}
          >
            <button
              type="button"
              id="drawer-tab-action"
              role="tab"
              aria-selected={tab === "action"}
              aria-controls="drawer-panel-action"
              tabIndex={tab === "action" ? 0 : -1}
              className={`drawer-tab ${tab === "action" ? "active" : ""}`}
              onClick={() => onTab("action")}
            >
              <SlidersHorizontal size={14} aria-hidden="true" />
              操作
            </button>
            <button
              type="button"
              id="drawer-tab-tasks"
              role="tab"
              aria-selected={tab === "tasks"}
              aria-controls="drawer-panel-tasks"
              tabIndex={tab === "tasks" ? 0 : -1}
              className={`drawer-tab ${tab === "tasks" ? "active" : ""}`}
              onClick={() => onTab("tasks")}
            >
              <Activity size={14} aria-hidden="true" />
              任务
              {runningJobs > 0 && (
                <span className="live-dot" aria-hidden="true" />
              )}
            </button>
          </div>
        </header>

        <div className="drawer-body">{children}</div>
      </aside>

      <button
        type="button"
        className="drawer-backdrop"
        onClick={onClose}
        aria-label="关闭面板遮罩"
        tabIndex={-1}
      />
    </>
  );
}
