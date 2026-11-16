import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type KeyboardEvent,
  type PointerEvent as ReactPointerEvent,
} from "react";

/* ==========================================================================
   可调列宽（table-layout: fixed + <colgroup>）

   - 拖动只直接改写 <col> 与 <table> 的 min-width，不触发 React 渲染；
     松手时一次性提交到 state 并写入 localStorage。
   - 键盘：←/→ 8px，Shift 32px，Home 最小、End 最大，Enter 或双击恢复默认。
   - 表格保留一列无宽度的填充列吸收剩余空间，用户设置的数据列宽不会被拉伸。
   ========================================================================== */

export type ColSpec = {
  id: string;
  label: string;
  min: number;
  def: number;
  max?: number;
};

const MAX_W = 720;
const STORAGE_KEY = "cfv2-records-cols";

function loadWidths(
  storageKey: string,
  specs: ColSpec[],
): Record<string, number> {
  const out = Object.fromEntries(specs.map((spec) => [spec.id, spec.def]));
  try {
    const raw = localStorage.getItem(storageKey);
    if (!raw) return out;
    const saved = JSON.parse(raw) as Record<string, unknown>;
    for (const spec of specs) {
      const value = saved[spec.id];
      if (typeof value === "number" && Number.isFinite(value)) {
        out[spec.id] = Math.round(
          Math.min(spec.max ?? MAX_W, Math.max(spec.min, value)),
        );
      }
    }
  } catch {
    /* 存储损坏或隐私模式：使用默认宽度，仅保存在内存。 */
  }
  return out;
}

export function useColumnWidths(
  specs: ColSpec[],
  fixedExtra: number,
  fillerMin: number,
) {
  const [widths, setWidths] = useState(() => loadWidths(STORAGE_KEY, specs));
  const cols = useRef(new Map<string, HTMLTableColElement>());
  const table = useRef<HTMLTableElement | null>(null);
  const latest = useRef({ widths, specs, fixedExtra, fillerMin });
  latest.current = { widths, specs, fixedExtra, fillerMin };

  const totalOf = useCallback((next: Record<string, number>) => {
    const current = latest.current;
    return (
      current.specs.reduce((sum, spec) => sum + (next[spec.id] ?? spec.def), 0) +
      current.fixedExtra +
      current.fillerMin
    );
  }, []);

  const clamp = useCallback((id: string, width: number) => {
    const spec = latest.current.specs.find((item) => item.id === id);
    return Math.round(
      Math.min(spec?.max ?? MAX_W, Math.max(spec?.min ?? 48, width)),
    );
  }, []);

  /** 拖动中的即时预览：直接写 DOM，不触发 React 渲染。 */
  const preview = useCallback(
    (id: string, width: number) => {
      const value = clamp(id, width);
      cols.current.get(id)?.style.setProperty("width", `${value}px`);
      const node = table.current;
      if (node) {
        const next = { ...latest.current.widths, [id]: value };
        node.style.minWidth = `${totalOf(next)}px`;
      }
    },
    [clamp, totalOf],
  );

  const commit = useCallback(
    (id: string, width: number) => {
      setWidths((current) => ({ ...current, [id]: clamp(id, width) }));
    },
    [clamp],
  );

  const reset = useCallback((id: string) => {
    setWidths((current) => {
      const spec = latest.current.specs.find((item) => item.id === id);
      return spec ? { ...current, [id]: spec.def } : current;
    });
  }, []);

  const resetAll = useCallback(() => {
    setWidths(
      Object.fromEntries(
        latest.current.specs.map((spec) => [spec.id, spec.def]),
      ),
    );
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(widths));
    } catch {
      /* 隐私模式：仅保存在内存。 */
    }
  }, [widths]);

  const colRef = useCallback(
    (id: string) => (element: HTMLTableColElement | null) => {
      if (element) cols.current.set(id, element);
      else cols.current.delete(id);
    },
    [],
  );

  const tableRef = useCallback((element: HTMLTableElement | null) => {
    table.current = element;
  }, []);

  const total = totalOf(widths);
  const isDefault = specs.every((spec) => widths[spec.id] === spec.def);

  return {
    widths,
    total,
    colRef,
    tableRef,
    preview,
    commit,
    reset,
    resetAll,
    isDefault,
  };
}

export function ResizeHandle({
  column,
  label,
  value,
  min,
  max = MAX_W,
  onPreview,
  onCommit,
  onReset,
}: {
  column: string;
  label: string;
  value: number;
  min: number;
  max?: number;
  onPreview: (width: number) => void;
  onCommit: (width: number) => void;
  onReset: () => void;
}) {
  const drag = useRef<{ x: number; width: number } | null>(null);
  const [active, setActive] = useState(false);

  const stopDrag = useCallback(() => {
    drag.current = null;
    setActive(false);
    document.body.classList.remove("col-resizing");
  }, []);

  useEffect(() => stopDrag, [stopDrag]);

  const widthAt = (clientX: number) => {
    const start = drag.current;
    if (!start) return value;
    return Math.min(max, Math.max(min, start.width + clientX - start.x));
  };

  const onKeyDown = (event: KeyboardEvent<HTMLSpanElement>) => {
    const step = event.shiftKey ? 32 : 8;
    if (event.key === "ArrowLeft") onCommit(value - step);
    else if (event.key === "ArrowRight") onCommit(value + step);
    else if (event.key === "Home") onCommit(min);
    else if (event.key === "End") onCommit(max);
    else if (event.key === "Enter") onReset();
    else return;
    event.preventDefault();
    event.stopPropagation();
  };

  return (
    <span
      role="separator"
      aria-orientation="vertical"
      aria-label={`调整${label}列宽`}
      aria-valuenow={Math.round(value)}
      aria-valuemin={min}
      aria-valuemax={max}
      aria-valuetext={`${Math.round(value)} 像素`}
      tabIndex={0}
      className="col-resizer"
      data-column={column}
      data-active={active || undefined}
      title={`拖动调整${label}列宽；双击或按 Enter 恢复默认`}
      onClick={(event) => event.stopPropagation()}
      onDoubleClick={(event) => {
        event.preventDefault();
        event.stopPropagation();
        onReset();
      }}
      onKeyDown={onKeyDown}
      onPointerDown={(event: ReactPointerEvent<HTMLSpanElement>) => {
        if (event.button !== 0) return;
        event.preventDefault();
        event.stopPropagation();
        event.currentTarget.focus();
        event.currentTarget.setPointerCapture(event.pointerId);
        drag.current = { x: event.clientX, width: value };
        document.body.classList.add("col-resizing");
        setActive(true);
      }}
      onPointerMove={(event) => {
        if (!drag.current) return;
        onPreview(widthAt(event.clientX));
      }}
      onPointerUp={(event) => {
        if (!drag.current) return;
        const width = widthAt(event.clientX);
        stopDrag();
        onCommit(width);
      }}
      onPointerCancel={() => {
        if (!drag.current) return;
        onPreview(drag.current.width);
        stopDrag();
      }}
      onLostPointerCapture={() => {
        if (!drag.current) return;
        onPreview(drag.current.width);
        stopDrag();
      }}
    />
  );
}
