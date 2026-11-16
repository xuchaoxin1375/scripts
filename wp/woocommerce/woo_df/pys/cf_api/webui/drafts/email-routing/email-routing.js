/* Email routing panel prototype. Static mock data only; no API calls. */
(() => {
  "use strict";

  const ICONS = {
    mail: `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2"></rect><path d="m3 7 9 6 9-6"></path></svg>`,
    check: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6"></path></svg>`,
    clock: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8"></circle><path d="M12 8v4l2.5 2.5"></path></svg>`,
    alert: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 22 21H2Z"></path><path d="M12 9v5M12 18h.01"></path></svg>`,
    refresh: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 11a8 8 0 1 0-2.3 6.3"></path><path d="M20 5v6h-6"></path></svg>`,
    external: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 4h6v6"></path><path d="M20 4 10 14"></path><path d="M20 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h5"></path></svg>`,
  };

  const BASE_ACCOUNTS = {
    cf00: {
      verified: ["owner@gmail.com"],
      pending: ["new@gmail.com"],
      zones: [
        { name: "example.com", status: "active" },
        { name: "shop.example.net", status: "pending" },
      ],
    },
    cf01: {
      verified: [],
      pending: ["pending@example.net"],
      zones: [{ name: "shop.example.net", status: "active" }],
    },
    cf02: {
      verified: ["ops@example.com", "backup@example.com"],
      pending: [],
      zones: [{ name: "example.com", status: "active" }],
    },
    cf03: {
      verified: [],
      pending: [],
      zones: [{ name: "example.com", status: "active" }],
    },
  };

  const STATE_PRESETS = {
    verified: {
      account: "cf00",
      zone: "example.com",
      selected: "owner@gmail.com",
      catchAll: "",
      mx: [],
    },
    pending: {
      account: "cf01",
      zone: "shop.example.net",
      selected: "pending@example.net",
      catchAll: "",
      mx: [],
    },
    empty: {
      account: "cf03",
      zone: "example.com",
      selected: "",
      catchAll: "",
      mx: [],
    },
    configured: {
      account: "cf02",
      zone: "example.com",
      selected: "ops@example.com",
      catchAll: "ops@example.com",
      mx: [],
    },
    conflict: {
      account: "cf00",
      zone: "example.com",
      selected: "owner@gmail.com",
      catchAll: "old@example.com",
      mx: ["mx.google.com"],
    },
    "mx-conflict": {
      account: "cf00",
      zone: "example.com",
      selected: "owner@gmail.com",
      catchAll: "",
      mx: ["mx.google.com"],
    },
    inactive: {
      account: "cf00",
      zone: "shop.example.net",
      selected: "owner@gmail.com",
      catchAll: "",
      mx: [],
    },
  };

  const STATE_OPTIONS = [
    ["verified", "已验证 · cf00（可配置）"],
    ["pending", "待验证 · cf01（域名配置被阻止）"],
    ["empty", "未添加 · cf03（空状态）"],
    ["configured", "已配置 · cf02（同目标）"],
    ["conflict", "风险冲突 · cf00（覆盖其他 catch-all）"],
    ["mx-conflict", "MX 冲突 · cf00（启用会替换现有 MX）"],
    ["inactive", "域名未激活 · cf00"],
    ["custom", "自定义（手动调整）"],
  ];

  const THEME_KEY = "cf-draft-theme";
  let ACCOUNTS = clone(BASE_ACCOUNTS);
  let view = makeView("verified");

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function eq(left, right) {
    return String(left || "").trim().toLowerCase() === String(right || "").trim().toLowerCase();
  }

  function esc(value) {
    return String(value ?? "").replace(/[&<>"']/g, (ch) => {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch];
    });
  }

  function makeView(state) {
    const preset = STATE_PRESETS[state] || STATE_PRESETS.verified;
    const account = ACCOUNTS[preset.account];
    const zone = account.zones.find((item) => item.name === preset.zone) || account.zones[0];
    return {
      state,
      account: preset.account,
      zone: zone.name,
      zoneStatus: zone.status,
      selected: preset.selected,
      catchAll: preset.catchAll,
      mx: [...preset.mx],
      addOpen: false,
      addEmail: "",
      confirming: false,
      notice: "",
      error: "",
    };
  }

  function derive() {
    const account = ACCOUNTS[view.account];
    const verified = account.verified;
    const pending = account.pending;
    const target = view.selected || verified[0] || pending[0] || "";
    const targetVerified = verified.some((email) => eq(email, target));
    const catchAll = view.catchAll;
    const configured = Boolean(catchAll && targetVerified && eq(catchAll, target));
    const conflict = Boolean(catchAll && !configured);
    const zoneActive = view.zoneStatus === "active";
    const canComplete = Boolean(targetVerified && zoneActive && !configured);

    return {
      account,
      verified,
      pending,
      target,
      targetVerified,
      catchAll,
      configured,
      conflict,
      zoneActive,
      canComplete,
    };
  }

  function normalizeSelection() {
    const account = ACCOUNTS[view.account];
    if (!account) return;
    const all = [...account.verified, ...account.pending];
    if (!view.selected || !all.some((email) => eq(email, view.selected))) {
      view.selected = account.verified[0] || account.pending[0] || "";
    }
  }

  function render(focusTarget) {
    normalizeSelection();
    root.innerHTML = template();
    syncStateSelect();
    if (typeof focusTarget === "function") {
      window.requestAnimationFrame(focusTarget);
    } else if (focusTarget) {
      window.requestAnimationFrame(() => root.querySelector(focusTarget)?.focus());
    }
  }

  function syncStateSelect() {
    const select = document.querySelector("[data-state-select]");
    if (select) select.value = view.state;
  }

  function focusAddress(email) {
    const inputs = [...root.querySelectorAll('input[data-action="select-address"]')];
    inputs.find((input) => input.value === email)?.focus();
  }

  function addressItem(email, verified) {
    const selected = eq(email, view.selected);
    const safe = esc(email);
    return `
      <div class="er-address-item ${verified ? "is-verified" : "is-pending"} ${selected ? "is-selected" : ""}">
        <input
          class="er-address-radio"
          type="radio"
          name="er-target"
          value="${safe}"
          ${selected ? "checked" : ""}
          data-action="select-address"
          aria-label="选择 ${safe}"
        >
        <span class="er-address-icon ${verified ? "is-verified" : "is-pending"}">
          ${verified ? ICONS.check : ICONS.clock}
        </span>
        <span class="er-address-copy">
          <strong>${safe}</strong>
          <small>${verified ? "已验证 · 本账号域名可直接复用" : "待验证 · 请检查收件箱和垃圾箱"}</small>
        </span>
        <span class="er-badge ${verified ? "is-success" : "is-warning"}">${verified ? "已验证" : "待验证"}</span>
        ${
          verified
            ? ""
            : `<span class="er-address-actions">
                <button class="button ghost" type="button" data-action="refresh-pending" data-email="${safe}">
                  ${ICONS.refresh} 刷新验证
                </button>
              </span>`
        }
      </div>`;
  }

  function addForm(hasAddresses, hidden) {
    return `
      <div class="er-add-form" id="er-add-form"${hidden ? " hidden" : ""}>
        <label class="field">
          <span class="field-label">新目标邮箱</span>
          <input
            type="email"
            inputmode="email"
            autocomplete="email"
            placeholder="you@gmail.com"
            data-new-email
            value="${esc(view.addEmail)}"
          >
          <span class="field-hint">首次添加会触发 Cloudflare 验证邮件；验证完成前不要切换 MX。</span>
        </label>
        ${
          view.error
            ? `<div class="error-inline" role="alert">${esc(view.error)}</div>`
            : ""
        }
        <div class="button-row">
          <button class="button primary" type="button" data-action="add-address">添加并发送验证</button>
          ${
            hasAddresses
              ? `<button class="button ghost" type="button" data-action="cancel-add">取消</button>`
              : ""
          }
        </div>
      </div>`;
  }

  function accountSection(d) {
    const hasAddresses = d.verified.length > 0 || d.pending.length > 0;
    const pendingOpen = d.pending.some((email) => eq(email, view.selected));

    return `
      <section class="er-scope" aria-labelledby="er-account-title">
        <div class="er-scope-head">
          <span class="er-scope-tag">账号级</span>
          <h3 id="er-account-title">目标邮箱</h3>
          <span class="er-scope-note">验证一次，账号内所有域名复用</span>
        </div>

        <div class="er-account-row">
          <label class="field">
            <span class="field-label">账号</span>
            <select data-account-select>
              ${Object.keys(ACCOUNTS)
                .map(
                  (name) =>
                    `<option value="${esc(name)}" ${name === view.account ? "selected" : ""}>${esc(name)}</option>`,
                )
                .join("")}
            </select>
          </label>
          <span class="er-account-counts">
            已验证 ${d.verified.length} 个 · 待验证 ${d.pending.length} 个
          </span>
        </div>

        ${
          hasAddresses
            ? `<div class="er-address-list" role="radiogroup" aria-label="选择转发目标邮箱">
                ${d.verified.map((email) => addressItem(email, true)).join("")}
                ${
                  d.pending.length
                    ? d.verified.length
                      ? `<details class="er-more" ${pendingOpen ? "open" : ""}>
                          <summary>账号内待验证地址（${d.pending.length}）</summary>
                          ${d.pending.map((email) => addressItem(email, false)).join("")}
                        </details>`
                      : d.pending.map((email) => addressItem(email, false)).join("")
                    : ""
                }
              </div>
              <button
                class="button ghost er-add-toggle"
                type="button"
                data-action="toggle-add"
                aria-expanded="${view.addOpen}"
                aria-controls="er-add-form"
              >
                ${view.addOpen ? "收起添加表单" : "+ 添加新目标邮箱"}
              </button>`
            : ""
        }

        ${hasAddresses ? addForm(true, !view.addOpen) : addForm(false, false)}

        ${
          d.target && !d.targetVerified
            ? `<p class="field-hint">当前选择的目标邮箱尚未验证；域名级配置在验证完成前不可用。</p>`
            : ""
        }
      </section>`;
  }

  function confirmBlock(d) {
    const hasCatchAll = Boolean(d.catchAll);
    const hasMx = view.mx.length > 0;
    const title = hasCatchAll ? "确认覆盖现有 catch-all？" : "确认替换现有 MX？";
    const lines = [];

    if (hasCatchAll) {
      lines.push(
        `${esc(view.zone)} 当前 catch-all 指向 ${esc(d.catchAll)}，确认后将改为 ${esc(d.target)}。`,
      );
    }
    if (hasMx) {
      lines.push(
        `检测到非 Cloudflare MX：${esc(view.mx.join(", "))}；启用后会替换现有 MX，原邮箱可能中断。`,
      );
    }
    if (!lines.length) {
      lines.push(`确认后将把 ${esc(view.zone)} 的 catch-all 设置为 ${esc(d.target)}。`);
    }

    return `
      <div class="er-confirm" role="group" aria-labelledby="er-confirm-title">
        <strong id="er-confirm-title">${title}</strong>
        <p>${lines.join(" ")}</p>
        <div class="button-row">
          <button class="button danger" type="button" data-action="confirm-complete">
            确认替换并启用
          </button>
          <button class="button ghost" type="button" data-action="cancel-confirm">取消</button>
        </div>
      </div>`;
  }

  function statusCard(d) {
    if (!d.target) {
      return `
        <div class="er-status-card is-blocked">
          <div class="er-status-line">
            <span class="er-status-dot is-warn"></span>
            <strong>等待目标邮箱</strong>
            <span>先在上方添加并验证目标邮箱</span>
          </div>
          <div class="er-blocked-reason">
            ${ICONS.alert}
            <span>验证完成前不能启用域名转发；不要先切换 MX。</span>
          </div>
        </div>`;
    }

    if (!d.targetVerified) {
      return `
        <div class="er-status-card is-blocked">
          <div class="er-status-line">
            <span class="er-status-dot is-warn"></span>
            <strong>等待验证</strong>
            <span>${esc(d.target)} 尚未验证</span>
            <button class="button ghost" type="button" data-action="refresh-pending" data-email="${esc(d.target)}">
              ${ICONS.refresh} 刷新验证状态
            </button>
          </div>
          <div class="er-blocked-reason">
            ${ICONS.alert}
            <span>验证完成前不能完成 catch-all 配置；请不要先切换 MX。</span>
          </div>
        </div>`;
    }

    if (!d.zoneActive) {
      return `
        <div class="er-status-card is-blocked">
          <div class="er-status-line">
            <span class="er-status-dot is-warn"></span>
            <strong>域名未激活</strong>
            <span>当前 ${esc(view.zoneStatus)}，Email Routing 要求 active</span>
          </div>
          <div class="inline-warning">
            ${ICONS.alert}
            <span>请先完成 nameserver 激活，再回来刷新状态。</span>
          </div>
          <div class="er-action-row">
            <button class="button primary" type="button" disabled>等待域名激活</button>
            <span class="field-hint">激活后刷新状态再配置。</span>
          </div>
        </div>`;
    }

    if (d.configured) {
      return `
        <div class="er-status-card is-on">
          <div class="er-status-line">
            <span class="er-status-dot is-on"></span>
            <strong>已启用</strong>
            <span>catch-all → ${esc(d.catchAll)}</span>
            <button class="button ghost" type="button" data-action="refresh-status">
              ${ICONS.refresh} 刷新状态
            </button>
          </div>
          <div class="er-action-row">
            <button class="button" type="button" disabled>已配置</button>
            <span class="field-hint">如需更换目标地址，先在账号级选择另一个已验证地址。</span>
          </div>
        </div>`;
    }

    if (d.conflict) {
      return `
        <div class="er-status-card is-warn">
          <div class="er-status-line">
            <span class="er-status-dot is-warn"></span>
            <strong>已启用</strong>
            <span>catch-all → ${esc(d.catchAll)}</span>
            <button class="button ghost" type="button" data-action="refresh-status">
              ${ICONS.refresh} 刷新状态
            </button>
          </div>
          <div class="inline-warning">
            ${ICONS.alert}
            <span>完成配置会将 catch-all 改为 ${esc(d.target)}；当前规则将停止转发到 ${esc(d.catchAll)}。</span>
          </div>
          ${
            view.confirming
              ? confirmBlock(d)
              : `<div class="er-action-row">
                  <button class="button primary" type="button" data-action="complete">
                    改为转发到 ${esc(d.target)}
                  </button>
                  <span class="field-hint">需要确认后才会写入。</span>
                </div>`
          }
        </div>`;
    }

    return `
      <div class="er-status-card">
        <div class="er-status-line">
          <span class="er-status-dot is-off"></span>
          <strong>未启用</strong>
          <span>catch-all 尚未设置</span>
          <button class="button ghost" type="button" data-action="refresh-status">
            ${ICONS.refresh} 刷新状态
          </button>
        </div>
        ${
          view.confirming
            ? confirmBlock(d)
            : `<div class="er-action-row">
                <button class="button primary" type="button" data-action="complete">
                  启用转发并设置 catch-all
                </button>
                <span class="field-hint">将添加/接管 MX、SPF、DKIM；DNS 生效通常 5–15 分钟。</span>
              </div>`
        }
      </div>`;
  }

  function mxWarning() {
    if (!view.mx.length) return "";
    return `
      <div class="inline-warning er-mx-warning">
        ${ICONS.alert}
        <span>检测到非 Cloudflare MX：${esc(view.mx.join(", "))}。启用 Email Routing 会替换现有 MX，原邮箱可能中断。</span>
      </div>`;
  }

  function advancedDetails(d) {
    return `
      <details class="er-advanced">
        <summary>高级详情（MX、所需记录、路由状态）</summary>
        <div class="er-detail-grid">
          <div><span>zone 状态</span><strong>${esc(view.zoneStatus)}</strong></div>
          <div><span>routing</span><strong>${d.catchAll ? "已启用" : "未启用"}</strong></div>
          <div><span>catch-all</span><strong>${esc(d.catchAll || "未设置")}</strong></div>
          <div><span>所需记录</span><strong>${d.zoneActive ? "MX / SPF / DKIM（3 条）" : "—"}</strong></div>
        </div>
        <div class="er-record-list">
          <div><code>MX</code><span>${esc(view.zone)}</span><span>route1.mx.cloudflare.net</span><span>10</span></div>
          <div><code>TXT</code><span>${esc(view.zone)}</span><span>v=spf1 include:_spf.mx.cloudflare.net ~all</span><span>—</span></div>
          <div><code>TXT</code><span>cf2024-1._domainkey.${esc(view.zone)}</span><span>v=DKIM1; p=…</span><span>—</span></div>
          ${view.mx
            .map(
              (mx) =>
                `<div><code>MX</code><span>${esc(view.zone)}</span><span>${esc(mx)}</span><span>1</span></div>`,
            )
            .join("")}
        </div>
        <p class="field-hint" style="margin-top:6px">高级详情只用于排障；日常配置不需要看这些原始字段。</p>
      </details>`;
  }

  function domainSection(d) {
    const selectable = [...d.verified];
    if (d.target && !d.targetVerified) selectable.push(d.target);
    const zones = d.account.zones;

    return `
      <section class="er-scope" aria-labelledby="er-domain-title">
        <div class="er-scope-head">
          <span class="er-scope-tag">域名级</span>
          <h3 id="er-domain-title">启用转发</h3>
          <span class="er-scope-note">每个域名单独启用</span>
        </div>

        <div class="form-grid er-domain-form">
          <label class="field">
            <span class="field-label">域名</span>
            <select data-zone-select>
              ${zones
                .map(
                  (zone) =>
                    `<option value="${esc(zone.name)}" ${zone.name === view.zone ? "selected" : ""}>${esc(zone.name)}${zone.status !== "active" ? "（pending）" : ""}</option>`,
                )
                .join("")}
            </select>
          </label>
          <label class="field">
            <span class="field-label">转发到</span>
            <select data-target-select ${selectable.length ? "" : "disabled"}>
              ${
                selectable.length
                  ? selectable
                      .map(
                        (email) =>
                          `<option value="${esc(email)}" ${eq(email, d.target) ? "selected" : ""}>${esc(email)}${d.verified.some((item) => eq(item, email)) ? "（已验证）" : "（待验证）"}</option>`,
                      )
                      .join("")
                  : `<option>先添加目标邮箱</option>`
              }
            </select>
            <span class="field-hint">只显示账号内目标地址；已验证的地址可直接复用。</span>
          </label>
        </div>

        ${statusCard(d)}
        ${mxWarning()}
        ${advancedDetails(d)}
      </section>`;
  }

  function template() {
    normalizeSelection();
    const d = derive();

    return `
      <header class="page-head">
        <div class="page-head-copy">
          <span class="eyebrow">高级工具 / ADVANCED</span>
          <h1>邮箱转发</h1>
          <p>管理账号级目标邮箱；验证后为当前域名启用路由并设置 catch-all。</p>
        </div>
      </header>

      <div class="advanced-context">
        <span>当前范围</span>
        <strong>${esc(view.account)} / ${esc(view.zone)}</strong>
        <button class="button ghost" type="button" data-action="back">← 回到工作台</button>
      </div>

      <section class="panel wide er-panel">
        <div class="panel-head">
          ${ICONS.mail}
          <div>
            <h2>邮箱转发（Email Routing）</h2>
            <p>目标邮箱按账号共享：验证一次，本账号下所有域名都可复用。</p>
          </div>
        </div>

        <div class="er-scopes">
          ${accountSection(d)}
          ${domainSection(d)}
        </div>

        ${view.notice ? `<div class="success-inline er-notice" role="status">${esc(view.notice)}</div>` : ""}
        ${view.error ? `<div class="error-inline er-notice" role="alert">${esc(view.error)}</div>` : ""}

        <details class="forward-notes er-help">
          <summary>邮箱转发注意事项（首次配置必看）</summary>
          <ul>
            <li>目标邮箱必须先验证：Cloudflare 会向该地址发送验证邮件，点击“Verify email address”后 catch-all 才会生效；验证邮件可能进垃圾箱。</li>
            <li>目标地址是账号级的，验证一次可复用到同账号其他域名；换一个新的目标邮箱要重新验证，第一个域名也不例外。</li>
            <li>域名必须在 Cloudflare DNS 且 zone 已激活；已有其他 MX（Google Workspace、企业邮箱等）会冲突，启用 Email Routing 会替换 MX，原邮箱可能中断。</li>
            <li>收信测试：从另一个邮箱发到 <code>test@${esc(view.zone)}</code>，检查目标邮箱收件箱和垃圾箱；不要用同一个 Gmail 发给自己。</li>
            <li>catch-all 会接收所有未匹配地址；只想收指定前缀时要在 Cloudflare 控制台建具体 routing rule。</li>
            <li>API Token 需要 Email Routing Addresses / Rules / Settings 权限；权限不足会报 403。</li>
          </ul>
        </details>
      </section>`;
  }

  function setAccount(name) {
    if (!ACCOUNTS[name]) return;
    clearToasts();
    const account = ACCOUNTS[name];
    const firstZone = account.zones[0];
    view = {
      ...view,
      state: "custom",
      account: name,
      zone: firstZone.name,
      zoneStatus: firstZone.status,
      selected: account.verified[0] || account.pending[0] || "",
      catchAll: "",
      mx: [],
      addOpen: false,
      addEmail: "",
      confirming: false,
      notice: "",
      error: "",
    };
    if (name === "cf02" && account.verified[0]) {
      view.catchAll = account.verified[0];
    }
    render(() => root.querySelector("[data-account-select]")?.focus());
  }

  function setZone(name) {
    const account = ACCOUNTS[view.account];
    const zone = account.zones.find((item) => item.name === name);
    if (!zone) return;
    clearToasts();
    view.zone = zone.name;
    view.zoneStatus = zone.status;
    view.state = "custom";
    view.confirming = false;
    view.notice = "";
    view.error = "";
    render(() => root.querySelector("[data-zone-select]")?.focus());
  }

  function selectAddress(email) {
    view.selected = email;
    view.state = "custom";
    view.confirming = false;
    view.notice = "";
    view.error = "";
    render(() => focusAddress(email));
  }

  function toggleAdd() {
    view.addOpen = !view.addOpen;
    view.error = "";
    view.notice = "";
    render(() => {
      if (view.addOpen) {
        root.querySelector("[data-new-email]")?.focus();
      } else {
        root.querySelector('[data-action="toggle-add"]')?.focus();
      }
    });
  }

  function cancelAdd() {
    view.addOpen = false;
    view.addEmail = "";
    view.error = "";
    render(() => root.querySelector('[data-action="toggle-add"]')?.focus());
  }

  function addAddress() {
    const input = root.querySelector("[data-new-email]");
    const raw = input ? input.value : view.addEmail;
    const email = String(raw || "").trim().toLowerCase();
    view.addEmail = raw || "";

    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      view.error = "请输入有效的目标邮箱。";
      view.notice = "";
      render(() => root.querySelector("[data-new-email]")?.focus());
      return;
    }

    const account = ACCOUNTS[view.account];
    if (account.verified.some((item) => eq(item, email))) {
      view.selected = email;
      view.addOpen = false;
      view.addEmail = "";
      view.error = "";
      view.notice = "该目标邮箱已验证，可以直接使用。";
      view.state = "custom";
      render(() => focusAddress(email));
      return;
    }

    if (account.pending.some((item) => eq(item, email))) {
      view.selected = email;
      view.addOpen = false;
      view.addEmail = "";
      view.error = "";
      view.notice = "该目标邮箱已在等待验证，请检查收件箱。";
      view.state = "custom";
      render(() => focusAddress(email));
      return;
    }

    account.pending.push(email);
    view.selected = email;
    view.addOpen = false;
    view.addEmail = "";
    view.error = "";
    view.notice = "已添加目标邮箱，Cloudflare 已发送验证邮件（mock）；请到收件箱点击验证链接。";
    view.state = "custom";
    render(() => focusAddress(email));
    showToast("验证邮件已发送（mock）");
  }

  function refreshPending(email) {
    const account = ACCOUNTS[view.account];
    const index = account.pending.findIndex((item) => eq(item, email));
    if (index < 0) return;
    account.pending.splice(index, 1);
    account.verified.push(email);
    view.selected = email;
    view.state = "custom";
    view.addOpen = false;
    view.confirming = false;
    view.error = "";
    view.notice = `目标邮箱 ${email} 已验证；本账号下所有域名都可复用（mock）。`;
    render(() => focusAddress(email));
    showToast("目标邮箱验证状态已刷新（mock）");
  }

  function refreshStatus() {
    view.notice = "邮箱转发状态已刷新（mock）。";
    view.error = "";
    render(() => root.querySelector('[data-action="refresh-status"]')?.focus());
    showToast("状态已刷新（mock）");
  }

  function applyComplete(d) {
    view.catchAll = d.target;
    view.mx = [];
    view.confirming = false;
    view.state = "custom";
    view.notice = `邮箱转发已配置到 ${d.target}（mock）。`;
    view.error = "";
    render(() => root.querySelector('[data-action="refresh-status"]')?.focus());
    showToast("邮箱转发已配置（mock）");
  }

  function complete() {
    const d = derive();
    if (!d.canComplete) {
      view.error = !d.targetVerified
        ? "目标邮箱尚未验证，不能启用转发。"
        : "域名未激活，不能启用转发。";
      view.notice = "";
      render();
      return;
    }
    if (view.confirming) return;
    if (view.mx.length > 0 || d.conflict) {
      view.confirming = true;
      view.notice = "";
      view.error = "";
      render(() => root.querySelector('[data-action="confirm-complete"]')?.focus());
      return;
    }
    applyComplete(d);
  }

  function cancelConfirm() {
    view.confirming = false;
    render(() => root.querySelector('[data-action="complete"]')?.focus());
  }

  function confirmComplete() {
    const d = derive();
    if (!d.canComplete) {
      view.confirming = false;
      view.error = "无法完成配置：目标邮箱未验证或域名未激活。";
      render();
      return;
    }
    applyComplete(d);
  }

  function showToast(message) {
    const region = document.querySelector("[data-toast-region]");
    if (!region) return;
    const toast = document.createElement("div");
    toast.className = "er-toast";
    toast.setAttribute("role", "status");
    toast.textContent = message;
    region.appendChild(toast);
    window.setTimeout(() => toast.remove(), 3200);
  }

  function clearToasts() {
    const region = document.querySelector("[data-toast-region]");
    if (region) region.innerHTML = "";
  }

  function bindRootEvents() {
    root.addEventListener("click", (event) => {
      const target = event.target.closest("[data-action]");
      if (!target) return;
      const action = target.dataset.action;
      if (action === "select-address") return;
      event.preventDefault();
      if (action === "toggle-add") toggleAdd();
      else if (action === "add-address") addAddress();
      else if (action === "cancel-add") cancelAdd();
      else if (action === "refresh-pending") refreshPending(target.dataset.email || "");
      else if (action === "refresh-status") refreshStatus();
      else if (action === "complete") complete();
      else if (action === "confirm-complete") confirmComplete();
      else if (action === "cancel-confirm") cancelConfirm();
      else if (action === "back") showToast("草稿不会跳转；正式页面会回到工作台。");
    });

    root.addEventListener("change", (event) => {
      const target = event.target;
      if (target.matches("[data-account-select]")) {
        setAccount(target.value);
      } else if (target.matches("[data-zone-select]")) {
        setZone(target.value);
      } else if (target.matches("[data-target-select]")) {
        selectAddress(target.value);
      } else if (target.matches('input[data-action="select-address"]')) {
        selectAddress(target.value);
      }
    });
  }

  function initStateSelect() {
    const select = document.querySelector("[data-state-select]");
    if (!select) return;
    select.innerHTML = STATE_OPTIONS.map(([value, label]) => {
      const disabled = value === "custom" ? " disabled" : "";
      return `<option value="${value}"${disabled}>${label}</option>`;
    }).join("");
    select.value = view.state;
    select.addEventListener("change", () => {
      if (select.value === "custom") return;
      clearToasts();
      ACCOUNTS = clone(BASE_ACCOUNTS);
      view = makeView(select.value);
      render();
    });
  }

  function initTheme() {
    let saved = "";
    try {
      saved = localStorage.getItem(THEME_KEY) || "";
    } catch {
      saved = "";
    }
    if (saved === "dark" || saved === "light") {
      document.documentElement.dataset.theme = saved;
    }
    const buttons = [...document.querySelectorAll("[data-theme-toggle]")];

    function sync() {
      const dark = document.documentElement.dataset.theme === "dark";
      buttons.forEach((button) => {
        button.textContent = dark ? "浅色" : "深色";
        button.setAttribute("aria-label", dark ? "切换到浅色主题" : "切换到深色主题");
      });
    }

    buttons.forEach((button) => {
      button.addEventListener("click", () => {
        const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
        document.documentElement.dataset.theme = next;
        try {
          localStorage.setItem(THEME_KEY, next);
        } catch {
          // Ignore storage failures in file:// previews.
        }
        sync();
      });
    });
    sync();
  }

  initTheme();

  const root = document.getElementById("prototype-root");
  if (!root) return;

  initStateSelect();
  bindRootEvents();
  render();
})();
