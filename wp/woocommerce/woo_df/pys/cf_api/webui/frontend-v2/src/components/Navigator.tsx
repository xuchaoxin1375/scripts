import { Search, Settings2 } from "lucide-react";
import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import type { Account, Zone } from "../types";

type Props = {
  accounts: Account[];
  zones: Zone[];
  account: string;
  zone: string;
  onAccount: (name: string) => void;
  onZone: (name: string) => void;
  onAdvanced: () => void;
};

export default function Navigator({
  accounts,
  zones,
  account,
  zone,
  onAccount,
  onZone,
  onAdvanced,
}: Props) {
  const navigate = useNavigate();
  const [accountQuery, setAccountQuery] = useState("");
  const [zoneQuery, setZoneQuery] = useState("");

  const visibleAccounts = useMemo(() => {
    const q = accountQuery.trim().toLowerCase();
    if (!q) return accounts;
    return accounts.filter(
      (item) =>
        item.name.toLowerCase().includes(q) || item.email.toLowerCase().includes(q),
    );
  }, [accounts, accountQuery]);

  const visibleZones = useMemo(() => {
    const q = zoneQuery.trim().toLowerCase();
    if (!q) return zones;
    return zones.filter((item) => item.name.toLowerCase().includes(q));
  }, [zones, zoneQuery]);

  return (
    <aside className="navigator" aria-label="账号与域名导航">
      <div className="nav-section">
        <div className="nav-heading">
          <span>账号</span>
          <span className="nav-count">{accounts.length}</span>
        </div>
        <label className="nav-search">
          <Search size={14} />
          <input
            value={accountQuery}
            onChange={(event) => setAccountQuery(event.target.value)}
            placeholder="搜索账号或邮箱"
            aria-label="搜索账号"
          />
        </label>
        <div className="account-list">
          {visibleAccounts.map((item) => (
            <button
              key={item.name}
              className={`account-item ${item.name === account ? "selected" : ""}`}
              onClick={() => onAccount(item.name)}
            >
              <span className="status-dot" />
              <span className="account-name">{item.name}</span>
              <span className="account-count">{item.zoneCount ?? "—"}</span>
            </button>
          ))}
          {visibleAccounts.length === 0 && <p className="nav-empty">没有匹配账号</p>}
        </div>
      </div>

      <div className="nav-section zones-section">
        <div className="nav-heading">
          <span>域名</span>
          <span className="nav-count">{zones.length}</span>
        </div>
        <label className="nav-search">
          <Search size={14} />
          <input
            value={zoneQuery}
            onChange={(event) => setZoneQuery(event.target.value)}
            placeholder="过滤域名"
            aria-label="过滤域名"
          />
        </label>
        <div className="zone-list">
          {visibleZones.map((item) => (
            <button
              key={item.id}
              className={`zone-item ${item.name === zone ? "selected" : ""}`}
              onClick={() => onZone(item.name)}
            >
              <span className={`zone-dot ${item.status}`} />
              <span className="zone-name">{item.name}</span>
              <span className={`zone-status ${item.status}`}>{item.status}</span>
            </button>
          ))}
          {visibleZones.length === 0 && <p className="nav-empty">没有匹配域名</p>}
        </div>
      </div>

      <button
        className="advanced-link"
        onClick={() => {
          onAdvanced();
          navigate("/advanced");
        }}
      >
        <Settings2 size={16} />
        高级页
      </button>
    </aside>
  );
}
