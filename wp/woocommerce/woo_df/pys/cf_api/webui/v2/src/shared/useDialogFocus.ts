import { useEffect, useRef } from "react";

const FOCUSABLE =
  'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

function focusableItems(root: HTMLElement): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
    (element) =>
      element.getClientRects().length > 0 &&
      getComputedStyle(element).visibility !== "hidden",
  );
}

function restoreFocus(previous: HTMLElement | null) {
  if (
    previous &&
    previous !== document.body &&
    document.contains(previous) &&
    previous.getClientRects().length > 0
  ) {
    previous.focus();
    return;
  }
  document.querySelector<HTMLElement>("[data-focus-fallback]")?.focus();
}

/**
 * 模态弹窗的焦点、Esc 与滚动锁。返回绑到弹窗根节点的 ref。
 * 首焦优先 [data-dialog-initial]；关闭后回到触发按钮，触发器已消失时回退到列表。
 */
export function useDialogFocus(onClose: () => void) {
  const ref = useRef<HTMLDivElement>(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;

  useEffect(() => {
    const root = ref.current;
    if (!root) return;
    const previous = document.activeElement as HTMLElement | null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    const initial =
      root.querySelector<HTMLElement>("[data-dialog-initial]") ??
      focusableItems(root)[0];
    initial?.focus();

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        closeRef.current();
        return;
      }
      if (event.key !== "Tab") return;
      const items = focusableItems(root!);
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

    root.addEventListener("keydown", onKeyDown);
    return () => {
      root.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previousOverflow;
      restoreFocus(previous);
    };
  }, []);

  return ref;
}
