import {
  Activity,
  ListTree,
  PanelLeftClose,
  PanelLeftOpen,
  Settings2,
  X,
} from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import type {
  FocusEvent,
  MouseEvent as ReactMouseEvent,
  PointerEvent as ReactPointerEvent,
} from "react";
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
  pinned: boolean;
  onPinnedChange: (pinned: boolean) => void;
};

const FOCUSABLE =
  'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

const HOVER_ENTER_DELAY = 110;
const HOVER_LEAVE_DELAY = 220;

function canHover() {
  return window.matchMedia("(hover: hover)").matches;
}

function isDesktopSidebar() {
  return window.matchMedia("(min-width: 1025px)").matches;
}

function isTypingTarget(target: EventTarget | null) {
  const element = target as HTMLElement | null;
  if (!element) return false;
  return (
    element.tagName === "INPUT" ||
    element.tagName === "TEXTAREA" ||
    element.tagName === "SELECT" ||
    element.isContentEditable
  );
}

export default function Sidebar({
  mobileOpen,
  onClose,
  onTasks,
  tasksActive,
  runningJobs,
  recordCount,
  configPath,
  proxyCount,
  pinned,
  onPinnedChange,
}: Props) {
  const sidebarRef = useRef<HTMLElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const collapseRef = useRef<HTMLButtonElement>(null);
  const previousRef = useRef<HTMLElement | null>(null);
  const closeCallback = useRef(onClose);
  closeCallback.current = onClose;

  const [hoverPeek, setHoverPeek] = useState(false);
  const [focusPeek, setFocusPeek] = useState(false);
  const enterTimer = useRef<number | null>(null);
  const leaveTimer = useRef<number | null>(null);
  const focusRearmTimer = useRef<number | null>(null);
  // A manual collapse must not be undone by the pointer still hovering the rail.
  const suppressHover = useRef(false);
  // Esc keeps focus inside the panel without immediately re-opening peek.
  const suppressFocus = useRef(false);
  // A press held inside the rail defers expansion so the row cannot move mid-click.
  const pressHold = useRef(false);

  const peek = (hoverPeek || focusPeek) && !pinned;

  const clearTimers = useCallback(() => {
    if (enterTimer.current !== null) {
      window.clearTimeout(enterTimer.current);
      enterTimer.current = null;
    }
    if (leaveTimer.current !== null) {
      window.clearTimeout(leaveTimer.current);
      leaveTimer.current = null;
    }
    if (focusRearmTimer.current !== null) {
      window.clearTimeout(focusRearmTimer.current);
      focusRearmTimer.current = null;
    }
  }, []);

  useEffect(() => clearTimers, [clearTimers]);

  useEffect(() => {
    if (!pinned) return;
    clearTimers();
    suppressFocus.current = false;
    setHoverPeek(false);
    setFocusPeek(false);
  }, [pinned, clearTimers]);

  const dismissPeek = useCallback(() => {
    clearTimers();
    const active = document.activeElement as HTMLElement | null;
    const inside = Boolean(active && sidebarRef.current?.contains(active));
    suppressFocus.current = inside;
    setHoverPeek(false);
    setFocusPeek(false);
    if (inside) collapseRef.current?.focus();
  }, [clearTimers]);

  const togglePinned = useCallback(() => {
    if (pinned) {
      suppressHover.current = true;
      clearTimers();
      setHoverPeek(false);
      setFocusPeek(false);
      onPinnedChange(false);
      return;
    }
    onPinnedChange(true);
  }, [pinned, clearTimers, onPinnedChange]);

  useEffect(() => {
    if (!peek) return;
    function onKeyDown(event: KeyboardEvent) {
      if (event.key !== "Escape") return;
      if (document.querySelector(".drawer.open, .modal-backdrop")) return;
      event.preventDefault();
      event.stopPropagation();
      dismissPeek();
    }
    document.addEventListener("keydown", onKeyDown, true);
    return () => document.removeEventListener("keydown", onKeyDown, true);
  }, [peek, dismissPeek]);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (
        event.key !== "[" ||
        event.ctrlKey ||
        event.metaKey ||
        event.altKey ||
        isTypingTarget(event.target) ||
        !isDesktopSidebar()
      ) {
        return;
      }
      event.preventDefault();
      togglePinned();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [togglePinned]);

  useEffect(() => {
    function releasePress() {
      pressHold.current = false;
    }
    window.addEventListener("pointerup", releasePress);
    window.addEventListener("pointercancel", releasePress);
    return () => {
      window.removeEventListener("pointerup", releasePress);
      window.removeEventListener("pointercancel", releasePress);
    };
  }, []);

  function handleEnter() {
    if (pinned || !canHover() || suppressHover.current || pressHold.current) return;
    if (enterTimer.current !== null) window.clearTimeout(enterTimer.current);
    if (leaveTimer.current !== null) {
      window.clearTimeout(leaveTimer.current);
      leaveTimer.current = null;
    }
    enterTimer.current = window.setTimeout(() => {
      enterTimer.current = null;
      setHoverPeek(true);
    }, HOVER_ENTER_DELAY);
  }

  function handleLeave() {
    suppressHover.current = false;
    if (enterTimer.current !== null) {
      window.clearTimeout(enterTimer.current);
      enterTimer.current = null;
    }
    if (leaveTimer.current !== null) window.clearTimeout(leaveTimer.current);
    leaveTimer.current = window.setTimeout(() => {
      leaveTimer.current = null;
      setHoverPeek(false);
    }, HOVER_LEAVE_DELAY);
  }

  function handleFocusIn() {
    if (pinned || suppressFocus.current || pressHold.current) return;
    setFocusPeek(true);
  }

  function handleFocusOut(event: FocusEvent<HTMLElement>) {
    const next = event.relatedTarget;
    if (next instanceof Node && sidebarRef.current?.contains(next)) return;
    suppressFocus.current = false;
    setFocusPeek(false);
  }

  function handlePointerDown(event: ReactPointerEvent<HTMLElement>) {
    if (pinned || event.button !== 0) return;
    pressHold.current = true;
    if (enterTimer.current !== null) {
      window.clearTimeout(enterTimer.current);
      enterTimer.current = null;
    }
    if (focusRearmTimer.current !== null) {
      window.clearTimeout(focusRearmTimer.current);
      focusRearmTimer.current = null;
    }
  }

  function handlePointerUp() {
    if (!pressHold.current) return;
    pressHold.current = false;
    if (pinned) return;
    focusRearmTimer.current = window.setTimeout(() => {
      focusRearmTimer.current = null;
      const panel = sidebarRef.current;
      if (!panel?.isConnected) return;
      const active = document.activeElement;
      if (!suppressFocus.current && active && panel.contains(active)) {
        setFocusPeek(true);
      }
    }, 0);
    if (!canHover() || suppressHover.current) return;
    if (enterTimer.current !== null) window.clearTimeout(enterTimer.current);
    if (leaveTimer.current !== null) {
      window.clearTimeout(leaveTimer.current);
      leaveTimer.current = null;
    }
    enterTimer.current = window.setTimeout(() => {
      enterTimer.current = null;
      setHoverPeek(true);
    }, HOVER_ENTER_DELAY);
  }

  const releaseFocusPeekAfterAction = useCallback((pointer: boolean) => {
    if (pinned || !pointer) return;
    // 鼠标点击后只释放焦点维持的展开；hover peek 保留到指针离开。
    suppressFocus.current = true;
    setFocusPeek(false);
  }, [pinned]);

  function handleNavigate(event: ReactMouseEvent<HTMLAnchorElement>) {
    closeCallback.current();
    releaseFocusPeekAfterAction(event.detail > 0);
  }

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

  function handleTasks(event: ReactMouseEvent<HTMLButtonElement>) {
    closeCallback.current();
    releaseFocusPeekAfterAction(event.detail > 0);
    onTasks();
  }

  return (
    <>
      <aside
        ref={sidebarRef}
        className={`sidebar ${peek ? "peek" : ""}`}
        aria-label="主导航"
        data-state={pinned ? "pinned" : peek ? "peek" : "rail"}
        role={mobileOpen ? "dialog" : undefined}
        aria-modal={mobileOpen ? true : undefined}
        onMouseEnter={handleEnter}
        onMouseLeave={handleLeave}
        onFocusCapture={handleFocusIn}
        onBlurCapture={handleFocusOut}
        onPointerDown={handlePointerDown}
        onPointerUp={handlePointerUp}
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
              <NavLink
                to="/"
                end
                className={({ isActive }) =>
                  `nav-link ${isActive ? "active" : ""}`
                }
                aria-label="DNS 记录"
                title="DNS 记录"
                onClick={handleNavigate}
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
                onClick={handleNavigate}
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
            <button
              type="button"
              className="sidebar-collapse"
              ref={collapseRef}
              onClick={togglePinned}
              aria-pressed={pinned}
              aria-label={pinned ? "收起侧栏" : "保持展开"}
              title={pinned ? "收起侧栏（[）" : "保持展开（[）"}
            >
              {pinned ? (
                <PanelLeftClose size={18} aria-hidden="true" />
              ) : (
                <PanelLeftOpen size={18} aria-hidden="true" />
              )}
              <span className="nav-label">
                {pinned ? "收起侧栏" : "保持展开"}
              </span>
              <span className="sidebar-shortcut" aria-hidden="true">
                [
              </span>
            </button>
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
