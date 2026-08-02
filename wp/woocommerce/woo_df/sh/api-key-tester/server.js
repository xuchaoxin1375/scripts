#!/usr/bin/env node
// KeyLens 本地后端：静态托管 + 服务器通道测试（绕开浏览器 CORS）
// 用法: node server.js [端口]   （默认 8899，仅监听 127.0.0.1）
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const PORT = parseInt(process.argv[2] || process.env.PORT || '8899', 10);
const DIR = __dirname;

function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*'
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let d = '';
    req.on('data', c => { d += c; if (d.length > 5e6) { req.destroy(new Error('请求体过大')); } });
    req.on('end', () => {
      if (!d.trim()) return resolve({});
      try { resolve(JSON.parse(d)); } catch (e) { reject(new Error('JSON 解析失败')); }
    });
    req.on('error', reject);
  });
}

function apiReq(url, opts = {}) {
  return new Promise((resolve, reject) => {
    let u;
    try { u = new URL(url); } catch (e) { return reject(new Error('无效地址: ' + url)); }
    const mod = u.protocol === 'http:' ? http : https;
    const req = mod.request({
      hostname: u.hostname,
      port: u.port || (u.protocol === 'http:' ? 80 : 443),
      path: u.pathname + u.search,
      method: opts.method || 'GET',
      headers: opts.headers || {}
    }, res => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.setTimeout(30000, () => req.destroy(new Error('请求超时(30s)')));
    req.on('error', reject);
    if (opts.body !== undefined) req.write(opts.body);
    req.end();
  });
}

function parseModels(body) {
  try {
    const j = JSON.parse(body);
    if (Array.isArray(j.data)) return j.data.map(m => m.id).filter(Boolean);
    if (Array.isArray(j.models)) return j.models.map(m => (m.name || '').replace(/^models\//, '')).filter(Boolean);
  } catch {}
  return [];
}

function extractError(body) {
  try {
    const j = JSON.parse(body);
    if (j.error) return typeof j.error === 'string' ? j.error : (j.error.message || j.error.type || j.error.code || '');
    if (j.message) return j.message;
  } catch {}
  return '';
}

async function runTest(cfg) {
  const { base, key, models, auth = 'bearer', chat = 'openai', extraHeaders = {} } = cfg;
  const out = { keyOk: false, modelsStatus: 0, modelIds: [], results: [], totalMs: 0, modelsError: '' };
  const t0 = Date.now();
  const headers = { 'Content-Type': 'application/json' };
  if (auth === 'bearer') headers['Authorization'] = 'Bearer ' + key;
  if (auth === 'x-api-key') { headers['x-api-key'] = key; Object.assign(headers, extraHeaders || {}); }
  const qk = auth === 'query-key' ? '?key=' + encodeURIComponent(key) : '';

  try {
    const m = await apiReq(base + '/models' + qk, { headers });
    out.modelsStatus = m.status;
    out.keyOk = m.status === 200;
    out.modelIds = m.status === 200 ? parseModels(m.body) : [];
    if (m.status !== 200) out.modelsError = extractError(m.body);
  } catch (e) { out.modelsError = e.message; }

  for (const model of models) {
    const r = { model, ok: false, ms: 0, status: 0, reply: '', error: '', raw: '' };
    const t1 = Date.now();
    try {
      let url, method = 'POST', hdrs, body;
      if (chat === 'anthropic') {
        url = base + '/messages';
        hdrs = headers;
        body = JSON.stringify({ model, max_tokens: 16, messages: [{ role: 'user', content: '请回复：收到' }] });
      } else if (chat === 'gemini') {
        url = base + '/models/' + encodeURIComponent(model) + ':generateContent' + qk;
        hdrs = { 'Content-Type': 'application/json' };
        body = JSON.stringify({ contents: [{ role: 'user', parts: [{ text: '请回复：收到' }] }] });
      } else {
        url = base + '/chat/completions';
        hdrs = headers;
        body = JSON.stringify({ model, messages: [{ role: 'user', content: '请回复：收到' }], max_tokens: 10 });
      }
      const resp = await apiReq(url, { method, headers: hdrs, body });
      r.status = resp.status;
      r.ms = Date.now() - t1;
      if (resp.status === 200) {
        const j = JSON.parse(resp.body);
        if (chat === 'anthropic') r.reply = j.content && j.content[0] ? j.content[0].text : '';
        else if (chat === 'gemini') r.reply = j.candidates && j.candidates[0] && j.candidates[0].content ? j.candidates[0].content.parts[0].text : '';
        else r.reply = j.choices && j.choices[0] ? j.choices[0].message.content : '';
        r.ok = true;
      } else {
        r.error = extractError(resp.body);
        r.raw = resp.body.slice(0, 600);
      }
    } catch (e) { r.error = e.message; r.ms = Date.now() - t1; }
    out.results.push(r);
  }
  out.totalMs = Date.now() - t0;
  return out;
}

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon', '.txt': 'text/plain; charset=utf-8'
};

function serveStatic(req, res) {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const file = path.join(DIR, path.normalize(p).replace(/^\.\.(\/|\\)?/, ''));
  if (!file.startsWith(DIR)) { res.writeHead(403); res.end('Forbidden'); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }); res.end('404 Not Found'); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream' });
    res.end(data);
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(204, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'POST, GET, OPTIONS' }); res.end(); return; }
  if (req.url === '/api/ping') return send(res, 200, { ok: true });
  if (req.url === '/api/test' && req.method === 'POST') {
    try {
      const cfg = await readBody(req);
      if (!cfg.base || !cfg.key) return send(res, 400, { error: '缺少 base 或 key' });
      const out = await runTest(cfg);
      return send(res, 200, out);
    } catch (e) { return send(res, 400, { error: e.message }); }
  }
  if (req.method === 'GET' || req.method === 'HEAD') return serveStatic(req, res);
  res.writeHead(405); res.end('Method Not Allowed');
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('----------------------------------------------');
  console.log('  KeyLens 本地服务已启动');
  console.log('  浏览器访问 : http://localhost:' + PORT);
  console.log('  停止      : Ctrl+C');
  console.log('----------------------------------------------');
});
