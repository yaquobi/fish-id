// حوات ميل: كل إيميلات حوات (Google Workspace / Gmail) في تطبيق واحد على الجوال والكمبيوتر.
// يتصل بكل حساب عن طريق IMAP (كلمة مرور تطبيقات من Google)، يراقب البريد الوارد لحظيًا (IDLE)،
// ويرسل إشعار للجوال (Web Push). الدخول برمز يوصل على تلقرام المالك.
// يشتغل خلف nginx على https://hawat.id/mail/ (nginx يشيل /mail من بداية الرابط).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { ImapFlow } from 'imapflow';
import { simpleParser } from 'mailparser';
import nodemailer from 'nodemailer';
import webpush from 'web-push';

const PORT = Number(process.env.PORT || 8095);
const DATA = process.env.MAIL_DATA || '/data';
const PUBLIC = path.join(path.dirname(new URL(import.meta.url).pathname), 'public');
const TG_TOKEN = process.env.FISHID_TELEGRAM_TOKEN || '';
const TG_CHAT = process.env.FISHID_TELEGRAM_CHAT || '';
const BASE = '/mail';
const CFG_FILE = path.join(DATA, 'config.json');
let LOCAL_TOKEN = '';
try { LOCAL_TOKEN = fs.readFileSync(path.join(DATA, 'local-token'), 'utf8').trim(); } catch {}
const PER_ACCOUNT = 60; // آخر كم رسالة من كل صندوق وارد نعرضها

// ---------- الإعدادات (ملف واحد على السيرفر، للمالك فقط) ----------
fs.mkdirSync(DATA, { recursive: true });
let cfg = { accounts: [], subs: [], sessions: {} };
try { cfg = { ...cfg, ...JSON.parse(fs.readFileSync(CFG_FILE, 'utf8')) }; } catch {}
if (!cfg.vapid) cfg.vapid = webpush.generateVAPIDKeys();
function save() {
  const tmp = CFG_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(cfg, null, 1), { mode: 0o600 });
  fs.renameSync(tmp, CFG_FILE);
}
save();
webpush.setVapidDetails('mailto:info@hawat.id', cfg.vapid.publicKey, cfg.vapid.privateKey);

const COLORS = ['#F2C14E', '#4FA3E0', '#6CC59A', '#E07B6C', '#B48CE0', '#E0A84F'];
const pub = (a) => ({ id: a.id, email: a.email, name: a.name, color: a.color, aliases: a.aliases || [] });

// ---------- الدخول برمز تلقرام ----------
const login = { code: null, until: 0, tries: 0, last: 0 };
async function telegram(text) {
  if (!TG_TOKEN || !TG_CHAT) throw new Error('تلقرام غير مربوط');
  const r = await fetch(`https://api.telegram.org/bot${TG_TOKEN}/sendMessage`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ chat_id: TG_CHAT, text }),
  });
  if (!r.ok) throw new Error('تعذّر الإرسال لتلقرام');
}
function cookieToken(req) {
  const m = /(?:^|;\s*)hm=([a-f0-9]{64})/.exec(req.headers.cookie || '');
  return m && cfg.sessions[m[1]] ? m[1] : null;
}

// ---------- IMAP: اتصال دائم لكل حساب يراقب الوارد ----------
const live = new Map(); // id -> { client, list, status, error }
// ربط بدون كلمات مرور: حساب خدمة Google بتفويض على مستوى النطاق (Domain-wide delegation)،
// المفتاح الخاص يتولّد على السيرفر نفسه (data/mail/sa-key.pem) وما يطلع منه، والمفتاح العام بس ينرفع لـ Google.
const SA_FILE = path.join(DATA, 'sa.json'), SA_KEY = path.join(DATA, 'sa-key.pem');
const saInfo = () => { try { return { ...JSON.parse(fs.readFileSync(SA_FILE, 'utf8')), key: fs.readFileSync(SA_KEY, 'utf8') }; } catch { return null; } };
const tokens = new Map(); // email -> { token, exp }
async function googleToken(email) {
  const t = tokens.get(email);
  if (t && t.exp > Date.now() + 120000) return t.token;
  const sa = saInfo();
  if (!sa?.client_email) throw new Error('حساب خدمة Google غير مجهّز');
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: 'RS256', typ: 'JWT', ...(sa.key_id ? { kid: sa.key_id } : {}) });
  const body = b64({ iss: sa.client_email, sub: email, scope: 'https://mail.google.com/', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 });
  const sig = crypto.sign('RSA-SHA256', Buffer.from(`${head}.${body}`), sa.key).toString('base64url');
  const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${head}.${body}.${sig}` }) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) throw new Error('Google رفض الربط: ' + (j.error_description || j.error || r.status) + ' (تأكد من التفويض في لوحة المدير)');
  tokens.set(email, { token: j.access_token, exp: Date.now() + (j.expires_in || 3600) * 1000 });
  return j.access_token;
}
const authOf = async (a) => (a.google ? { user: a.email, accessToken: await googleToken(a.email) } : { user: a.email, pass: a.pass });
const imapOpts = async (a) => ({ host: 'imap.gmail.com', port: 993, secure: true, auth: await authOf(a), logger: false, emitLogs: false });

function envelopeRow(a, m) {
  const f = m.envelope?.from?.[0] || {};
  return {
    acc: a.id, uid: m.uid, date: (m.internalDate || m.envelope?.date || new Date()).toISOString(),
    from: f.name || f.address || '', fromAddr: f.address || '',
    to: (m.envelope?.to || []).map((x) => x.address).join(', '),
    toName: (m.envelope?.to || []).map((x) => x.name || x.address).join('، '),
    subject: m.envelope?.subject || '(بدون عنوان)',
    seen: m.flags?.has('\\Seen') || false, starred: m.flags?.has('\\Flagged') || false,
    att: hasAtt(m.bodyStructure),
  };
}

async function loadInbox(st, a) {
  const c = st.client;
  const lock = await c.getMailboxLock('INBOX');
  try {
    const total = c.mailbox.exists;
    const rows = [];
    if (total > 0) {
      const from = Math.max(1, total - PER_ACCOUNT + 1);
      for await (const m of c.fetch(`${from}:*`, { uid: true, envelope: true, flags: true, internalDate: true, bodyStructure: true })) {
        rows.push(envelopeRow(a, m));
      }
    }
    return rows;
  } finally { lock.release(); }
}

async function notifyNew(a, rows) {
  if (!rows.length || !cfg.subs.length) return;
  const n = rows.length;
  const r = rows[rows.length - 1];
  const payload = JSON.stringify({
    title: n === 1 ? (r.from || r.fromAddr) : `${n} رسائل جديدة`,
    body: n === 1 ? `${r.subject}\n${a.email}` : `${a.email}`,
    url: `${BASE}/#/inbox/m/${a.id}/inbox/${r.uid}`, tag: `${a.id}-${r.uid}`,
  });
  const dead = [];
  await Promise.all(cfg.subs.map((s) => webpush.sendNotification(s, payload, { TTL: 3600 }).catch((e) => {
    if (e.statusCode === 404 || e.statusCode === 410) dead.push(s.endpoint);
  })));
  if (dead.length) { cfg.subs = cfg.subs.filter((s) => !dead.includes(s.endpoint)); save(); }
}

async function refresh(a, { notify = false } = {}) {
  const st = live.get(a.id);
  if (!st?.client?.usable) return;
  const before = new Set((st.list || []).map((r) => r.uid));
  const maxUid = Math.max(0, ...before);
  const rows = await loadInbox(st, a);
  const sig = (l) => l.map((r) => `${r.uid}${r.seen ? 's' : ''}${r.starred ? '*' : ''}`).join(',');
  const changed = sig(st.list || []) !== sig(rows);
  st.list = rows;
  const fresh = rows.filter((r) => !before.has(r.uid) && r.uid > maxUid && !r.seen);
  if (changed) broadcast({ t: 'inbox', acc: a.id, n: fresh.length });
  if (notify && st.ready) await notifyNew(a, fresh);
  st.ready = true;
  prefetch(a).catch(() => {});
}

async function connect(a) {
  const old = live.get(a.id);
  if (old?.timer) clearTimeout(old.timer);
  const st = { client: null, list: old?.list || [], status: 'connecting', error: null, ready: old?.ready || false };
  live.set(a.id, st);
  let opts;
  try { opts = await imapOpts(a); } catch (e) {
    st.status = 'error'; st.error = String(e.message || e);
    st.timer = setTimeout(() => connect(a).catch(() => {}), 60000);
    return;
  }
  const c = new ImapFlow(opts);
  st.client = c;
  let debounce;
  c.on('exists', () => { clearTimeout(debounce); debounce = setTimeout(() => refresh(a, { notify: true }).catch(() => {}), 800); });
  c.on('flags', () => { clearTimeout(debounce); debounce = setTimeout(() => refresh(a).catch(() => {}), 800); });
  c.on('error', (e) => { st.error = String(e.message || e); });
  c.on('close', () => {
    st.status = 'closed';
    if (!cfg.accounts.find((x) => x.id === a.id)) return; // انحذف الحساب
    st.timer = setTimeout(() => connect(a).catch(() => {}), 15000);
  });
  try {
    await c.connect();
    await c.mailboxOpen('INBOX');
    st.status = 'ok'; st.error = null;
    worker(a, 'fg').catch(() => {}); worker(a, 'bg').catch(() => {}); // نجهّز الاتصالين من البداية
    await refresh(a);
  } catch (e) {
    st.status = 'error'; st.error = e.authenticationFailed ? 'كلمة المرور غير صحيحة' : String(e.message || e);
    try { c.close(); } catch {}
  }
}
cfg.accounts.forEach((a) => connect(a).catch(() => {}));
// احتياط: تحديث كل دقيقتين لو فات حدث من IDLE.
setInterval(() => cfg.accounts.forEach((a) => refresh(a, { notify: true }).catch(() => {})), 120000);

// أوامر منفصلة (قراءة رسالة، نقل، حذف) باتصال قصير عشان ما نوقف المراقبة.
// اتصال ثاني دائم لكل حساب للأوامر (فتح رسالة، نقل…) عشان ما ننتظر تسجيل دخول جديد كل مرة.
// اتصالين لكل حساب: "fg" لطلبات المستخدم، و"bg" للتجهيز المسبق، عشان ضغطتك ما تنتظر خلف التجهيز.
const workers = new Map(); // "id:kind" -> Promise<ImapFlow>
async function worker(a, kind = 'fg') {
  const k = `${a.id}:${kind}`;
  let p = workers.get(k);
  if (p) { const c = await p.catch(() => null); if (c?.usable) return c; workers.delete(k); }
  p = (async () => {
    const c = new ImapFlow(await imapOpts(a));
    c.on('error', () => {}); c.on('close', () => { if (workers.get(k) === p) workers.delete(k); });
    await c.connect();
    return c;
  })();
  workers.set(k, p);
  p.catch(() => workers.delete(k));
  return p;
}
async function withImap(a, fn, kind = 'fg') {
  try { return await fn(await worker(a, kind)); }
  catch (e) {
    // انقطع الاتصال؟ نجرب مرة ثانية باتصال جديد
    if (!/closed|ECONN|EPIPE|timeout|Connection not available/i.test(String(e.message || e))) throw e;
    workers.delete(`${a.id}:${kind}`);
    return fn(await worker(a, kind));
  }
}

// ذاكرة مؤقتة للرسائل المفتوحة، ونجهّز أحدث رسائل الوارد مسبقًا عشان تفتح على طول.
const inflight = new Map(); // رسائل يجري جلبها الحين
const msgCache = new Map(); // "acc/f/uid" -> شكل الرسالة الجاهز
const fmtAddr = (x) => (x?.value || []).map((v) => ({ name: v.name, address: v.address }));
async function getMessage(a, f, uid, { markSeen = true, kind = 'fg' } = {}) {
  const key = `${a.id}/${f}/${uid}`;
  let out = msgCache.get(key);
  // لو التجهيز المسبق يجيبها الحين ننتظره شوي بس، وبعدها نجيبها بنفسنا عشان ما تتأخر ضغطتك
  if (!out && inflight.has(key)) out = await Promise.race([inflight.get(key), new Promise((ok) => setTimeout(() => ok(null), kind === 'fg' ? 250 : 60000))]).catch(() => null);
  if (!out) {
    let done; inflight.set(key, new Promise((ok) => (done = ok)));
    try {
    const parsed = await withImap(a, async (c) => {
      const lock = await c.getMailboxLock(await folderPath(c, a, f));
      try { const msg = await c.fetchOne(String(uid), { source: true }, { uid: true }); return msg ? simpleParser(msg.source) : null; }
      finally { lock.release(); }
    }, kind);
    if (!parsed) return null;
    out = {
      acc: a.id, f, uid: Number(uid), subject: parsed.subject || '(بدون عنوان)', date: parsed.date,
      from: fmtAddr(parsed.from), to: fmtAddr(parsed.to), cc: fmtAddr(parsed.cc), replyTo: fmtAddr(parsed.replyTo),
      messageId: parsed.messageId || '', references: [].concat(parsed.references || []),
      html: parsed.html || null, text: parsed.text || '',
      attachments: (parsed.attachments || []).filter((x) => x.contentDisposition !== 'inline' || x.filename)
        .map((x) => ({ i: parsed.attachments.indexOf(x), name: x.filename || 'مرفق', size: x.size, type: x.contentType })),
    };
    msgCache.set(key, out);
    while (msgCache.size > 300) msgCache.delete(msgCache.keys().next().value);
    } finally { done(out || null); inflight.delete(key); }
  }
  if (markSeen) {
    withImap(a, async (c) => {
      const lock = await c.getMailboxLock(await folderPath(c, a, f));
      try { await c.messageFlagsAdd(String(uid), ['\\Seen'], { uid: true }); } finally { lock.release(); }
    }).catch(() => {});
  }
  return out;
}
async function prefetch(a, f = 'inbox', uids = null) {
  const list = uids || (live.get(a.id)?.list || []).slice(-25).reverse().map((r) => r.uid);
  for (const uid of list) if (!msgCache.has(`${a.id}/${f}/${uid}`)) await getMessage(a, f, uid, { markSeen: false, kind: 'bg' }).catch(() => {});
}

// تحديث لحظي للتطبيق المفتوح (Server-Sent Events)
const sse = new Set();
function broadcast(ev) { for (const res of sse) { try { res.write(`data: ${JSON.stringify(ev)}\n\n`); } catch {} } }
setInterval(() => { for (const res of sse) { try { res.write(': ping\n\n'); } catch {} } }, 25000);
async function specialPath(c, use) {
  const list = await c.list();
  return list.find((f) => f.specialUse === use)?.path;
}

// المجلدات (زي أوتلوك). Gmail يسمّيها حسب لغة الحساب، فنعرفها من specialUse.
const FOLDERS = { inbox: 'INBOX', sent: '\\Sent', archive: '\\All', starred: '\\Flagged', trash: '\\Trash', att: '\\All', drafts: '\\Drafts', spam: '\\Junk' };
const pathCache = new Map(); // id -> { key: path }
async function folderPath(c, a, key) {
  if (key === 'inbox') return 'INBOX';
  let m = pathCache.get(a.id);
  if (!m) {
    m = {};
    for (const f of await c.list()) if (f.specialUse) m[f.specialUse] = f.path;
    pathCache.set(a.id, m);
  }
  const fallback = { '\\Sent': '[Gmail]/Sent Mail', '\\All': '[Gmail]/All Mail', '\\Flagged': '[Gmail]/Starred', '\\Trash': '[Gmail]/Trash', '\\Drafts': '[Gmail]/Drafts', '\\Junk': '[Gmail]/Spam' };
  return m[FOLDERS[key]] || fallback[FOLDERS[key]];
}
async function listFolder(a, key) {
  return withImap(a, async (c) => {
    const lock = await c.getMailboxLock(await folderPath(c, a, key));
    try {
      let range;
      if (key === 'att') {
        const uids = (await c.search({ gmraw: 'has:attachment' }, { uid: true })) || [];
        if (!uids.length) return [];
        range = uids.slice(-PER_ACCOUNT).join(',');
      } else {
        const total = c.mailbox.exists;
        if (!total) return [];
        range = `${Math.max(1, total - PER_ACCOUNT + 1)}:*`;
      }
      const rows = [];
      for await (const m of c.fetch(range, { uid: true, envelope: true, flags: true, internalDate: true, bodyStructure: true }, { uid: key === 'att' })) {
        rows.push({ ...envelopeRow(a, m), f: key, att: key === 'att' || hasAtt(m.bodyStructure) });
      }
      return rows;
    } finally { lock.release(); }
  });
}
function hasAtt(n) {
  if (!n) return false;
  if (n.disposition === 'attachment' || (n.dispositionParameters?.filename && n.disposition !== 'inline')) return true;
  return (n.childNodes || []).some(hasAtt);
}

// ---------- HTTP ----------
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };
const SEC = { 'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer', 'x-frame-options': 'DENY' };

function send(res, code, body, headers = {}) {
  const isBuf = Buffer.isBuffer(body);
  const data = isBuf ? body : typeof body === 'string' ? body : JSON.stringify(body);
  res.writeHead(code, { ...SEC, 'cache-control': 'no-store',
    'content-type': isBuf || typeof body === 'string' ? 'text/plain; charset=utf-8' : 'application/json; charset=utf-8', ...headers });
  res.end(data);
}
async function readJson(req) {
  if (!(req.headers['content-type'] || '').startsWith('application/json')) throw new Error('json');
  let s = '';
  for await (const ch of req) { s += ch; if (s.length > 30e6) throw new Error('كبير'); }
  return JSON.parse(s || '{}');
}
function staticFile(res, p) {
  const f = path.join(PUBLIC, path.normalize(p).replace(/^(\.\.[/\\])+/, ''));
  if (!f.startsWith(PUBLIC) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) return send(res, 404, 'not found');
  const ext = path.extname(f);
  const csp = "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com 'self'; frame-src 'self' blob: data:; connect-src 'self'; script-src 'self'";
  res.writeHead(200, { ...SEC, 'content-type': MIME[ext] || 'application/octet-stream',
    'cache-control': ['.html', '.js', '.css', '.webmanifest'].includes(ext) ? 'no-cache' : 'public, max-age=3600',
    ...(ext === '.html' ? { 'content-security-policy': csp } : {}),
    ...(p === 'sw.js' ? { 'service-worker-allowed': BASE + '/' } : {}) });
  fs.createReadStream(f).pipe(res);
}
const accOf = (id) => cfg.accounts.find((a) => a.id === id);
const addrList = (s) => String(s || '').split(/[,;،\s]+/).map((x) => x.trim()).filter((x) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(x));

async function api(req, res, url) {
  const p = url.pathname.replace(/^\/api/, '');
  const m = req.method;

  if (p === '/login/start' && m === 'POST') {
    if (Date.now() - login.last < 60000) return send(res, 429, { error: 'انتظر دقيقة قبل طلب رمز جديد' });
    login.code = String(crypto.randomInt(100000, 1000000)); login.until = Date.now() + 5 * 60000; login.tries = 0; login.last = Date.now();
    await telegram(`رمز دخول حوات ميل: ${login.code}\nصالح 5 دقائق. إذا ما طلبته أنت، تجاهله.`);
    return send(res, 200, { ok: true });
  }
  if (p === '/login/verify' && m === 'POST') {
    const { code } = await readJson(req);
    if (!login.code || Date.now() > login.until || login.tries >= 5) return send(res, 400, { error: 'الرمز انتهى، اطلب رمز جديد' });
    login.tries++;
    if (String(code || '').trim() !== login.code) return send(res, 400, { error: 'الرمز غير صحيح' });
    login.code = null;
    const tok = crypto.randomBytes(32).toString('hex');
    cfg.sessions[tok] = { created: new Date().toISOString(), ua: String(req.headers['user-agent'] || '').slice(0, 120) };
    save();
    telegram('تم الدخول على حوات ميل من جهاز جديد.').catch(() => {});
    return send(res, 200, { ok: true }, { 'set-cookie': `hm=${tok}; Path=${BASE}; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000` });
  }

  // إضافة حساب من السيرفر نفسه (بدون كلمة مرور، عن طريق حساب الخدمة):
  // curl -H "x-local: $(cat data/mail/local-token)" -H 'content-type: application/json' -d '{"email":"...","aliases":"..."}' 127.0.0.1:18495/api/local/google
  if (p === '/local/google' && m === 'POST') {
    if (!LOCAL_TOKEN || req.headers['x-local'] !== LOCAL_TOKEN || req.headers['x-real-ip'] || req.headers['x-forwarded-for']) return send(res, 403, { error: 'forbidden' });
    const b = await readJson(req);
    const email = String(b.email || '').trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+$/.test(email)) return send(res, 400, { error: 'email' });
    try { tokens.delete(email); const c = new ImapFlow(await imapOpts({ email, google: true })); await c.connect(); await c.logout(); }
    catch (e) { return send(res, 400, { error: String(e.message || e) }); }
    const aliases = addrList(b.aliases).map((x) => x.toLowerCase()).filter((x) => x !== email);
    const old = cfg.accounts.find((a) => a.email === email);
    const a = old || { id: crypto.randomBytes(4).toString('hex'), email, color: COLORS[cfg.accounts.length % COLORS.length] };
    Object.assign(a, { google: true, pass: undefined, name: String(b.name || '').trim() || a.name || email.split('@')[1], aliases });
    if (!old) cfg.accounts.push(a);
    save(); connect(a).catch(() => {});
    return send(res, 200, { ok: true, account: pub(a) });
  }

  const tok = cookieToken(req);
  if (!tok) return send(res, 401, { error: 'login' });

  if (p === '/logout' && m === 'POST') { delete cfg.sessions[tok]; save(); return send(res, 200, { ok: true }, { 'set-cookie': `hm=; Path=${BASE}; Max-Age=0` }); }

  if (p === '/events') {
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', 'x-accel-buffering': 'no', connection: 'keep-alive' });
    res.write(': ok\n\n');
    sse.add(res); req.on('close', () => sse.delete(res));
    return;
  }
  if (p === '/me') {
    return send(res, 200, { vapid: cfg.vapid.publicKey, accounts: cfg.accounts.map((a) => ({ ...pub(a),
      status: live.get(a.id)?.status || 'off', error: live.get(a.id)?.error || null })) });
  }
  if (p === '/list') {
    const only = url.searchParams.get('acc');
    const f = url.searchParams.get('f') || 'inbox';
    if (!FOLDERS[f]) return send(res, 400, { error: 'مجلد غير معروف' });
    const accs = cfg.accounts.filter((a) => !only || a.id === only);
    let rows;
    if (f === 'inbox') rows = accs.flatMap((a) => (live.get(a.id)?.list || []).map((x) => ({ ...x, f })));
    else rows = (await Promise.all(accs.map((a) => listFolder(a, f).catch(() => [])))).flat();
    rows.sort((x, y) => y.date.localeCompare(x.date));
    if (f !== 'inbox') for (const a of accs) prefetch(a, f, rows.filter((x) => x.acc === a.id).slice(0, 10).map((x) => x.uid)).catch(() => {});
    return send(res, 200, { rows });
  }
  if (p === '/counts') {
    const unread = {};
    for (const a of cfg.accounts) unread[a.id] = (live.get(a.id)?.list || []).filter((x) => !x.seen).length;
    return send(res, 200, { unread });
  }
  if (p === '/refresh' && m === 'POST') {
    await Promise.all(cfg.accounts.map((a) => (live.get(a.id)?.status === 'ok' ? refresh(a) : connect(a)).catch(() => {})));
    return send(res, 200, { ok: true });
  }

  let r;
  if ((r = /^\/msg\/(\w+)\/(\w+)\/(\d+)$/.exec(p)) && m === 'GET') {
    const a = accOf(r[1]); if (!a || !FOLDERS[r[2]]) return send(res, 404, { error: 'غير موجود' });
    const peek = url.searchParams.has('peek'); // تجهيز مسبق من التطبيق: لا نعلّمها مقروءة
    const out = await getMessage(a, r[2], r[3], { markSeen: !peek });
    if (!out) return send(res, 404, { error: 'الرسالة غير موجودة' });
    if (r[2] === 'inbox' && !peek) { const row = live.get(a.id)?.list?.find((x) => x.uid === Number(r[3])); if (row) row.seen = true; }
    return send(res, 200, out);
  }
  if ((r = /^\/att\/(\w+)\/(\w+)\/(\d+)\/(\d+)$/.exec(p))) {
    const a = accOf(r[1]); if (!a || !FOLDERS[r[2]]) return send(res, 404, 'not found');
    const out = await withImap(a, async (c) => {
      const lock = await c.getMailboxLock(await folderPath(c, a, r[2]));
      try { const msg = await c.fetchOne(r[3], { source: true }, { uid: true }); return msg && simpleParser(msg.source); }
      finally { lock.release(); }
    });
    const at = out?.attachments?.[Number(r[4])];
    if (!at) return send(res, 404, 'not found');
    const view = url.searchParams.has('view') && /^(image\/|application\/pdf)/.test(at.contentType || '');
    return send(res, 200, at.content, { 'content-type': view ? at.contentType : 'application/octet-stream',
      'content-disposition': `${view ? 'inline' : 'attachment'}; filename*=UTF-8''${encodeURIComponent(at.filename || 'file')}` });
  }
  if ((r = /^\/msg\/(\w+)\/(\w+)\/(\d+)\/(archive|trash|unread|star|unstar|inbox)$/.exec(p)) && m === 'POST') {
    const a = accOf(r[1]); if (!a || !FOLDERS[r[2]]) return send(res, 404, { error: 'غير موجود' });
    const [, , f, uid, act] = r;
    await withImap(a, async (c) => {
      const trash = await folderPath(c, a, 'trash');
      const lock = await c.getMailboxLock(await folderPath(c, a, f));
      try {
        if (act === 'archive') {
          if (f === 'inbox') await c.messageDelete(uid, { uid: true }); // في Gmail: يشيله من الوارد ويبقى في كل البريد
          else await c.messageFlagsRemove(uid, ['\\Inbox'], { uid: true, useLabels: true });
        } else if (act === 'inbox') await c.messageFlagsAdd(uid, ['\\Inbox'], { uid: true, useLabels: true });
        else if (act === 'trash') await c.messageMove(uid, trash, { uid: true });
        else if (act === 'unread') await c.messageFlagsRemove(uid, ['\\Seen'], { uid: true });
        else if (act === 'star') await c.messageFlagsAdd(uid, ['\\Flagged'], { uid: true });
        else await c.messageFlagsRemove(uid, ['\\Flagged'], { uid: true });
      } finally { lock.release(); }
    });
    msgCache.delete(`${a.id}/${f}/${uid}`);
    const st = live.get(a.id);
    if (st && f === 'inbox' && (act === 'archive' || act === 'trash')) st.list = st.list.filter((x) => x.uid !== Number(uid));
    refresh(a).catch(() => {});
    return send(res, 200, { ok: true });
  }
  if (p === '/send' && m === 'POST') {
    const b = await readJson(req);
    const a = accOf(b.acc); if (!a) return send(res, 400, { error: 'اختر الحساب' });
    const from = [a.email, ...(a.aliases || [])].includes(b.from) ? b.from : a.email;
    const to = addrList(b.to), cc = addrList(b.cc);
    if (!to.length) return send(res, 400, { error: 'اكتب إيميل المرسل إليه' });
    // التحويل: نرفق مرفقات الرسالة الأصلية
    let fwdAtts = [];
    const fo = b.forwardOf;
    if (fo && accOf(fo.acc) && FOLDERS[fo.f] && /^\d+$/.test(String(fo.uid))) {
      const oa = accOf(fo.acc);
      const orig = await withImap(oa, async (c) => {
        const lock = await c.getMailboxLock(await folderPath(c, oa, fo.f));
        try { const msg = await c.fetchOne(String(fo.uid), { source: true }, { uid: true }); return msg && simpleParser(msg.source); }
        finally { lock.release(); }
      }).catch(() => null);
      fwdAtts = (orig?.attachments || []).map((x) => ({ filename: x.filename || 'file', content: x.content, contentType: x.contentType }));
    }
    const t = nodemailer.createTransport({ host: 'smtp.gmail.com', port: 465, secure: true,
      auth: a.google ? { type: 'OAuth2', user: a.email, accessToken: await googleToken(a.email) } : { user: a.email, pass: a.pass } });
    const fromName = (a.fromNames || {})[from] || a.name || '';
    await t.sendMail({
      from: fromName ? { name: fromName, address: from } : from, to, cc: cc.length ? cc : undefined,
      subject: String(b.subject || ''), text: String(b.text || ''),
      html: `<div dir="auto" style="font-family:Tahoma,Arial,sans-serif;font-size:15px;line-height:1.7;white-space:pre-wrap">${String(b.text || '').replace(/[&<>]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[ch]))}</div>`,
      inReplyTo: b.inReplyTo || undefined, references: b.references?.length ? b.references : undefined,
      attachments: [...fwdAtts, ...(b.attachments || []).slice(0, 10).map((x) => ({ filename: String(x.name), content: Buffer.from(String(x.data), 'base64') }))],
    });
    return send(res, 200, { ok: true });
  }
  if (p === '/accounts' && m === 'POST') {
    const b = await readJson(req);
    const email = String(b.email || '').trim().toLowerCase();
    const pass = String(b.pass || '').replace(/\s+/g, '');
    if (!/^[^@\s]+@[^@\s]+$/.test(email) || pass.length < 8) return send(res, 400, { error: 'اكتب الإيميل وكلمة مرور التطبيقات' });
    const test = new ImapFlow(await imapOpts({ email, pass }));
    try { await test.connect(); await test.logout(); } catch (e) {
      return send(res, 400, { error: e.authenticationFailed ? 'Google رفض الدخول: تأكد من كلمة مرور التطبيقات (16 حرف) وإن IMAP مفعّل' : 'تعذّر الاتصال: ' + (e.message || e) });
    }
    const aliases = addrList(b.aliases).map((x) => x.toLowerCase()).filter((x) => x !== email);
    const old = cfg.accounts.find((a) => a.email === email);
    const a = old || { id: crypto.randomBytes(4).toString('hex'), email, color: COLORS[cfg.accounts.length % COLORS.length] };
    Object.assign(a, { pass, name: String(b.name || '').trim() || email.split('@')[1], aliases });
    if (!old) cfg.accounts.push(a);
    save();
    connect(a).catch(() => {});
    return send(res, 200, { ok: true, account: pub(a) });
  }
  if ((r = /^\/accounts\/(\w+)$/.exec(p)) && m === 'DELETE') {
    const a = accOf(r[1]); if (!a) return send(res, 404, { error: 'غير موجود' });
    cfg.accounts = cfg.accounts.filter((x) => x.id !== a.id); save();
    const st = live.get(a.id); live.delete(a.id); try { st?.client?.close(); } catch {}
    return send(res, 200, { ok: true });
  }
  if (p === '/push' && m === 'POST') {
    const { sub } = await readJson(req);
    if (!sub?.endpoint || !/^https:\/\//.test(sub.endpoint)) return send(res, 400, { error: 'اشتراك غير صالح' });
    cfg.subs = cfg.subs.filter((s) => s.endpoint !== sub.endpoint).concat([{ endpoint: sub.endpoint, keys: sub.keys }]);
    save();
    await webpush.sendNotification(sub, JSON.stringify({ title: 'حوات ميل', body: 'تم تفعيل الإشعارات ✅', url: BASE + '/' })).catch(() => {});
    return send(res, 200, { ok: true });
  }
  return send(res, 404, { error: 'not found' });
}

http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x');
    if (url.pathname === '/health') return send(res, 200, { ok: true, accounts: cfg.accounts.length });
    if (url.pathname.startsWith('/api/')) return await api(req, res, url);
    if (url.pathname === '/' || url.pathname === '') return staticFile(res, 'index.html');
    return staticFile(res, url.pathname.slice(1));
  } catch (e) {
    console.error(e);
    if (!res.headersSent) send(res, 500, { error: String(e.message || 'خطأ') });
  }
}).listen(PORT, () => console.log(`hawat-mail on :${PORT}`));
