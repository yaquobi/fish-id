/// لوحة الجهة الرسمية (وزارة البيئة والمياه والزراعة أو غيرها) على https://hawat.id/api/gov?k=المفتاح:
/// الزيارات التفتيشية والمخالفات والأسواق، وإدارة المفتشين ورموزهم، وتقرير شهري ينطبع.
/// نفس تصميم لوحة الأدمن: زوايا حادة وخطوط خفيفة.
const govPage = r'''<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="referrer" content="no-referrer">
<title>FISH ID · لوحة الجهة الرسمية</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@400;500;600&family=Tajawal:wght@300;400;500;700&display=swap" rel="stylesheet">
<style>
:root{--navy:#0B2236;--navy-3:#1B3D5C;--gold:#F2C14E;--gold-soft:#FDF3DA;--gold-ink:#7A5300;--bg:#F5F7F9;--surface:#fff;--ink:#0F1A24;--muted:#5B6B79;--line:#EAEEF2;--edge:#CFD9DE;--chip:#F3F5F7;--hover:#F7F9FA;--good:#17804F;--good-soft:#E3F4EA;--bad:#B3261E;--bad-soft:#FBE6E4;--info:#21507A;--info-soft:#E5EEF8;--on-navy:#B8C8D8;--primary:#0B2236;--on-primary:#fff;--num:"Chakra Petch",Tajawal,ui-monospace,monospace}
:root[data-theme=dark]{--bg:#08131E;--surface:#0F2131;--ink:#E7EEF5;--muted:#93A6B8;--line:#1E3548;--edge:#2A4559;--chip:#17303F;--hover:#132A3C;--gold-soft:#3A2F14;--gold-ink:#F2C14E;--good:#5CD49A;--good-soft:#123527;--bad:#FF8F84;--bad-soft:#3D1A18;--info:#8EC0F0;--info-soft:#14304A;--primary:#F2C14E;--on-primary:#0B2236;color-scheme:dark}
*{box-sizing:border-box}*,*::before,*::after{border-radius:0!important}
[hidden]{display:none!important}
body{margin:0;background:var(--bg);color:var(--ink);font:300 14px/1.6 Tajawal,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
b,strong{font-weight:500}
.shell{display:grid;grid-template-columns:240px minmax(0,1fr);gap:14px;min-height:100vh;padding:12px}
aside{background:var(--surface);border:1px solid var(--line);padding:14px 10px;position:sticky;top:12px;height:calc(100vh - 24px);overflow-y:auto;display:flex;flex-direction:column;gap:6px}
.brand{padding:4px 8px 12px;border-bottom:1px solid var(--line);display:flex;align-items:center;gap:10px}
.brand b{font:600 16px var(--num);letter-spacing:.4px}.brand b span{color:#C9961F}
.brand small{display:block;color:var(--muted);font-size:12px}
.brand .theme{margin-inline-start:auto;background:transparent;border:0;padding:6px;color:var(--muted);cursor:pointer}
nav{display:flex;flex-direction:column;gap:1px}
nav .grp{font-size:12px;color:var(--muted);padding:12px 12px 4px}
nav button{display:flex;align-items:center;gap:10px;background:transparent;color:var(--ink);border:0;padding:8px 12px;font:300 14px Tajawal,sans-serif;cursor:pointer;text-align:start;position:relative}
nav button:hover{background:var(--hover)}
nav button.on{font-weight:500}
nav button.on::before{content:"";position:absolute;inset-inline-start:-10px;top:7px;bottom:7px;width:3px;background:var(--ink)}
nav svg{width:18px;height:18px;flex:none}
.side-foot{margin-top:auto;border-top:1px solid var(--line);padding:10px 8px 0;color:var(--muted);font-size:12px}
main{background:var(--surface);border:1px solid var(--line);padding:22px clamp(16px,2.4vw,30px) 28px;min-width:0}
.top{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-bottom:18px}
.top h1{margin:0;font-size:22px;font-weight:500}.top .sub{color:var(--muted);font-size:13px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:12px}
.cols{display:grid;grid-template-columns:3fr 2fr;gap:14px;margin-top:14px}
.card{background:var(--surface);border:1px solid var(--line);padding:16px 18px;min-width:0}
.card h3{margin:0 0 12px;font-size:15px;font-weight:500;display:flex;justify-content:space-between;align-items:center;gap:8px}
.kpi .k{color:var(--muted);font-size:13px}
.kpi .v{font:400 25px var(--num);margin:4px 0 2px;font-variant-numeric:tabular-nums}
.kpi .n{color:var(--muted);font-size:13px}
.kpi.hero{background:var(--navy);color:#fff;border-color:var(--navy)}.kpi.hero .k,.kpi.hero .n{color:var(--on-navy)}.kpi.hero .v{color:var(--gold)}
table{width:100%;border-collapse:collapse}
th,td{padding:9px 8px;border-bottom:1px solid var(--line);text-align:start;font-size:13.5px;vertical-align:middle}
th{color:var(--muted);font-weight:400;font-size:12px}
tr:last-child td{border-bottom:0}
td.num,th.num{text-align:left;direction:ltr;font-variant-numeric:tabular-nums;white-space:nowrap}
tbody tr.click{cursor:pointer}tbody tr.click:hover td{background:var(--hover)}
.wrap{overflow-x:auto}
.mono{font-family:ui-monospace,monospace;direction:ltr;font-size:12px;unicode-bidi:isolate}
.k{color:var(--muted);font-size:12px}
.pill{display:inline-block;padding:1px 9px;background:var(--chip);font-size:12px;font-weight:400;white-space:nowrap}
.pill.ok{background:var(--good-soft);color:var(--good)}.pill.no{background:var(--bad-soft);color:var(--bad)}.pill.auto{background:var(--info-soft);color:var(--info)}.pill.pay{background:var(--gold-soft);color:var(--gold-ink)}
button.act{background:var(--primary);color:var(--on-primary);border:1px solid var(--primary);padding:7px 16px;font:400 13px Tajawal,sans-serif;cursor:pointer;white-space:nowrap}
button.gold{background:var(--gold);border-color:var(--gold);color:var(--navy);font-weight:500}
button.ghost{background:var(--surface);color:var(--ink);border-color:var(--edge)}
button.sm{padding:3px 10px;font-size:12px}
input,select{font:400 14px Tajawal,sans-serif;padding:7px 10px;border:1px solid var(--edge);background:var(--surface);color:var(--ink);max-width:100%}
input:focus,select:focus{outline:2px solid var(--gold);outline-offset:0;border-color:var(--gold)}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.form{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:10px;align-items:end}
.form label{display:flex;flex-direction:column;gap:4px;font-size:13px;color:var(--muted)}
.bars{display:flex;align-items:flex-end;gap:3px;height:140px;padding-top:8px;direction:ltr}
.bars div{flex:1;display:flex;flex-direction:column;justify-content:flex-end;height:100%;min-width:0}
.bars i{display:block;background:var(--navy-3);min-height:1px}
.bars i.v{background:var(--bad);opacity:.8}
:root[data-theme=dark] .bars i{background:#3E6A93}
.axis{display:flex;justify-content:space-between;color:var(--muted);font-size:11px;margin-top:6px;direction:ltr}
.meter{height:6px;background:var(--chip);margin-top:4px}.meter i{display:block;height:100%;background:var(--navy-3)}.meter i.v{background:var(--bad)}
.note{background:var(--gold-soft);padding:10px 14px;font-size:13px;color:var(--gold-ink);margin-top:14px}
.secret{display:flex;gap:8px;align-items:center;background:var(--navy);color:var(--gold);padding:10px 14px;margin-top:12px;flex-wrap:wrap}
.secret code{flex:1;direction:ltr;font-size:15px;letter-spacing:1px}
.msg{color:var(--muted);padding:28px;text-align:center}.err{color:var(--bad)}
.login{max-width:420px;margin:14vh auto;text-align:center;padding:0 16px}
.drawer{position:fixed;inset-block:0;inset-inline-end:0;width:min(520px,100%);background:var(--surface);border-inline-start:1px solid var(--edge);z-index:20;overflow-y:auto;padding:20px 22px;box-shadow:0 0 40px rgba(0,0,0,.15)}
.scrim{position:fixed;inset:0;background:rgba(8,19,30,.35);z-index:19}
.kv{display:flex;justify-content:space-between;gap:12px;padding:7px 0;border-bottom:1px solid var(--line);font-size:13.5px}.kv span{color:var(--muted)}
.photos{display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:8px;margin-top:12px}
.photos img{width:100%;aspect-ratio:1;object-fit:cover;background:var(--chip)}
.print-head{display:none}
@media (max-width:860px){.shell{grid-template-columns:1fr}aside{position:static;height:auto}.cols{grid-template-columns:1fr}}
@media print{
  @page{size:A4;margin:14mm}
  body{background:#fff}aside,.noprint,.drawer,.scrim{display:none!important}
  .shell{display:block;padding:0}main{border:0;padding:0}
  .print-head{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:3px solid #0B2236;padding-bottom:8px;margin-bottom:16px}
  .print-head b{font:600 20px "Chakra Petch",sans-serif;color:#0B2236}.print-head b span{color:#C9971F}
  .card{break-inside:avoid}
}
</style>
</head>
<body>
<div id="login" class="login" hidden>
  <div style="font:600 22px 'Chakra Petch',sans-serif">FISH <span style="color:#C9961F">ID</span></div>
  <h2 style="font-weight:500;margin:6px 0">لوحة الجهة الرسمية</h2>
  <p class="k">افتح اللوحة من الرابط الخاص اللي وصلكم من فريق FISH ID.</p>
  <p id="login-err" class="err"></p>
</div>
<div class="shell" id="shell" hidden>
  <aside>
    <div class="brand">
      <svg width="32" height="32" viewBox="0 0 34 34" aria-hidden="true"><rect width="34" height="34" fill="#0B2236"/><path d="M6 11V7h4M28 11V7h-4M6 23v4h4M28 23v4h-4" stroke="#F2C14E" stroke-width="2" fill="none"/><path d="M9 17c3-4 8-5 12-2l4-3v10l-4-3c-4 3-9 2-12-2z" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>
      <div><b>FISH <span>ID</span></b><small>رسمي</small></div>
      <button class="theme" id="theme" title="الوضع الليلي" aria-label="الوضع الليلي"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/></svg></button>
    </div>
    <nav id="nav"></nav>
    <div class="side-foot"><div id="ag-name"></div><div id="ag-until"></div></div>
  </aside>
  <main>
    <div class="print-head"><div><b>FISH <span>ID</span></b><div class="k" id="ph-ag"></div></div><div style="text-align:end"><div id="ph-title" style="font-weight:700;color:#0B2236"></div><div class="k" id="ph-when"></div></div></div>
    <div id="app"></div>
  </main>
</div>
<div class="scrim" id="scrim" hidden></div>
<div class="drawer" id="drawer" hidden></div>
<script>
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num = n => (n || 0).toLocaleString('en-US');
const pct = (a, b) => b ? Math.round(a * 100 / b) + '%' : '—';
const when = iso => { if (!iso) return '—'; const d = new Date(iso); return d.toLocaleDateString('en-GB', {timeZone: 'Asia/Riyadh'}) + ' ' + d.toLocaleTimeString('en-GB', {timeZone: 'Asia/Riyadh', hour: '2-digit', minute: '2-digit'}); };
const types = {name: 'تسمية مضللة للصنف', fresh: 'سمك غير طازج', price: 'السعر غير معلن أو مخالف', hygiene: 'النظافة والتبريد', other: 'أخرى'};
const decision = v => v.decision === 'violation' ? '<span class="pill no">مخالفة</span>' : v.decision === 'followup' ? '<span class="pill pay">متابعة</span>' : '<span class="pill ok">سليم</span>';
const icons = {
  home: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  visits: '<path d="M5 3h10l4 4v14H5z"/><path d="M14 3v5h5M8 12h8M8 16h5"/>',
  violations: '<path d="M12 3l9 16H3z"/><path d="M12 10v4M12 17v.5"/>',
  markets: '<path d="M3 9l1.5-5h15L21 9M3 9v11h18V9M3 9h18M9 20v-6h6v6"/>',
  inspectors: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.5 3.4-5.5 6.5-5.5s5.7 2 6.5 5.5M16 4.5a3.5 3.5 0 0 1 0 7M18 14.5c1.9.6 3.1 2.6 3.5 5.5"/>',
};
const tabs = [['الرقابة', [['home', 'الملخص'], ['visits', 'الزيارات'], ['violations', 'المخالفات'], ['markets', 'الأسواق']]], ['الفريق', [['inspectors', 'المفتشين']]]];
let key = new URLSearchParams(location.search).get('k') || '';
try { if (key) sessionStorage.setItem('fishid-gov', key); else key = sessionStorage.getItem('fishid-gov') || ''; } catch (e) {}
if (location.search) history.replaceState(null, '', location.pathname + location.hash);
let data = null, month = '', current = 'home';

async function api(path, opts = {}) {
  const res = await fetch('gov/' + path, {...opts, headers: {'x-gov': key, 'content-type': 'application/json'}});
  const body = await res.json().catch(() => ({}));
  if (res.status === 401) { showLogin(body.message); throw new Error(body.message); }
  if (!res.ok) throw new Error(body.message || 'خطأ ' + res.status);
  return body;
}
function showLogin(m) { $('#shell').hidden = true; $('#login').hidden = false; $('#login-err').textContent = m || ''; }

function buildNav() {
  $('#nav').innerHTML = tabs.map(([g, items]) => `<div class="grp">${g}</div>` + items.map(([k, n]) => `<button data-tab="${k}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${icons[k]}</svg>${n}</button>`).join('')).join('');
  $('#nav').querySelectorAll('button').forEach(b => b.onclick = () => show(b.dataset.tab));
}

async function load(m = '') {
  data = await api('data' + (m ? '?month=' + m : ''));
  month = data.month;
  $('#ag-name').textContent = data.agency.name;
  $('#ag-until').textContent = (data.agency.active ? 'العقد ساري حتى ' : 'العقد منتهي ') + (data.agency.until || '').slice(0, 10);
  $('#ph-ag').textContent = data.agency.name;
}

const monthPick = () => {
  const ms = [...new Set([month, ...data.months])].sort().reverse();
  return `<select id="month" class="noprint" aria-label="الشهر">${ms.map(m => `<option ${m === month ? 'selected' : ''}>${m}</option>`).join('')}</select> <button class="act ghost noprint" onclick="window.print()">طباعة التقرير</button>`;
};
const heading = (t, sub) => `<div class="top"><div><h1>${t}</h1><div class="sub">${sub}</div></div><div class="row">${monthPick()}</div></div>`;
const kpi = (k, v, n = '', cls = '') => `<div class="card kpi ${cls}"><div class="k">${k}</div><div class="v">${v}</div>${n ? `<div class="n">${n}</div>` : ''}</div>`;

function visitRows(list) {
  return `<div class="wrap"><table><thead><tr><th>المرجع</th><th>الوقت</th><th>السوق</th><th>المحل</th><th>المكتوب</th><th>المرجّح</th><th>الطزاجة</th><th>المفتش</th><th>النتيجة</th></tr></thead><tbody>
    ${list.map(v => `<tr class="click" data-ref="${esc(v.ref)}"><td class="mono">${esc(v.ref)}</td><td class="num">${when(v.at)}</td><td>${esc(v.market)}${v.city ? `<div class="k">${esc(v.city)}</div>` : ''}</td><td>${esc(v.shop)}</td>
      <td>${esc(v.labelName || '—')}${v.labelPrice != null ? `<div class="k">${num(v.labelPrice)} ر.س/كجم</div>` : ''}</td>
      <td>${esc(v.speciesName || '—')}${v.confidence != null ? ` <span class="k">${v.confidence}%</span>` : ''}${v.match === false ? '<div><span class="pill no">ما يطابق اللوحة</span></div>' : ''}</td>
      <td class="num">${v.freshness != null ? v.freshness + '/100' : '—'}</td><td>${esc(v.inspectorName)}</td>
      <td>${decision(v)}${(v.violations || []).map(t => `<div class="k">${esc(types[t] || t)}</div>`).join('')}</td></tr>`).join('') || '<tr><td colspan="9" class="msg">ما فيه زيارات في هذا الشهر.</td></tr>'}
  </tbody></table></div>`;
}
function bindRows() { $('#app').querySelectorAll('[data-ref]').forEach(r => r.onclick = () => openVisit(r.dataset.ref)); }

function openVisit(ref) {
  const v = data.visitsList.find(x => x.ref === ref);
  if (!v) return;
  const photo = n => `<img alt="صورة ${n + 1}" src="gov/photo/${encodeURIComponent(v.ref)}/${n}?k=${encodeURIComponent(key)}">`;
  $('#drawer').innerHTML = `<div class="row" style="justify-content:space-between"><h2 style="margin:0;font-weight:500;font-size:18px">زيارة <span class="mono" style="font-size:15px">${esc(v.ref)}</span></h2><button class="act ghost sm" id="close">إغلاق</button></div>
    <div style="margin-top:10px">${decision(v)} ${(v.violations || []).map(t => `<span class="pill">${esc(types[t] || t)}</span>`).join(' ')}</div>
    <div style="margin-top:12px">
      <div class="kv"><span>المفتش</span><b>${esc(v.inspectorName)}${v.branch ? ` · ${esc(v.branch)}` : ''}</b></div>
      <div class="kv"><span>الوقت</span><b class="mono">${when(v.at)}</b></div>
      <div class="kv"><span>السوق</span><b>${esc(v.market)}${v.city ? ` · ${esc(v.city)}` : ''}</b></div>
      <div class="kv"><span>المحل</span><b>${esc(v.shop)}</b></div>
      <div class="kv"><span>المكتوب على اللوحة</span><b>${esc(v.labelName || '—')}${v.labelPrice != null ? ` · ${num(v.labelPrice)} ر.س/كجم` : ''}</b></div>
      <div class="kv"><span>الصنف المرجّح (استرشادي)</span><b>${esc(v.speciesName || '—')}${v.sci ? ` <i class="k">${esc(v.sci)}</i>` : ''}${v.confidence != null ? ` · ${v.confidence}%` : ''}</b></div>
      <div class="kv"><span>الطزاجة</span><b>${v.freshness != null ? v.freshness + '/100' : '—'}${v.grade ? ` · ${esc(v.grade)}` : ''}</b></div>
      ${v.lat != null ? `<div class="kv"><span>الموقع</span><b><a class="mono" target="_blank" rel="noopener" href="https://maps.google.com/?q=${v.lat},${v.lng}">${v.lat.toFixed(5)}, ${v.lng.toFixed(5)}</a></b></div>` : ''}
    </div>
    ${v.note ? `<div class="card" style="margin-top:12px"><div class="k">ملاحظة المفتش</div>${esc(v.note)}</div>` : ''}
    ${v.photos ? `<div class="photos">${Array.from({length: v.photos}, (_, n) => photo(n)).join('')}</div>` : ''}
    <div class="note">نتيجة التعرّف من الذكاء الاصطناعي استرشادية، والقرار للمفتش.</div>`;
  $('#drawer').hidden = $('#scrim').hidden = false;
  $('#close').onclick = closeVisit;
}
function closeVisit() { $('#drawer').hidden = $('#scrim').hidden = true; }
$('#scrim').onclick = closeVisit;
addEventListener('keydown', e => { if (e.key === 'Escape') closeVisit(); });

const views = {
  home() {
    const d = data, maxDay = Math.max(1, ...d.days.map(x => x.visits));
    const types_ = Object.entries(d.byType).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]);
    const maxT = Math.max(1, ...types_.map(([, n]) => n));
    const active = d.inspectors.filter(i => i.visits > 0).length;
    return heading('الملخص', `${esc(d.agency.name)} · ${month}${d.agency.pilot ? ' · مرحلة تجريبية' : ''}`) + `
      <div class="grid">
        ${kpi('الزيارات', num(d.visits), `${num(d.markets.length)} سوق`, 'hero')}
        ${kpi('المخالفات', num(d.violations), `${pct(d.violations, d.visits)} من الزيارات`)}
        ${kpi('اسم ما يطابق الصنف', num(d.mismatch), 'حسب الفحص، قبل قرار المفتش')}
        ${kpi('تحتاج متابعة', num(d.followup))}
        ${kpi('مفتشين نشطين', `${num(active)} <small class="k">من ${num(d.seatsUsed)}</small>`, `الرخص ${num(d.agency.seats)}`)}
      </div>
      <div class="cols">
        <div class="card"><h3>الزيارات يوميًا <span class="k">الأحمر: المخالفات</span></h3>
          <div class="bars">${d.days.map(x => `<div title="${x.day}: ${x.visits} زيارة، ${x.violations} مخالفة"><i style="height:${(x.visits - x.violations) * 100 / maxDay}%"></i><i class="v" style="height:${x.violations * 100 / maxDay}%"></i></div>`).join('')}</div>
          <div class="axis"><span>${d.days[0].day.slice(5)}</span><span>${d.days[d.days.length - 1].day.slice(5)}</span></div></div>
        <div class="card"><h3>أنواع المخالفات</h3>
          ${types_.map(([t, n]) => `<div style="margin-bottom:10px"><div class="row" style="justify-content:space-between"><span>${esc(types[t] || t)}</span><b class="mono">${num(n)}</b></div><div class="meter"><i class="v" style="width:${n * 100 / maxT}%"></i></div></div>`).join('') || '<div class="msg">ما فيه مخالفات.</div>'}
          ${d.topMismatch.length ? `<h3 style="margin-top:16px">أكثر الأسماء المضللة</h3>${d.topMismatch.map(m => `<div class="kv"><span>${esc(m.label)}</span><b class="mono">${num(m.count)}</b></div>`).join('')}` : ''}
        </div>
      </div>
      <div class="card" style="margin-top:14px"><h3>آخر المخالفات</h3>${visitRows(d.visitsList.filter(v => v.decision === 'violation').slice(0, 10))}</div>
      <div class="note">الأرقام من زيارات المفتشين في تطبيق FISH ID. التعرّف على الصنف والطزاجة بالذكاء الاصطناعي استرشادي، والقرار النهائي للمفتش.</div>`;
  },
  visits() { return heading('الزيارات', `${num(data.visits)} زيارة في ${month}`) + `<div class="card">${visitRows(data.visitsList)}</div>`; },
  violations() {
    const list = data.visitsList.filter(v => v.decision !== 'ok');
    return heading('المخالفات والمتابعة', `${num(data.violations)} مخالفة و ${num(data.followup)} متابعة في ${month}`) + `<div class="card">${visitRows(list)}</div>`;
  },
  markets() {
    const max = Math.max(1, ...data.markets.map(m => m.visits));
    return heading('الأسواق', `${num(data.markets.length)} سوق زارها المفتشين في ${month}`) + `<div class="card"><div class="wrap"><table><thead><tr><th>السوق</th><th>المدينة</th><th class="num">الزيارات</th><th class="num">المخالفات</th><th class="num">النسبة</th><th style="width:30%"></th></tr></thead><tbody>
      ${data.markets.map(m => `<tr><td>${esc(m.market)}</td><td>${esc(m.city || '—')}</td><td class="num">${num(m.visits)}</td><td class="num">${num(m.violations)}</td><td class="num">${pct(m.violations, m.visits)}</td><td><div class="meter"><i style="width:${m.visits * 100 / max}%"></i></div></td></tr>`).join('') || '<tr><td colspan="6" class="msg">ما فيه زيارات في هذا الشهر.</td></tr>'}
    </tbody></table></div></div>`;
  },
  inspectors(added = null) {
    const d = data;
    return `<div class="top"><div><h1>المفتشين</h1><div class="sub">${num(d.seatsUsed)} من ${num(d.agency.seats)} رخصة مستخدمة</div></div></div>
      ${added ? `<div class="card" style="margin-bottom:14px"><h3>رمز ${esc(added.name)}</h3><div class="k">أرسلوا الرمز للمفتش. يفتح تطبيق FISH ID، ومن القائمة يختار «دخول المفتشين» ويكتب الرمز.</div>
        <div class="secret"><code>${esc(added.code)}</code><button class="act gold sm" data-copy="${esc(added.code)}">نسخ</button></div></div>` : ''}
      <div class="card noprint" style="margin-bottom:14px"><h3>إضافة مفتش</h3>
        <form class="form" id="add"><label>الاسم<input id="in-name" required minlength="3" maxlength="80"></label>
          <label>الجوال<input id="in-phone" inputmode="tel" placeholder="05xxxxxxxx" dir="ltr"></label>
          <label>الفرع أو المنطقة<input id="in-branch" maxlength="80"></label>
          <label>&nbsp;<button class="act gold" type="submit">إنشاء رمز</button></label></form>
        <div id="add-err" class="err"></div></div>
      <div class="card"><div class="wrap"><table><thead><tr><th>المفتش</th><th>الفرع</th><th>الرمز</th><th class="num">الأجهزة</th><th>آخر نشاط</th><th class="num">زيارات الشهر</th><th class="num">مخالفات</th><th>الحالة</th><th class="noprint"></th></tr></thead><tbody>
        ${d.inspectors.map(i => `<tr${i.stopped ? ' style="opacity:.55"' : ''}><td>${esc(i.name)}${i.phone ? `<div class="k mono">${esc(i.phone)}</div>` : ''}</td><td>${esc(i.branch || '—')}</td><td class="mono">${esc(i.code)}</td>
          <td class="num">${num(i.devices)} / 2</td><td class="num">${i.lastSeen ? when(i.lastSeen) : '—'}</td><td class="num">${num(i.visits)}</td><td class="num">${num(i.violations)}</td>
          <td>${i.stopped ? '<span class="pill">موقوف</span>' : i.devices ? '<span class="pill ok">نشط</span>' : '<span class="pill auto">لم يدخل بعد</span>'}</td>
          <td class="noprint"><button class="act ghost sm" data-copy="${esc(i.code)}">نسخ الرمز</button> <button class="act ghost sm" data-new="${esc(i.id)}">رمز جديد</button> <button class="act ghost sm" data-stop="${esc(i.id)}" data-on="${i.stopped ? 1 : ''}">${i.stopped ? 'تفعيل' : 'إيقاف'}</button></td></tr>`).join('') || '<tr><td colspan="9" class="msg">ما فيه مفتشين للحين. أضيفوا أول مفتش من فوق.</td></tr>'}
      </tbody></table></div></div>
      <div class="note">كل رمز يشتغل على جهازين بحد أقصى. «رمز جديد» يوقف الرمز القديم ويفك أجهزته (مثلًا إذا ضاع الجوال).</div>`;
  },
};

function bindInspectors() {
  const f = $('#add');
  if (f) f.onsubmit = async e => {
    e.preventDefault();
    try {
      const r = await api('inspectors', {method: 'POST', body: JSON.stringify({add: {name: $('#in-name').value, phone: $('#in-phone').value, branch: $('#in-branch').value}})});
      await load(month); render('inspectors', r);
    } catch (err) { $('#add-err').textContent = err.message; }
  };
  $('#app').querySelectorAll('[data-copy]').forEach(b => b.onclick = async () => { try { await navigator.clipboard.writeText(b.dataset.copy); b.textContent = 'تم النسخ'; } catch (e) {} });
  const sure = (b, run) => async () => { if (!b.dataset.sure) { b.dataset.sure = 1; b.textContent = 'متأكد؟'; return; } try { const r = await run(); await load(month); render('inspectors', r); } catch (e) { b.textContent = e.message; } };
  $('#app').querySelectorAll('[data-stop]').forEach(b => b.onclick = sure(b, () => api('inspectors', {method: 'POST', body: JSON.stringify({id: b.dataset.stop, update: {stopped: !b.dataset.on}})}).then(() => null)));
  $('#app').querySelectorAll('[data-new]').forEach(b => b.onclick = sure(b, () => api('inspectors', {method: 'POST', body: JSON.stringify({id: b.dataset.new, update: {newCode: true}})})));
}

function render(tab, arg) {
  current = tab;
  document.querySelectorAll('#nav button').forEach(b => b.classList.toggle('on', b.dataset.tab === tab));
  $('#app').innerHTML = views[tab](arg);
  $('#ph-title').textContent = $('#app h1')?.textContent || '';
  $('#ph-when').textContent = 'الفترة ' + month + ' · طُبع ' + when(new Date().toISOString());
  bindRows();
  if (tab === 'inspectors') bindInspectors();
  const m = $('#month');
  if (m) m.onchange = async () => { await load(m.value); render(current); };
  history.replaceState(null, '', '#' + tab);
}
async function show(tab) { try { render(tabs.flatMap(g => g[1]).some(t => t[0] === tab) ? tab : 'home'); } catch (e) { $('#app').innerHTML = `<div class="msg err">${esc(e.message)}</div>`; } }

(function theme() {
  let t = 'light';
  try { t = localStorage.getItem('fishid-theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'); } catch (e) {}
  document.documentElement.dataset.theme = t;
  $('#theme').onclick = () => { t = t === 'dark' ? 'light' : 'dark'; document.documentElement.dataset.theme = t; try { localStorage.setItem('fishid-theme', t); } catch (e) {} };
})();

(async () => {
  if (!key) return showLogin();
  try {
    await load();
    $('#login').hidden = true; $('#shell').hidden = false;
    buildNav(); show(location.hash.slice(1));
  } catch (e) { if (!$('#login').hidden) return; $('#shell').hidden = true; $('#login').hidden = false; $('#login-err').textContent = e.message; }
})();
</script>
</body>
</html>
''';
