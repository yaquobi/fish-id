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
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@700;800&family=Tajawal:wght@400;500;700;800&display=swap" rel="stylesheet">
<style>
:root{--navy:#0B2236;--navy-deep:#061624;--gold:#F2C14E;--gold-ink:#8A5E00;--bg:#EEF2F5;--surface:#fff;--ink:#0B2236;--muted:#4A5B6B;--line:#D5DEE6;--chip:#E6EDF3;--good:#1D7A51;--bad:#B3261E;--on-navy:#C9D6E2}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 Tajawal,system-ui,sans-serif}
header{background:var(--navy);color:#fff;padding:14px 16px;display:flex;align-items:center;gap:12px;flex-wrap:wrap}
header h1{font:800 20px Montserrat,sans-serif;margin:0;letter-spacing:.5px}
header h1 b{color:var(--gold)}
nav{display:flex;gap:6px;flex-wrap:wrap;margin-inline-start:auto}
nav button{background:transparent;color:var(--on-navy);border:1px solid #23415c;border-radius:999px;padding:6px 14px;font:500 15px Tajawal;cursor:pointer}
nav button.on{background:var(--gold);color:var(--navy);border-color:var(--gold);font-weight:700}
main{max-width:1100px;margin:0 auto;padding:16px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:12px}
.card{background:var(--surface);border:1px solid var(--line);border-radius:14px;padding:14px}
.k{color:var(--muted);font-size:14px}
.v{font:800 26px Montserrat,Tajawal,sans-serif;direction:ltr;text-align:right}
.v small{font:500 14px Tajawal;color:var(--muted)}
h2{font-size:18px;margin:22px 0 10px}
table{width:100%;border-collapse:collapse;background:var(--surface);border-radius:14px;overflow:hidden;border:1px solid var(--line)}
th,td{padding:8px 10px;border-bottom:1px solid var(--line);text-align:right;font-size:14px;vertical-align:top}
th{background:var(--chip);font-weight:700}
.wrap{overflow-x:auto}
.mono{font-family:ui-monospace,monospace;direction:ltr;font-size:12px}
.pill{display:inline-block;padding:1px 10px;border-radius:999px;background:var(--chip);font-size:13px}
.pill.pay{background:#FDF1D3;color:var(--gold-ink);font-weight:700}
.pill.ok{background:#DDF1E6;color:var(--good)}
.pill.no{background:#F8DEDC;color:var(--bad)}
button.act{background:var(--navy);color:#fff;border:0;border-radius:10px;padding:6px 12px;font:500 14px Tajawal;cursor:pointer}
button.gold{background:var(--gold);color:var(--navy);font-weight:700}
button.ghost{background:var(--chip);color:var(--ink)}
input,select{font:16px Tajawal;padding:8px 10px;border:1px solid var(--line);border-radius:10px;background:#fff;color:var(--ink);max-width:100%}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.login{max-width:380px;margin:60px auto}
.login input{width:100%;margin:10px 0}
.photos{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:12px}
.photos img{width:100%;aspect-ratio:4/3;object-fit:cover;border-radius:10px;background:var(--chip)}
.thumbs{display:flex;gap:6px}
.thumbs img{width:33%;aspect-ratio:1;object-fit:cover}
.msg{color:var(--muted);padding:20px;text-align:center}
.err{color:var(--bad)}
label.set{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:8px 0;border-bottom:1px solid var(--line)}
label.set input{width:110px;direction:ltr}
</style>
</head>
<body>
<header>
  <h1>FISH <b>ID</b> · الأدمن</h1>
  <nav id="nav" hidden>
    <button data-tab="home" class="on">الرئيسية</button>
    <button data-tab="users">المستخدمين</button>
    <button data-tab="scans">الفحوصات</button>
    <button data-tab="contrib">الصور المساهم فيها</button>
    <button data-tab="settings">الباقات والأسعار</button>
  </nav>
</header>
<main id="app"></main>
<script>
const $ = (s, e = document) => e.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const sar = n => (Math.round((n || 0) * 100) / 100).toLocaleString('ar-SA', {maximumFractionDigits: 2}) + ' ريال';
const num = n => (n || 0).toLocaleString('ar-SA');
const when = s => s ? new Date(s).toLocaleString('ar-SA', {dateStyle: 'medium', timeStyle: 'short'}) : '';
const storageName = {ice: 'على ثلج', fridge: 'ثلاجة', room: 'حرارة الغرفة', hot: 'بالحر', frozen: 'مجمّد', unknown: 'الحفظ غير معروف'};
const planName = {free: 'مجاني', monthly: 'شهري', yearly: 'سنوي', shop: 'محل'};
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

function logout() {
  token = '';
  try { sessionStorage.removeItem('fishid-admin'); } catch (e) {}
  $('#nav').hidden = true;
  $('#app').innerHTML = `<div class="card login"><h2>دخول الأدمن</h2>
    <div class="k">الصق الرمز اللي طبعه install.sh على السيرفر (FISHID_ADMIN_TOKEN).</div>
    <input id="tok" type="password" autocomplete="current-password" placeholder="الرمز">
    <button class="act gold" id="go">دخول</button> <span id="lerr" class="err"></span></div>`;
  $('#go').onclick = async () => {
    token = $('#tok').value.trim();
    try { await api('stats'); try { sessionStorage.setItem('fishid-admin', token); } catch (e) {} start(); }
    catch (e) { $('#lerr').textContent = e.message; }
  };
}

async function start() {
  $('#nav').hidden = false;
  names = await api('species').catch(() => ({}));
  show('home');
}

document.querySelectorAll('#nav button').forEach(b => b.onclick = () => show(b.dataset.tab));
async function show(tab) {
  document.querySelectorAll('#nav button').forEach(b => b.classList.toggle('on', b.dataset.tab === tab));
  $('#app').innerHTML = '<div class="msg">جاري التحميل…</div>';
  try { await views[tab](); } catch (e) { $('#app').innerHTML = `<div class="msg err">${esc(e.message)}</div>`; }
}

const card = (k, v, note = '') => `<div class="card"><div class="k">${k}</div><div class="v">${v}</div>${note ? `<div class="k">${note}</div>` : ''}</div>`;

const views = {
  async home() {
    const s = await api('stats');
    $('#app').innerHTML = `
      <div class="grid">
        ${card('المستخدمين', num(s.users), `جدد اليوم ${num(s.newToday)} · هالأسبوع ${num(s.newWeek)}`)}
        ${card('المشتركين', num(s.paying), `شهري ${num(s.plans.monthly)} · سنوي ${num(s.plans.yearly)} · محلات ${num(s.plans.shop)}`)}
        ${card('خلصت فحوصاتهم المجانية', num(s.outOfFree), 'ما اشتركوا للحين')}
        ${card('فحوصات اليوم', num(s.scansToday), `هالشهر ${num(s.scansMonth)}`)}
        ${card('تكلفة Claude اليوم', sar(s.costTodaySar))}
        ${card('تكلفة Claude هالشهر', sar(s.costMonthSar), `للفحص ${sar(s.costPerScanSar)} · ${(s.avgSeconds || 0).toFixed(1)} ثانية`)}
        ${card('الدخل الشهري التقديري', sar(s.mrrSar), 'الصافي بعد العمولة والضريبة')}
        ${card('الصافي هالشهر', sar(s.profitMonthSar), 'الدخل ناقص تكلفة Claude')}
      </div>
      <h2>أكثر الأنواع فحصًا هالشهر</h2>
      <div class="wrap"><table><tr><th>النوع</th><th>الفحوصات</th></tr>
      ${s.topSpecies.map(t => `<tr><td>${sp(t.id)}</td><td>${num(t.n)}</td></tr>`).join('') || '<tr><td colspan="2" class="msg">ما فيه فحوصات للحين</td></tr>'}
      </table></div>`;
  },

  async users(q = '') {
    const list = await api('users?q=' + encodeURIComponent(q));
    $('#app').innerHTML = `
      <div class="row"><input id="q" placeholder="ابحث برقم الحساب أو اكتب monthly / yearly / shop" value="${esc(q)}" style="flex:1;min-width:220px">
      <button class="act" id="find">بحث</button></div>
      <h2>${num(list.length)} حساب</h2>
      <div class="wrap"><table><tr><th>الحساب</th><th>الباقة</th><th>المتبقي</th><th>الفحوصات</th><th>آخر فحص</th><th></th></tr>
      ${list.map(u => `<tr data-id="${esc(u.id)}">
        <td class="mono">${esc(u.id.slice(0, 12))}…</td>
        <td><span class="pill ${u.active ? 'pay' : ''}">${planName[u.active ? u.plan : 'free']}</span>${u.active ? `<div class="k">لين ${when(u.until)}</div>` : ''}${u.blocked ? ' <span class="pill no">موقوف</span>' : ''}</td>
        <td>${num(u.remaining)}${u.bonus ? `<div class="k">منها ${num(u.bonus)} هدية</div>` : ''}</td>
        <td>${num(u.scans)}</td><td>${when(u.lastScan)}</td>
        <td class="row"><button class="act ghost" data-do="grant">+ فحوصات</button>
          <select data-do="plan"><option value="">تغيير الباقة…</option><option value="monthly:31">شهري 31 يوم</option><option value="yearly:366">سنوي</option><option value="shop:31">محل 31 يوم</option><option value="free:0">مجاني</option></select>
          <button class="act ghost" data-do="block">${u.blocked ? 'تفعيل' : 'إيقاف'}</button></td></tr>`).join('')}
      </table></div>`;
    $('#find').onclick = () => views.users($('#q').value.trim());
    $('#q').onkeydown = e => { if (e.key === 'Enter') views.users($('#q').value.trim()); };
    $('#app').querySelectorAll('tr[data-id]').forEach(tr => {
      const id = tr.dataset.id, u = list.find(x => x.id === id);
      tr.querySelector('[data-do=grant]').onclick = async () => {
        const n = parseInt(prompt('كم فحص تبي تهديه؟', '5'), 10);
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
    $('#app').innerHTML = `<h2>آخر ${num(list.length)} فحص</h2>
      <div class="wrap"><table><tr><th>الوقت</th><th>النوع</th><th>الثقة</th><th>الصور</th><th>المدة</th><th>التكلفة</th><th>الحساب</th></tr>
      ${list.map(s => `<tr><td>${when(s.at)}</td><td>${s.species ? sp(s.species) : '<span class="k">بدون نوع</span>'}</td>
        <td>${s.confidence ?? ''}${s.confidence != null ? '%' : ''}</td><td>${s.photos}</td><td>${(s.ms / 1000).toFixed(1)} ث</td>
        <td>${sar((s.usd || 0) * 3.75)}</td><td class="mono">${esc((s.user || 'قديم').slice(0, 8))}</td></tr>`).join('') || '<tr><td colspan="7" class="msg">ما فيه فحوصات للحين</td></tr>'}
      </table></div>`;
  },

  async contrib(status = 'new') {
    const list = await api('contrib?status=' + status);
    const tabs = {new: 'جديدة', approved: 'مقبولة', rejected: 'مرفوضة'};
    $('#app').innerHTML = `<div class="row">${Object.entries(tabs).map(([k, v]) => `<button class="act ${k === status ? 'gold' : 'ghost'}" data-st="${k}">${v}</button>`).join('')}</div>
      <h2>${num(list.length)} مساهمة</h2>
      <div class="photos">${list.map(c => `<div class="card" data-day="${esc(c.day)}" data-id="${esc(c.id)}">
        <div class="thumbs">${c.files.map(f => `<img alt="" data-src="contrib/${esc(c.day)}/${esc(c.id)}/${esc(f)}">`).join('')}</div>
        <div><b>${c.species ? sp(c.species) : 'بدون نوع'}</b> ${c.species_confirmed ? '<span class="pill ok">أكّده المستخدم</span>' : ''}</div>
        <div class="k">${c.days_since_catch >= 0 ? `${num(c.days_since_catch)} يوم من الصيد` : 'الأيام غير معروفة'} · ${esc(storageName[c.storage] || c.storage)} · ${when(c.at)}</div>
        <div class="k">التطبيق توقع: ${(c.predicted || []).map(sp).join('، ') || '—'}</div>
        <div class="row" style="margin-top:8px"><button class="act" data-r="approved">قبول</button><button class="act ghost" data-r="rejected">رفض</button>
          <input data-fix placeholder="تصحيح النوع (4 أرقام)" inputmode="numeric" style="width:150px"></div></div>`).join('') || '<div class="msg">ما فيه مساهمات هنا</div>'}</div>`;
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
      ['priceMonthly', 'سعر الشهري (ريال، للعرض والحسبة)'],
      ['priceYearly', 'سعر السنوي (ريال)'],
      ['priceShop', 'سعر باقة المحل بالشهر (ريال)'],
      ['netShare', 'نسبة الصافي بعد العمولة والضريبة (0.74 = 74%)'],
    ];
    $('#app').innerHTML = `<div class="card" style="max-width:640px">
      <h2 style="margin-top:0">الباقات والأسعار</h2>
      ${rows.map(([k, l]) => `<label class="set"><span>${l}</span><input data-k="${k}" type="number" step="any" min="0" value="${esc(s[k])}"></label>`).join('')}
      <label class="set"><span>إلزام رقم الحساب (التطبيقات القديمة توقف وتطلب التحديث)</span><input data-b="requireAccount" type="checkbox" ${s.requireAccount ? 'checked' : ''} style="width:auto"></label>
      <div class="k" style="margin:10px 0">أسعار المتجر نفسها تتغير من Google Play Console و App Store Connect. هنا السقف والحسبة بس.</div>
      <button class="act gold" id="save">حفظ</button> <span id="saved" class="k"></span></div>`;
    $('#save').onclick = async () => {
      const body = {};
      $('#app').querySelectorAll('[data-k]').forEach(i => body[i.dataset.k] = parseFloat(i.value));
      $('#app').querySelectorAll('[data-b]').forEach(i => body[i.dataset.b] = i.checked);
      await post('settings', body);
      $('#saved').textContent = 'تم الحفظ';
    };
  },
};

token ? start().catch(logout) : logout();
</script>
</body>
</html>
''';
