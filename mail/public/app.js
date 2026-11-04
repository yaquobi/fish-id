// حوات ميل: واجهة بشكل أوتلوك (مجلدات | قائمة الرسائل | قراءة الرسالة) بدون مكتبات.
const $ = (s, el = document) => el.querySelector(s);
const app = $('#app');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const store = { get: (k) => { try { return localStorage.getItem(k); } catch { return null; } }, set: (k, v) => { try { localStorage.setItem(k, v); } catch {} } };

const FOLDERS = [
  { id: 'inbox', name: 'البريد الوارد', ico: '📥' },
  { id: 'sent', name: 'المرسلة', ico: '📤' },
  { id: 'att', name: 'فيها مرفقات', ico: '📎' },
  { id: 'starred', name: 'المميّزة بنجمة', ico: '★' },
  { id: 'archive', name: 'الأرشيف (كل البريد)', ico: '🗄' },
  { id: 'drafts', name: 'المسودات', ico: '📝' },
  { id: 'spam', name: 'غير المرغوب', ico: '⚠' },
  { id: 'trash', name: 'المحذوفة', ico: '🗑' },
];
let me = null, rows = [], folder = 'inbox', accFilter = store.get('hm-acc') || '', query = '', draft = null, unread = {}, loading = false;
let deferredInstall = null;

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
const ppl = (l) => l.map((p) => (p.name ? `<bdi>${esc(p.name)}</bdi> <bdi class="en mute">&lt;${esc(p.address)}&gt;</bdi>` : `<bdi class="en">${esc(p.address)}</bdi>`)).join('، ');
const initials = (s) => (String(s || '?').replace(/[^\p{L}\p{N}]/gu, '')[0] || '?').toUpperCase();

// ---------- الدخول ----------
function showLogin() {
  ['#menu', '#search', '#refresh', '#settingsBtn'].forEach((s) => $(s).classList.add('hide'));
  app.innerHTML = `<div class="login"><img src="icon-512.png" alt="">
    <h1 class="lg"><img src="huwat-blue.png" alt="حوات"><span>MAIL</span></h1>
    <p>كل إيميلات حوات في مكان واحد.<br>نرسل لك رمز دخول على تلقرام.</p>
    <button class="btn gold wide" id="send">أرسل الرمز</button>
    <div id="step2" class="hide"><input id="code" inputmode="numeric" maxlength="6" autocomplete="one-time-code" placeholder="••••••">
    <button class="btn navy wide" id="ok">دخول</button></div></div>`;
  $('#send').onclick = async () => {
    try { await call('login/start', { method: 'POST', body: {} }); $('#step2').classList.remove('hide'); $('#code').focus(); toast('وصلك الرمز على تلقرام'); }
    catch (e) { toast(e.message); }
  };
  const go = async () => {
    try { await call('login/verify', { method: 'POST', body: { code: $('#code').value } }); await boot(); }
    catch (e) { if (e.message !== 'login') toast(e.message); }
  };
  $('#ok').onclick = go;
  $('#code').oninput = (e) => { if (e.target.value.length === 6) go(); };
}

// ---------- الهيكل: مجلدات | قائمة | قراءة ----------
function shell() {
  ['#menu', '#search', '#refresh', '#settingsBtn'].forEach((s) => $(s).classList.remove('hide'));
  if ($('#nav')) return;
  app.innerHTML = `<div class="shell" id="shell">
    <aside class="nav" id="nav"></aside>
    <section class="listpane"><div class="listhead" id="listhead"></div><div class="list" id="list"></div></section>
    <section class="readpane" id="read"></section>
    <div class="scrim" id="scrim"></div></div>`;
  $('#scrim').onclick = () => $('#shell').classList.remove('navopen');
}
function renderNav() {
  const total = Object.values(unread).reduce((x, y) => x + y, 0);
  const accId = () => accFilter.split('|')[0], accAddr = () => accFilter.split('|')[1] || '';
  const u = accFilter ? unread[accId()] || 0 : total;
  $('#nav').innerHTML = `<button class="btn gold wide newmail" id="newmail">✎ رسالة جديدة</button>
    <div class="navsec">المجلدات</div>
    ${FOLDERS.map((f) => `<a class="nf ${f.id === folder ? 'on' : ''}" href="#/${f.id}"><span class="fi">${f.ico}</span>${f.name}${f.id === 'inbox' && u ? `<b class="cnt num">${u}</b>` : ''}</a>`).join('')}
    <div class="navsec">الحسابات</div>
    <a class="nf ${!accFilter ? 'on' : ''}" data-acc=""><span class="fi">◎</span>كل الحسابات${total ? `<b class="cnt num">${total}</b>` : ''}</a>
    ${me.accounts.map((a) => `<a class="nf ${a.id === accFilter ? 'on' : ''}" data-acc="${a.id}" title="${esc(a.email)}"><span class="fi"><i class="dot" style="background:${a.color}"></i></span>
      <span class="ellip">${esc(a.name)}<small class="en">${esc(a.email)}</small></span>${unread[a.id] ? `<b class="cnt num">${unread[a.id]}</b>` : ''}${a.status === 'error' ? '<b class="err">!</b>' : ''}</a>
      ${[a.email, ...(a.aliases || [])].length > 1 ? [a.email, ...a.aliases].map((e) => `<a class="nf sub ${accFilter === a.id + '|' + e ? 'on' : ''}" data-acc="${a.id}|${esc(e)}"><span class="fi">↳</span><span class="ellip en">${esc(e)}</span></a>`).join('') : ''}`).join('')}
    <a class="nf" href="#/${folder}/s"><span class="fi">⚙</span>الإعدادات وإضافة حساب</a>`;
  $('#newmail').onclick = () => { draft = null; location.hash = `#/${folder}/c`; };
  $('#nav').querySelectorAll('[data-acc]').forEach((el) => (el.onclick = () => {
    accFilter = el.dataset.acc; store.set('hm-acc', accFilter); $('#shell').classList.remove('navopen'); renderNav(); loadList();
  }));
  $('#nav').querySelectorAll('a[href]').forEach((el) => el.addEventListener('click', () => $('#shell').classList.remove('navopen')));
}
function renderList(sel) {
  const f = FOLDERS.find((x) => x.id === folder);
  const q = query.trim().toLowerCase();
  const [fa, fe] = accFilter.split('|');
  const list = rows.filter((r) => (!fa || r.acc === fa) && (!fe || [r.to, r.fromAddr].join(',').toLowerCase().includes(fe)) &&
    (!q || [r.from, r.fromAddr, r.subject, r.to, r.toName].some((x) => String(x || '').toLowerCase().includes(q))));
  $('#listhead').innerHTML = `<b>${f.name}</b><span class="mute">${accFilter ? esc(fe || accById(fa).name) + ' · ' : ''}<span class="num">${list.length}</span></span>`;
  const L = $('#list');
  if (!me.accounts.length) { L.innerHTML = `<div class="empty">ما فيه حسابات مربوطة بعد.<br><br><a class="btn gold" href="#/inbox/s">أضف أول حساب</a></div>`; return; }
  if (loading && !list.length) { L.innerHTML = '<div class="empty">جاري التحميل…</div>'; return; }
  if (!list.length) { L.innerHTML = `<div class="empty">${q ? 'ما فيه نتائج' : 'ما فيه رسائل هنا 👌'}</div>`; return; }
  const sent = folder === 'sent' || folder === 'drafts';
  L.innerHTML = list.map((r) => { const a = accById(r.acc); const who = sent ? 'إلى: ' + (r.toName || r.to) : r.from || r.fromAddr;
    const k = `${r.acc}/${r.f || folder}/${r.uid}`; return `
    <div class="row ${r.seen ? '' : 'new'} ${k === sel ? 'sel' : ''}" data-k="${k}">
      <div class="av" style="border-color:${a.color}">${esc(initials(sent ? r.toName || r.to : r.from || r.fromAddr))}</div>
      <div class="rb">
        <div class="l1"><span class="who">${esc(who)}</span><span class="when num">${when(r.date)}</span></div>
        <div class="l2"><span class="sub">${esc(r.subject)}</span><span class="flags">${r.att ? '📎' : ''}${r.starred ? '<i class="star">★</i>' : ''}</span></div>
        <div class="l3 en"><i class="dot" style="background:${a.color}"></i>${esc(toLine(r, a))}</div>
      </div></div>`; }).join('');
  L.querySelectorAll('.row').forEach((el) => (el.onclick = () => (location.hash = `#/${folder}/m/${el.dataset.k}`)));
}
function toLine(r, a) {
  // نوضّح على أي عنوان وصلت (مثلاً info@hawat.id داخل حساب info@ksafish.com)
  const mine = [a.email, ...(a.aliases || [])];
  return (r.to || '').split(', ').find((x) => mine.includes(x.toLowerCase())) || a.email;
}
async function loadList(quiet) {
  const f = folder;
  loading = true; if (!quiet) { rows = f === 'inbox' ? rows.filter((r) => (r.f || 'inbox') === 'inbox') : []; renderList(selKey()); }
  try {
    const [l, c] = await Promise.all([call(`list?f=${f}`), call('counts')]);
    if (f !== folder) return;
    rows = l.rows; unread = c.unread;
  } catch (e) { if (!quiet && e.message !== 'login') toast(e.message); }
  loading = false;
  if (f === folder) { renderList(selKey()); renderNav(); }
}
const selKey = () => { const r = /^#\/\w+\/m\/(\w+\/\w+\/\d+)$/.exec(location.hash); return r ? r[1] : null; };
function readEmpty() {
  $('#shell').classList.remove('reading');
  $('#read').innerHTML = `<div class="readempty"><img src="icon-192.png" alt=""><div>اختر رسالة لقراءتها</div></div>`;
}

// ---------- قراءة رسالة ----------
async function openMsg(acc, f, uid) {
  $('#shell').classList.add('reading');
  const R = $('#read');
  R.innerHTML = '<div class="empty">جاري الفتح…</div>';
  let m;
  try { m = await call(`msg/${acc}/${f}/${uid}`); } catch (e) { if (e.message !== 'login') R.innerHTML = `<div class="empty">${esc(e.message)}</div>`; return; }
  const row = rows.find((x) => x.acc === acc && x.uid === Number(uid));
  if (row && !row.seen) { row.seen = true; if (f === 'inbox' && unread[acc]) unread[acc]--; renderNav(); }
  renderList(selKey());
  const a = accById(acc);
  const starred = row?.starred;
  R.innerHTML = `<div class="toolbar">
      <button class="tb mob" id="back" title="رجوع">→</button>
      <button class="tb" id="rep">↩ رد</button><button class="tb" id="repAll">↩↩ رد للكل</button><button class="tb" id="fwd">↪ تحويل</button>
      <span class="sep"></span>
      ${f === 'inbox' ? '<button class="tb" id="arc">🗄 أرشفة</button>' : f !== 'trash' ? '<button class="tb" id="toInbox">📥 للوارد</button>' : ''}
      ${f !== 'trash' ? '<button class="tb red" id="del">🗑 حذف</button>' : ''}
      <button class="tb" id="unr">✉ غير مقروءة</button><button class="tb" id="star">${starred ? '★ إلغاء النجمة' : '☆ نجمة'}</button>
    </div>
    <div class="msg"><h1>${esc(m.subject)}</h1>
      <div class="hdr"><div class="av big" style="border-color:${a.color}">${esc(initials(m.from[0]?.name || m.from[0]?.address))}</div>
      <div class="meta"><div class="from">${ppl(m.from)}</div>
        <div>إلى: ${ppl(m.to)}${m.cc.length ? `<br>نسخة: ${ppl(m.cc)}` : ''}</div>
        <div class="mute"><span class="num">${new Date(m.date).toLocaleString('ar-SA-u-nu-latn-ca-gregory', { dateStyle: 'medium', timeStyle: 'short' })}</span> · <i class="dot" style="background:${a.color}"></i><span class="en">${esc(a.email)}</span></div></div></div>
      ${m.attachments.length ? `<div class="atts">${m.attachments.map((x) => attCard(acc, f, uid, x)).join('')}</div>` : ''}
    </div>
    <div class="body" id="body"></div>
    <div class="quick"><button class="btn" id="rep2">↩ رد</button><button class="btn" id="fwd2">↪ تحويل</button></div>`;
  const body = $('#body');
  if (m.html) {
    const fr = document.createElement('iframe');
    fr.setAttribute('sandbox', 'allow-same-origin allow-popups allow-popups-to-escape-sandbox');
    fr.srcdoc = `<!doctype html><meta charset="utf-8"><base target="_blank"><style>body{margin:16px;font-family:Tahoma,Arial,sans-serif;word-wrap:break-word}img{max-width:100%;height:auto}</style>${m.html}`;
    fr.onload = () => { const fit = () => { try { fr.style.height = fr.contentDocument.documentElement.scrollHeight + 24 + 'px'; } catch {} }; fit(); setTimeout(fit, 600); setTimeout(fit, 2000); };
    body.appendChild(fr);
  } else body.innerHTML = `<pre dir="auto">${esc(m.text)}</pre>`;

  const back = () => (location.hash = `#/${folder}`);
  $('#back').onclick = back;
  const act = async (what, msg, leave = true) => {
    try {
      await call(`msg/${acc}/${f}/${uid}/${what}`, { method: 'POST', body: {} }); toast(msg);
      if (leave) { rows = rows.filter((r) => !(r.acc === acc && r.uid === Number(uid))); renderList(); back(); }
    } catch (e) { toast(e.message); }
  };
  if ($('#arc')) $('#arc').onclick = () => act('archive', 'انأرشفت');
  if ($('#toInbox')) $('#toInbox').onclick = () => act('inbox', 'رجعت للوارد', false);
  if ($('#del')) $('#del').onclick = () => act('trash', 'انحذفت');
  $('#unr').onclick = () => { if (row) row.seen = false; if (f === 'inbox') unread[acc] = (unread[acc] || 0) + 1; act('unread', 'صارت غير مقروءة'); renderNav(); };
  $('#star').onclick = async () => { await act(starred ? 'unstar' : 'star', starred ? 'انشالت النجمة' : 'تمّت النجمة ★', false); if (row) row.starred = !starred; renderList(selKey()); openMsg(acc, f, uid); };

  const quote = () => `\n\n\nفي ${new Date(m.date).toLocaleString('ar-SA-u-nu-latn-ca-gregory')} كتب ${m.from[0]?.name || m.from[0]?.address || ''}:\n` + (m.text || '').split('\n').map((l) => '> ' + l).join('\n');
  const mine = [a.email, ...(a.aliases || [])];
  const myAddr = [...m.to, ...m.cc].map((p) => p.address?.toLowerCase()).find((x) => mine.includes(x)) || a.email;
  const reSub = /^(re|رد)\s*:/i.test(m.subject) ? m.subject : 'Re: ' + m.subject;
  const replyTo = (m.replyTo.length ? m.replyTo : m.from).map((p) => p.address);
  const base = { acc, from: myAddr, inReplyTo: m.messageId, references: [...m.references, m.messageId].filter(Boolean) };
  const reply = () => { draft = { ...base, to: replyTo.join(', '), cc: '', subject: reSub, text: quote(), title: 'رد' }; location.hash = `#/${folder}/c`; };
  const fwd = () => { draft = { acc, from: myAddr, to: '', cc: '', subject: 'Fwd: ' + m.subject, title: 'تحويل', fwd: { acc, f, uid, atts: m.attachments },
    text: '\n\n\n---------- رسالة محوّلة ----------\nمن: ' + (m.from[0]?.address || '') + '\nالتاريخ: ' + new Date(m.date).toLocaleString('ar-SA-u-nu-latn-ca-gregory') + '\nالعنوان: ' + m.subject + '\n\n' + (m.text || '') }; location.hash = `#/${folder}/c`; };
  $('#rep').onclick = $('#rep2').onclick = reply;
  $('#fwd').onclick = $('#fwd2').onclick = fwd;
  $('#repAll').onclick = () => {
    const others = [...m.to, ...m.cc].map((p) => p.address).filter((x) => x && !mine.includes(x.toLowerCase()) && !replyTo.includes(x));
    draft = { ...base, to: replyTo.join(', '), cc: others.join(', '), subject: reSub, text: quote(), title: 'رد للكل' }; location.hash = `#/${folder}/c`;
  };
}
function attCard(acc, f, uid, x) {
  const ext = (x.name.split('.').pop() || '').slice(0, 4).toUpperCase();
  const canView = /^(image\/|application\/pdf)/.test(x.type || '');
  return `<div class="att"><div class="ext en">${esc(ext || 'FILE')}</div><div class="an"><div class="ellip">${esc(x.name)}</div>
    <small class="num mute">${x.size > 1048576 ? (x.size / 1048576).toFixed(1) + ' MB' : Math.ceil(x.size / 1024) + ' KB'}</small></div>
    ${canView ? `<a href="api/att/${acc}/${f}/${uid}/${x.i}?view" target="_blank" rel="noopener" title="عرض">👁</a>` : ''}
    <a href="api/att/${acc}/${f}/${uid}/${x.i}" title="تحميل">⬇</a></div>`;
}

// ---------- كتابة رسالة ----------
function compose() {
  $('#shell').classList.add('reading');
  const [ca, ce] = accFilter.split('|');
  const d = draft || { acc: ca || me.accounts[0]?.id, from: ce || accById(ca || me.accounts[0]?.id).email, to: '', cc: '', subject: '', text: '' };
  const froms = me.accounts.flatMap((a) => [a.email, ...(a.aliases || [])].map((e) => ({ acc: a.id, e })));
  $('#read').innerHTML = `<div class="toolbar"><button class="tb mob" id="back">→</button><b class="tt">${esc(d.title || 'رسالة جديدة')}</b>
      <span class="grow"></span><button class="tb" id="discard">تجاهل</button><button class="btn gold" id="go">إرسال ➤</button></div>
    <div class="form compose">
    <label class="fl"><span>من</span><select id="from">${froms.map((f) => `<option value="${f.acc}|${esc(f.e)}" ${f.acc === d.acc && f.e === d.from ? 'selected' : ''}>${esc(f.e)}</option>`).join('')}</select></label>
    <label class="fl"><span>إلى</span><input id="to" class="ltr" value="${esc(d.to)}" placeholder="name@example.com"></label>
    <label class="fl"><span>نسخة</span><input id="cc" class="ltr" value="${esc(d.cc)}"></label>
    <label class="fl"><span>العنوان</span><input id="subject" value="${esc(d.subject)}"></label>
    <div class="attbar"><label class="btn">📎 إرفاق ملف<input id="files" type="file" multiple hidden></label><span id="flist" class="mute"></span></div>
    <textarea id="text" dir="auto" placeholder="اكتب رسالتك…">${esc(d.text)}</textarea></div>`;
  const back = () => (history.length > 1 ? history.back() : (location.hash = `#/${folder}`));
  $('#back').onclick = $('#discard').onclick = () => { draft = null; back(); };
  const showFiles = () => { const n = [...$('#files').files].map((f) => f.name); $('#flist').textContent = n.join('، ') + (d.fwd?.atts?.length ? (n.length ? '، ' : '') + 'مرفقات الرسالة الأصلية: ' + d.fwd.atts.map((x) => x.name).join('، ') : ''); };
  $('#files').onchange = showFiles; showFiles();
  if (!d.to) setTimeout(() => $('#to').focus(), 50); else { const t = $('#text'); t.focus(); t.setSelectionRange(0, 0); }
  $('#go').onclick = async () => {
    const [acc, from] = $('#from').value.split('|');
    const attachments = await Promise.all([...$('#files').files].map((f) => new Promise((ok) => {
      const r = new FileReader(); r.onload = () => ok({ name: f.name, data: String(r.result).split(',')[1] }); r.readAsDataURL(f);
    })));
    $('#go').disabled = true; $('#go').textContent = 'جاري الإرسال…';
    try {
      await call('send', { method: 'POST', body: { acc, from, to: $('#to').value, cc: $('#cc').value, subject: $('#subject').value, text: $('#text').value,
        inReplyTo: d.inReplyTo, references: d.references, attachments, forwardOf: d.fwd ? { acc: d.fwd.acc, f: d.fwd.f, uid: d.fwd.uid } : undefined } });
      draft = null; toast('انرسلت ✅'); back();
    } catch (e) { toast(e.message); $('#go').disabled = false; $('#go').textContent = 'إرسال ➤'; }
  };
}

// ---------- الإعدادات ----------
async function settings() {
  $('#shell').classList.add('reading');
  me = await call('me');
  const push = 'Notification' in window && Notification.permission === 'granted';
  $('#read').innerHTML = `<div class="toolbar"><button class="tb mob" id="back">→</button><b class="tt">الإعدادات</b></div><div class="settings">
    <h2>الحسابات المربوطة</h2>${me.accounts.map((a) => `<div class="acct"><i class="dot" style="background:${a.color}"></i>
      <div class="t"><div>${esc(a.name)}</div><small class="en">${esc(a.email)}${a.aliases.length ? ' + ' + a.aliases.map(esc).join(', ') : ''}</small>
      <div class="${a.status === 'ok' ? 'ok' : 'err'} sm">${a.status === 'ok' ? 'متصل' : esc(a.error || a.status)}</div></div>
      <button class="btn red" data-del="${a.id}">حذف</button></div>`).join('') || '<div class="empty">ما فيه حسابات بعد</div>'}
    <h2>إضافة حساب</h2>
    <div class="help">لكل إيميل في Google: افتح <a href="https://myaccount.google.com/apppasswords" target="_blank" rel="noopener">كلمات مرور التطبيقات</a>
      وأنت داخل بنفس الإيميل، سمّها «حوات ميل»، وانسخ الرمز (16 حرف) والصقه هنا. يحتاج التحقق بخطوتين يكون مفعّل.</div>
    <div class="form">
      <label>الإيميل<input id="em" class="ltr" type="email" placeholder="info@ksafish.com"></label>
      <label>كلمة مرور التطبيقات<input id="pw" class="ltr" type="password" autocomplete="off" placeholder="xxxx xxxx xxxx xxxx"></label>
      <label>اسم يظهر لك (اختياري)<input id="nm" placeholder="موسوعة KSAFish"></label>
      <label>عناوين إضافية توصل لنفس الصندوق (اختياري)<input id="al" class="ltr" placeholder="info@hawat.id, support@hawat.id"></label>
      <button class="btn gold" id="add">ربط الحساب</button></div>
    <h2>الإشعارات</h2>
    <div class="form"><div>${push ? '<span class="ok">الإشعارات مفعّلة على هذا الجهاز</span>' : 'فعّل الإشعارات عشان توصلك الرسائل الجديدة على هذا الجهاز.'}</div>
      <button class="btn ${push ? '' : 'gold'}" id="push">${push ? 'إعادة التفعيل' : 'تفعيل الإشعارات'}</button></div>
    <h2>الجهاز</h2>
    <div class="form"><div class="mute sm">لتثبيت الأيقونة: من قائمة Chrome (⋮) اختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية».</div>
      <button class="btn" id="install">تثبيت حوات ميل</button>
      <button class="btn red" id="out">تسجيل خروج</button></div></div>`;
  $('#back').onclick = () => (location.hash = `#/${folder}`);
  $('#read').querySelectorAll('[data-del]').forEach((b) => (b.onclick = async () => {
    if (!b.dataset.sure) { b.dataset.sure = '1'; b.textContent = 'متأكد؟'; setTimeout(() => { delete b.dataset.sure; b.textContent = 'حذف'; }, 3000); return; }
    await call('accounts/' + b.dataset.del, { method: 'DELETE' }).catch((e) => toast(e.message)); settings(); renderNav();
  }));
  $('#add').onclick = async () => {
    $('#add').disabled = true; $('#add').textContent = 'جاري التحقق…';
    try { await call('accounts', { method: 'POST', body: { email: $('#em').value, pass: $('#pw').value, name: $('#nm').value, aliases: $('#al').value } }); toast('تم الربط ✅'); await settings(); renderNav(); setTimeout(() => loadList(true), 3000); }
    catch (e) { toast(e.message); $('#add').disabled = false; $('#add').textContent = 'ربط الحساب'; }
  };
  $('#push').onclick = enablePush;
  $('#install').onclick = () => (deferredInstall ? deferredInstall.prompt() : toast('من قائمة Chrome (⋮) ← تثبيت التطبيق'));
  $('#out').onclick = async () => { await call('logout', { method: 'POST', body: {} }).catch(() => {}); me = null; showLogin(); };
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

// ---------- التنقل: #/<مجلد>[/m/<حساب>/<مجلد>/<رقم> | /c | /s] ----------
async function route() {
  if (!me) return;
  shell();
  const h = location.hash.replace(/^#\/?/, '');
  const [f0, sub, ...rest] = h.split('/');
  const f = FOLDERS.some((x) => x.id === f0) ? f0 : 'inbox';
  if (f !== folder || !route.done) { folder = f; route.done = true; renderNav(); loadList(); }
  else { renderNav(); renderList(selKey()); }
  if (sub === 'm' && rest.length === 3) return openMsg(rest[0], rest[1], rest[2]);
  if (sub === 'c') return compose();
  if (sub === 's') return settings().catch(() => {});
  draft = null; readEmpty();
}
window.addEventListener('hashchange', route);
window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); deferredInstall = e; });
$('#menu').onclick = () => $('#shell')?.classList.toggle('navopen');
$('#settingsBtn').onclick = () => (location.hash = `#/${folder}/s`);
$('#search').oninput = (e) => { query = e.target.value; renderList(selKey()); };
$('#refresh').onclick = async () => { toast('جاري التحديث…'); await call('refresh', { method: 'POST', body: {} }).catch(() => {}); await loadList(true); };
document.addEventListener('visibilitychange', () => { if (!document.hidden && me) loadList(true); });
setInterval(() => { if (!document.hidden && me && folder === 'inbox') loadList(true); }, 30000);

async function boot() {
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js', { scope: './' }).catch(() => {});
  try { me = await call('me'); } catch { return; }
  app.innerHTML = ''; route.done = false;
  route();
}
boot();
