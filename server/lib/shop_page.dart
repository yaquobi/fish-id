/// صفحة باقة المحلات (https://hawat.id/shop يحوّل لها): تسجيل المحل والدفع أونلاين عن طريق ميسر،
/// ولوحة المحل برابطه الخاص (?k=المفتاح): الاشتراك والرصيد والأجهزة والإيصالات.
const shopPage = r"""<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0B2236">
<title>FISH ID · باقة المحلات والمطاعم</title>
<meta name="description" content="اشترك محلك أو مطعمك في FISH ID أونلاين: افحص نوع السمك وطزاجته من جوالات موظفينك، 300 فحص بالشهر بـ 350 ريال، والدفع بمدى أو Apple Pay أو البطاقة.">
<link rel="icon" href="/img/favicon.png">
<link rel="apple-touch-icon" href="/img/apple-touch-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@300;400;500&family=Tajawal:wght@300;400;500&display=swap" rel="stylesheet">
<style>
:root { --navy: #0B2236; --gold: #F2C14E; --ink: #0B2236; --mute: #5b6b7a; --line: #dfe5ea; --bg: #f5f7f9; --card: #fff; --ok: #1f8a4c; --err: #b3261e; }
* { box-sizing: border-box; border-radius: 0 !important; }
html, body { margin: 0; background: var(--bg); color: var(--ink); font: 300 16px/1.7 'Tajawal', system-ui, sans-serif; -webkit-tap-highlight-color: transparent; }
.num, .mono { font-family: 'Chakra Petch', 'Tajawal', sans-serif; }
a { color: var(--navy); }
header { background: var(--navy); color: #fff; padding: 14px 16px; display: flex; align-items: center; justify-content: space-between; gap: 12px; }
header a { color: #fff; text-decoration: none; }
header .brand { font: 500 18px 'Chakra Petch', sans-serif; letter-spacing: 1px; }
header .brand b { color: var(--gold); font-weight: 500; }
header .who { font-size: 14px; opacity: .85; }
main { max-width: 640px; margin: 0 auto; padding: 16px; }
.card { background: var(--card); border: 1px solid var(--line); padding: 18px; margin-bottom: 14px; }
.hero { background: var(--navy); color: #fff; border: 0; }
.hero p, .hero li { color: #c9d3dc; }
.hero h1 { color: #fff; }
.price { display: flex; align-items: baseline; gap: 8px; margin: 10px 0 4px; }
.price b { font: 400 44px 'Chakra Petch', sans-serif; color: var(--gold); }
.price span { color: #c9d3dc; }
.sr { width: .9em; height: .9em; vertical-align: -.08em; fill: currentColor; }
h1 { font-size: 22px; font-weight: 500; margin: 0 0 6px; }
h2 { font-size: 17px; font-weight: 500; margin: 0 0 10px; }
p, li { color: var(--mute); }
ul, ol { padding-inline-start: 22px; margin: 8px 0; }
li { margin: 3px 0; }
label.f { display: block; font-weight: 400; margin: 12px 0 6px; }
label.f small { color: var(--mute); font-weight: 300; }
input[type=text], input[type=tel], input[type=email], select { width: 100%; font: inherit; font-weight: 400; padding: 12px; border: 1px solid var(--line); background: #fff; color: var(--ink); }
input:focus, select:focus { outline: 2px solid var(--gold); outline-offset: -1px; }
.two { display: grid; grid-template-columns: 1fr 1fr; gap: 0 12px; }
@media (max-width: 480px) { .two { grid-template-columns: 1fr; } }
.check { display: flex; gap: 10px; align-items: flex-start; margin-top: 12px; color: var(--ink); }
.check input { width: 20px; height: 20px; margin-top: 4px; accent-color: var(--navy); flex: none; }
button { font-family: 'Tajawal', sans-serif; cursor: pointer; }
button.go { width: 100%; font-size: 17px; font-weight: 500; padding: 14px; border: 0; background: var(--navy); color: #fff; margin-top: 14px; }
button.go.gold { background: var(--gold); color: var(--navy); }
button.go:disabled { background: #9aa6b2; }
button.sm { font-size: 14px; padding: 8px 12px; border: 1px solid var(--line); background: #fff; color: var(--ink); }
.row { display: flex; gap: 8px; align-items: stretch; }
.row input { flex: 1; }
.row button { flex: none; border: 0; background: var(--navy); color: #fff; padding: 0 16px; font-size: 15px; }
.stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 14px; }
@media (max-width: 480px) { .stats { grid-template-columns: 1fr 1fr; } }
.stat { background: var(--card); border: 1px solid var(--line); padding: 12px; }
.stat .n { font: 400 24px 'Chakra Petch', sans-serif; }
.stat .l { color: var(--mute); font-size: 13px; }
.meter { height: 4px; background: var(--line); margin-top: 8px; }
.meter i { display: block; height: 100%; background: var(--gold); }
.pill { display: inline-block; font-size: 13px; padding: 1px 8px; border: 1px solid currentColor; }
.pill.ok { color: var(--ok); } .pill.err { color: var(--err); } .pill.mute { color: var(--mute); }
.msg { padding: 12px; margin: 12px 0 0; font-weight: 400; }
.msg.ok { background: #e8f5ee; color: var(--ok); }
.msg.err { background: #fbeceb; color: var(--err); }
.msg.info { background: #fdf6e3; color: #6b5310; }
table { width: 100%; border-collapse: collapse; font-size: 14px; }
td, th { text-align: start; padding: 8px 4px; border-bottom: 1px solid var(--line); font-weight: 300; }
th { color: var(--mute); font-size: 13px; }
.code { font: 500 22px 'Chakra Petch', sans-serif; letter-spacing: 2px; background: var(--bg); border: 1px dashed #b8c3cc; padding: 8px 12px; display: inline-block; direction: ltr; }
.secret { display: flex; gap: 8px; align-items: center; background: var(--bg); border: 1px solid var(--line); padding: 8px; margin-top: 8px; }
.secret code { flex: 1; font: 13px 'Chakra Petch', monospace; direction: ltr; text-align: left; word-break: break-all; }
.steps { counter-reset: s; list-style: none; padding: 0; }
.steps li { counter-increment: s; position: relative; padding-inline-start: 36px; margin: 10px 0; color: var(--ink); }
.steps li::before { content: counter(s); position: absolute; inset-inline-start: 0; top: 0; width: 26px; height: 26px; background: var(--gold); color: var(--navy); font: 500 14px/26px 'Chakra Petch', sans-serif; text-align: center; }
.hero .steps li { color: #fff; }
.hide { display: none !important; }
.k { font-size: 13px; color: var(--mute); }
.wa { display: flex; align-items: center; justify-content: center; gap: 8px; background: #1f8a4c; color: #fff; text-decoration: none; padding: 12px; font-weight: 500; margin-top: 10px; }
.mysr-form { margin-top: 10px; }
/* نماذج ميسر بنفس شكل الموقع: زوايا حادة وكحلي. */
/* تنسيق ميسر كله تحت div#mysr بـ !important، فنزيد عليه #app عشان نغلبه. */
#app div#mysr *, #app .mysr-form, #app .mysr-form * { border-radius: 0 !important; font-family: 'Tajawal', system-ui, sans-serif !important; }
#app div#mysr button[type=submit], #app .mysr-form button[type=submit] { background: var(--navy) !important; color: #fff !important; }
#app div#mysr input:focus { outline: 2px solid var(--gold) !important; box-shadow: none !important; }
footer { text-align: center; color: var(--mute); font-size: 13px; padding: 20px 16px 40px; }
footer a { color: var(--mute); }
@media print { header, footer, .noprint { display: none !important; } body { background: #fff; } }
</style>
</head>
<body>
<svg width="0" height="0" style="position:absolute" aria-hidden="true"><symbol id="riyal" viewBox="0 0 1256 1256"><path fill="currentColor" d="M750,1119 C730,1163,716,1211,711,1262 C711,1262,1136,1172,1136,1172 C1156,1127,1169,1079,1174,1028 C1174,1028,750,1119,750,1119Z M1136,901 C1136,901,1136,901,1136,901 C1156,857,1169,809,1174,758 C1174,758,843,828,843,828 C843,828,843,693,843,693 C843,693,1136,631,1136,631 C1156,587,1169,538,1174,488 C1174,488,843,558,843,558 C843,558,843,72,843,72 C793,100,748,138,711,183 C711,183,711,586,711,586 C711,586,579,614,579,614 C579,614,579,6,579,6 C528,34,483,72,447,117 C447,117,447,642,447,642 C447,642,151,705,151,705 C131,750,117,798,112,849 C112,849,447,777,447,777 C447,777,447,948,447,948 C447,948,88,1024,88,1024 C68,1068,55,1117,50,1167 C50,1167,425,1088,425,1088 C456,1081,482,1063,499,1038 C499,1038,568,936,568,936 C568,936,568,936,568,936 C575,926,579,913,579,899 C579,899,579,749,579,749 C579,749,711,721,711,721 C711,721,711,992,711,992 C711,992,1136,901,1136,901Z"/></symbol></svg>
<header><a class="brand" href="/">FISH <b>ID</b></a><div class="who" id="who">باقة المحلات</div></header>
<main id="app"><div class="card"><p>جاري التحميل...</p></div></main>
<footer>إحدى مبادرات منظومة حوات · <a href="/">hawat.id</a> · <a href="mailto:info@hawat.id">info@hawat.id</a> · <a href="/privacy.html">الخصوصية</a></footer>
<script>
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'})[c]);
const num = n => Number(n || 0).toLocaleString('ar-SA-u-nu-latn');
const day = t => t ? new Date(t).toLocaleDateString('ar-SA-u-ca-gregory-nu-latn', {year: 'numeric', month: 'long', day: 'numeric'}) : '—';
const SR = '<svg class="sr" role="img" aria-label="ريال"><use href="#riyal"/></svg>';
const WA = 'https://wa.me/966595233393?text=';
const params = new URLSearchParams(location.search);
const kinds = {market: 'سوق سمك', shop: 'محل سمك', restaurant: 'مطعم', hotel: 'فندق أو تموين', other: 'أخرى'};
let key = params.get('k') || '';
try { if (!key) key = localStorage.getItem('fishid-shop') || ''; } catch (e) {}
let cfg = {price: 350, cap: 300, devices: 5, pay: null};

async function call(path, body) {
  const res = await fetch('/api/' + path, {method: body ? 'POST' : 'GET', headers: {'content-type': 'application/json', 'x-shop': key}, body: body ? JSON.stringify(body) : undefined});
  const data = await res.json().catch(() => ({}));
  if (!res.ok) { const e = new Error(data.message || 'صار خطأ، حاول مرة ثانية'); e.status = res.status; throw e; }
  return data;
}

function remember(k) {
  key = k;
  try { localStorage.setItem('fishid-shop', k); } catch (e) {}
  history.replaceState(null, '', location.pathname + '?k=' + encodeURIComponent(k));
}

const features = () => `
  <ul>
    <li><b>${num(cfg.cap)} فحص بالشهر</b> مشتركة بين جوالات المحل.</li>
    <li>حتى <b>${num(cfg.devices)} جوالات</b> للموظفين، تضيفها وتشيلها بنفسك.</li>
    <li>نوع السمكة واسمها المحلي، ودرجة طزاجتها من 100، وكم يوم تتحمل.</li>
    <li>يتجدد كل شهر تلقائيًا، وتقدر توقف التجديد متى ما بغيت.</li>
    <li>إيصال لكل دفعة باسم محلك.</li>
  </ul>`;

function signup(err = '') {
  $('#app').innerHTML = `
  <div class="card hero">
    <h1>باقة المحلات والمطاعم</h1>
    <p>افحص شحنة السمك وقت الاستلام من جوالات موظفينك: صورة وحدة تعطيك النوع والطزاجة.</p>
    <div class="price"><b class="num">${num(cfg.price)}</b><span>${SR} / شهر</span></div>
    ${features()}
    <ol class="steps">
      <li>سجّل محلك وادفع ${cfg.pay ? 'بمدى أو البطاقة' + (cfg.pay.methods.includes('applepay') ? ' أو Apple Pay' : '') : ''}.</li>
      <li>حمّل تطبيق FISH ID على جوالات الموظفين.</li>
      <li>أضف الجوالات من لوحة محلك، وتبدأ الفحوصات على طول.</li>
    </ol>
  </div>
  <form class="card" id="f" novalidate>
    <h2>بيانات المحل</h2>
    <label class="f" for="name">اسم المحل أو المطعم</label><input type="text" id="name" maxlength="80" autocomplete="organization" required>
    <div class="two">
      <div><label class="f" for="kind">النوع</label><select id="kind">${Object.entries(kinds).map(([k, v]) => `<option value="${k}">${v}</option>`).join('')}</select></div>
      <div><label class="f" for="city">المدينة</label><input type="text" id="city" maxlength="40" placeholder="جدة، الدمام، جيزان..." required></div>
    </div>
    <div class="two">
      <div><label class="f" for="phone">جوال صاحب المحل</label><input type="tel" id="phone" dir="ltr" inputmode="tel" placeholder="05xxxxxxxx" autocomplete="tel" required></div>
      <div><label class="f" for="email">الإيميل <small>(اختياري، للإيصالات)</small></label><input type="email" id="email" dir="ltr" autocomplete="email"></div>
    </div>
    <label class="f" for="cr">رقم السجل التجاري <small>(اختياري، يطلع في الإيصال)</small></label><input type="text" id="cr" dir="ltr" inputmode="numeric" maxlength="10">
    <label class="check"><input type="checkbox" id="auto" checked><span>جدّد اشتراكي كل شهر تلقائيًا من نفس البطاقة (أقدر أوقفه من لوحة المحل).</span></label>
    <label class="check"><input type="checkbox" id="ok"><span>أوافق على <a href="/privacy.html" target="_blank" rel="noopener">سياسة الخصوصية</a>، وأعرف إن نتيجة الفحص تقدير يساعد وما يغني عن الفحص الرسمي.</span></label>
    <div id="msg">${err ? `<div class="msg err">${esc(err)}</div>` : ''}</div>
    <button class="go" id="go">${cfg.pay ? 'التالي: الدفع' : 'أرسل الطلب'}</button>
  </form>
  ${opened()}
  <div class="card"><h2>عندك سؤال؟</h2><p>كلّمنا واتساب ونرد عليك، أو راسلنا على <a href="mailto:info@hawat.id">info@hawat.id</a>.</p>
    <a class="wa" href="${WA}${encodeURIComponent('هلا، عندي محل وأبغى أعرف عن باقة المحلات في FISH ID')}" target="_blank" rel="noopener">واتساب 0595233393</a></div>`;
  $('#f').onsubmit = async e => {
    e.preventDefault();
    const go = $('#go');
    go.disabled = true;
    $('#msg').innerHTML = '';
    try {
      const r = await call('shop/start', {name: $('#name').value, kind: $('#kind').value, city: $('#city').value, phone: $('#phone').value, email: $('#email').value, cr: $('#cr').value, autoRenew: $('#auto').checked, consent: $('#ok').checked});
      remember(r.key);
      await dashboard(true);
    } catch (err) {
      $('#msg').innerHTML = `<div class="msg err">${esc(err.message)}</div>`;
      go.disabled = false;
    }
  };
}

// جهاز سبق وسجّل فيه محل: نعرض رابط لوحته.
function opened() {
  let k = '';
  try { k = localStorage.getItem('fishid-shop') || ''; } catch (e) {}
  return k ? `<div class="card"><p style="margin:0">سجّلت محلك من هذا الجهاز قبل؟ <a href="?k=${encodeURIComponent(k)}">افتح لوحة محلك</a></p></div>` : '';
}

let moyasarLoaded = null;
function loadMoyasar() {
  if (moyasarLoaded) return moyasarLoaded;
  moyasarLoaded = new Promise((ok, fail) => {
    const css = document.createElement('link');
    css.rel = 'stylesheet';
    css.href = 'https://cdn.jsdelivr.net/npm/moyasar-payment-form@2.2.14/dist/moyasar.css';
    document.head.append(css);
    const js = document.createElement('script');
    js.src = 'https://cdn.jsdelivr.net/npm/moyasar-payment-form@2.2.14/dist/moyasar.umd.js';
    js.onload = ok;
    js.onerror = fail;
    document.head.append(js);
  });
  return moyasarLoaded;
}

function payBox(s) {
  if (!cfg.pay) {
    const text = `هلا، سجّلت محلي «${s.name}» في باقة المحلات وأبغى أدفع بالتحويل البنكي. رمز المحل: ${s.join}`;
    return `<div class="card" id="pay"><h2>الدفع</h2>
      <p>الدفع الإلكتروني يتفعّل قريب. الحين تقدر تدفع <b>${num(cfg.price)} ${SR}</b> بالتحويل البنكي: كلّمنا واتساب ونرسل لك بيانات الحساب، ونفعّل محلك أول ما يوصل التحويل.</p>
      <a class="wa" href="${WA}${encodeURIComponent(text)}" target="_blank" rel="noopener">كلّمنا واتساب للدفع</a></div>`;
  }
  return `<div class="card" id="pay"><h2>${s.active ? 'جدّد شهر إضافي' : 'ادفع وفعّل محلك'}</h2>
    <p>${num(cfg.price)} ${SR} لمدة شهر${s.active ? '، تنضاف بعد تاريخ الانتهاء الحالي' : ''}. مدى، فيزا، ماستركارد${cfg.pay.methods.includes('applepay') ? '، Apple Pay' : ''}${cfg.pay.methods.includes('stcpay') ? '، STC Pay' : ''}.</p>
    ${cfg.pay.test ? '<div class="msg info">وضع التجربة: ما ينسحب مبلغ حقيقي.</div>' : ''}
    <div class="mysr-form"></div>
    <p class="k">الدفع يتم عند ميسر (Moyasar)، شركة مدفوعات سعودية مرخّصة من البنك المركزي. ما نشوف ولا نحفظ رقم بطاقتك.</p></div>`;
}

async function mountPay(s) {
  if (!cfg.pay || !$('.mysr-form')) return;
  try { await loadMoyasar(); } catch (e) { $('.mysr-form').innerHTML = '<div class="msg err">تعذّر تحميل صفحة الدفع، حدّث الصفحة.</div>'; return; }
  Moyasar.init({
    element: '.mysr-form',
    amount: cfg.price * 100,
    currency: 'SAR',
    description: 'FISH ID - باقة المحلات - ' + s.name,
    publishable_api_key: cfg.pay.key,
    callback_url: location.origin + '/api/shop/paid?k=' + encodeURIComponent(key),
    methods: cfg.pay.methods,
    supported_networks: ['mada', 'visa', 'mastercard'],
    language: 'ar',
    metadata: {shop: s.id},
    credit_card: {save_card: true},
    apple_pay: {country: 'SA', label: 'FISH ID', validate_merchant_url: 'https://api.moyasar.com/v1/applepay/initiate'},
  });
}

const mask = id => id.length > 12 ? id.slice(0, 6) + '…' + id.slice(-4) : id;
const methodName = p => p.method === 'transfer' ? 'تحويل بنكي' : (p.card || p.method || '');

async function dashboard(fresh = false) {
  let s;
  try { s = await call('shop/me'); }
  catch (e) {
    if (e.status === 401) { try { localStorage.removeItem('fishid-shop'); } catch (x) {} key = ''; history.replaceState(null, '', location.pathname); return signup(e.message); }
    $('#app').innerHTML = `<div class="card msg err">${esc(e.message)}</div>`; return;
  }
  $('#who').textContent = s.name;
  const r = params.get('r');
  const flash = r === 'ok' ? '<div class="msg ok">تم الدفع وتفعّل محلك ✅ أضف جوالات الموظفين تحت.</div>'
    : r === 'fail' ? `<div class="msg err">ما تم الدفع${params.get('m') ? ': ' + esc(params.get('m')) : ''}. جرّب مرة ثانية أو ببطاقة ثانية.</div>` : '';
  if (r) history.replaceState(null, '', location.pathname + '?k=' + encodeURIComponent(key));
  const left = s.until ? Math.ceil((new Date(s.until) - Date.now()) / 864e5) : 0;
  const showPay = !s.active || left <= 7 || !s.autoRenew || !s.canRenew;
  const pct = Math.min(100, Math.round(s.used / Math.max(1, s.cap) * 100));
  $('#app').innerHTML = `
  ${flash ? `<div class="card" style="padding:0;border:0">${flash}</div>` : ''}
  ${fresh ? `<div class="card"><h2>احفظ رابط لوحة محلك</h2><p>هذا الرابط هو مفتاح محلك، منه تدفع وتضيف الجوالات. احفظه في مكان آمن وما ترسله لأحد غير موظفينك اللي تثق فيهم.</p>
    <div class="secret"><code id="link">${esc(location.href)}</code><button class="sm" id="copy">نسخ</button></div></div>` : ''}
  <div class="card">
    <h1>${esc(s.name)}</h1>
    <div class="k">${esc(kinds[s.kind] || '')} · ${esc(s.city)}</div>
    <p style="margin:10px 0 0">${s.active ? `<span class="pill ok">مفعّل</span> لين <b>${day(s.until)}</b>${s.autoRenew && s.canRenew ? ' · يتجدد تلقائيًا من ' + esc(s.card) : ''}` : (s.until ? `<span class="pill err">منتهي</span> انتهى ${day(s.until)}` : '<span class="pill mute">ما تفعّل للحين</span> ادفع تحت وتفعّل على طول')}</p>
    ${s.renewError ? `<div class="msg err">ما قدرنا نجدد من بطاقتك: ${esc(s.renewError)}. جدّد تحت ببطاقة ثانية.</div>` : ''}
  </div>
  <div class="stats">
    <div class="stat"><div class="n num">${num(s.used)} <small style="font-size:14px">/ ${num(s.cap)}</small></div><div class="l">فحوصات هذا الشهر</div><div class="meter"><i style="width:${pct}%"></i></div></div>
    <div class="stat"><div class="n num">${num(s.devices.length)} <small style="font-size:14px">/ ${num(s.maxDevices)}</small></div><div class="l">جوالات مربوطة</div></div>
    <div class="stat"><div class="n num">${s.active ? num(Math.max(0, left)) : '—'}</div><div class="l">يوم باقي</div></div>
  </div>
  ${showPay ? payBox(s) : ''}
  <div class="card" id="dev">
    <h2>جوالات الموظفين</h2>
    <ol class="steps">
      <li>حمّل تطبيق FISH ID على جوال الموظف (<a href="/#download" target="_blank">روابط التحميل</a>).</li>
      <li>في التطبيق افتح القائمة واضغط <b>«رقم حسابك»</b>، ينسخ الرقم.</li>
      <li>الصق الرقم هنا واضغط «أضف».</li>
    </ol>
    <div class="row"><input type="text" id="acct" dir="ltr" placeholder="رقم الحساب من التطبيق" autocomplete="off"><button id="add">أضف</button></div>
    <div id="dmsg"></div>
    <p class="k" style="margin-top:12px">على أندرويد أسهل: القائمة ← <b>«عندك رمز؟»</b> واكتب رمز محلك:</p>
    <div class="code">${esc(s.join)}</div>
    <table style="margin-top:14px"><tr><th>الجهاز</th><th>آخر فحص</th><th class="num">الفحوصات</th><th></th></tr>
    ${s.devices.map(d => `<tr><td class="mono">${esc(mask(d.id))}</td><td>${d.lastScan ? day(d.lastScan) : '—'}</td><td class="num">${num(d.scans)}</td><td style="text-align:end"><button class="sm" data-rm="${esc(d.id)}">شيل</button></td></tr>`).join('') || '<tr><td colspan="4" class="k">ما فيه جوالات للحين</td></tr>'}
    </table>
  </div>
  <div class="card">
    <h2>التجديد التلقائي</h2>
    <label class="check"><input type="checkbox" id="renew" ${s.autoRenew ? 'checked' : ''}><span>جدّد كل شهر تلقائيًا${s.card ? ' من ' + esc(s.card) : ' (يتفعّل بعد أول دفعة بالبطاقة)'}</span></label>
    ${s.card ? '<button class="sm" id="forget" style="margin-top:10px">احذف البطاقة المحفوظة</button>' : ''}
  </div>
  <div class="card">
    <h2>الدفعات والإيصالات</h2>
    <table><tr><th>التاريخ</th><th>المبلغ</th><th>الطريقة</th><th></th></tr>
    ${s.payments.map((p, i) => `<tr><td>${day(p.at)}</td><td class="num">${num(p.sar)} ${SR}</td><td>${esc(methodName(p))}</td><td style="text-align:end"><button class="sm" data-rc="${i}">إيصال</button></td></tr>`).join('') || '<tr><td colspan="4" class="k">ما فيه دفعات للحين</td></tr>'}
    </table>
  </div>
  <div class="card"><h2>تحتاج مساعدة؟</h2><p>كلّمنا واتساب وعطنا رمز محلك <span class="mono">${esc(s.join)}</span>.</p>
    <a class="wa" href="${WA}${encodeURIComponent('هلا، عندي سؤال عن باقة المحلات. رمز المحل: ' + s.join)}" target="_blank" rel="noopener">واتساب 0595233393</a></div>`;
  if ($('#copy')) $('#copy').onclick = async () => { try { await navigator.clipboard.writeText(location.href); $('#copy').textContent = 'تم النسخ'; } catch (e) {} };
  const devMsg = (t, ok) => $('#dmsg').innerHTML = `<div class="msg ${ok ? 'ok' : 'err'}">${esc(t)}</div>`;
  $('#add').onclick = async () => {
    const v = $('#acct').value.trim();
    if (!v) return;
    $('#add').disabled = true;
    try { await call('shop/devices', {add: v}); await dashboard(); devMsg('تمت إضافة الجوال ✅ يقدر يفحص الحين.', true); }
    catch (e) { devMsg(e.message); $('#add').disabled = false; }
  };
  document.querySelectorAll('[data-rm]').forEach(b => b.onclick = async () => {
    if (!b.dataset.sure) { b.dataset.sure = 1; b.textContent = 'متأكد؟'; return; }
    try { await call('shop/devices', {remove: b.dataset.rm}); dashboard(); } catch (e) { devMsg(e.message); }
  });
  $('#renew').onchange = async () => { try { await call('shop/settings', {autoRenew: $('#renew').checked}); dashboard(); } catch (e) {} };
  if ($('#forget')) $('#forget').onclick = async () => {
    if (!$('#forget').dataset.sure) { $('#forget').dataset.sure = 1; $('#forget').textContent = 'متأكد؟ التجديد التلقائي يوقف'; return; }
    await call('shop/settings', {forgetCard: true}); dashboard();
  };
  document.querySelectorAll('[data-rc]').forEach(b => b.onclick = () => receipt(s, s.payments[+b.dataset.rc]));
  if (showPay) mountPay(s);
}

// إيصال رسمي للطباعة أو الحفظ PDF.
function receipt(s, p) {
  const w = window.open('', '_blank');
  if (!w) return;
  w.document.write(`<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>إيصال ${esc(p.id)}</title>
  <link href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@400&family=Tajawal:wght@300;400;500&display=swap" rel="stylesheet">
  <style>body{font:300 15px/1.8 Tajawal,sans-serif;color:#111;max-width:680px;margin:40px auto;padding:0 24px}h1{font-weight:500;font-size:20px;margin:0}
  .top{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:2px solid #0B2236;padding-bottom:14px;margin-bottom:20px}
  .brand{font:400 20px 'Chakra Petch',sans-serif;letter-spacing:1px}table{width:100%;border-collapse:collapse;margin:18px 0}td{border:1px solid #ccc;padding:8px 10px}
  td:first-child{width:38%;color:#555}.n{font-family:'Chakra Petch',sans-serif}.sr{width:.85em;height:.85em;vertical-align:-.06em}.foot{color:#666;font-size:12px;margin-top:30px;border-top:1px solid #ccc;padding-top:10px}
  @media print{button{display:none}}</style></head><body>
  ${document.querySelector('svg').outerHTML}
  <div class="top"><div><h1>إيصال دفع</h1><div>اشتراك باقة المحلات</div></div><div style="text-align:left"><div class="brand">FISH ID</div><div style="font-size:12px">إحدى مبادرات منظومة حوات</div></div></div>
  <table>
  <tr><td>رقم الإيصال</td><td class="n" dir="ltr" style="text-align:right">${esc(p.id)}</td></tr>
  <tr><td>التاريخ</td><td>${day(p.at)}</td></tr>
  <tr><td>العميل</td><td>${esc(s.name)} · ${esc(s.city)}</td></tr>
  ${s.cr ? `<tr><td>السجل التجاري</td><td class="n">${esc(s.cr)}</td></tr>` : ''}
  <tr><td>الوصف</td><td>باقة المحلات: ${num(s.cap)} فحص بالشهر، حتى ${num(s.maxDevices)} جوالات</td></tr>
  <tr><td>الفترة</td><td>حتى ${day(p.until)}</td></tr>
  <tr><td>طريقة الدفع</td><td>${esc(methodName(p))}</td></tr>
  <tr><td>المبلغ</td><td class="n"><b>${num(p.sar)}</b> ${SR}</td></tr>
  </table>
  <div class="foot">FISH ID · hawat.id · info@hawat.id</div>
  <button onclick="print()" style="margin-top:20px;padding:10px 18px;border:0;background:#0B2236;color:#fff;font:inherit">طباعة أو حفظ PDF</button>
  </body></html>`);
  w.document.close();
}

(async () => {
  try { cfg = await (await fetch('/api/shop/config')).json(); } catch (e) {}
  if (key) dashboard(); else signup();
})();
</script>
</body>
</html>
""";
