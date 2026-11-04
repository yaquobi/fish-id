// حوات ميل: واجهة بسيطة بدون مكتبات.
const $ = (s) => document.querySelector(s);
const view = $('#view');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
let me = null, rows = [], filter = '', draft = null;

function toast(t) { const el = $('#toast'); el.textContent = t; el.classList.add('on'); clearTimeout(toast.t); toast.t = setTimeout(() => el.classList.remove('on'), 2800); }
async function call(path, opts = {}) {
  const r = await fetch('api/' + path, { credentials: 'same-origin', ...opts,
    headers: opts.body ? { 'content-type': 'application/json' } : {}, body: opts.body ? JSON.stringify(opts.body) : undefined });
  const j = await r.json().catch(() => ({}));
  if (r.status === 401) { me = null; showLogin(); throw new Error('login'); }
  if (!r.ok) throw new Error(j.error || 'خطأ');
  return j;
}
const accById = (id) => me?.accounts.find((a) => a.id === id) || {};
function when(d) {
  const t = new Date(d), now = new Date();
  if (t.toDateString() === now.toDateString()) return t.toLocaleTimeString('ar-SA-u-nu-latn', { hour: 'numeric', minute: '2-digit' });
  return t.toLocaleDateString('ar-SA-u-nu-latn-ca-gregory', { day: 'numeric', month: 'short' });
}
function chrome(mode) {
  const inApp = !!me;
  $('#back').classList.toggle('hide', !inApp || mode === 'inbox');
  $('#refresh').classList.toggle('hide', !inApp || mode !== 'inbox');
  $('#settingsBtn').classList.toggle('hide', !inApp || mode === 'settings');
  $('#compose').classList.toggle('hide', !inApp || mode !== 'inbox');
  $('#tabs').classList.toggle('hide', !inApp || mode !== 'inbox' || me.accounts.length < 2);
}

// ---------- الدخول ----------
function showLogin() {
  chrome('login');
  view.innerHTML = `<div class="login"><img src="icon-512.png" alt=""><h1>حوات ميل</h1>
    <p>كل إيميلات حوات في مكان واحد.<br>نرسل لك رمز دخول على تلقرام.</p>
    <button class="btn gold" id="send" style="width:100%;padding:12px">أرسل الرمز</button>
    <div id="step2" class="hide"><input id="code" inputmode="numeric" maxlength="6" autocomplete="one-time-code" placeholder="••••••">
    <button class="btn navy" id="ok" style="width:100%;padding:12px">دخول</button></div></div>`;
  $('#send').onclick = async () => {
    try { await call('login/start', { method: 'POST', body: {} }); $('#step2').classList.remove('hide'); $('#code').focus(); toast('وصلك الرمز على تلقرام'); }
    catch (e) { toast(e.message); }
  };
  const go = async () => {
    try { await call('login/verify', { method: 'POST', body: { code: $('#code').value } }); await boot(); }
    catch (e) { if (e.message !== 'login') toast(e.message); }
  };
  $('#ok').onclick = go;
  view.addEventListener('input', (e) => { if (e.target.id === 'code' && e.target.value.length === 6) go(); });
}

// ---------- الوارد ----------
function tabs() {
  const t = [{ id: '', name: 'الكل', color: 'transparent' }, ...me.accounts];
  $('#tabs').innerHTML = t.map((a) => `<button data-a="${a.id}" class="${a.id === filter ? 'on' : ''}">${a.id ? `<i style="background:${a.color}"></i>` : ''}${esc(a.name)}</button>`).join('');
  $('#tabs').querySelectorAll('button').forEach((b) => (b.onclick = () => { filter = b.dataset.a; tabs(); renderList(); }));
}
function renderList() {
  const list = rows.filter((r) => !filter || r.acc === filter);
  if (!me.accounts.length) {
    view.innerHTML = `<div class="empty">ما فيه حسابات مربوطة بعد.<br><button class="btn gold" onclick="location.hash='#/s'">أضف أول حساب</button></div>`;
    return;
  }
  const bad = me.accounts.filter((a) => a.status === 'error');
  view.innerHTML = (bad.length ? `<div class="help err">تعذّر الاتصال بـ: ${bad.map((a) => esc(a.email)).join('، ')}. افتح الإعدادات.</div>` : '') +
    (list.length ? `<div class="list">${list.map((r) => { const a = accById(r.acc); return `
    <div class="row ${r.seen ? '' : 'new'}" data-k="${r.acc}/${r.uid}">
      <div class="bar" style="background:${a.color}"></div>
      <div class="who">${r.starred ? '★ ' : ''}${esc(r.from || r.fromAddr)}</div><div class="when">${when(r.date)}</div>
      <div class="sub">${r.att ? '📎 ' : ''}${esc(r.subject)}</div>
      <div class="acc">${esc(r.to && me.accounts.length ? toLine(r, a) : a.email)}</div>
    </div>`; }).join('')}</div>` : `<div class="empty">الوارد فاضي 👌</div>`);
  view.querySelectorAll('.row').forEach((el) => (el.onclick = () => (location.hash = '#/m/' + el.dataset.k)));
}
function toLine(r, a) {
  // نوضّح على أي عنوان وصلت (مثلاً info@hawat.id داخل حساب info@ksafish.com)
  const mine = [a.email, ...(a.aliases || [])];
  const hit = r.to.split(', ').find((x) => mine.includes(x.toLowerCase()));
  return hit || a.email;
}
async function loadInbox(quiet) {
  try { rows = (await call('inbox')).rows; if (location.hash === '' || location.hash === '#/' ) renderList(); }
  catch (e) { if (!quiet && e.message !== 'login') toast(e.message); }
}
async function inbox() {
  chrome('inbox'); if (me.accounts.length > 1) tabs();
  if (!rows.length) view.innerHTML = '<div class="empty">جاري التحميل…</div>';
  else renderList();
  await loadInbox();
}

// ---------- رسالة ----------
async function openMsg(acc, uid) {
  chrome('msg');
  view.innerHTML = '<div class="empty">جاري الفتح…</div>';
  let m;
  try { m = await call(`msg/${acc}/${uid}`); } catch (e) { if (e.message !== 'login') view.innerHTML = `<div class="empty">${esc(e.message)}</div>`; return; }
  const a = accById(acc);
  const ppl = (l) => l.map((p) => (p.name ? `<bdi>${esc(p.name)}</bdi> <bdi class="en">&lt;${esc(p.address)}&gt;</bdi>` : `<bdi class="en">${esc(p.address)}</bdi>`)).join('، ');
  view.innerHTML = `<div class="msg"><h1>${esc(m.subject)}</h1>
    <div class="meta"><b>من:</b> ${ppl(m.from)}<br><b>إلى:</b> ${ppl(m.to)}${m.cc.length ? `<br><b>نسخة:</b> ${ppl(m.cc)}` : ''}<br>
    <span class="num">${new Date(m.date).toLocaleString('ar-SA-u-nu-latn-ca-gregory')}</span> · <span style="color:${a.color}">■</span> <span class="en">${esc(a.email)}</span></div>
    <div class="actions"><button class="btn gold" id="rep">↩ رد</button><button class="btn" id="repAll">رد للكل</button><button class="btn" id="fwd">تحويل</button>
    <button class="btn" id="arc">أرشفة</button><button class="btn" id="unr">غير مقروءة</button><button class="btn red" id="del">حذف</button></div></div>
    ${m.attachments.length ? `<div class="atts">${m.attachments.map((x) => `<a href="api/att/${acc}/${uid}/${x.i}">📎 ${esc(x.name)} <span class="num">${Math.ceil(x.size / 1024)}KB</span></a>`).join('')}</div>` : ''}
    <div class="body" id="body"></div>`;
  const body = $('#body');
  if (m.html) {
    const f = document.createElement('iframe');
    f.setAttribute('sandbox', 'allow-same-origin allow-popups allow-popups-to-escape-sandbox');
    f.srcdoc = `<!doctype html><meta charset="utf-8"><base target="_blank"><style>body{margin:12px;font-family:Tahoma,Arial,sans-serif;word-wrap:break-word}img{max-width:100%;height:auto}</style>${m.html}`;
    f.onload = () => { const fit = () => { try { f.style.height = f.contentDocument.documentElement.scrollHeight + 20 + 'px'; } catch {} }; fit(); setTimeout(fit, 600); setTimeout(fit, 2000); };
    body.appendChild(f);
  } else { body.innerHTML = `<pre dir="auto">${esc(m.text)}</pre>`; }
  const act = async (what, msg) => { try { await call(`msg/${acc}/${uid}/${what}`, { method: 'POST', body: {} }); toast(msg); rows = rows.filter((r) => !(what !== 'unread' && r.acc === acc && r.uid === Number(uid))); history.back(); } catch (e) { toast(e.message); } };
  $('#arc').onclick = () => act('archive', 'انأرشفت');
  $('#del').onclick = () => act('trash', 'انحذفت');
  $('#unr').onclick = () => { const r = rows.find((x) => x.acc === acc && x.uid === Number(uid)); if (r) r.seen = false; act('unread', 'صارت غير مقروءة'); };
  const quote = () => `\n\n\nفي ${new Date(m.date).toLocaleString('ar-SA-u-nu-latn-ca-gregory')} كتب ${m.from[0]?.name || m.from[0]?.address || ''}:\n` + (m.text || '').split('\n').map((l) => '> ' + l).join('\n');
  const mine = [a.email, ...(a.aliases || [])];
  const myAddr = [...m.to, ...m.cc].map((p) => p.address?.toLowerCase()).find((x) => mine.includes(x)) || a.email;
  const reSub = /^(re|رد)\s*:/i.test(m.subject) ? m.subject : 'Re: ' + m.subject;
  const replyTo = (m.replyTo.length ? m.replyTo : m.from).map((p) => p.address);
  const base = { acc, from: myAddr, inReplyTo: m.messageId, references: [...m.references, m.messageId].filter(Boolean) };
  $('#rep').onclick = () => { draft = { ...base, to: replyTo.join(', '), cc: '', subject: reSub, text: quote() }; location.hash = '#/c'; };
  $('#repAll').onclick = () => {
    const others = [...m.to, ...m.cc].map((p) => p.address).filter((x) => x && !mine.includes(x.toLowerCase()) && !replyTo.includes(x));
    draft = { ...base, to: replyTo.join(', '), cc: others.join(', '), subject: reSub, text: quote() }; location.hash = '#/c';
  };
  $('#fwd').onclick = () => { draft = { acc, from: myAddr, to: '', cc: '', subject: 'Fwd: ' + m.subject, text: '\n\n\n---------- رسالة محوّلة ----------\nمن: ' + (m.from[0]?.address || '') + '\nالعنوان: ' + m.subject + '\n\n' + (m.text || '') }; location.hash = '#/c'; };
}

// ---------- كتابة رسالة ----------
function compose() {
  chrome('compose');
  const d = draft || { acc: me.accounts[0]?.id, from: me.accounts[0]?.email, to: '', cc: '', subject: '', text: '' };
  const froms = me.accounts.flatMap((a) => [a.email, ...(a.aliases || [])].map((e) => ({ acc: a.id, e })));
  view.innerHTML = `<div class="form">
    <label>من<select id="from">${froms.map((f) => `<option value="${f.acc}|${esc(f.e)}" ${f.acc === d.acc && f.e === d.from ? 'selected' : ''}>${esc(f.e)}</option>`).join('')}</select></label>
    <label>إلى<input id="to" class="ltr" type="email" multiple value="${esc(d.to)}" placeholder="name@example.com"></label>
    <label>نسخة<input id="cc" class="ltr" type="email" multiple value="${esc(d.cc)}"></label>
    <label>العنوان<input id="subject" value="${esc(d.subject)}"></label>
    <label>الرسالة<textarea id="text" dir="auto">${esc(d.text)}</textarea></label>
    <label>مرفقات<input id="files" type="file" multiple></label>
    <button class="btn gold" id="go" style="padding:12px">إرسال</button></div>`;
  $('#go').onclick = async () => {
    const [acc, from] = $('#from').value.split('|');
    const attachments = await Promise.all([...$('#files').files].map((f) => new Promise((ok) => {
      const r = new FileReader(); r.onload = () => ok({ name: f.name, data: String(r.result).split(',')[1] }); r.readAsDataURL(f);
    })));
    $('#go').disabled = true; $('#go').textContent = 'جاري الإرسال…';
    try {
      await call('send', { method: 'POST', body: { acc, from, to: $('#to').value, cc: $('#cc').value, subject: $('#subject').value, text: $('#text').value,
        inReplyTo: d.inReplyTo, references: d.references, attachments } });
      draft = null; toast('انرسلت ✅'); history.back();
    } catch (e) { toast(e.message); $('#go').disabled = false; $('#go').textContent = 'إرسال'; }
  };
}

// ---------- الإعدادات ----------
async function settings() {
  chrome('settings');
  me = await call('me');
  const push = 'PushManager' in window && Notification.permission === 'granted';
  view.innerHTML = `<h2>الحسابات</h2>${me.accounts.map((a) => `<div class="acct"><i style="background:${a.color}"></i>
      <div class="t"><div>${esc(a.name)}</div><small>${esc(a.email)}${a.aliases.length ? ' + ' + a.aliases.map(esc).join(', ') : ''}</small>
      <div class="${a.status === 'ok' ? 'ok' : 'err'}" style="font-size:12px">${a.status === 'ok' ? 'متصل' : esc(a.error || a.status)}</div></div>
      <button class="btn red" data-del="${a.id}">حذف</button></div>`).join('') || '<div class="empty">ما فيه حسابات بعد</div>'}
    <h2>إضافة حساب</h2>
    <div class="help">لكل إيميل في Google: افتح <a href="https://myaccount.google.com/apppasswords" target="_blank" rel="noopener">كلمات مرور التطبيقات</a>
      وأنت داخل بنفس الإيميل، سمّها «حوات ميل»، وانسخ الرمز (16 حرف) والصقه هنا. يحتاج التحقق بخطوتين يكون مفعّل.</div>
    <div class="form">
      <label>الإيميل<input id="em" class="ltr" type="email" placeholder="info@ksafish.com"></label>
      <label>كلمة مرور التطبيقات<input id="pw" class="ltr" type="password" autocomplete="off" placeholder="xxxx xxxx xxxx xxxx"></label>
      <label>اسم يظهر لك (اختياري)<input id="nm" placeholder="موسوعة KSAFish"></label>
      <label>عناوين إضافية توصل لنفس الصندوق (اختياري)<input id="al" class="ltr" placeholder="info@hawat.id, support@hawat.id"></label>
      <button class="btn gold" id="add" style="padding:12px">ربط الحساب</button></div>
    <h2>الإشعارات</h2>
    <div class="form"><div>${push ? '<span class="ok">الإشعارات مفعّلة على هذا الجهاز</span>' : 'فعّل الإشعارات عشان توصلك الرسائل الجديدة على هذا الجهاز.'}</div>
      <button class="btn ${push ? '' : 'gold'}" id="push" style="padding:12px">${push ? 'إعادة التفعيل' : 'تفعيل الإشعارات'}</button></div>
    <h2>الجهاز</h2>
    <div class="form"><div style="font-size:14px;line-height:1.9;color:var(--mute)">لتثبيت الأيقونة: من قائمة Chrome (⋮) اختر «إضافة إلى الشاشة الرئيسية» أو «تثبيت التطبيق».</div>
      <button class="btn" id="install" style="padding:12px">تثبيت حوات ميل</button>
      <button class="btn red" id="out" style="padding:12px">تسجيل خروج</button></div>`;
  view.querySelectorAll('[data-del]').forEach((b) => (b.onclick = async () => {
    if (!confirmDel(b)) return;
    await call('accounts/' + b.dataset.del, { method: 'DELETE' }).catch((e) => toast(e.message)); settings();
  }));
  $('#add').onclick = async () => {
    $('#add').disabled = true; $('#add').textContent = 'جاري التحقق…';
    try { await call('accounts', { method: 'POST', body: { email: $('#em').value, pass: $('#pw').value, name: $('#nm').value, aliases: $('#al').value } }); toast('تم الربط ✅'); rows = []; settings(); }
    catch (e) { toast(e.message); $('#add').disabled = false; $('#add').textContent = 'ربط الحساب'; }
  };
  $('#push').onclick = enablePush;
  $('#install').onclick = () => (deferredInstall ? deferredInstall.prompt() : toast('من قائمة Chrome (⋮) ← إضافة إلى الشاشة الرئيسية'));
  $('#out').onclick = async () => { await call('logout', { method: 'POST', body: {} }).catch(() => {}); me = null; showLogin(); };
}
function confirmDel(b) {
  // ضغطتين بدل نافذة تأكيد
  if (b.dataset.sure) return true;
  b.dataset.sure = '1'; b.textContent = 'متأكد؟'; setTimeout(() => { delete b.dataset.sure; b.textContent = 'حذف'; }, 3000); return false;
}
async function enablePush() {
  try {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) throw new Error('المتصفح هذا ما يدعم الإشعارات');
    const perm = await Notification.requestPermission();
    if (perm !== 'granted') throw new Error('لازم تسمح بالإشعارات من إعدادات المتصفح');
    const reg = await navigator.serviceWorker.ready;
    const key = Uint8Array.from(atob(me.vapid.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (me.vapid.length % 4)) % 4)), (c) => c.charCodeAt(0));
    const sub = (await reg.pushManager.getSubscription()) || (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key }));
    await call('push', { method: 'POST', body: { sub: sub.toJSON() } });
    toast('تم التفعيل، بيوصلك إشعار تجربة'); settings();
  } catch (e) { toast(e.message); }
}

// ---------- التنقل ----------
let deferredInstall = null;
window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); deferredInstall = e; });
async function route() {
  if (!me) return;
  const h = location.hash.replace(/^#\/?/, '');
  let r;
  if ((r = /^m\/(\w+)\/(\d+)$/.exec(h))) return openMsg(r[1], r[2]);
  if (h === 'c') return compose();
  if (h === 's') return settings().catch(() => {});
  draft = null;
  return inbox();
}
window.addEventListener('hashchange', route);
$('#back').onclick = () => (history.length > 1 ? history.back() : (location.hash = '#/'));
$('#settingsBtn').onclick = () => (location.hash = '#/s');
$('#compose').onclick = () => { draft = null; location.hash = '#/c'; };
$('#refresh').onclick = async () => { toast('جاري التحديث…'); await call('refresh', { method: 'POST', body: {} }).catch(() => {}); await loadInbox(); };
document.addEventListener('visibilitychange', () => { if (!document.hidden && me) loadInbox(true); });
setInterval(() => { if (!document.hidden && me) loadInbox(true); }, 30000);

async function boot() {
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js', { scope: './' }).catch(() => {});
  try { me = await call('me'); } catch { return; }
  route();
}
boot();
