/// صفحة المصوّرين (https://hawat.id/api/collect?k=المفتاح): يكتب اسم السمكة ويصوّرها من 5 زوايا ويرفعها.
/// الصور تتصغّر في الجوال قبل الرفع (أسرع على نت السوق، وتنحذف منها بيانات الموقع).
const collectPage = r'''<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<meta name="theme-color" content="#0B2236">
<title>FISH ID · تصوير الأسماك</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@300;400;500&family=Tajawal:wght@300;400;500&display=swap" rel="stylesheet">
<style>
:root { --navy: #0B2236; --gold: #F2C14E; --ink: #0B2236; --mute: #5b6b7a; --line: #dfe5ea; --bg: #f5f7f9; --card: #fff; --ok: #1f8a4c; --err: #b3261e; }
* { box-sizing: border-box; border-radius: 0; }
html, body { margin: 0; background: var(--bg); color: var(--ink); font: 300 16px/1.6 'Tajawal', system-ui, sans-serif; -webkit-tap-highlight-color: transparent; }
.num, .mono { font-family: 'Chakra Petch', 'Tajawal', sans-serif; }
header { background: var(--navy); color: #fff; padding: 14px 16px; display: flex; align-items: center; justify-content: space-between; gap: 12px; }
header .brand { font: 500 18px 'Chakra Petch', sans-serif; letter-spacing: 1px; }
header .brand b { color: var(--gold); font-weight: 500; }
header .who { font-size: 14px; opacity: .85; text-align: left; }
main { max-width: 560px; margin: 0 auto; padding: 16px; }
.card { background: var(--card); border: 1px solid var(--line); padding: 16px; margin-bottom: 14px; }
h1 { font-size: 20px; font-weight: 500; margin: 0 0 6px; }
h2 { font-size: 16px; font-weight: 500; margin: 0 0 10px; }
p, li { color: var(--mute); }
ul { padding-inline-start: 20px; margin: 8px 0; }
label.f { display: block; font-weight: 400; margin: 12px 0 6px; }
input[type=text], input[type=tel], textarea { width: 100%; font: inherit; font-weight: 400; padding: 12px; border: 1px solid var(--line); background: #fff; color: var(--ink); }
input:focus, textarea:focus { outline: 2px solid var(--gold); outline-offset: -1px; }
.check { display: flex; gap: 10px; align-items: flex-start; margin-top: 12px; color: var(--ink); }
.check input { width: 20px; height: 20px; margin-top: 3px; accent-color: var(--navy); }
button.go { width: 100%; font: 500 17px 'Tajawal', sans-serif; padding: 14px; border: 0; background: var(--navy); color: #fff; margin-top: 14px; cursor: pointer; }
button.go:disabled { background: #9aa6b2; }
.stats { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 14px; }
.stat { background: var(--card); border: 1px solid var(--line); padding: 12px; }
.stat .n { font: 400 28px 'Chakra Petch', sans-serif; }
.stat .l { color: var(--mute); font-size: 14px; }
.shots { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 8px; }
.shot { position: relative; aspect-ratio: 4 / 3; border: 1px dashed #b8c3cc; background: #fafbfc; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; cursor: pointer; overflow: hidden; }
.shot.wide { grid-column: span 2; aspect-ratio: 16 / 7; }
.shot input { position: absolute; inset: 0; opacity: 0; cursor: pointer; }
.shot svg { width: 30px; height: 30px; stroke: var(--navy); fill: none; stroke-width: 1.4; }
.shot .t { font-weight: 400; margin-top: 4px; }
.shot .s { font-size: 12px; color: var(--mute); }
.shot img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
.shot.done { border: 2px solid var(--ok); }
.shot.done::after { content: '✓ ' attr(data-t); position: absolute; bottom: 0; inset-inline: 0; background: rgba(11, 34, 54, .75); color: #fff; font-size: 13px; padding: 3px; }
.msg { padding: 12px; margin-top: 12px; font-weight: 400; }
.msg.ok { background: #e8f5ee; color: var(--ok); }
.msg.err { background: #fbeceb; color: var(--err); }
.bar { height: 4px; background: var(--line); margin-top: 12px; display: none; }
.bar i { display: block; height: 100%; width: 0; background: var(--gold); transition: width .2s; }
.hint { font-size: 13px; color: var(--mute); margin-top: 6px; }
.match { font-size: 13px; margin-top: 6px; color: var(--ok); }
.tips li { margin: 3px 0; }
.hide { display: none; }
footer { text-align: center; color: var(--mute); font-size: 12px; padding: 20px 16px 40px; }
</style>
</head>
<body>
<header><div class="brand">FISH <b>ID</b></div><div class="who" id="who"></div></header>
<main id="app"><div class="card"><p>جاري التحميل...</p></div></main>
<footer>إحدى مبادرات منظومة حوات · hawat.id</footer>
<script>
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'})[c]);
const num = n => Number(n || 0).toLocaleString('ar-SA-u-nu-latn');
const params = new URLSearchParams(location.search);
let key = params.get('k') || '';
try { if (key) localStorage.setItem('fishid-collector', key); else key = localStorage.getItem('fishid-collector') || ''; } catch (e) {}
// المفتاح ما يبقى في شريط العنوان (عشان لو أحد صوّر الشاشة).
if (params.get('k')) history.replaceState(null, '', location.pathname);

async function api(path, body) {
  const res = await fetch(path, {method: body ? 'POST' : 'GET', headers: {'x-collector': key, 'content-type': 'application/json'}, body: body ? JSON.stringify(body) : undefined});
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.message || 'صار خطأ، حاول مرة ثانية');
  return data;
}

const PARTS = [
  ['right', 'الجنب اليمين', 'السمكة كاملة من جنبها اليمين', '<path d="M3 12c3-5 9-6 14-3l4-3v12l-4-3c-5 3-11 2-14-3z"/><circle cx="7" cy="11" r="1"/>'],
  ['left', 'الجنب اليسار', 'اقلبها وصوّر الجنب الثاني', '<path d="M21 12c-3-5-9-6-14-3L3 6v12l4-3c5 3 11 2 14-3z"/><circle cx="17" cy="11" r="1"/>'],
  ['tail', 'الذيل والزعانف', 'قريب، يبان شكل الذيل', '<path d="M4 12h8M12 12l8-7v14z"/>'],
  ['whole', 'السمكة كاملة', 'من فوق، كلها داخل الصورة', '<rect x="3" y="5" width="18" height="14"/><path d="M6 12c2-3 6-3.5 9-1.5l2-1.5v6l-2-1.5c-3 2-7 1.5-9-1.5z"/>'],
  ['ice', 'على الثلج', 'زي ما هي معروضة في البسطة', '<path d="M12 3v18M4 7.5l16 9M4 16.5l16-9"/>'],
];
let me = null, shots = {}, options = {};

async function start() {
  if (!key) return fail('افتح الرابط الخاص اللي وصلك من فريق FISH ID.');
  try { me = await api('collect/me'); } catch (e) { return fail(e.message); }
  $('#who').innerHTML = `${esc(me.name)}<br><span style="opacity:.7">${esc(me.city)}</span>`;
  options = {};
  for (const [id, name] of Object.entries(me.species || {})) options[`${name} (${id})`] = id;
  me.joined ? form() : join();
}

function fail(text) {
  $('#app').innerHTML = `<div class="card"><h1>ما قدرنا نفتح الصفحة</h1><p>${esc(text)}</p></div>`;
}

function join() {
  $('#app').innerHTML = `<div class="card"><h1>هلا ${esc(me.name)} 👋</h1>
    <p>شكرًا إنك معنا. صورك بتعلّم نموذج FISH ID يعرف أسماك أسواقنا بأسمائها المحلية.</p>
    <h2 style="margin-top:14px">الشروط باختصار</h2>
    <ul><li>الصور اللي ترفعها تصير ملك حوات، ونستخدمها لتدريب النموذج وتحسين التطبيق.</li>
    <li>لا تصوّر وجوه الناس، واستأذن البيّاع قبل التصوير.</li>
    <li>كل رفعة لسمكة وحدة، وما تتكرر نفس السمكة.</li>
    <li>المكافأة على كل سمكة تنقبل بعد المراجعة، حسب الاتفاق مع فريق حوات.</li></ul>
    <label class="f" for="contact">رقم جوالك أو إيميلك</label>
    <input type="tel" id="contact" dir="ltr" placeholder="05xxxxxxxx" autocomplete="tel">
    <label class="check"><input type="checkbox" id="ok"> <span>قريت الشروط وأوافق عليها</span></label>
    <button class="go" id="go">ابدأ التصوير</button><div id="m"></div></div>`;
  $('#go').onclick = async () => {
    if (!$('#ok').checked) return show('#m', 'وافق على الشروط أول', true);
    $('#go').disabled = true;
    try { await api('collect/join', {contact: $('#contact').value, consent: true}); me.joined = true; form(); }
    catch (e) { show('#m', e.message, true); $('#go').disabled = false; }
  };
}

function show(where, text, bad) { $(where).innerHTML = `<div class="msg ${bad ? 'err' : 'ok'}">${esc(text)}</div>`; }

function form(done) {
  shots = {};
  $('#app').innerHTML = `<div class="stats"><div class="stat"><div class="n num" id="today">${num(me.today)}</div><div class="l">سمكة اليوم</div></div>
    <div class="stat"><div class="n num" id="fish">${num(me.fish)}</div><div class="l">المجموع</div></div></div>
    ${done ? `<div class="msg ok" style="margin:0 0 14px">✓ انرفعت ${esc(done)}. يعطيك العافية! الحين السمكة اللي بعدها.</div>` : ''}
    <div class="card"><h2>1. اسم السمكة</h2>
      <input type="text" id="name" list="sp" placeholder="مثل: هامور، بياض، شعري..." autocomplete="off">
      <datalist id="sp">${Object.keys(options).map(o => `<option value="${esc(o)}">`).join('')}</datalist>
      <div class="hint">اكتب الاسم اللي يسميه البيّاع. لو طلع لك من القائمة اختره.</div><div class="match" id="match"></div></div>
    <div class="card"><h2>2. الصور</h2><div class="hint" style="margin-top:-6px">على الأقل 3 صور، والأفضل الخمس كلها.</div>
      <div class="shots">${PARTS.map(([k, t, s, icon], i) => `<label class="shot${i === 4 ? ' wide' : ''}" id="s-${k}" data-t="${t}">
        <svg viewBox="0 0 24 24">${icon}</svg><span class="t">${t}</span><span class="s">${s}</span>
        <input type="file" accept="image/*" capture="environment" data-k="${k}"></label>`).join('')}</div></div>
    <div class="card"><h2>3. ملاحظة (اختياري)</h2><textarea id="note" rows="2" placeholder="مثل: من صيد اليوم، أو الوزن تقريبًا"></textarea>
      <button class="go" id="send" disabled>ارفع السمكة</button><div class="bar" id="bar"><i></i></div><div id="m"></div></div>
    <div class="card tips"><h2>نصايح لصور أفضل</h2><ul>
      <li>الضوء يكون كويس، وبدون فلاش قوي يلمّع السمكة.</li>
      <li>السمكة كاملة داخل الصورة، من الراس للذيل.</li>
      <li>سمكة مختلفة كل مرة، حتى لو نفس النوع.</li>
      <li>إذا ما تعرف الاسم اسأل البيّاع، واكتبه زي ما قال.</li></ul></div>`;
  $('#name').oninput = () => { const id = options[$('#name').value]; $('#match').textContent = id ? `✓ من الموسوعة: رقم ${id}` : ''; ready(); };
  document.querySelectorAll('.shot input').forEach(inp => inp.onchange = async () => {
    const file = inp.files[0];
    if (!file) return;
    const box = $('#s-' + inp.dataset.k);
    try {
      shots[inp.dataset.k] = await shrink(file);
      box.querySelector('img')?.remove();
      const img = new Image();
      img.src = 'data:image/jpeg;base64,' + shots[inp.dataset.k];
      box.prepend(img);
      box.classList.add('done');
    } catch (e) { show('#m', 'ما قدرنا نقرأ الصورة، صوّرها مرة ثانية', true); }
    ready();
  });
  $('#send').onclick = send;
}

function ready() { $('#send').disabled = !($('#name').value.trim() && Object.keys(shots).length >= 3); }

// نصغّر الصورة لـ 1600 بكسل JPEG. الرسم على canvas يشيل بيانات الموقع والجهاز من الصورة.
function shrink(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      const scale = Math.min(1, 1600 / Math.max(img.naturalWidth, img.naturalHeight));
      const c = document.createElement('canvas');
      c.width = Math.round(img.naturalWidth * scale);
      c.height = Math.round(img.naturalHeight * scale);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      URL.revokeObjectURL(url);
      resolve(c.toDataURL('image/jpeg', 0.85).split(',')[1]);
    };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('bad image')); };
    img.src = url;
  });
}

function send() {
  const name = $('#name').value.trim();
  const body = JSON.stringify({
    name, species: options[name] || '', note: $('#note').value,
    images: PARTS.filter(([k]) => shots[k]).map(([k]) => ({part: k, image: shots[k], mediaType: 'image/jpeg'})),
  });
  $('#send').disabled = true;
  $('#m').innerHTML = '';
  const bar = $('#bar'); bar.style.display = 'block';
  // XMLHttpRequest عشان نعرض تقدم الرفع على نت السوق.
  const x = new XMLHttpRequest();
  x.open('POST', 'collect/upload');
  x.setRequestHeader('x-collector', key);
  x.setRequestHeader('content-type', 'application/json');
  x.upload.onprogress = e => { if (e.lengthComputable) bar.firstChild.style.width = Math.round(e.loaded / e.total * 100) + '%'; };
  x.onload = () => {
    let data = {};
    try { data = JSON.parse(x.responseText); } catch (e) {}
    if (x.status === 200) { me.fish = data.fish; me.today = data.today; form(name); scrollTo(0, 0); }
    else { bar.style.display = 'none'; show('#m', data.message || 'ما انرفعت، حاول مرة ثانية', true); ready(); }
  };
  x.onerror = () => { bar.style.display = 'none'; show('#m', 'النت ضعيف وما انرفعت. صورك محفوظة هنا، اضغط ارفع مرة ثانية.', true); ready(); };
  x.send(body);
}

start();
</script>
</body>
</html>
''';
