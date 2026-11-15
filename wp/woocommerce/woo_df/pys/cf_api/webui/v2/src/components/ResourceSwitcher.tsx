import {
  ChevronDown,
  Globe2,
  Loader2,
  RefreshCw,
  Search,
  Server,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import type { KeyboardEvent } from "react";
import type { Account, Zone } from "../types";

type Props = {
  accounts: Account[];
  zones: Zone[];
  account: string;
  zone: string;
  accountsLoading: boolean;
  zonesLoading: boolean;
  accountsError: string | null;
  zonesError: string | null;
  onAccount: (name: string) => void;
  onZone: (name: string) => void;
  onRetryAccounts: () => void;
  onRetryZones: () => void;
};

const ACCOUNT_LIMIT = 60;
const ZONE_LIMIT = 80;

export default function ResourceSwitcher({
  accounts,
  zones,
  account,
  zone,
  accountsLoading,
  zonesLoading,
  accountsError,
  zonesError,
  onAccount,
  onZone,
  onRetryAccounts,
  onRetryZones,
}: Props) {
  const [open, setOpen] = useState(false);
  const [accountQuery, setAccountQuery] = useState("");
  const [zoneQuery, setZoneQuery] = useState("");
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  const filteredAccounts = useMemo(() => {
    const query = accountQuery.trim().toLowerCase();
    if (!query) return accounts;
    return accounts.filter(
      (item) =>
        item.name.toLowerCase().includes(query) ||
        item.email.toLowerCase().includes(query),
    );
  }, [accounts, accountQuery]);

  const filteredZones = useMemo(() => {
    const query = zoneQuery.trim().toLowerCase();
    if (!query) return zones;
    return zones.filter((item) => item.name.toLowerCase().includes(query));
  }, [zones, zoneQuery]);

  const visibleAccounts = filteredAccounts.slice(0, ACCOUNT_LIMIT);
  const visibleZones = filteredZones.slice(0, ZONE_LIMIT);
  const currentZone = zones.find((item) => item.name === zone);

  useEffect(() => {
    if (!open) return;
    const timer = window.setTimeout(() => searchRef.current?.focus(), 20);
    return () => window.clearTimeout(timer);
  }, [open]);

  useEffect(() => {
    if (!open) {
      setAccountQuery("");
      setZoneQuery("");
    }
  }, [open]);

  useEffect(() => {
    if (!open) return;
    function onPointerDown(event: PointerEvent) {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("pointerdown", onPointerDown);
    return () => document.removeEventListener("pointerdown", onPointerDown);
  }, [open]);

  function closeAndFocus() {
    setOpen(false);
    triggerRef.current?.focus();
  }

  function chooseAccount(name: string) {
    setZoneQuery("");
    onAccount(name);
  }

  function chooseZone(name: string) {
    onZone(name);
    closeAndFocus();
  }

  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape" && open) {
      event.preventDefault();
      event.stopPropagation();
      closeAndFocus();
    }
  }

  return (
    <div className="resource-switcher" ref={rootRef} onKeyDown={handleKeyDown}>
      <button
        type="button"
        className="resource-trigger"
        ref={triggerRef}
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? "resource-switcher-menu" : undefined}
        aria-label={`切换账号与域名，当前 ${account || "未选择账号"} / ${
          zone || "未选择域名"
        }`}
        title={`${account || "未选择账号"} / ${zone || "未选择域名"}`}
        onClick={() => setOpen((value) => !value)}
      >
        {currentZone && (
          <span
            className={`zone-dot ${currentZone.status}`}
            aria-hidden="true"
          />
        )}
        <span className="resource-account-name">{account || "选择账号"}</span>
        <span className="resource-sep" aria-hidden="true">
          /
        </span>
        <span className="resource-zone-name">{zone || "选择域名"}</span>
        <ChevronDown
          size={14}
          aria-hidden="true"
          className={`resource-chevron ${open ? "open" : ""}`}
        />
      </button>

      {open && (
        <div
          className="resource-menu"
          id="resource-switcher-menu"
          role="dialog"
          aria-label="切换账号与域名"
        >
          <div className="resource-columns">
            <section
              className="resource-section"
              aria-labelledby="resource-accounts-heading"
            >
              <div className="resource-section-head">
                <h4 id="resource-accounts-heading">
                  <Server size={13} aria-hidden="true" /> 账号
                </h4>
                <span>{accounts.length}</span>
              </div>
              <label className="resource-search">
                <Search size={14} aria-hidden="true" />
                <input
                  ref={searchRef}
                  value={accountQuery}
                  onChange={(event) => setAccountQuery(event.target.value)}
                  placeholder="搜索账号或邮箱"
                  aria-label="搜索账号"
                />
              </label>
              <div className="resource-list">
                {accountsLoading && accounts.length === 0 && (
                  <p className="resource-empty" role="status">
                    <Loader2 size={13} className="spin" aria-hidden="true" />
                    正在读取账号…
                  </p>
                )}
                {accountsError && accounts.length === 0 && (
                  <div className="resource-empty resource-error">
                    <span>账号读取失败</span>
                    <button
                      type="button"
                      className="link-button"
                      onClick={onRetryAccounts}
                    >
                      <RefreshCw size={12} aria-hidden="true" /> 重试
                    </button>
                  </div>
                )}
                {!accountsLoading &&
                  !accountsError &&
                  filteredAccounts.length === 0 && (
                    <p className="resource-empty">没有匹配账号</p>
                  )}
                {visibleAccounts.map((item) => (
                  <button
                    type="button"
                    key={item.name}
                    className={`resource-option ${
                      item.name === account ? "active" : ""
                    }`}
                    data-resource-kind="account"
                    aria-pressed={item.name === account}
                    onClick={() => chooseAccount(item.name)}
                    title={item.email || item.name}
                  >
                    <span className="resource-option-name">
                      <span className="status-dot" aria-hidden="true" />
                      {item.name}
                    </span>
                    <small>
                      {item.zoneCount ??
                        (item.auth === "key" ? "KEY" : "TOKEN")}
                    </small>
                  </button>
                ))}
                {filteredAccounts.length > visibleAccounts.length && (
                  <p className="resource-more">
                    仅显示前 {ACCOUNT_LIMIT} 个，输入可继续过滤
                  </p>
                )}
              </div>
            </section>

            <section
              className="resource-section"
              aria-labelledby="resource-zones-heading"
            >
              <div className="resource-section-head">
                <h4 id="resource-zones-heading">
                  <Globe2 size={13} aria-hidden="true" /> 域名
                </h4>
                <span>{zones.length}</span>
              </div>
              <label className="resource-search">
                <Search size={14} aria-hidden="true" />
                <input
                  value={zoneQuery}
                  onChange={(event) => setZoneQuery(event.target.value)}
                  placeholder="过滤域名"
                  aria-label="过滤域名"
                />
              </label>
              <div className="resource-list">
                {!account && (
                  <p className="resource-empty">先选择账号</p>
                )}
                {account && zonesLoading && zones.length === 0 && (
                  <p className="resource-empty" role="status">
                    <Loader2 size={13} className="spin" aria-hidden="true" />
                    正在读取域名…
                  </p>
                )}
                {account && zonesError && zones.length === 0 && (
                  <div className="resource-empty resource-error">
                    <span>域名读取失败</span>
                    <button
                      type="button"
                      className="link-button"
                      onClick={onRetryZones}
                    >
                      <RefreshCw size={12} aria-hidden="true" /> 重试
                    </button>
                  </div>
                )}
                {account &&
                  !zonesLoading &&
                  !zonesError &&
                  zones.length === 0 && (
                    <p className="resource-empty">该账号暂无域名</p>
                  )}
                {account &&
                  zones.length > 0 &&
                  filteredZones.length === 0 && (
                    <p className="resource-empty">没有匹配域名</p>
                  )}
                {visibleZones.map((item) => (
                  <button
                    type="button"
                    key={item.id}
                    className={`resource-option ${
                      item.name === zone ? "active" : ""
                    }`}
                    data-resource-kind="zone"
                    aria-pressed={item.name === zone}
                    onClick={() => chooseZone(item.name)}
                  >
                    <span className="resource-option-name">
                      <span
                        className={`zone-dot ${item.status}`}
                        aria-hidden="true"
                      />
                      {item.name}
                    </span>
                    <small>{item.status}</small>
                  </button>
                ))}
                {filteredZones.length > visibleZones.length && (
                  <p className="resource-more">
                    仅显示前 {ZONE_LIMIT} 个，输入可继续过滤
                  </p>
                )}
              </div>
            </section>
          </div>
          <p className="resource-hint">
            选择账号后域名列表会随账号刷新；记录表只加载当前域名。
          </p>
        </div>
      )}
    </div>
  );
}
