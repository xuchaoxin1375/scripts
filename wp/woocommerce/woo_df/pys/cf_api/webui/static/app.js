"use strict";
/* Cloudflare DNS 操作台前端：原生 JS，无构建。所有长列表统一客户端分页。 */

const $ = (id) => document.getElementById(id);
const PAGE_CAP = 100; // 单页最多渲染行数

const store = {
  token: sessionStorage.getItem("cf_token") || "",
  meta: null,
  accounts: [], // masked {name,auth,email,secret}
  zones: [], // {name,status}
  zonesAccount: "",
  records: [],
  previewRows: [],
  previewJob: null,
  jobs: [],
  activeJob: null,
  jobDetail: null,
  jobZones: [],
  logsLen: 0,
  resumePath: "",
  pendingDelete: null,
  pages: { accounts: 1, zones: 1, records: 1, preview: 1, jobZones: 1 },
};

function toast(msg) {
  const box = $("toast");
  const div = document.createElement("div");
  div.textContent = msg;
  box.appendChild(div);
  setTimeout(() => div.remove(), 4200);
}

function authHeaders(extra) {
  const h = Object.assign({}, extra || {});
  if (store.token) h["X-Auth-Token"] = store.token;
  return h;
}

async function api(path, opts) {
  opts = opts || {};
  const init = { method: opts.method || "GET", headers: authHeaders() };
  if (opts.body !== undefined) {
    init.headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(opts.body);
  }
  if (opts.form !== undefined) {
    init.body = opts.form; // FormData：浏览器自动设置 boundary
  }
  const resp = await fetch(path, init);
  if (resp.status === 401) {
    showLogin("口令无效或已过期，请重新登录");
    throw new Error("未授权（401）");
  }
  if (!resp.ok) {
    let detail = resp.statusText;
    try {
      const data = await resp.json();
      detail = data.detail || JSON.stringify(data);
    } catch (e) { /* 保持原文 */ }
    throw new Error(detail);
  }
  const ct = resp.headers.get("content-type") || "";
  if (ct.includes("application/json")) return resp.json();
  return resp.text();
}

/* ---------- 通用分页 ---------- */
function paginate(rows, page, size) {
  const total = rows.length;
  const pages = Math.max(1, Math.ceil(total / size));
  const p = Math.min(Math.max(1, page), pages);
  const start = (p - 1) * size;
  return { total, pages, page: p, slice: rows.slice(start, start + size) };
}

function renderPager(el, total, page, pages, onGoto) {
  el.innerHTML = "";
  const info = document.createElement("span");
  info.textContent = `共 ${total} 行 · 第 ${page}/${pages} 页（单页最多 ${PAGE_CAP} 行）`;
  const prev = document.createElement("button");
  prev.textContent = "上一页";
  prev.disabled = page <= 1;
  prev.onclick = () => onGoto(page - 1);
  const next = document.createElement("button");
  next.textContent = "下一页";
  next.disabled = page >= pages;
  next.onclick = () => onGoto(page + 1);
  el.append(info, prev, next);
}

function fillTable(tbodySel, rows, cols) {
  const tb = document.querySelector(tbodySel + " tbody");
  tb.innerHTML = "";
  const frag = document.createDocumentFragment();
  for (const r of rows) {
    const tr = document.createElement("tr");
    for (const c of cols) {
      const td = document.createElement("td");
      td.textContent = r[c] === undefined || r[c] === null ? "" : String(r[c]);
      tr.appendChild(td);
    }
    frag.appendChild(tr);
  }
  tb.appendChild(frag);
}

/* ---------- 登录 ---------- */
function showLogin(msg) {
  if (!store.meta || !store.meta.requires_auth) return;
  if (msg) $("login-err").textContent = msg;
  $("login-overlay").classList.add("show");
}
function hideLogin() {
  $("login-overlay").classList.remove("show");
  $("login-err").textContent = "";
}
function refreshAuthState() {
  const need = store.meta && store.meta.requires_auth;
  $("auth-state").textContent = !need ? "未设口令（仅本机）" : store.token ? "已登录" : "未登录";
  $("btn-auth").textContent = !need ? "无需登录" : store.token ? "退出" : "登录";
  $("btn-auth").disabled = !need;
}

/* ---------- 浏览 ---------- */
async function loadAccounts() {
  $("accounts-status").className = "status";
  $("accounts-status").textContent = "加载中…";
  try {
    const data = await api("/api/accounts");
    store.accounts = data.accounts || [];
    store.pages.accounts = 1;
    renderAccounts();
    syncAccountSelectors();
    $("accounts-status").className = "status ok";
    $("accounts-status").textContent = `已加载 ${store.accounts.length} 个账号`;
  } catch (e) {
    $("accounts-status").className = "status err";
    $("accounts-status").textContent = `加载失败：${e.message}`;
  }
}

function renderAccounts() {
  const size = PAGE_CAP;
  const pg = paginate(store.accounts, store.pages.accounts, size);
  store.pages.accounts = pg.page;
  fillTable("#accounts-table", pg.slice, ["name", "auth", "email", "secret"]);
  $("accounts-count").textContent = `（共 ${pg.total} 个）`;
  renderPager($("accounts-pager"), pg.total, pg.page, pg.pages, (p) => {
    store.pages.accounts = p;
    renderAccounts();
  });
}

function syncAccountSelectors() {
  const names = store.accounts.map((a) => a.name);
  const za = $("zone-account");
  const cur = za.value;
  za.innerHTML = "";
  for (const n of names) {
    const o = document.createElement("option");
    o.value = n;
    o.textContent = n;
    za.appendChild(o);
  }
  if (names.includes(cur)) za.value = cur;
  renderOperateAccountList();
}

async function loadZones() {
  const account = $("zone-account").value;
  if (!account) { toast("请先加载账号"); return; }
  $("zones-status").className = "status";
  $("zones-status").textContent = "加载中…";
  try {
    const data = await api(`/api/zones?account=${encodeURIComponent(account)}`);
    store.zones = data.zones || [];
    store.zonesAccount = account;
    store.pages.zones = 1;
    const dl = $("zone-datalist");
    dl.innerHTML = "";
    for (const z of store.zones.slice(0, 500)) {
      const o = document.createElement("option");
      o.value = z.name;
      dl.appendChild(o);
    }
    renderZones();
    $("zones-status").className = "status ok";
    $("zones-status").textContent = `账号 ${account} 共 ${data.total} 个域名`;
  } catch (e) {
    $("zones-status").className = "status err";
    $("zones-status").textContent = `加载失败：${e.message}`;
  }
}

function filteredZones() {
  const kw = ($("zone-filter").value || "").trim().toLowerCase();
  if (!kw) return store.zones;
  return store.zones.filter((z) => (z.name || "").toLowerCase().includes(kw));
}

function renderZones() {
  const size = parseInt($("zone-size").value, 10) || 50;
  const rows = filteredZones();
  const pg = paginate(rows, store.pages.zones, Math.min(size, PAGE_CAP));
  store.pages.zones = pg.page;
  fillTable("#zones-table", pg.slice, ["name", "status"]);
  renderPager($("zones-pager"), pg.total, pg.page, pg.pages, (p) => {
    store.pages.zones = p;
    renderZones();
  });
}

async function loadRecords() {
  const account = $("zone-account").value;
  const zone = ($("record-zone").value || "").trim();
  if (!account || !zone) { toast("请选择账号并填写域名"); return; }
  $("records-status").className = "status";
  $("records-status").textContent = "加载中…";
  try {
    const data = await api(
      `/api/records?account=${encodeURIComponent(account)}&zone=${encodeURIComponent(zone)}`
    );
    store.records = data.records || [];
    store.pages.records = 1;
    renderRecords();
    const extra = data.truncated ? "（服务端截断前 2000 条）" : "";
    $("records-status").className = "status ok";
    $("records-status").textContent = `共 ${data.total} 条记录${extra}`;
  } catch (e) {
    $("records-status").className = "status err";
    $("records-status").textContent = `加载失败：${e.message}`;
  }
}

function renderRecords() {
  const size = parseInt($("record-size").value, 10) || 50;
  const kw = ($("record-filter").value || "").trim().toLowerCase();
  let rows = store.records;
  if (kw) {
    rows = rows.filter((r) =>
      `${r.type || ""} ${r.name || ""} ${r.content || ""}`.toLowerCase().includes(kw)
    );
  }
  const pg = paginate(rows, store.pages.records, Math.min(size, PAGE_CAP));
  store.pages.records = pg.page;
  const mapped = pg.slice.map((r) => ({
    type: r.type, name: r.name, content: r.content, ttl: r.ttl,
    proxied: r.proxied ? "开" : "关",
  }));
  fillTable("#records-table", mapped, ["type", "name", "content", "ttl", "proxied"]);
  renderPager($("records-pager"), pg.total, pg.page, pg.pages, (p) => {
    store.pages.records = p;
    renderRecords();
  });
}

/* ---------- 操作 ---------- */
function currentMode() {
  const el = document.querySelector('input[name="mode"]:checked');
  return el ? el.value : "update";
}

function refreshModeFields() {
  const m = currentMode();
  for (const name of ["update", "delete_ip", "delete_zone", "set_attrs", "export"]) {
    $("fields-" + name).hidden = m !== name && !(name === "update" && m === "delete_wildcard");
  }
  refreshSpeedResolved();
}

function refreshSpeedResolved() {
  const speeds = (store.meta && store.meta.speeds) || {};
  const v = $("f-speed").value;
  const p = speeds[v];
  $("speed-resolved").textContent = p
    ? `档位解析：账号并发 ${p.account_workers}，单账号内并发 ${p.workers}，请求间隔 ${p.request_interval}s`
    : "未知档位";
}

function renderOperateAccountList() {
  const kw = ($("acct-search").value || "").trim().toLowerCase();
  const box = $("acct-list");
  box.innerHTML = "";
  const prev = new Set(
    Array.from(box.querySelectorAll("input:checked")).map((i) => i.value)
  );
  const frag = document.createDocumentFragment();
  let shown = 0;
  for (const a of store.accounts) {
    if (kw && !(a.name || "").toLowerCase().includes(kw)) continue;
    if (shown >= 500) break;
    shown += 1;
    const label = document.createElement("label");
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.value = a.name;
    cb.checked = prev.has(a.name);
    cb.onchange = updatePicked;
    const sp = document.createElement("span");
    sp.textContent = `${a.name}（${a.auth || ""}）`;
    label.append(cb, sp);
    frag.appendChild(label);
  }
  box.appendChild(frag);
  if (store.accounts.length > 500) {
    const hint = document.createElement("div");
    hint.className = "hint";
    hint.textContent = "账号过多，仅展示前 500 个，请用搜索过滤。";
    box.appendChild(hint);
  }
  updatePicked();
}

function pickedAccounts() {
  return Array.from(document.querySelectorAll("#acct-list input:checked")).map((i) => i.value);
}

function updatePicked() {
  const n = pickedAccounts().length;
  $("acct-picked").textContent = n ? `已选 ${n} 个` : "未选择";
}

function parseLines(id) {
  return ($(id).value || "").split("\n").map((s) => s.trim()).filter(Boolean);
}

function buildSubmit(dryRun) {
  const accounts = pickedAccounts();
  if (!accounts.length) { toast("请先选择执行账号"); return null; }
  const mode = currentMode();
  const ttlRaw = ($("f-ttl").value || "").trim();
  let ttl = null;
  if (ttlRaw) {
    ttl = parseInt(ttlRaw, 10);
    if (!Number.isInteger(ttl) || ttl < 1) { toast("TTL 必须为正整数（1=自动）"); return null; }
  }
  const body = {
    mode, accounts, dry_run: dryRun,
    record_type: $("f-type").value || "auto",
    old_content: ($("f-old").value || "").trim() || null,
    new_content: ($("f-new").value || "").trim() || null,
    delete_ip: ($("f-delip").value || "").trim() || null,
    delete_zone_mode: $("f-zonemode").value || "dns",
    set_proxied: $("f-proxied").value || null,
    set_ttl: ttl,
    include_subdomains: $("f-sub").checked,
    whitelist: parseLines("f-whitelist"),
    whitelist_file: ($("f-whitelist-file").value || "").trim() || null,
    domains: parseLines("f-domains"),
    resume_csv: store.resumePath || null,
    backup_dir: ($("f-backup").value || "").trim() || (store.meta.defaults.backup_dir) || null,
    export_fmt: $("f-fmt").value || "json",
    export_dir: ($("f-exportdir").value || "").trim() || store.meta.defaults.export_dir,
    speed: $("f-speed").value || "eco",
    scope: $("f-scope").value || "account",
    max_retries: parseInt($("f-retries").value, 10) || 5,
  };
  if (mode === "update" && !body.new_content) { toast("更新模式必须填写新内容"); return null; }
  if (mode === "delete_ip" && !body.delete_ip) { toast("删除 IP 模式必须填写目标 IP"); return null; }
  if (mode === "set_attrs" && !body.set_proxied && body.set_ttl === null) {
    toast("属性设置至少选择代理状态或填写 TTL"); return null;
  }
  return body;
}

async function submitJob(dryRun) {
  if (!store.meta) return;
  const body = buildSubmit(dryRun);
  if (!body) return;
  if (!dryRun && body.mode === "delete_zone") {
    store.pendingDelete = body;
    const full = body.delete_zone_mode === "full";
    $("delete-summary").textContent =
      `影响账号：${body.accounts.join(", ")}；模式：${full ? "full（彻底删除域名）" : "dns（仅清空记录）"}；快照目录：${body.backup_dir}`;
    $("delete-confirm").value = "";
    $("delete-confirm-card").hidden = false;
    $("delete-confirm-card").scrollIntoView({ behavior: "smooth", block: "center" });
    return;
  }
  await doSubmit(body);
}

async function doSubmit(body) {
  $("op-status").className = "status";
  $("op-status").textContent = "提交中…";
  try {
    const data = await api("/api/jobs", { method: "POST", body });
    $("op-status").className = "status ok";
    $("op-status").textContent = `已提交 ${data.job_id}，下方查看结果`;
    store.previewJob = data.job_id;
    store.activeJob = data.job_id;
    pollPreview(data.job_id);
    switchTab("jobs");
    refreshJobs();
  } catch (e) {
    $("op-status").className = "status err";
    $("op-status").textContent = `提交失败：${e.message}`;
  }
}

async function pollPreview(jobId) {
  for (;;) {
    await new Promise((r) => setTimeout(r, 1500));
    if (store.previewJob !== jobId) return;
    try {
      const d = await api(`/api/jobs/${encodeURIComponent(jobId)}`);
      if (["done", "failed", "cancelled"].includes(d.status)) {
        await loadPreviewResults(jobId);
        return;
      }
    } catch (e) { return; }
  }
}

async function loadPreviewResults(jobId) {
  try {
    const data = await api(`/api/jobs/${encodeURIComponent(jobId)}/results?limit=500`);
    store.previewRows = data.results || [];
    store.pages.preview = 1;
    renderPreview();
    switchTab("operate");
  } catch (e) {
    toast(`加载结果失败：${e.message}`);
  }
}

function renderPreview() {
  const size = parseInt($("preview-size").value, 10) || 50;
  const kw = ($("preview-filter").value || "").trim().toLowerCase();
  let rows = store.previewRows;
  if (kw) {
    rows = rows.filter((r) =>
      `${r.account || ""} ${r.zone || ""} ${r.status || ""} ${r.name || ""}`.toLowerCase().includes(kw)
    );
  }
  const pg = paginate(rows, store.pages.preview, Math.min(size, PAGE_CAP));
  store.pages.preview = pg.page;
  const mapped = pg.slice.map((r) => ({
    account: r.account, zone: r.zone, type: r.type, name: r.name,
    old: r.old, new: r.new, status: r.status,
  }));
  fillTable("#preview-table", mapped, ["account", "zone", "type", "name", "old", "new", "status"]);
  $("preview-count").textContent = `（共 ${rows.length} 行）`;
  renderPager($("preview-pager"), pg.total, pg.page, pg.pages, (p) => {
    store.pages.preview = p;
    renderPreview();
  });
}

async function uploadResume(file) {
  const fd = new FormData();
  fd.append("file", file);
  try {
    const data = await api("/api/resume-upload", { method: "POST", form: fd });
    store.resumePath = data.path;
    $("resume-status").textContent = `重跑清单：${data.rows} 行（服务端路径已记录）`;
    toast(`已载入重跑清单 ${data.rows} 行`);
  } catch (e) {
    toast(`重跑清单上传失败：${e.message}`);
  }
}

/* ---------- 任务 ---------- */
async function refreshJobs() {
  try {
    const data = await api("/api/jobs");
    store.jobs = data.jobs || [];
    renderJobsTable();
    if (store.activeJob) pollJobDetail();
  } catch (e) {
    toast(`刷新任务失败：${e.message}`);
  }
}

function renderJobsTable() {
  const tb = document.querySelector("#jobs-table tbody");
  tb.innerHTML = "";
  const frag = document.createDocumentFragment();
  for (const j of store.jobs.slice(0, 100)) {
    const tr = document.createElement("tr");
    if (j.id === store.activeJob) tr.style.background = "#eff5ff";
    const cells = [
      j.id, j.label, j.status,
      `${j.accounts_done}/${j.accounts_total}`,
      String(j.failure_count),
    ];
    for (const c of cells) {
      const td = document.createElement("td");
      td.textContent = c;
      tr.appendChild(td);
    }
    const op = document.createElement("td");
    const view = document.createElement("button");
    view.textContent = "查看";
    view.onclick = () => { store.activeJob = j.id; store.logsLen = 0; $("job-logs").textContent = ""; pollJobDetail(); };
    const cancel = document.createElement("button");
    cancel.textContent = "取消";
    cancel.style.marginLeft = "6px";
    cancel.onclick = async () => {
      try {
        await api(`/api/jobs/${encodeURIComponent(j.id)}/cancel`, { method: "POST" });
        toast(`已请求取消 ${j.id}`);
      } catch (e) { toast(`取消失败：${e.message}`); }
    };
    op.append(view, cancel);
    tr.appendChild(op);
    tr.style.cursor = "pointer";
    tr.ondblclick = () => { store.activeJob = j.id; store.logsLen = 0; $("job-logs").textContent = ""; pollJobDetail(); };
    frag.appendChild(tr);
  }
  tb.appendChild(frag);
}

async function pollJobDetail() {
  const id = store.activeJob;
  if (!id) return;
  try {
    const d = await api(`/api/jobs/${encodeURIComponent(id)}`);
    store.jobDetail = d;
    renderJobDetail();
    const logs = await api(`/api/jobs/${encodeURIComponent(id)}/logs?offset=${store.logsLen}`);
    if (logs.logs && logs.logs.length) {
      const pre = $("job-logs");
      pre.textContent += logs.logs.join("\n") + "\n";
      store.logsLen = logs.total;
      if ($("log-follow").checked) pre.scrollTop = pre.scrollHeight;
    }
    const sel = $("job-zone-account").value || d.current_account;
    if (sel) await loadJobZones(sel);
  } catch (e) {
    toast(`任务查询失败：${e.message}`);
  }
}

function renderJobDetail() {
  const d = store.jobDetail;
  if (!d) return;
  $("job-title").textContent = `${d.id} ${d.label}`;
  const total = Math.max(1, d.accounts_total);
  $("job-bar").style.width = `${Math.min(100, (d.accounts_done / total) * 100)}%`;
  $("job-detail").textContent =
    `状态=${d.status} 账号 ${d.accounts_done}/${d.accounts_total} 当前 ${d.current_account || "-"} 结果 ${d.result_count} 未完成 ${d.failure_count}`;
  const v = $("job-verdict");
  const lines = (d.verdict || []).slice(-3).join("\n") || "进行中…";
  v.textContent = lines;
  v.className = "verdict" + (d.status === "done" && d.exit_code === 0 ? " ok" : d.status === "failed" ? " bad" : "");
  const box = $("job-accounts");
  box.innerHTML = "";
  const frag = document.createDocumentFragment();
  for (const acc of Object.keys(d.account_status || {})) {
    const sum = (d.zone_summary || {})[acc] || {};
    const card = document.createElement("div");
    card.className = "acctcard";
    const nm = document.createElement("div");
    nm.className = "nm";
    nm.textContent = acc;
    const st = document.createElement("div");
    st.className = "st";
    st.textContent = `${d.account_status[acc]} · 域名 ${sum.done || 0}/${sum.total || 0}`;
    const bar = document.createElement("div");
    bar.className = "bar";
    const fill = document.createElement("i");
    const t = Math.max(1, sum.total || 0);
    fill.style.width = `${Math.min(100, ((sum.done || 0) / t) * 100)}%`;
    bar.appendChild(fill);
    card.append(nm, st, bar);
    frag.appendChild(card);
  }
  box.appendChild(frag);
  const sel = $("job-zone-account");
  const cur = sel.value;
  sel.innerHTML = "";
  for (const acc of Object.keys(d.account_status || {})) {
    const o = document.createElement("option");
    o.value = acc;
    o.textContent = acc;
    sel.appendChild(o);
  }
  if (cur && d.account_status[cur]) sel.value = cur;
  else if (d.current_account) sel.value = d.current_account;
  renderJobsTable();
}

async function loadJobZones(account) {
  const id = store.activeJob;
  if (!id || !account) return;
  try {
    const data = await api(
      `/api/jobs/${encodeURIComponent(id)}/zones?account=${encodeURIComponent(account)}`
    );
    store.jobZones = data.rows || [];
    store.pages.jobZones = 1;
    renderJobZones(data.total || store.jobZones.length);
  } catch (e) { /* 任务进行中域名明细可能为空 */ }
}

function renderJobZones(total) {
  const stateF = $("job-zone-state").value;
  const kw = ($("job-zone-filter").value || "").trim().toLowerCase();
  let rows = store.jobZones;
  if (stateF) rows = rows.filter((r) => r.state === stateF);
  if (kw) rows = rows.filter((r) => (r.zone || "").toLowerCase().includes(kw));
  const done = store.jobZones.filter((r) => ["done", "error"].includes(r.state)).length;
  const t = Math.max(1, total || store.jobZones.length);
  $("zone-bar").style.width = `${Math.min(100, (done / t) * 100)}%`;
  $("zone-title").textContent = `${$("job-zone-account").value || ""}：${done}/${total || store.jobZones.length}`;
  const pg = paginate(rows, store.pages.jobZones, PAGE_CAP);
  store.pages.jobZones = pg.page;
  fillTable("#job-zones-table", pg.slice, ["zone", "state"]);
  renderPager($("job-zones-pager"), pg.total, pg.page, pg.pages, (p) => {
    store.pages.jobZones = p;
    renderJobZones(total);
  });
}

async function downloadFailures() {
  const id = store.activeJob;
  if (!id) { toast("请先选择任务"); return; }
  try {
    const resp = await fetch(`/api/jobs/${encodeURIComponent(id)}/failures.csv`, {
      headers: authHeaders(),
    });
    if (!resp.ok) throw new Error(resp.status === 404 ? "该任务无失败清单" : resp.statusText);
    const blob = await resp.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `failures_${id}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  } catch (e) {
    toast(`下载失败：${e.message}`);
  }
}

/* ---------- 页签 / 初始化 ---------- */
function switchTab(name) {
  for (const b of document.querySelectorAll(".tabs button")) {
    b.classList.toggle("active", b.dataset.tab === name);
  }
  for (const s of document.querySelectorAll(".tabpage")) {
    s.classList.toggle("active", s.id === "tab-" + name);
  }
  if (name === "jobs") refreshJobs();
}

async function initMeta() {
  const data = await api("/api/meta");
  store.meta = data;
  $("preset-line").textContent = `预设：${data.config_path || "（空）"}`;
  $("config-path").value = data.config_path || "";
  $("config-preset-hint").textContent = `预设路径（与 CLI -C 同源）：${data.preset_path || "（空）"}；快照/导出默认派生自该文件所在目录。`;
  $("f-backup").placeholder = `默认 ${data.defaults.backup_dir}`;
  $("f-exportdir").value = data.defaults.export_dir;
  $("f-speed").value = data.defaults.speed || "eco";
  $("f-scope").value = data.defaults.scope || "account";
  $("f-retries").value = data.defaults.max_retries ?? 5;
  const sp = $("f-speed");
  sp.innerHTML = "";
  for (const k of Object.keys(data.speeds || { eco: 1 })) {
    const o = document.createElement("option");
    o.value = k;
    o.textContent = k;
    sp.appendChild(o);
  }
  sp.value = data.defaults.speed || "eco";
  refreshSpeedResolved();
  refreshAuthState();
  if (data.requires_auth && !store.token) showLogin("");
  else hideLogin();
}

function bind() {
  for (const b of document.querySelectorAll(".tabs button")) {
    b.onclick = () => switchTab(b.dataset.tab);
  }
  $("btn-auth").onclick = () => {
    if (store.token) {
      store.token = "";
      sessionStorage.removeItem("cf_token");
      refreshAuthState();
      showLogin("");
    } else showLogin("");
  };
  $("btn-login").onclick = () => {
    const v = ($("login-pw").value || "").trim();
    if (!v) { $("login-err").textContent = "请输入口令"; return; }
    store.token = v;
    sessionStorage.setItem("cf_token", v);
    $("login-pw").value = "";
    hideLogin();
    refreshAuthState();
    initMeta().then(loadAccounts).catch((e) => toast(e.message));
  };
  $("btn-load-accounts").onclick = async () => {
    const p = ($("config-path").value || "").trim();
    try {
      if (p && p !== (store.meta && store.meta.config_path)) {
        await api("/api/config", { method: "POST", body: { path: p } });
        await initMeta();
      }
      await loadAccounts();
    } catch (e) {
      $("accounts-status").className = "status err";
      $("accounts-status").textContent = `切换配置失败：${e.message}`;
    }
  };
  $("btn-load-zones").onclick = loadZones;
  $("btn-load-records").onclick = loadRecords;
  $("zone-filter").oninput = () => { store.pages.zones = 1; renderZones(); };
  $("zone-size").onchange = () => { store.pages.zones = 1; renderZones(); };
  $("record-filter").oninput = () => { store.pages.records = 1; renderRecords(); };
  $("record-size").onchange = () => { store.pages.records = 1; renderRecords(); };
  $("acct-search").oninput = renderOperateAccountList;
  $("acct-all").onclick = () => {
    document.querySelectorAll("#acct-list input").forEach((i) => { i.checked = true; });
    updatePicked();
  };
  $("acct-none").onclick = () => {
    document.querySelectorAll("#acct-list input").forEach((i) => { i.checked = false; });
    updatePicked();
  };
  for (const r of document.querySelectorAll('input[name="mode"]')) {
    r.onchange = refreshModeFields;
  }
  $("f-speed").onchange = refreshSpeedResolved;
  $("preview-filter").oninput = () => { store.pages.preview = 1; renderPreview(); };
  $("preview-size").onchange = () => { store.pages.preview = 1; renderPreview(); };
  $("f-resume").onchange = (e) => {
    const f = e.target.files && e.target.files[0];
    if (f) uploadResume(f);
  };
  $("btn-preview").onclick = () => submitJob(true);
  $("btn-exec").onclick = () => submitJob(false);
  $("btn-delete-yes").onclick = async () => {
    if (($("delete-confirm").value || "").trim() !== "DELETE") {
      toast("确认口令不符，已取消");
      return;
    }
    const body = store.pendingDelete;
    store.pendingDelete = null;
    $("delete-confirm-card").hidden = true;
    if (body) await doSubmit(body);
  };
  $("btn-delete-no").onclick = () => {
    store.pendingDelete = null;
    $("delete-confirm-card").hidden = true;
  };
  $("btn-jobs-refresh").onclick = refreshJobs;
  $("btn-job-cancel").onclick = async () => {
    if (!store.activeJob) { toast("请先选择任务"); return; }
    try {
      await api(`/api/jobs/${encodeURIComponent(store.activeJob)}/cancel`, { method: "POST" });
      toast("已请求取消");
    } catch (e) { toast(`取消失败：${e.message}`); }
  };
  $("btn-job-csv").onclick = downloadFailures;
  $("job-zone-account").onchange = () => { store.pages.jobZones = 1; loadJobZones($("job-zone-account").value); };
  $("job-zone-state").onchange = () => { store.pages.jobZones = 1; renderJobZones(); };
  $("job-zone-filter").oninput = () => { store.pages.jobZones = 1; renderJobZones(); };
  setInterval(() => {
    if (document.querySelector("#tab-jobs").classList.contains("active") && store.activeJob) {
      pollJobDetail();
    }
    if (document.querySelector("#tab-jobs").classList.contains("active")) refreshJobsQuiet();
  }, 2000);
}

async function refreshJobsQuiet() {
  try {
    const data = await api("/api/jobs");
    store.jobs = data.jobs || [];
    renderJobsTable();
  } catch (e) { /* 轮询失败不打扰 */ }
}

document.addEventListener("DOMContentLoaded", async () => {
  bind();
  refreshModeFields();
  try {
    await initMeta();
    await loadAccounts(); // 预设自动加载一次，对齐 CLI 默认
  } catch (e) {
    toast(`初始化失败：${e.message}`);
    showLogin("");
  }
});
