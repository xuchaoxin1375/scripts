import {
  AlertTriangle,
  Check,
  Clock,
  ExternalLink,
  Mail,
  Plus,
  RefreshCw,
  ShieldCheck,
} from "lucide-react";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import {
  useAddEmailRoutingAddress,
  useCompleteEmailRouting,
  useEmailRoutingAddresses,
  useEmailRoutingStatus,
  useZones,
} from "../api/hooks";
import type { ApiEmailRoutingAddress } from "../api/types";
import type { Account } from "../types";
import EmailRoutingNotes from "./EmailRoutingNotes";

type Props = {
  accounts: Account[];
  defaultAccount: string;
  defaultZone: string;
  onNotify: (message: string) => void;
};

type AddressRowProps = {
  address: ApiEmailRoutingAddress;
  selected: boolean;
  refreshing: boolean;
  onSelect: (email: string) => void;
  onRefresh: (email: string) => void;
};

function sameEmail(left: string, right: string): boolean {
  return left.trim().toLowerCase() === right.trim().toLowerCase();
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function AddressRow({
  address,
  selected,
  refreshing,
  onSelect,
  onRefresh,
}: AddressRowProps) {
  const verified = address.verified;
  const inputId = useId();
  return (
    <div
      className={`email-routing-address ${selected ? "is-selected" : ""} ${
        verified ? "" : "is-pending"
      }`}
    >
      <label className="email-routing-address-main" htmlFor={inputId}>
        <input
          id={inputId}
          className="email-routing-radio"
          type="radio"
          name="email-routing-target"
          checked={selected}
          onChange={() => onSelect(address.email)}
          aria-label={`选择 ${address.email}`}
        />
        <span
          className={`email-routing-address-icon ${
            verified ? "is-verified" : "is-pending"
          }`}
          aria-hidden="true"
        >
          {verified ? <Check size={13} /> : <Clock size={13} />}
        </span>
        <span className="email-routing-address-copy">
          <strong>{address.email}</strong>
          <small>
            {verified ? "已验证 · 本账号域名可直接复用" : "待验证 · 请检查收件箱和垃圾箱"}
          </small>
        </span>
        <span
          className={`email-routing-badge ${
            verified ? "is-success" : "is-warning"
          }`}
        >
          {verified ? "已验证" : "待验证"}
        </span>
      </label>
      {!verified && (
        <span className="email-routing-address-actions">
          <button
            className="button ghost"
            type="button"
            onClick={() => onRefresh(address.email)}
            disabled={refreshing}
          >
            <RefreshCw size={13} aria-hidden="true" />
            {refreshing ? "刷新中…" : "刷新验证"}
          </button>
        </span>
      )}
    </div>
  );
}

export default function EmailRoutingPanel({
  accounts,
  defaultAccount,
  defaultZone,
  onNotify,
}: Props) {
  const [account, setAccount] = useState(defaultAccount);
  const [zone, setZone] = useState(defaultZone);
  const [selectedEmail, setSelectedEmail] = useState("");
  const [addOpen, setAddOpen] = useState(false);
  const [adding, setAdding] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [formError, setFormError] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [refreshingEmail, setRefreshingEmail] = useState("");
  const [confirming, setConfirming] = useState<"catch-all" | "mx" | null>(
    null,
  );
  const previousDefaults = useRef({ account: defaultAccount, zone: defaultZone });
  const newEmailRef = useRef<HTMLInputElement>(null);
  const addToggleRef = useRef<HTMLButtonElement>(null);
  const cancelConfirmRef = useRef<HTMLButtonElement>(null);
  const completeButtonRef = useRef<HTMLButtonElement>(null);

  const zonesQuery = useZones(account);
  const addressesQuery = useEmailRoutingAddresses(account);
  const activeZone = useMemo(() => {
    if (!zone) return "";
    return (zonesQuery.data ?? []).some((item) => item.name === zone)
      ? zone
      : "";
  }, [zone, zonesQuery.data]);
  const statusQuery = useEmailRoutingStatus(account, activeZone);
  const addAddress = useAddEmailRoutingAddress();
  const complete = useCompleteEmailRouting();

  useEffect(() => {
    const previous = previousDefaults.current;
    if (defaultAccount && defaultAccount !== previous.account) {
      setAccount(defaultAccount);
      previous.account = defaultAccount;
    }
    if (defaultZone && defaultZone !== previous.zone) {
      setZone(defaultZone);
      previous.zone = defaultZone;
    }
  }, [defaultAccount, defaultZone]);

  useEffect(() => {
    if (accounts.length === 0) return;
    if (!account || !accounts.some((item) => item.name === account)) {
      setAccount(accounts[0].name);
    }
  }, [account, accounts]);

  useEffect(() => {
    setZone("");
    setSelectedEmail("");
    setAddOpen(false);
    setNewEmail("");
    setFormError("");
    setMessage("");
    setError("");
    setConfirming(null);
  }, [account]);

  useEffect(() => {
    setMessage("");
    setError("");
    setConfirming(null);
  }, [activeZone]);

  useEffect(() => {
    const list = zonesQuery.data ?? [];
    if (zonesQuery.isLoading) return;
    if (list.length === 0) {
      if (zone) setZone("");
      return;
    }
    if (!zone || !list.some((item) => item.name === zone)) {
      const preferred = list.find((item) => item.name === defaultZone);
      setZone(preferred?.name ?? list[0].name);
    }
  }, [zonesQuery.data, zonesQuery.isLoading, zone, defaultZone]);

  useEffect(() => {
    const list = addressesQuery.data?.items ?? [];
    if (!list.length) {
      if (!addressesQuery.isLoading && selectedEmail) setSelectedEmail("");
      return;
    }
    if (
      !selectedEmail ||
      !list.some((item) => sameEmail(item.email, selectedEmail))
    ) {
      const next = list.find((item) => item.verified) ?? list[0];
      setSelectedEmail(next?.email ?? "");
    }
  }, [addressesQuery.data, addressesQuery.isLoading, selectedEmail]);

  useEffect(() => {
    if (addOpen) newEmailRef.current?.focus();
  }, [addOpen]);

  useEffect(() => {
    if (confirming) cancelConfirmRef.current?.focus();
  }, [confirming]);

  const addresses = addressesQuery.data?.items ?? [];
  const verifiedAddresses = useMemo(
    () => addresses.filter((item) => item.verified),
    [addresses],
  );
  const pendingAddresses = useMemo(
    () => addresses.filter((item) => !item.verified),
    [addresses],
  );
  const target = useMemo(
    () =>
      addresses.find((item) => sameEmail(item.email, selectedEmail)) ?? null,
    [addresses, selectedEmail],
  );
  const status = statusQuery.data;
  const zoneStatus = status?.zone_status ?? "";
  const catchAllTo = status?.catch_all.forward_to ?? [];
  const catchAllEnabled = Boolean(status?.catch_all.enabled);
  const nonCloudflareMx = status?.non_cloudflare_mx ?? [];
  const targetVerified = Boolean(target?.verified);
  const configured = Boolean(
    target &&
      targetVerified &&
      catchAllEnabled &&
      catchAllTo.some((email) => sameEmail(email, target.email)),
  );
  const conflict = Boolean(catchAllEnabled && catchAllTo.length > 0 && !configured);
  const zoneActive = zoneStatus === "active";
  const canComplete = Boolean(
    targetVerified &&
      activeZone &&
      zoneActive &&
      !configured &&
      !complete.isPending,
  );
  const addressesLoading = addressesQuery.isLoading;
  const statusLoading = Boolean(activeZone) && statusQuery.isLoading;
  const hasAddresses = verifiedAddresses.length > 0 || pendingAddresses.length > 0;
  const selectedPending = Boolean(target && !target.verified);
  const pendingOpen = pendingAddresses.some((item) =>
    sameEmail(item.email, selectedEmail),
  );
  const targetOptions = useMemo(() => {
    const options = verifiedAddresses.map((item) => item.email);
    if (target && !target.verified) options.push(target.email);
    return options;
  }, [verifiedAddresses, target]);

  function handleAccountChange(name: string) {
    setAccount(name);
    setZone("");
    setSelectedEmail("");
    setAddOpen(false);
    setNewEmail("");
    setFormError("");
    setMessage("");
    setError("");
    setConfirming(null);
  }

  function handleZoneChange(name: string) {
    setZone(name);
    setMessage("");
    setError("");
    setConfirming(null);
  }

  function handleSelectAddress(email: string) {
    setSelectedEmail(email);
    setMessage("");
    setError("");
    setConfirming(null);
  }

  function handleToggleAdd() {
    setAddOpen((open) => !open);
    setFormError("");
  }

  function handleCancelAdd() {
    setAddOpen(false);
    setNewEmail("");
    setFormError("");
    window.requestAnimationFrame(() => addToggleRef.current?.focus());
  }

  async function handleAdd() {
    if (adding) return;
    const email = newEmail.trim().toLowerCase();
    if (!email) {
      setFormError("请输入目标邮箱");
      window.requestAnimationFrame(() => newEmailRef.current?.focus());
      return;
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      setFormError("目标邮箱格式不正确");
      window.requestAnimationFrame(() => newEmailRef.current?.focus());
      return;
    }
    setFormError("");
    setError("");
    setMessage("");
    setAdding(true);
    try {
      const result = await addAddress.mutateAsync({ account, email });
      try {
        const refreshed = await addressesQuery.refetch();
        if (refreshed.error) throw refreshed.error;
      } catch (err) {
        setError(`目标地址已提交，但刷新列表失败：${errorText(err)}`);
      }
      setSelectedEmail(result.email);
      setAddOpen(false);
      setNewEmail("");
      setMessage(result.message);
      window.requestAnimationFrame(() => addToggleRef.current?.focus());
    } catch (err) {
      setFormError(errorText(err));
    } finally {
      setAdding(false);
    }
  }

  async function refresh() {
    setMessage("");
    setError("");
    try {
      const addressResult = await addressesQuery.refetch();
      if (addressResult.error) throw addressResult.error;
      if (activeZone) {
        const statusResult = await statusQuery.refetch();
        if (statusResult.error) throw statusResult.error;
      }
      onNotify("邮箱转发状态已刷新");
    } catch (err) {
      setError(errorText(err));
    }
  }

  async function handleRefreshAddress(email: string) {
    setMessage("");
    setError("");
    setRefreshingEmail(email);
    try {
      const addressResult = await addressesQuery.refetch();
      if (addressResult.error) throw addressResult.error;
      const refreshedAddress = (addressResult.data?.items ?? []).find((item) =>
        sameEmail(item.email, email),
      );
      if (activeZone) {
        const statusResult = await statusQuery.refetch();
        if (statusResult.error) throw statusResult.error;
      }
      setSelectedEmail(email);
      setMessage(
        refreshedAddress?.verified
          ? `${email} 已验证，可直接用于本账号下任意域名。`
          : `${email} 仍未验证，请检查收件箱和垃圾箱。`,
      );
      onNotify("目标邮箱验证状态已刷新");
    } catch (err) {
      setError(errorText(err));
    } finally {
      setRefreshingEmail("");
    }
  }

  async function runComplete() {
    if (!target || !activeZone || !targetVerified || !zoneActive) {
      setConfirming(null);
      setError("无法完成配置：目标邮箱未验证或域名未激活。");
      return;
    }
    setError("");
    setMessage("");
    try {
      const result = await complete.mutateAsync({
        account,
        zone: activeZone,
        email: target.email,
      });
      setConfirming(null);
      setMessage(result.message || "邮箱转发已配置");
      onNotify("邮箱转发已配置");
    } catch (err) {
      setConfirming(null);
      setError(errorText(err));
    }
  }

  function handleCompleteClick() {
    if (!canComplete) return;
    if (conflict || nonCloudflareMx.length > 0) {
      setConfirming(conflict ? "catch-all" : "mx");
      setMessage("");
      setError("");
      return;
    }
    void runComplete();
  }

  function handleCancelConfirm() {
    setConfirming(null);
    window.requestAnimationFrame(() => completeButtonRef.current?.focus());
  }

  function addFormBody(withCancel: boolean) {
    return (
      <>
        <label className="field">
          <span className="field-label">新目标邮箱</span>
          <input
            ref={newEmailRef}
            type="email"
            inputMode="email"
            autoComplete="email"
            placeholder="you@gmail.com"
            value={newEmail}
            onChange={(event) => {
              setNewEmail(event.target.value);
              if (formError) setFormError("");
            }}
            onKeyDown={(event) => {
              if (
                event.key === "Enter" &&
                !addAddress.isPending &&
                !adding
              ) {
                event.preventDefault();
                void handleAdd();
              }
            }}
          />
          <span className="field-hint">
            首次添加会触发 Cloudflare 验证邮件；验证完成前不要切换 MX。
          </span>
        </label>
        {formError && (
          <div className="error-inline" role="alert">
            {formError}
          </div>
        )}
        <div className="button-row">
          <button
            className="button primary"
            type="button"
            onClick={() => void handleAdd()}
            disabled={addAddress.isPending || adding || !account}
          >
            {addAddress.isPending || adding ? "提交中…" : "添加并发送验证"}
          </button>
          {withCancel && (
            <button
              className="button ghost"
              type="button"
              onClick={handleCancelAdd}
            >
              取消
            </button>
          )}
        </div>
      </>
    );
  }

  function renderConfirm() {
    const hasCatchAll = conflict && catchAllTo.length > 0;
    const hasMx = nonCloudflareMx.length > 0;
    const title = hasCatchAll ? "确认覆盖现有 catch-all？" : "确认替换现有 MX？";
    const lines: string[] = [];
    if (hasCatchAll && target) {
      lines.push(
        `${activeZone} 当前 catch-all 指向 ${catchAllTo.join(", ")}，确认后将改为 ${target.email}。`,
      );
    }
    if (hasMx) {
      lines.push(
        `检测到非 Cloudflare MX：${nonCloudflareMx.join(", ")}；启用后会替换现有 MX，原邮箱可能中断。`,
      );
    }
    if (!lines.length && target) {
      lines.push(`确认后将把 ${activeZone} 的 catch-all 设置为 ${target.email}。`);
    }
    return (
      <div
        className="email-routing-confirm"
        role="group"
        aria-labelledby="email-routing-confirm-title"
      >
        <strong id="email-routing-confirm-title">{title}</strong>
        <p>{lines.join(" ")}</p>
        <div className="button-row">
          <button
            ref={cancelConfirmRef}
            className="button"
            type="button"
            onClick={handleCancelConfirm}
          >
            取消
          </button>
          <button
            className="button danger-solid"
            type="button"
            onClick={() => void runComplete()}
            disabled={complete.isPending}
          >
            {complete.isPending ? "配置中…" : "确认替换并启用"}
          </button>
        </div>
      </div>
    );
  }

  function renderStatusCard() {
    if (!account) {
      return (
        <div className="email-routing-status">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-off" />
            <strong>先选择账号</strong>
            <span>目标地址按账号隔离</span>
          </div>
        </div>
      );
    }

    if (addressesLoading) {
      return (
        <div className="email-routing-status">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-off" />
            <strong>正在读取目标地址…</strong>
          </div>
        </div>
      );
    }

    if (addressesQuery.isError) {
      return (
        <div className="email-routing-status is-blocked">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-warn" />
            <strong>无法读取目标地址</strong>
            <span>请先重试，或检查 API Token 的 Email Routing 权限。</span>
            <button
              className="button ghost"
              type="button"
              onClick={() => void addressesQuery.refetch()}
              disabled={addressesQuery.isFetching}
            >
              <RefreshCw size={13} aria-hidden="true" />
              {addressesQuery.isFetching ? "重试中…" : "重试"}
            </button>
          </div>
        </div>
      );
    }

    if (!target) {
      return (
        <div className="email-routing-status is-blocked">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-warn" />
            <strong>等待目标邮箱</strong>
            <span>先在上方添加并验证目标邮箱</span>
          </div>
          <div className="email-routing-blocked">
            <AlertTriangle size={13} aria-hidden="true" />
            <span>验证完成前不能启用域名转发；不要先切换 MX。</span>
          </div>
        </div>
      );
    }

    if (!activeZone) {
      return (
        <div className="email-routing-status">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-off" />
            <strong>先选择域名</strong>
            <span>选择域名后读取路由状态</span>
          </div>
        </div>
      );
    }

    if (statusLoading) {
      return (
        <div className="email-routing-status">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-off" />
            <strong>正在读取域名状态…</strong>
          </div>
        </div>
      );
    }

    if (statusQuery.isError) {
      return (
        <div className="email-routing-status is-blocked">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-warn" />
            <strong>无法读取域名状态</strong>
            <span>读取失败：{errorText(statusQuery.error)}</span>
            <button
              className="button ghost"
              type="button"
              onClick={() => void refresh()}
              disabled={statusQuery.isFetching}
            >
              <RefreshCw size={13} aria-hidden="true" />
              刷新状态
            </button>
          </div>
          <div className="email-routing-blocked">
            <AlertTriangle size={13} aria-hidden="true" />
            <span>请刷新状态，或检查 API Token 的 Email Routing 权限。</span>
          </div>
        </div>
      );
    }

    if (!zoneActive) {
      return (
        <div className="email-routing-status is-blocked">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-warn" />
            <strong>域名未激活</strong>
            <span>
              当前 {zoneStatus || "未知"}，Email Routing 要求 active
            </span>
            <button
              className="button ghost"
              type="button"
              onClick={() => void refresh()}
              disabled={statusQuery.isFetching}
            >
              <RefreshCw size={13} aria-hidden="true" />
              刷新状态
            </button>
          </div>
          <div className="inline-warning">
            <AlertTriangle size={13} aria-hidden="true" />
            <span>请先完成 nameserver 激活，再回来刷新状态。</span>
          </div>
          <div className="email-routing-action-row">
            <button className="button primary" type="button" disabled>
              等待域名激活
            </button>
            <span className="field-hint">激活后刷新状态再配置。</span>
          </div>
        </div>
      );
    }

    if (conflict && !targetVerified) {
      return (
        <div className="email-routing-status is-warn">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-warn" />
            <strong>已启用</strong>
            <span>catch-all → {catchAllTo.join(", ")}</span>
            <button
              className="button ghost"
              type="button"
              onClick={() => void handleRefreshAddress(target.email)}
              disabled={refreshingEmail === target.email}
            >
              <RefreshCw size={13} aria-hidden="true" />
              {refreshingEmail === target.email ? "刷新中…" : "刷新验证状态"}
            </button>
          </div>
          <div className="inline-warning">
            <AlertTriangle size={13} aria-hidden="true" />
            <span>
              {target.email} 尚未验证；验证完成前不会改动当前 catch-all。
            </span>
          </div>
          <div className="email-routing-action-row">
            <span className="field-hint">
              当前域名仍转发到 {catchAllTo.join(", ")}。
            </span>
          </div>
        </div>
      );
    }

    if (!targetVerified) {
      return (
        <div className="email-routing-status is-blocked">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-warn" />
            <strong>等待验证</strong>
            <span>{target.email} 尚未验证</span>
            <button
              className="button ghost"
              type="button"
              onClick={() => void handleRefreshAddress(target.email)}
              disabled={refreshingEmail === target.email}
            >
              <RefreshCw size={13} aria-hidden="true" />
              {refreshingEmail === target.email ? "刷新中…" : "刷新验证状态"}
            </button>
          </div>
          <div className="email-routing-blocked">
            <AlertTriangle size={13} aria-hidden="true" />
            <span>验证完成前不能完成 catch-all 配置；请不要先切换 MX。</span>
          </div>
        </div>
      );
    }

    if (configured) {
      return (
        <div className="email-routing-status is-on">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-on" />
            <strong>已启用</strong>
            <span>catch-all → {catchAllTo.join(", ")}</span>
            <button
              className="button ghost"
              type="button"
              onClick={() => void refresh()}
              disabled={statusQuery.isFetching}
            >
              <RefreshCw size={13} aria-hidden="true" />
              刷新状态
            </button>
          </div>
          <div className="email-routing-action-row">
            <button className="button" type="button" disabled>
              已配置
            </button>
            <span className="field-hint">
              如需更换目标地址，先在账号级选择另一个已验证地址。
            </span>
          </div>
        </div>
      );
    }

    if (conflict) {
      return (
        <div className="email-routing-status is-warn">
          <div className="email-routing-status-line">
            <span className="email-routing-dot is-warn" />
            <strong>已启用</strong>
            <span>catch-all → {catchAllTo.join(", ")}</span>
            <button
              className="button ghost"
              type="button"
              onClick={() => void refresh()}
              disabled={statusQuery.isFetching}
            >
              <RefreshCw size={13} aria-hidden="true" />
              刷新状态
            </button>
          </div>
          <div className="inline-warning">
            <AlertTriangle size={13} aria-hidden="true" />
            <span>
              完成配置会将 catch-all 改为 {target.email}；当前规则将停止转发到{" "}
              {catchAllTo.join(", ")}。
            </span>
          </div>
          {confirming ? (
            renderConfirm()
          ) : (
            <div className="email-routing-action-row">
              <button
                ref={completeButtonRef}
                className="button primary"
                type="button"
                onClick={handleCompleteClick}
                disabled={!canComplete}
              >
                <ShieldCheck size={13} aria-hidden="true" />
                {complete.isPending
                  ? "配置中…"
                  : `改为转发到 ${target.email}`}
              </button>
              <span className="field-hint">需要确认后才会写入。</span>
            </div>
          )}
        </div>
      );
    }

    return (
      <div className="email-routing-status">
        <div className="email-routing-status-line">
          <span className="email-routing-dot is-off" />
          <strong>未启用</strong>
          <span>catch-all 尚未设置</span>
          <button
            className="button ghost"
            type="button"
            onClick={() => void refresh()}
            disabled={statusQuery.isFetching}
          >
            <RefreshCw size={13} aria-hidden="true" />
            刷新状态
          </button>
        </div>
        {confirming ? (
          renderConfirm()
        ) : (
          <div className="email-routing-action-row">
            <button
              ref={completeButtonRef}
              className="button primary"
              type="button"
              onClick={handleCompleteClick}
              disabled={!canComplete}
            >
              <ShieldCheck size={13} aria-hidden="true" />
              {complete.isPending ? "配置中…" : "启用转发并设置 catch-all"}
            </button>
            <span className="field-hint">
              将添加/接管 MX、SPF、DKIM；DNS 生效通常 5–15 分钟。
            </span>
          </div>
        )}
      </div>
    );
  }

  function renderAdvancedDetails() {
    const required = status?.required_records ?? [];
    const mxRecords = status?.mx_records ?? [];
    return (
      <details className="email-routing-advanced">
        <summary>高级详情（MX、所需记录、路由状态）</summary>
        <div className="email-routing-detail-grid">
          <div>
            <span>zone 状态</span>
            <strong>{zoneStatus || "—"}</strong>
          </div>
          <div>
            <span>routing</span>
            <strong>
              {status ? (status.routing_enabled ? "已启用" : "未启用") : "—"}
            </strong>
          </div>
          <div>
            <span>catch-all</span>
            <strong>{catchAllTo.length ? catchAllTo.join(", ") : "未设置"}</strong>
          </div>
          <div>
            <span>所需记录</span>
            <strong>{required.length ? `${required.length} 条` : "—"}</strong>
          </div>
        </div>
        {status?.records_error && (
          <div className="error-inline email-routing-notice">
            读取邮箱路由记录失败：{status.records_error}
          </div>
        )}
        {required.length > 0 && (
          <div className="email-routing-records">
            <div className="email-routing-records-head">
              <span>类型</span>
              <span>名称</span>
              <span>内容</span>
              <span>优先级</span>
            </div>
            {required.map((record) => (
              <div key={`${record.type}:${record.name}:${record.content}`}>
                <code>{record.type}</code>
                <span>{record.name}</span>
                <span>{record.content}</span>
                <span>{record.priority ?? "—"}</span>
              </div>
            ))}
          </div>
        )}
        {mxRecords.length > 0 && (
          <>
            <p className="field-hint">当前 MX 记录</p>
            <div className="email-routing-records">
              {mxRecords.map((record) => {
                const isNonCloudflare = nonCloudflareMx.includes(record.content);
                return (
                  <div
                    key={`${record.name}:${record.content}:${record.priority ?? ""}`}
                    className={isNonCloudflare ? "is-warning" : ""}
                  >
                    <code>MX</code>
                    <span>{record.name}</span>
                    <span>{record.content}</span>
                    <span>{record.priority ?? "—"}</span>
                  </div>
                );
              })}
            </div>
          </>
        )}
        <p className="field-hint">
          高级详情只用于排障；日常配置不需要看这些原始字段。
        </p>
      </details>
    );
  }

  return (
    <section className="panel wide">
      <div className="panel-head">
        <Mail size={17} aria-hidden="true" />
        <div>
          <h2>邮箱转发（Email Routing）</h2>
          <p>目标邮箱按账号共享：验证一次，本账号下所有域名都可复用。</p>
        </div>
      </div>

      {zonesQuery.isError && (
        <div className="error-inline">
          读取域名列表失败：{errorText(zonesQuery.error)}
        </div>
      )}

      <div className="email-routing-scopes">
        <section
          className="email-routing-scope"
          aria-labelledby="email-routing-account-title"
        >
          <div className="email-routing-scope-head">
            <span className="email-routing-tag">账号级</span>
            <h3 id="email-routing-account-title">目标邮箱</h3>
            <span className="email-routing-scope-note">
              验证一次，账号内所有域名复用
            </span>
          </div>

          <div className="email-routing-account-row">
            <label className="field">
              <span className="field-label">账号</span>
              <select
                value={account}
                onChange={(event) => handleAccountChange(event.target.value)}
                disabled={adding}
              >
                <option value="">选择账号</option>
                {accounts.map((item) => (
                  <option key={item.name} value={item.name}>
                    {item.name}
                  </option>
                ))}
              </select>
            </label>
            <span className="email-routing-counts">
              {addressesQuery.isError
                ? "读取目标地址失败"
                : addressesLoading
                  ? "正在读取目标地址…"
                  : `已验证 ${verifiedAddresses.length} 个 · 待验证 ${pendingAddresses.length} 个`}
            </span>
          </div>

          {addressesQuery.isError ? (
            <div className="email-routing-empty">
              <div className="error-inline">
                读取目标地址失败：{errorText(addressesQuery.error)}
              </div>
              <div className="button-row email-routing-notice">
                <button
                  className="button ghost"
                  type="button"
                  onClick={() => void addressesQuery.refetch()}
                  disabled={addressesQuery.isFetching}
                >
                  <RefreshCw size={13} aria-hidden="true" />
                  {addressesQuery.isFetching ? "重试中…" : "重试"}
                </button>
              </div>
            </div>
          ) : addressesLoading ? (
            <p className="field-hint">正在读取账号级目标地址…</p>
          ) : hasAddresses ? (
            <>
              <div
                className="email-routing-address-list"
                role="radiogroup"
                aria-label="选择转发目标邮箱"
              >
                {verifiedAddresses.map((item) => (
                  <AddressRow
                    key={item.id || item.email}
                    address={item}
                    selected={sameEmail(item.email, selectedEmail)}
                    refreshing={refreshingEmail === item.email}
                    onSelect={handleSelectAddress}
                    onRefresh={(email) => void handleRefreshAddress(email)}
                  />
                ))}
                {pendingAddresses.length > 0 &&
                  (verifiedAddresses.length > 0 ? (
                    <details className="email-routing-more" open={pendingOpen}>
                      <summary>
                        账号内待验证地址（{pendingAddresses.length}）
                      </summary>
                      {pendingAddresses.map((item) => (
                        <AddressRow
                          key={item.id || item.email}
                          address={item}
                          selected={sameEmail(item.email, selectedEmail)}
                          refreshing={refreshingEmail === item.email}
                          onSelect={handleSelectAddress}
                          onRefresh={(email) => void handleRefreshAddress(email)}
                        />
                      ))}
                    </details>
                  ) : (
                    pendingAddresses.map((item) => (
                      <AddressRow
                        key={item.id || item.email}
                        address={item}
                        selected={sameEmail(item.email, selectedEmail)}
                        refreshing={refreshingEmail === item.email}
                        onSelect={handleSelectAddress}
                        onRefresh={(email) => void handleRefreshAddress(email)}
                      />
                    ))
                  ))}
              </div>
              <button
                ref={addToggleRef}
                className="button ghost email-routing-add-toggle"
                type="button"
                onClick={handleToggleAdd}
                aria-expanded={addOpen}
                aria-controls="email-routing-add-form"
              >
                <Plus size={13} aria-hidden="true" />
                {addOpen ? "收起添加表单" : "添加新目标邮箱"}
              </button>
              <div
                className="email-routing-add-form"
                id="email-routing-add-form"
                hidden={!addOpen}
              >
                {addFormBody(true)}
              </div>
            </>
          ) : (
            <div className="email-routing-empty" id="email-routing-add-form">
              {addFormBody(false)}
            </div>
          )}

          {selectedPending && (
            <p className="field-hint">
              当前选择的目标邮箱尚未验证；域名级配置在验证完成前不可用。
            </p>
          )}

          <a
            className="email-routing-console-link"
            href="https://dash.cloudflare.com/?to=/:account/email-service/routing"
            target="_blank"
            rel="noreferrer"
          >
            <ExternalLink size={12} aria-hidden="true" />
            在 Cloudflare 控制台管理目标地址
          </a>
        </section>

        <section
          className="email-routing-scope"
          aria-labelledby="email-routing-domain-title"
        >
          <div className="email-routing-scope-head">
            <span className="email-routing-tag">域名级</span>
            <h3 id="email-routing-domain-title">启用转发</h3>
            <span className="email-routing-scope-note">每个域名单独启用</span>
          </div>

          <div className="form-grid email-routing-domain-form">
            <label className="field">
              <span className="field-label">域名</span>
              <select
                value={zone}
                onChange={(event) => handleZoneChange(event.target.value)}
                disabled={!account || zonesQuery.isLoading}
              >
                <option value="">选择域名</option>
                {(zonesQuery.data ?? []).map((item) => (
                  <option key={item.id || item.name} value={item.name}>
                    {item.name}
                    {item.status !== "active" ? "（pending）" : ""}
                  </option>
                ))}
              </select>
            </label>
            <label className="field">
              <span className="field-label">转发到</span>
              <select
                value={selectedEmail}
                onChange={(event) => handleSelectAddress(event.target.value)}
                disabled={targetOptions.length === 0}
              >
                {targetOptions.length === 0 ? (
                  <option value="">先添加目标邮箱</option>
                ) : (
                  targetOptions.map((email) => (
                    <option key={email} value={email}>
                      {email}
                      {verifiedAddresses.some((item) => sameEmail(item.email, email))
                        ? "（已验证）"
                        : "（待验证）"}
                    </option>
                  ))
                )}
              </select>
              <span className="field-hint">
                只显示账号内目标地址；已验证的地址可直接复用。
              </span>
            </label>
          </div>

          {renderStatusCard()}
          {nonCloudflareMx.length > 0 && (
            <div className="inline-warning email-routing-mx-warning">
              <AlertTriangle size={13} aria-hidden="true" />
              <span>
                检测到非 Cloudflare MX：{nonCloudflareMx.join(", ")}
                。启用 Email Routing 会替换现有 MX，原邮箱可能中断。
              </span>
            </div>
          )}
          {renderAdvancedDetails()}
        </section>
      </div>

      {message && (
        <div className="success-inline email-routing-notice" role="status">
          {message}
        </div>
      )}
      {error && (
        <div className="error-inline email-routing-notice" role="alert">
          {error}
        </div>
      )}

      <EmailRoutingNotes />
    </section>
  );
}
