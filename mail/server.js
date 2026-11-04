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
const imapOpts = (a) => ({
  host: 'imap.gmail.com', port: 993, secure: true,
  auth: { user: a.email, pass: a.pass }, logger: false, emitLogs: false,
});

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
  st.list = rows;
  if (notify && st.ready) await notifyNew(a, rows.filter((r) => !before.has(r.uid) && r.uid > maxUid && !r.seen));
  st.ready = true;
}

async function connect(a) {
  const old = live.get(a.id);
  if (old?.timer) clearTimeout(old.timer);
  const st = { client: null, list: old?.list || [], status: 'connecting', error: null, ready: old?.ready || false };
  live.set(a.id, st);
  const c = new ImapFlow(imapOpts(a));
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
async function withImap(a, fn) {
  const c = new ImapFlow(imapOpts(a));
  await c.connect();
  try { return await fn(c); } finally { await c.logout().catch(() => {}); }
}
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

  const tok = cookieToken(req);
  if (!tok) return send(res, 401, { error: 'login' });

  if (p === '/logout' && m === 'POST') { delete cfg.sessions[tok]; save(); return send(res, 200, { ok: true }, { 'set-cookie': `hm=; Path=${BASE}; Max-Age=0` }); }

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
    const out = await withImap(a, async (c) => {
      const lock = await c.getMailboxLock(await folderPath(c, a, r[2]));
      try {
        const msg = await c.fetchOne(r[3], { source: true }, { uid: true });
        if (!msg) return null;
        await c.messageFlagsAdd(r[3], ['\\Seen'], { uid: true });
        return await simpleParser(msg.source);
      } finally { lock.release(); }
    });
    if (!out) return send(res, 404, { error: 'الرسالة غير موجودة' });
    if (r[2] === 'inbox') { const row = live.get(a.id)?.list?.find((x) => x.uid === Number(r[3])); if (row) row.seen = true; }
    const fmt = (x) => (x?.value || []).map((v) => ({ name: v.name, address: v.address }));
    return send(res, 200, {
      acc: a.id, f: r[2], uid: Number(r[3]), subject: out.subject || '(بدون عنوان)', date: out.date,
      from: fmt(out.from), to: fmt(out.to), cc: fmt(out.cc), replyTo: fmt(out.replyTo),
      messageId: out.messageId || '', references: [].concat(out.references || []),
      html: out.html || null, text: out.text || '',
      attachments: (out.attachments || []).filter((x) => x.contentDisposition !== 'inline' || x.filename)
        .map((x) => ({ i: out.attachments.indexOf(x), name: x.filename || 'مرفق', size: x.size, type: x.contentType })),
    });
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
    const t = nodemailer.createTransport({ host: 'smtp.gmail.com', port: 465, secure: true, auth: { user: a.email, pass: a.pass } });
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
    const test = new ImapFlow(imapOpts({ email, pass }));
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
