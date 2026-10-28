/// صفحة لوحة الأدمن على https://hawat.id/api/admin. الصفحة نفسها عامة، وكل البيانات تحتاج الرمز
/// FISHID_ADMIN_TOKEN (يُحفظ في sessionStorage للجلسة فقط).
const adminPage = r'''<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>FISH ID: لوحة الأدمن</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@600;700;800&family=Tajawal:wght@400;500;700;800&display=swap" rel="stylesheet">
<style>
:root{--navy:#0B2236;--navy-2:#122F48;--navy-3:#1B3D5C;--gold:#F2C14E;--gold-soft:#FDF3DA;--gold-ink:#7A5300;--bg:#F3F6F9;--surface:#fff;--ink:#0B2236;--muted:#5A6B7B;--line:#E1E8EE;--chip:#EDF2F6;--good:#17804F;--good-soft:#E2F4EA;--bad:#B3261E;--bad-soft:#FBE5E3;--on-navy:#B8C8D8;--shadow:0 1px 2px rgba(11,34,54,.05),0 4px 16px rgba(11,34,54,.06)}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 Tajawal,system-ui,sans-serif}
.shell{display:grid;grid-template-columns:240px 1fr;min-height:100vh}
aside{background:var(--navy);color:#fff;padding:20px 14px;position:sticky;top:0;height:100vh;display:flex;flex-direction:column;gap:18px}
.brand{display:flex;align-items:center;gap:10px;padding:0 6px}
.brand svg{flex:none}
.brand b{font:800 19px Montserrat,sans-serif;letter-spacing:.5px}
.brand b span{color:var(--gold)}
.brand small{display:block;color:var(--on-navy);font-size:12px}
nav{display:flex;flex-direction:column;gap:4px}
nav button{display:flex;align-items:center;gap:10px;background:transparent;color:var(--on-navy);border:0;border-radius:10px;padding:10px 12px;font:500 15px Tajawal;cursor:pointer;text-align:right}
nav button:hover{background:var(--navy-2);color:#fff}
nav button.on{background:var(--gold);color:var(--navy);font-weight:800}
nav svg{width:18px;height:18px;flex:none}
aside .out{margin-top:auto;background:transparent;border:1px solid var(--navy-3);color:var(--on-navy);border-radius:10px;padding:8px;font:500 14px Tajawal;cursor:pointer}
main{padding:24px clamp(16px,3vw,36px);max-width:1200px;width:100%}
.top{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-bottom:18px}
.top h1{margin:0;font-size:24px;font-weight:800}
.top .sub{color:var(--muted);font-size:14px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:14px}
.cols{display:grid;grid-template-columns:3fr 2fr;gap:14px;margin-top:14px}
.card{background:var(--surface);border:1px solid var(--line);border-radius:16px;padding:16px 18px;box-shadow:var(--shadow);min-width:0}
.card h3{margin:0 0 12px;font-size:16px;font-weight:800;display:flex;justify-content:space-between;align-items:center;gap:8px}
.kpi .k{color:var(--muted);font-size:14px;font-weight:500}
.kpi .v{font:700 27px Montserrat,Tajawal,sans-serif;margin:4px 0 2px;direction:ltr;text-align:right;font-variant-numeric:tabular-nums}
.kpi .v small{font:500 14px Tajawal;color:var(--muted)}
.kpi .n{color:var(--muted);font-size:13px}
.kpi.hero{background:var(--navy);color:#fff;border-color:var(--navy)}
.kpi.hero .k,.kpi.hero .n,.kpi.hero .v small{color:var(--on-navy)}
.kpi.hero .v,.kpi.hero .pos{color:var(--gold)!important}.kpi.hero .neg{color:#FF9A8F!important}
.pos{color:var(--good)!important}.neg{color:var(--bad)!important}
.k{color:var(--muted);font-size:14px}
table{width:100%;border-collapse:collapse}
th,td{padding:10px 8px;border-bottom:1px solid var(--line);text-align:right;font-size:14px;vertical-align:middle}
th{color:var(--muted);font-weight:700;font-size:13px}
tr:last-child td{border-bottom:0}
td.num,th.num{text-align:left;direction:ltr;font-variant-numeric:tabular-nums;white-space:nowrap}
tfoot td{font-weight:800;border-top:2px solid var(--line)}
.wrap{overflow-x:auto}
.mono{font-family:ui-monospace,monospace;direction:ltr;font-size:12px}
.pill{display:inline-block;padding:1px 10px;border-radius:999px;background:var(--chip);font-size:12px;font-weight:500;white-space:nowrap}
.pill.pay{background:var(--gold-soft);color:var(--gold-ink);font-weight:700}
.pill.ok{background:var(--good-soft);color:var(--good)}
.pill.no{background:var(--bad-soft);color:var(--bad)}
.pill.auto{background:#E4EEF8;color:#21507A}
button.act{background:var(--navy);color:#fff;border:0;border-radius:10px;padding:8px 14px;font:500 14px Tajawal;cursor:pointer;white-space:nowrap}
button.act:hover{background:var(--navy-2)}
button.gold{background:var(--gold);color:var(--navy);font-weight:800}
button.gold:hover{background:#E8B33A}
button.ghost{background:var(--chip);color:var(--ink)}
button.ghost:hover{background:var(--line)}
button.sm{padding:4px 10px;font-size:13px}
input,select,textarea{font:15px Tajawal;padding:8px 10px;border:1px solid var(--line);border-radius:10px;background:#fff;color:var(--ink);max-width:100%}
input:focus,select:focus{outline:2px solid var(--gold);outline-offset:0;border-color:var(--gold)}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.form{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:10px;align-items:end}
.form label{display:flex;flex-direction:column;gap:4px;font-size:13px;color:var(--muted)}
.seg{display:inline-flex;background:var(--chip);border-radius:10px;padding:3px}
.seg button{border:0;background:transparent;padding:6px 12px;border-radius:8px;font:500 14px Tajawal;cursor:pointer;color:var(--muted)}
.seg button.on{background:#fff;color:var(--ink);font-weight:700;box-shadow:var(--shadow)}
.login{max-width:400px;margin:12vh auto;text-align:center}
.login input{width:100%;margin:14px 0 10px}
.photos{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px}
.thumbs{display:flex;gap:6px;margin-bottom:8px}
.thumbs img{width:33%;aspect-ratio:1;object-fit:cover;border-radius:10px;background:var(--chip)}
.msg{color:var(--muted);padding:28px;text-align:center}
.err{color:var(--bad)}
label.set{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid var(--line)}
label.set input{width:120px;direction:ltr}
.bars{display:flex;align-items:flex-end;gap:3px;height:150px;padding-top:8px}
.bars div{flex:1;background:var(--navy-3);border-radius:4px 4px 0 0;min-height:2px;position:relative}
.bars div:hover{background:var(--gold)}
.axis{display:flex;justify-content:space-between;color:var(--muted);font-size:12px;margin-top:6px}
.pl{display:grid;grid-template-columns:repeat(12,1fr);gap:6px;align-items:end;height:180px}
.pl .m{display:flex;flex-direction:column;align-items:center;gap:4px;height:100%;justify-content:flex-end;cursor:pointer}
.pl .pair{display:flex;gap:2px;align-items:flex-end;width:100%;justify-content:center;flex:1}
.pl .pair i{display:block;width:40%;border-radius:3px 3px 0 0;min-height:2px}
.pl .in{background:var(--good)}.pl .out{background:var(--bad);opacity:.75}
.pl .m.on{background:var(--gold-soft);border-radius:8px}
.pl small{font-size:11px;color:var(--muted)}
.legend{display:flex;gap:14px;font-size:13px;color:var(--muted)}
.legend i{display:inline-block;width:10px;height:10px;border-radius:3px;margin-inline-end:5px;vertical-align:middle}
.meter{height:8px;background:var(--chip);border-radius:99px;overflow:hidden;margin-top:4px}
.meter i{display:block;height:100%;background:var(--gold);border-radius:99px}
.note{background:var(--gold-soft);border-radius:12px;padding:10px 14px;font-size:14px;color:var(--gold-ink);margin-top:14px}
@media (max-width:860px){
  .shell{grid-template-columns:1fr}
  aside{position:sticky;height:auto;padding:10px 12px;flex-direction:row;align-items:center;gap:10px;z-index:5;overflow-x:auto}
  .brand small,aside .out{display:none}
  nav{flex-direction:row}
  nav button{padding:8px 10px;white-space:nowrap}
  nav button span{display:none}
  nav button.on span{display:inline}
  .cols{grid-template-columns:1fr}
  .pl small{font-size:9px}
}
</style>
</head>
<body>
<div class="shell" id="shell" hidden>
<aside>
  <div class="brand">
    <svg width="34" height="34" viewBox="0 0 34 34" aria-hidden="true"><rect width="34" height="34" rx="9" fill="#122F48"/><path d="M6 11V7h4M28 11V7h-4M6 23v4h4M28 23v4h-4" stroke="#F2C14E" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M9 17c3-4 8-5 12-2l4-3v10l-4-3c-4 3-9 2-12-2z" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>
    <div><b>FISH <span>ID</span></b><small>لوحة الإدارة</small></div>
  </div>
  <nav id="nav"></nav>
  <button class="out" id="out">خروج</button>
</aside>
<main id="app"></main>
</div>
<main id="login"></main>
<script>
const $ = (s, e = document) => e.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money = n => (Math.round((n || 0) * 100) / 100).toLocaleString('ar-SA', {minimumFractionDigits: 2, maximumFractionDigits: 2});
const sar = n => money(n) + ' <small>ر.س</small>';
const num = n => (n || 0).toLocaleString('ar-SA');
const when = s => s ? new Date(s).toLocaleString('ar-SA', {dateStyle: 'medium', timeStyle: 'short'}) : '';
const monthName = m => new Date(m + '-01T00:00:00Z').toLocaleDateString('ar-SA-u-ca-gregory', {month: 'long', year: 'numeric', timeZone: 'UTC'});
const monthShort = m => new Date(m + '-01T00:00:00Z').toLocaleDateString('ar-SA-u-ca-gregory', {month: 'short', timeZone: 'UTC'});
const thisMonth = () => new Date().toISOString().slice(0, 7);
const storageName = {ice: 'على ثلج', fridge: 'ثلاجة', room: 'حرارة الغرفة', hot: 'بالحر', frozen: 'مجمّد', unknown: 'الحفظ غير معروف'};
const planName = {free: 'مجاني', monthly: 'شهري', yearly: 'سنوي', shop: 'محل'};
// اسم المنتج من رقمه في المتجر (fishid_monthly، fishid_yearly...).
const productName = id => /shop/.test(id) ? 'باقة المحل' : /year|annual/.test(id) ? 'الاشتراك السنوي' : /month/.test(id) ? 'الاشتراك الشهري' : id;
const repeatName = {once: 'مرة وحدة', monthly: 'كل شهر', yearly: 'كل سنة'};
const providers = {
  expense: ['Anthropic (Claude)', 'Hostinger (الخادم)', 'Google (Play و Cloud)', 'Apple', 'RevenueCat', 'الدومين', 'تسويق وإعلانات', 'رواتب ومستقلين', 'رسوم بنكية', 'رسوم حكومية', 'أخرى'],
  income: ['محلات (تحويل بنكي)', 'رعاية أو منحة', 'Google Play', 'App Store', 'أخرى'],
};
const icons = {
  home: '<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
  money: '<rect x="3" y="6" width="18" height="12" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M7 9v6M17 9v6"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.5 3.4-5.5 6.5-5.5s5.7 2 6.5 5.5M16 4.5a3.5 3.5 0 0 1 0 7M18 14.5c1.9.6 3.1 2.6 3.5 5.5"/>',
  scans: '<path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M4 16v3a1 1 0 0 0 1 1h3M16 20h3a1 1 0 0 0 1-1v-3M7 12c2-3 6-3.5 9-1.5l2-1.5v6l-2-1.5c-3 2-7 1.5-9-1.5z"/>',
  contrib: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-8 8"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>',
  codes: '<rect x="3" y="8" width="18" height="12" rx="2"/><path d="M12 8v12M3 12h18M12 8c-2-4-6-4-6-1.5S10 8 12 8zm0 0c2-4 6-4 6-1.5S14 8 12 8z"/>',
};
const tabs = [['home', 'الرئيسية'], ['money', 'المحاسبة'], ['users', 'المستخدمين'], ['scans', 'الفحوصات'], ['contrib', 'صور المساهمين'], ['settings', 'الباقات والأسعار'], ['codes', 'رموز الهدايا']];
let token = '';
try { token = sessionStorage.getItem('fishid-admin') || ''; } catch (e) {}
let names = {};

async function api(path, opts = {}) {
  const res = await fetch('admin/' + path, {...opts, headers: {authorization: 'Bearer ' + token, 'content-type': 'application/json'}});
  if (res.status === 401) { logout(); throw new Error('الرمز غير صحيح'); }
  if (!res.ok) throw new Error((await res.json().catch(() => ({}))).message || 'خطأ ' + res.status);
  return (res.headers.get('content-type') || '').includes('json') ? res.json() : res.blob();
}
const post = (path, body) => api(path, {method: 'POST', body: JSON.stringify(body)});
const sp = id => names[id] ? `${esc(names[id])} <span class="mono">${esc(id)}</span>` : `<span class="mono">${esc(id || '')}</span>`;
const heading = (title, sub = '', extra = '') => `<div class="top"><div><h1>${title}</h1>${sub ? `<div class="sub">${sub}</div>` : ''}</div>${extra}</div>`;
const kpi = (k, v, note = '', cls = '') => `<div class="card kpi ${cls}"><div class="k">${k}</div><div class="v">${v}</div>${note ? `<div class="n">${note}</div>` : ''}</div>`;
const signed = n => `<span class="${n < 0 ? 'neg' : 'pos'}">${sar(n)}</span>`;

function logout() {
  token = '';
  try { sessionStorage.removeItem('fishid-admin'); } catch (e) {}
  $('#shell').hidden = true;
  $('#login').hidden = false;
  $('#login').innerHTML = `<div class="card login">
    <svg width="56" height="56" viewBox="0 0 34 34" aria-hidden="true"><rect width="34" height="34" rx="9" fill="#0B2236"/><path d="M6 11V7h4M28 11V7h-4M6 23v4h4M28 23v4h-4" stroke="#F2C14E" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M9 17c3-4 8-5 12-2l4-3v10l-4-3c-4 3-9 2-12-2z" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>
    <h2 style="margin:10px 0 4px">لوحة إدارة FISH ID</h2>
    <div class="k">الصق رمز الأدمن من السيرفر (grep ADMIN /opt/fish-id/server/.env)</div>
    <input id="tok" type="password" autocomplete="current-password" placeholder="الرمز">
    <button class="act gold" id="go" style="width:100%">دخول</button><div id="lerr" class="err" style="margin-top:8px"></div></div>`;
  const go = async () => {
    token = $('#tok').value.trim();
    try { await api('stats'); try { sessionStorage.setItem('fishid-admin', token); } catch (e) {} start(); }
    catch (e) { $('#lerr').textContent = e.message; }
  };
  $('#go').onclick = go;
  $('#tok').onkeydown = e => { if (e.key === 'Enter') go(); };
}

async function start() {
  $('#login').hidden = true;
  $('#shell').hidden = false;
  $('#nav').innerHTML = tabs.map(([k, v]) => `<button data-tab="${k}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${icons[k]}</svg><span>${v}</span></button>`).join('');
  document.querySelectorAll('#nav button').forEach(b => b.onclick = () => show(b.dataset.tab));
  $('#out').onclick = logout;
  names = await api('species').catch(() => ({}));
  show(location.hash.slice(1) in views ? location.hash.slice(1) : 'home');
}

async function show(tab, ...args) {
  document.querySelectorAll('#nav button').forEach(b => b.classList.toggle('on', b.dataset.tab === tab));
  history.replaceState(null, '', '#' + tab);
  $('#app').innerHTML = '<div class="msg">جاري التحميل…</div>';
  try { await views[tab](...args); } catch (e) { $('#app').innerHTML = `<div class="msg err">${esc(e.message)}</div>`; }
}

function dailyChart(daily) {
  const max = Math.max(1, ...daily.map(d => d.n));
  return `<div class="bars">${daily.map(d => `<div style="height:${d.n / max * 100}%" title="${d.day}: ${d.n} فحص، ${money(d.sar)} ر.س"></div>`).join('')}</div>
    <div class="axis"><span>${daily[0].day.slice(5)}</span><span>${daily[daily.length - 1].day.slice(5)}</span></div>`;
}

function plChart(history, current) {
  const max = Math.max(1, ...history.flatMap(h => [h.incomeSar, h.expensesSar]));
  return `<div class="pl">${history.map(h => `<div class="m ${h.month === current ? 'on' : ''}" data-m="${h.month}" title="${monthName(h.month)}: دخل ${money(h.incomeSar)}، مصاريف ${money(h.expensesSar)}، صافي ${money(h.netSar)}">
      <div class="pair"><i class="in" style="height:${h.incomeSar / max * 100}%"></i><i class="out" style="height:${h.expensesSar / max * 100}%"></i></div>
      <small>${monthShort(h.month)}</small></div>`).join('')}</div>
    <div class="legend" style="margin-top:8px"><span><i style="background:var(--good)"></i>الدخل الصافي</span><span><i style="background:var(--bad);opacity:.75"></i>المصاريف</span></div>`;
}

const views = {
  async home() {
    const s = await api('stats');
    const l = s.ledger;
    $('#app').innerHTML = heading('الرئيسية', 'نظرة سريعة على ' + monthName(thisMonth())) + `
      <div class="grid">
        ${l ? kpi('صافي الربح هالشهر', signed(l.netSar), `دخل ${money(l.incomeSar)} · مصاريف ${money(l.expensesSar)}`, 'hero') : ''}
        ${kpi('المشتركين', num(s.paying), `شهري ${num(s.plans.monthly)} · سنوي ${num(s.plans.yearly)} · محلات ${num(s.plans.shop)}`)}
        ${kpi('المستخدمين', num(s.users), `جدد اليوم ${num(s.newToday)} · هالأسبوع ${num(s.newWeek)}`)}
        ${kpi('خلصت مجانيتهم', num(s.outOfFree), 'ما اشتركوا للحين')}
        ${kpi('فحوصات اليوم', num(s.scansToday), `هالشهر ${num(s.scansMonth)}`)}
        ${kpi('تكلفة الفحص', sar(s.costPerScanSar), `متوسط ${(s.avgSeconds || 0).toFixed(1)} ثانية`)}
        ${kpi('الدخل الشهري المتكرر', sar(s.mrrSar), 'تقديري من المشتركين الحاليين')}
      </div>
      <div class="cols">
        <div class="card"><h3>الفحوصات آخر 30 يوم <span class="k">${num(s.daily.reduce((t, d) => t + d.n, 0))} فحص</span></h3>${dailyChart(s.daily)}</div>
        <div class="card"><h3>أكثر الأنواع فحصًا هالشهر</h3>
          <table>${s.topSpecies.map(t => `<tr><td>${sp(t.id)}<div class="meter"><i style="width:${t.n / s.topSpecies[0].n * 100}%"></i></div></td><td class="num">${num(t.n)}</td></tr>`).join('') || '<tr><td class="msg">ما فيه فحوصات للحين</td></tr>'}</table></div>
      </div>`;
  },

  async money(month = thisMonth()) {
    const r = await api('ledger?month=' + month);
    const store = r.income.filter(i => i.auto);
    $('#app').innerHTML = heading('المحاسبة', 'الدخل والمصاريف والصافي لكل شهر، بالريال السعودي',
      `<div class="row"><input type="month" id="mon" value="${r.month}"><button class="act ghost" id="csv">تصدير Excel</button></div>`) + `
      <div class="grid">
        ${kpi('صافي الربح', signed(r.netSar), r.margin != null ? `الهامش ${num(r.margin)}%` : monthName(r.month), 'hero')}
        ${kpi('الدخل الصافي', sar(r.incomeSar), `مبيعات المتجر ${num(r.paidSales)}${r.sandboxSales ? ` · تجريبية ${num(r.sandboxSales)} (ما تنحسب)` : ''}`)}
        ${kpi('المصاريف', sar(r.expensesSar), `${num(r.expenses.length)} بند`)}
        ${kpi('ما يوصلك من المتجر', sar(r.grossSar - r.storeTaxSar - r.storeFeeSar), `من ${money(r.grossSar)}: ضريبة ${money(r.storeTaxSar)} · عمولة ${money(r.storeFeeSar)}`)}
        ${kpi('تكلفة الفحص', sar(r.scans ? (r.expenses.find(e => e.auto && e.n)?.sar || 0) / r.scans : 0), `${num(r.scans)} فحص هالشهر`)}
      </div>
      <div class="cols">
        <div class="card"><h3>آخر 12 شهر <span class="k">اضغط الشهر لعرضه</span></h3>${plChart(r.history, r.month)}</div>
        <div class="card"><h3>المصاريف حسب المزوّد</h3>
          <table>${r.providers.map(p => `<tr><td>${esc(p.provider)}<div class="meter"><i style="width:${p.sar / r.providers[0].sar * 100}%"></i></div></td><td class="num">${money(p.sar)}</td></tr>`).join('') || '<tr><td class="msg">ما فيه مصاريف هالشهر</td></tr>'}</table></div>
      </div>
      <div class="card" style="margin-top:14px"><h3>الدخل · ${monthName(r.month)}</h3><div class="wrap"><table>
        <tr><th>البند</th><th>المصدر</th><th class="num">العدد</th><th class="num">الإجمالي</th><th class="num">الضريبة</th><th class="num">عمولة المتجر</th><th class="num">الصافي</th><th></th></tr>
        ${r.income.map(i => `<tr><td>${esc(i.auto ? productName(i.label) : i.label)} ${i.auto ? '<span class="pill auto">تلقائي</span>' : i.repeat !== 'once' ? `<span class="pill">${repeatName[i.repeat]}</span>` : ''}${i.note ? `<div class="k">${esc(i.note)}</div>` : ''}</td>
          <td>${esc(i.provider)}</td><td class="num">${i.auto ? num(i.n) + (i.refunds ? ` (−${num(i.refunds)})` : '') : ''}</td>
          <td class="num">${money(i.auto ? i.grossSar : i.sar)}</td><td class="num">${i.auto ? money(i.taxSar) : ''}</td><td class="num">${i.auto ? money(i.feeSar) : ''}</td>
          <td class="num"><b>${money(i.sar)}</b></td><td>${rowActions(i, r.month)}</td></tr>`).join('') || '<tr><td colspan="8" class="msg">ما فيه دخل مسجّل هالشهر</td></tr>'}
        <tfoot><tr><td colspan="6">إجمالي الدخل الصافي</td><td class="num">${money(r.incomeSar)}</td><td></td></tr></tfoot></table></div></div>
      <div class="card" style="margin-top:14px"><h3>المصاريف · ${monthName(r.month)}</h3><div class="wrap"><table>
        <tr><th>البند</th><th>المزوّد</th><th>التكرار</th><th class="num">المبلغ</th><th></th></tr>
        ${r.expenses.map(e => `<tr><td>${esc(e.label)} ${e.auto ? '<span class="pill auto">تلقائي</span>' : ''}${e.n ? `<div class="k">${num(e.n)} فحص</div>` : ''}${e.note ? `<div class="k">${esc(e.note)}</div>` : ''}</td>
          <td>${esc(e.provider)}</td><td>${e.auto ? 'يُحسب من الاستخدام' : repeatName[e.repeat]}${e.original ? `<div class="k mono">${esc(e.original)}</div>` : ''}</td>
          <td class="num"><b>${money(e.sar)}</b></td><td>${rowActions(e, r.month)}</td></tr>`).join('') || '<tr><td colspan="5" class="msg">ما فيه مصاريف مسجّلة هالشهر</td></tr>'}
        <tfoot><tr><td colspan="3">إجمالي المصاريف</td><td class="num">${money(r.expensesSar)}</td><td></td></tr></tfoot></table></div></div>
      <div class="card" style="margin-top:14px"><h3>إضافة قيد</h3>
        <div class="form">
          <label>النوع<div class="seg" id="kind"><button data-k="expense" class="on">مصروف</button><button data-k="income">دخل</button></div></label>
          <label>المزوّد أو المصدر<input id="f-provider" list="provs"><datalist id="provs"></datalist></label>
          <label>الوصف<input id="f-label" placeholder="مثل: اشتراك الخادم KVM 8"></label>
          <label>المبلغ<input id="f-amount" type="number" min="0" step="0.01" dir="ltr"></label>
          <label>العملة<select id="f-currency"><option value="SAR">ريال</option><option value="USD">دولار</option></select></label>
          <label>التاريخ<input id="f-date" type="date" value="${r.month === thisMonth() ? new Date().toISOString().slice(0, 10) : r.month + '-01'}"></label>
          <label>التكرار<select id="f-repeat"><option value="once">مرة وحدة</option><option value="monthly">كل شهر</option><option value="yearly">كل سنة</option></select></label>
          <label>ملاحظة<input id="f-note" placeholder="اختياري: رقم الفاتورة مثلًا"></label>
          <div><button class="act gold" id="f-save" style="width:100%">إضافة</button></div>
        </div><div id="f-msg" class="err" style="margin-top:6px"></div>
        <div class="note">الدخل من Google Play وتكلفة Claude تنحسب لحالها. أضف هنا الباقي: الخادم من Hostinger، الدومين، رسوم المطوّرين، التسويق، أي دخل من المحلات بالتحويل. المصروف المتكرر ينحسب كل شهر لين توقفه.</div>
      </div>`;
    $('#mon').onchange = e => e.target.value && show('money', e.target.value);
    $('#app').querySelectorAll('.pl .m').forEach(m => m.onclick = () => show('money', m.dataset.m));
    $('#csv').onclick = () => csv(r);
    let kind = 'expense';
    const fill = () => $('#provs').innerHTML = providers[kind].map(p => `<option value="${esc(p)}">`).join('');
    fill();
    $('#kind').querySelectorAll('button').forEach(b => b.onclick = () => {
      kind = b.dataset.k;
      $('#kind').querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b));
      fill();
    });
    $('#f-save').onclick = async () => {
      try {
        await post('ledger', {add: {kind, provider: $('#f-provider').value, label: $('#f-label').value, amount: parseFloat($('#f-amount').value),
          currency: $('#f-currency').value, date: $('#f-date').value, repeat: $('#f-repeat').value, note: $('#f-note').value}});
        show('money', r.month);
      } catch (e) { $('#f-msg').textContent = e.message; }
    };
    $('#app').querySelectorAll('[data-del]').forEach(b => b.onclick = async () => {
      if (b.dataset.sure) { await post('ledger', {delete: b.dataset.del}); show('money', r.month); }
      else { b.dataset.sure = 1; b.textContent = 'متأكد؟ يحذف من كل الشهور'; }
    });
    $('#app').querySelectorAll('[data-stop]').forEach(b => b.onclick = async () => {
      const [y, m] = r.month.split('-').map(Number);
      const prev = new Date(Date.UTC(y, m - 2, 1)).toISOString().slice(0, 7);
      await post('ledger', {stop: b.dataset.stop, last: prev}); show('money', r.month);
    });
  },

  async users(q = '') {
    const list = await api('users?q=' + encodeURIComponent(q));
    $('#app').innerHTML = heading('المستخدمين', `${num(list.length)} حساب${list.length === 100 ? ' (آخر 100)' : ''}`,
      `<div class="row"><input id="q" placeholder="رقم الحساب أو monthly / yearly / shop" value="${esc(q)}" style="min-width:240px"><button class="act" id="find">بحث</button></div>`) + `
      <div class="card"><div class="wrap"><table><tr><th>الحساب</th><th>الباقة</th><th class="num">المتبقي</th><th class="num">الفحوصات</th><th>آخر فحص</th><th>إجراءات</th></tr>
      ${list.map(u => `<tr data-id="${esc(u.id)}">
        <td class="mono">${esc(u.id.slice(0, 12))}…</td>
        <td><span class="pill ${u.active ? 'pay' : ''}">${planName[u.active ? u.plan : 'free']}</span>${u.source === 'store' && u.active ? ' <span class="pill auto">المتجر</span>' : ''}${u.blocked ? ' <span class="pill no">موقوف</span>' : ''}${u.active ? `<div class="k">لين ${when(u.until)}</div>` : ''}</td>
        <td class="num">${num(u.remaining)}${u.bonus ? `<div class="k">منها ${num(u.bonus)} هدية</div>` : ''}</td>
        <td class="num">${num(u.scans)}</td><td>${when(u.lastScan)}</td>
        <td><div class="row"><input data-n type="number" min="1" value="5" style="width:64px" aria-label="عدد الفحوصات"><button class="act ghost sm" data-do="grant">أهدِ</button>
          <select data-do="plan"><option value="">الباقة…</option><option value="monthly:31">شهري 31 يوم</option><option value="yearly:366">سنوي</option><option value="shop:31">محل 31 يوم</option><option value="free:0">مجاني</option></select>
          <button class="act ghost sm" data-do="block">${u.blocked ? 'تفعيل' : 'إيقاف'}</button></div></td></tr>`).join('') || '<tr><td colspan="6" class="msg">ما فيه حسابات</td></tr>'}
      </table></div></div>`;
    $('#find').onclick = () => views.users($('#q').value.trim());
    $('#q').onkeydown = e => { if (e.key === 'Enter') views.users($('#q').value.trim()); };
    $('#app').querySelectorAll('tr[data-id]').forEach(tr => {
      const id = tr.dataset.id, u = list.find(x => x.id === id);
      tr.querySelector('[data-do=grant]').onclick = async () => {
        const n = parseInt(tr.querySelector('[data-n]').value, 10);
        if (n > 0) { await post('users/' + id, {grant: n}); views.users(q); }
      };
      tr.querySelector('[data-do=plan]').onchange = async e => {
        if (!e.target.value) return;
        const [plan, days] = e.target.value.split(':');
        await post('users/' + id, {plan, days: +days}); views.users(q);
      };
      tr.querySelector('[data-do=block]').onclick = async () => { await post('users/' + id, {blocked: !u.blocked}); views.users(q); };
    });
  },

  async scans() {
    const list = await api('scans');
    $('#app').innerHTML = heading('الفحوصات', `آخر ${num(list.length)} فحص`) + `
      <div class="card"><div class="wrap"><table><tr><th>الوقت</th><th>النوع</th><th class="num">الثقة</th><th class="num">الصور</th><th class="num">المدة</th><th class="num">التكلفة</th><th>الحساب</th></tr>
      ${list.map(s => `<tr><td>${when(s.at)}</td><td>${s.species ? sp(s.species) : '<span class="k">بدون نوع</span>'}</td>
        <td class="num">${s.confidence != null ? s.confidence + '%' : ''}</td><td class="num">${s.photos}</td><td class="num">${(s.ms / 1000).toFixed(1)} ث</td>
        <td class="num">${money((s.usd || 0) * 3.75)}</td><td class="mono">${esc((s.user || 'قديم').slice(0, 8))}</td></tr>`).join('') || '<tr><td colspan="7" class="msg">ما فيه فحوصات للحين</td></tr>'}
      </table></div></div>`;
  },

  async contrib(status = 'new') {
    const list = await api('contrib?status=' + status);
    const st = {new: 'جديدة', approved: 'مقبولة', rejected: 'مرفوضة'};
    $('#app').innerHTML = heading('صور المساهمين', `${num(list.length)} مساهمة`,
      `<div class="seg">${Object.entries(st).map(([k, v]) => `<button data-st="${k}" class="${k === status ? 'on' : ''}">${v}</button>`).join('')}</div>`) + `
      <div class="photos">${list.map(c => `<div class="card" data-day="${esc(c.day)}" data-id="${esc(c.id)}">
        <div class="thumbs">${c.files.map(f => `<img alt="" data-src="contrib/${esc(c.day)}/${esc(c.id)}/${esc(f)}">`).join('')}</div>
        <div><b>${c.species ? sp(c.species) : 'بدون نوع'}</b> ${c.species_confirmed ? '<span class="pill ok">أكّده المستخدم</span>' : ''}</div>
        <div class="k">${c.days_since_catch >= 0 ? `${num(c.days_since_catch)} يوم من الصيد` : 'الأيام غير معروفة'} · ${esc(storageName[c.storage] || c.storage)} · ${when(c.at)}</div>
        <div class="k">التطبيق توقع: ${(c.predicted || []).map(sp).join('، ') || '—'}</div>
        <div class="row" style="margin-top:10px"><button class="act sm" data-r="approved">قبول</button><button class="act ghost sm" data-r="rejected">رفض</button>
          <input data-fix placeholder="تصحيح النوع (4 أرقام)" inputmode="numeric" style="width:150px"></div></div>`).join('') || '<div class="card msg">ما فيه مساهمات هنا</div>'}</div>`;
    $('#app').querySelectorAll('[data-st]').forEach(b => b.onclick = () => views.contrib(b.dataset.st));
    // الصور تحتاج الرمز، فتنحمّل بـ fetch بدل src مباشرة.
    $('#app').querySelectorAll('img[data-src]').forEach(async img => { try { img.src = URL.createObjectURL(await api(img.dataset.src)); } catch (e) {} });
    $('#app').querySelectorAll('.card[data-id]').forEach(el => el.querySelectorAll('[data-r]').forEach(b => b.onclick = async () => {
      const fix = el.querySelector('[data-fix]').value.trim();
      await post(`contrib/${el.dataset.day}/${el.dataset.id}`, {status: b.dataset.r, ...(fix ? {species: fix.padStart(4, '0')} : {})});
      el.remove();
    }));
  },

  async settings() {
    const s = await api('settings');
    const rows = [
      ['freeScans', 'الفحوصات المجانية لكل حساب (مرة وحدة)'],
      ['monthlyCap', 'سقف الفحوصات بالشهر للشهري والسنوي'],
      ['shopCap', 'سقف الفحوصات بالشهر للمحلات'],
      ['priceMonthly', 'سعر الشهري (ريال)'],
      ['priceYearly', 'سعر السنوي (ريال)'],
      ['priceShop', 'سعر باقة المحل بالشهر (ريال)'],
      ['netShare', 'نسبة الصافي التقديرية بعد العمولة والضريبة (0.74 = 74%)'],
      ['usdToSar', 'سعر الدولار بالريال'],
    ];
    $('#app').innerHTML = heading('الباقات والأسعار', 'السقف والأسعار المستخدمة في الحسبة') + `<div class="card" style="max-width:680px">
      ${rows.map(([k, l]) => `<label class="set"><span>${l}</span><input data-k="${k}" type="number" step="any" min="0" value="${esc(s[k])}"></label>`).join('')}
      <label class="set"><span>إلزام رقم الحساب (التطبيقات القديمة توقف وتطلب التحديث)</span><input data-b="requireAccount" type="checkbox" ${s.requireAccount ? 'checked' : ''} style="width:auto"></label>
      <div class="note">أسعار المتجر نفسها تتغير من Google Play Console و App Store Connect. هنا السقف والحسبة بس.</div>
      <div class="row" style="margin-top:14px"><button class="act gold" id="save">حفظ</button> <span id="saved" class="k"></span></div></div>`;
    $('#save').onclick = async () => {
      const body = {};
      $('#app').querySelectorAll('[data-k]').forEach(i => body[i.dataset.k] = parseFloat(i.value));
      $('#app').querySelectorAll('[data-b]').forEach(i => body[i.dataset.b] = i.checked);
      await post('settings', body);
      $('#saved').textContent = 'تم الحفظ';
    };
  },

  async codes() {
    const list = await api('codes');
    $('#app').innerHTML = heading('رموز الهدايا', 'المستخدم يكتب الرمز في التطبيق (القائمة ← عندك رمز؟) وتنضاف له الفحوصات، مرة وحدة لكل حساب') + `
      <div class="cols"><div class="card"><div class="wrap"><table><tr><th>الرمز</th><th class="num">الفحوصات</th><th class="num">المستخدم</th><th></th></tr>
      ${list.map(c => `<tr><td class="mono">${esc(c.code)}</td><td class="num">${num(c.scans)}</td><td class="num">${num(c.used || 0)} من ${num(c.max)}</td><td><button class="act ghost sm" data-del="${esc(c.code)}">حذف</button></td></tr>`).join('') || '<tr><td colspan="4" class="msg">ما فيه رموز</td></tr>'}
      </table></div></div>
      <div class="card"><h3>رمز جديد</h3>
      <label class="set"><span>الرمز (حروف إنجليزية كبيرة وأرقام)</span><input id="c-code" dir="ltr"></label>
      <label class="set"><span>كم فحص يعطي</span><input id="c-scans" type="number" min="1" value="50"></label>
      <label class="set"><span>كم حساب يقدر يستخدمه</span><input id="c-max" type="number" min="1" value="20"></label>
      <div class="row" style="margin-top:12px"><button class="act gold" id="c-save">حفظ الرمز</button> <span id="c-msg" class="err"></span></div>
      <div class="note">رمز مراجعة Google Play لازم يكون هنا عشان فريق المراجعة يقدر يجرب التطبيق.</div></div></div>`;
    $('#c-save').onclick = async () => {
      try { await post('codes', {code: $('#c-code').value, scans: parseInt($('#c-scans').value), max: parseInt($('#c-max').value)}); show('codes'); }
      catch (e) { $('#c-msg').textContent = e.message; }
    };
    $('#app').querySelectorAll('[data-del]').forEach(b => b.onclick = async () => { await post('codes', {code: b.dataset.del, max: 0}); show('codes'); });
  },
};

function rowActions(x, month) {
  if (x.auto) return '';
  const recurring = x.repeat && x.repeat !== 'once';
  return `<div class="row">${recurring ? `<button class="act ghost sm" data-stop="${esc(x.id)}" title="يبقى في الشهور اللي قبل">إيقاف من هالشهر</button>` : ''}<button class="act ghost sm" data-del="${esc(x.id)}">حذف</button></div>`;
}

// ملف CSV يفتح في Excel (مع BOM عشان العربي).
function csv(r) {
  const q = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const lines = [['النوع', 'البند', 'المزوّد', 'التكرار', 'الإجمالي', 'الضريبة', 'عمولة المتجر', 'الصافي (ريال)']];
  r.income.forEach(i => lines.push(['دخل', i.auto ? productName(i.label) : i.label, i.provider, i.auto ? 'تلقائي' : repeatName[i.repeat], i.auto ? i.grossSar : i.sar, i.taxSar ?? '', i.feeSar ?? '', i.sar]));
  r.expenses.forEach(e => lines.push(['مصروف', e.label, e.provider, e.auto ? 'تلقائي' : repeatName[e.repeat], e.sar, '', '', -e.sar]));
  lines.push([], ['', 'الدخل الصافي', '', '', '', '', '', r.incomeSar], ['', 'المصاريف', '', '', '', '', '', -r.expensesSar], ['', 'صافي الربح', '', '', '', '', '', r.netSar]);
  const blob = new Blob(['﻿' + lines.map(l => l.map(q).join(',')).join('\r\n')], {type: 'text/csv;charset=utf-8'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `fish-id-${r.month}.csv`;
  a.click();
}

token ? start().catch(logout) : logout();
</script>
</body>
</html>
''';
