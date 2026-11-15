import {
  ExternalLink,
  Mail,
  RefreshCw,
  Send,
  ShieldCheck,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
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

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export default function EmailRoutingPanel({
  accounts,
  defaultAccount,
  defaultZone,
  onNotify,
}: Props) {
  const [account, setAccount] = useState(defaultAccount);
  const [zone, setZone] = useState(defaultZone);
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const previousDefaults = useRef({ account: defaultAccount, zone: defaultZone });

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

  const addresses = addressesQuery.data?.items ?? [];
  const target = useMemo<ApiEmailRoutingAddress | null>(() => {
    const wanted = email.trim().toLowerCase();
    if (!wanted) return null;
    return (
      addresses.find((item) => item.email.toLowerCase() === wanted) ?? null
    );
  }, [addresses, email]);

  const status = statusQuery.data;
  const zoneStatus = status?.zone_status ?? "";
  const catchAllTo = status?.catch_all.forward_to ?? [];
  const nonCloudflareMx = status?.non_cloudflare_mx ?? [];
  const catchAllDone = Boolean(
    target?.verified &&
      status?.catch_all.enabled &&
      catchAllTo.some(
        (item) => item.toLowerCase() === target.email.toLowerCase(),
      ),
  );
  const canAdd = Boolean(
    account && email.trim() && !target && !addAddress.isPending,
  );
  const canComplete = Boolean(
    target?.verified &&
      activeZone &&
      zoneStatus === "active" &&
      !catchAllDone &&
      !complete.isPending,
  );
  const requiredTypes = Array.from(
    new Set((status?.required_records ?? []).map((item) => item.type)),
  );
  const targetState = target
    ? target.verified
      ? "已验证"
      : "待验证"
    : email.trim()
      ? "未添加"
      : "未填写";

  async function refresh() {
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

  async function handleAdd() {
    setError("");
    setMessage("");
    try {
      const result = await addAddress.mutateAsync({
        account,
        email: email.trim(),
      });
      setMessage(result.message);
    } catch (err) {
      setError(errorText(err));
    }
  }

  async function handleComplete() {
    if (!target || !activeZone) return;
    setError("");
    setMessage("");
    try {
      const result = await complete.mutateAsync({
        account,
        zone: activeZone,
        email: target.email,
      });
      setMessage(result.message || "邮箱转发已配置");
    } catch (err) {
      setError(errorText(err));
    }
  }

  return (
    <section className="panel wide">
      <div className="panel-head">
        <Mail size={17} />
        <div>
          <h2>邮箱转发（Email Routing）</h2>
          <p>
            把域名来信转发到 Gmail 等个人邮箱；先添加并验证目标邮箱，再启用路由和
            catch-all。目标地址在账号内共享。
          </p>
        </div>
      </div>

      <div className="form-grid">
        <label className="field">
          <span className="field-label">账号</span>
          <select
            value={account}
            onChange={(event) => setAccount(event.target.value)}
          >
            <option value="">选择账号</option>
            {accounts.map((item) => (
              <option key={item.name} value={item.name}>
                {item.name}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span className="field-label">域名</span>
          <select
            value={zone}
            onChange={(event) => setZone(event.target.value)}
            disabled={!account || zonesQuery.isLoading}
          >
            <option value="">选择域名</option>
            {(zonesQuery.data ?? []).map((item) => (
              <option key={item.id || item.name} value={item.name}>
                {item.name}
              </option>
            ))}
          </select>
        </label>
      </div>

      {zonesQuery.isError && (
        <div className="error-inline">
          读取域名列表失败：{errorText(zonesQuery.error)}
        </div>
      )}

      <label className="field">
        <span className="field-label">目标邮箱</span>
        <input
          value={email}
          onChange={(event) => {
            setEmail(event.target.value);
            setMessage("");
            setError("");
          }}
          onKeyDown={(event) => {
            if (event.key === "Enter" && canAdd) {
              event.preventDefault();
              void handleAdd();
            }
          }}
          placeholder="you@gmail.com"
          autoComplete="email"
        />
        <span className="field-hint">
          {targetState === "已验证"
            ? "目标邮箱已验证，可以完成 catch-all 配置。"
            : targetState === "待验证"
              ? "目标邮箱已添加，等待验证；请检查收件箱和垃圾箱。"
              : targetState === "未添加"
                ? "目标邮箱尚未添加；首次添加会触发 Cloudflare 验证邮件。"
                : "填写接收转发的个人邮箱，例如 Gmail。"}
        </span>
      </label>

      {addresses.length > 0 && (
        <div className="address-chip-row">
          <span className="field-label">账号内目标地址</span>
          {addresses.slice(0, 12).map((item) => (
            <button
              type="button"
              key={item.id || item.email}
              className={`address-chip ${item.verified ? "verified" : ""}`}
              onClick={() => {
                setEmail(item.email);
                setMessage("");
                setError("");
              }}
              title={`使用 ${item.email}`}
            >
              <span>{item.email}</span>
              <em>{item.verified ? "已验证" : "待验证"}</em>
            </button>
          ))}
          {addresses.length > 12 && (
            <span className="field-hint">另有 {addresses.length - 12} 个地址</span>
          )}
        </div>
      )}

      <div className="forward-status">
        <div>
          <span>目标邮箱</span>
          <strong>{targetState}</strong>
        </div>
        <div>
          <span>域名状态</span>
          <strong>{zoneStatus || "—"}</strong>
        </div>
        <div>
          <span>路由</span>
          <strong>
            {status ? (status.routing_enabled ? "已启用" : "未启用") : "读取中…"}
          </strong>
        </div>
        <div>
          <span>catch-all</span>
          <strong>
            {status
              ? status.catch_all.enabled
                ? catchAllTo.join(", ") || "已启用"
                : "未设置"
              : "读取中…"}
          </strong>
        </div>
        <div>
          <span>所需记录</span>
          <strong>
            {status
              ? requiredTypes.length
                ? `${requiredTypes.join(" / ")}（${status.required_records.length} 条）`
                : "—"
              : "读取中…"}
          </strong>
        </div>
      </div>

      {nonCloudflareMx.length > 0 && (
        <div className="inline-warning">
          检测到非 Cloudflare MX：{nonCloudflareMx.join(", ")}
          。启用 Email Routing 会与现有邮箱冲突；请先确认是否保留原邮箱，必要时先在
          Cloudflare DNS 删除旧 MX。
        </div>
      )}
      {activeZone && status && zoneStatus !== "active" && (
        <div className="inline-warning">
          域名状态为 {zoneStatus || "未知"}；Email Routing 要求 zone 为 active，请先完成
          nameserver 激活。
        </div>
      )}
      {status?.records_error && (
        <div className="error-inline">
          读取邮箱路由记录失败：{status.records_error}
        </div>
      )}
      {(addressesQuery.isError || statusQuery.isError) && (
        <div className="error-inline">
          读取邮箱转发状态失败：
          {errorText(addressesQuery.error ?? statusQuery.error)}
        </div>
      )}
      {target?.verified && !catchAllDone && status?.catch_all.enabled && (
        <div className="inline-warning">
          当前 catch-all 指向 {catchAllTo.join(", ") || "其他地址"}；点“完成配置”会改为
          {target.email}。
        </div>
      )}
      {message && (
        <div className="success-inline" role="status">
          {message}
        </div>
      )}
      {error && (
        <div className="error-inline" role="alert">
          {error}
        </div>
      )}

      <div className="button-row">
        <button
          type="button"
          className="button"
          onClick={() => void refresh()}
          disabled={!account || addressesQuery.isFetching || statusQuery.isFetching}
        >
          <RefreshCw size={14} aria-hidden="true" />
          刷新状态
        </button>
        <button
          type="button"
          className="button primary"
          onClick={() => void handleAdd()}
          disabled={!canAdd}
        >
          <Send size={14} aria-hidden="true" />
          {addAddress.isPending
            ? "提交中…"
            : target
              ? target.verified
                ? "目标邮箱已验证"
                : "已添加，等待验证"
              : "添加并发送验证"}
        </button>
        <button
          type="button"
          className="button"
          onClick={() => void handleComplete()}
          disabled={!canComplete}
          title={
            !target
              ? "先填写并添加目标邮箱"
              : !target.verified
                ? "目标邮箱尚未验证"
                : !status
                  ? "正在读取域名状态"
                  : zoneStatus !== "active"
                    ? "域名尚未激活"
                    : undefined
          }
        >
          <ShieldCheck size={14} aria-hidden="true" />
          {complete.isPending
            ? "配置中…"
            : catchAllDone
              ? "catch-all 已完成"
              : "验证后完成配置"}
        </button>
        <a
          className="button ghost"
          href="https://dash.cloudflare.com/?to=/:account/email-service/routing"
          target="_blank"
          rel="noreferrer"
        >
          <ExternalLink size={14} aria-hidden="true" />
          Cloudflare 控制台
        </a>
      </div>

      <p className="form-hint">
        完成后从另一个邮箱发到 <code>test@{zone || "你的域名"}</code>
        ，检查目标邮箱收件箱和垃圾箱；本页只配置 catch-all，若要只收指定前缀，请到
        Cloudflare 控制台建具体 routing rule。
      </p>
      <EmailRoutingNotes />
    </section>
  );
}
