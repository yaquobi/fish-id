/// صفحة لوحة الأدمن على https://hawat.id/api/admin. الصفحة نفسها عامة، وكل البيانات تحتاج رمز:
/// رمز المالك FISHID_ADMIN_TOKEN أو رمز موظف من تبويب الفريق (يُحفظ في sessionStorage للجلسة فقط).
/// اللوحة بالعربي والإنجليزي (الأرقام دايم 123)، وكل صفحة تنطبع.
const adminPage = r'''<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>FISH ID Admin</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@400;500;600&family=Montserrat:wght@600;700;800&family=Tajawal:wght@300;400;500;700;800&display=swap" rel="stylesheet">
<style>
/* شكل اللوحة على طريقة X Ads Manager: قائمة جانبية بيضاء عائمة، ولوحة عمل بيضاء، خطوط خفيفة، وزوايا حادة بدون انحناء. */
:root{--navy:#0B2236;--navy-2:#122F48;--navy-3:#1B3D5C;--gold:#F2C14E;--gold-soft:#FDF3DA;--gold-ink:#7A5300;--bg:#F5F7F9;--surface:#fff;--ink:#0F1A24;--muted:#5B6B79;--line:#EAEEF2;--edge:#CFD9DE;--chip:#F3F5F7;--hover:#F7F9FA;--good:#17804F;--good-soft:#E3F4EA;--warn:#9A6200;--warn-soft:#FDF0D8;--bad:#B3261E;--bad-soft:#FBE6E4;--info-soft:#E5EEF8;--info:#21507A;--on-navy:#B8C8D8;--primary:#0B2236;--on-primary:#fff;--shadow:0 0 0 1px rgba(15,26,36,.04),0 1px 3px rgba(15,26,36,.05);--num:"Chakra Petch",Tajawal,ui-monospace,monospace}
:root[data-theme=dark]{--bg:#08131E;--surface:#0F2131;--ink:#E7EEF5;--muted:#93A6B8;--line:#1E3548;--edge:#2A4559;--chip:#17303F;--hover:#132A3C;--gold-soft:#3A2F14;--gold-ink:#F2C14E;--good:#5CD49A;--good-soft:#123527;--warn:#F2C14E;--warn-soft:#3A2F14;--bad:#FF8F84;--bad-soft:#3D1A18;--info:#8EC0F0;--info-soft:#14304A;--primary:#F2C14E;--on-primary:#0B2236;--shadow:0 0 0 1px rgba(0,0,0,.2);color-scheme:dark}
*{box-sizing:border-box}
*,*::before,*::after{border-radius:0!important}
[hidden]{display:none!important}
body{margin:0;background:var(--bg);color:var(--ink);font:300 14px/1.6 Tajawal,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
[dir=ltr] body{font-family:"Chakra Petch",Tajawal,system-ui,sans-serif}
b,strong{font-weight:500}
.shell{display:grid;grid-template-columns:240px minmax(0,1fr);gap:14px;min-height:100vh;padding:12px}
aside{background:var(--surface);color:var(--ink);border:1px solid var(--line);padding:14px 10px;position:sticky;top:12px;height:calc(100vh - 24px);overflow-y:auto;display:flex;flex-direction:column;gap:6px}
.brand{display:flex;align-items:center;gap:10px;padding:4px 8px 12px;border-bottom:1px solid var(--line)}
.brand svg{flex:none}
.brand b{font:600 16px var(--num);letter-spacing:.4px}
.brand b span{color:#C9961F}
.brand small{display:block;color:var(--muted);font-size:12px}
.brand .theme{margin-inline-start:auto;background:transparent;border:0;padding:6px;color:var(--muted);cursor:pointer}
.brand .theme:hover{background:var(--chip);color:var(--ink)}
.brand .theme svg{width:18px;height:18px}
nav{display:flex;flex-direction:column;gap:1px}
nav .grp{font-size:12px;color:var(--muted);padding:12px 12px 4px}
nav button{display:flex;align-items:center;gap:10px;background:transparent;color:var(--ink);border:0;padding:8px 12px;font-weight:300;font-size:14px;font-family:inherit;cursor:pointer;text-align:start;position:relative}
nav button:hover{background:var(--hover)}
nav button.on{font-weight:500}
nav button.on::before{content:"";position:absolute;inset-inline-start:-10px;top:7px;bottom:7px;width:3px;background:var(--ink)}
nav svg{width:18px;height:18px;flex:none}
nav .badge{margin-inline-start:auto;background:var(--bad);color:#fff;border-radius:50%!important;font-size:11px;min-width:20px;padding:0 6px;text-align:center;font-weight:500}
.side-foot{margin-top:auto;display:flex;flex-direction:column;gap:6px;border-top:1px solid var(--line);padding-top:10px}
.side-foot .who{color:var(--muted);font-size:12px;padding:0 8px}
.side-foot button{background:transparent;border:1px solid var(--edge);color:var(--ink);padding:6px;font-weight:300;font-size:13px;font-family:inherit;cursor:pointer}
.side-foot button:hover{background:var(--hover)}
main{background:var(--surface);border:1px solid var(--line);padding:22px clamp(16px,2.4vw,30px) 28px;width:100%;min-width:0}
.top{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-bottom:18px}
.top h1{margin:0;font-size:22px;font-weight:500}
.top .sub{color:var(--muted);font-size:13px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:12px}
.cols{display:grid;grid-template-columns:3fr 2fr;gap:14px;margin-top:14px}
.card{background:var(--surface);border:1px solid var(--line);padding:16px 18px;min-width:0}
.card h3{margin:0 0 12px;font-size:15px;font-weight:500;display:flex;justify-content:space-between;align-items:center;gap:8px}
.kpi .k{color:var(--muted);font-size:13px;font-weight:300}
.kpi .v{font:400 25px var(--num);margin:4px 0 2px;direction:ltr;text-align:right;font-variant-numeric:tabular-nums}
[dir=ltr] .kpi .v{text-align:left}
.kpi .v small{font:300 13px Tajawal;color:var(--muted)}
.kpi .n{color:var(--muted);font-size:13px}
.kpi .d{font-size:13px;font-weight:500;direction:ltr;display:inline-block}
.kpi.hero{background:var(--navy);color:#fff;border-color:var(--navy)}
.kpi.hero .k,.kpi.hero .n,.kpi.hero .v small{color:var(--on-navy)}
.kpi.hero .v,.kpi.hero .pos{color:var(--gold)!important}.kpi.hero .neg{color:#FF9A8F!important}
.pos{color:var(--good)!important}.neg{color:var(--bad)!important}
.k{color:var(--muted);font-size:14px}
.sr{width:.9em;height:.9em;vertical-align:-.1em;display:inline-block}
table{width:100%;border-collapse:collapse}
th,td{padding:10px 8px;border-bottom:1px solid var(--line);text-align:start;font-size:14px;vertical-align:middle}
th{color:var(--muted);font-weight:400;font-size:12px}
tr:last-child td{border-bottom:0}
td.num,th.num{text-align:left;direction:ltr;font-variant-numeric:tabular-nums;white-space:nowrap}
[dir=ltr] td.num,[dir=ltr] th.num{text-align:right}
tfoot td{font-weight:500;border-top:2px solid var(--line)}
.wrap{overflow-x:auto}
.mono{font-family:ui-monospace,monospace;direction:ltr;font-size:12px}
.pill{display:inline-block;padding:1px 9px;background:var(--chip);font-size:12px;font-weight:400;white-space:nowrap}
.pill.pay{background:var(--gold-soft);color:var(--gold-ink);font-weight:500}
.pill.ok{background:var(--good-soft);color:var(--good)}
.pill.no{background:var(--bad-soft);color:var(--bad)}
.pill.auto{background:var(--info-soft);color:var(--info)}
button.act{background:var(--primary);color:var(--on-primary);border:1px solid var(--primary);padding:7px 16px;font-weight:400;font-size:13px;font-family:inherit;cursor:pointer;white-space:nowrap}
button.act:hover{opacity:.88}
button.gold{background:var(--gold);border-color:var(--gold);color:var(--navy);font-weight:500}
button.gold:hover{background:#E8B33A}
button.ghost{background:var(--surface);color:var(--ink);border-color:var(--edge)}
button.ghost:hover{background:var(--hover);opacity:1}
button.sm{padding:3px 10px;font-size:12px}
input,select,textarea{font-size:14px;font-family:inherit;font-weight:400;padding:7px 10px;border:1px solid var(--edge);background:var(--surface);color:var(--ink);max-width:100%}
input:focus,select:focus{outline:2px solid var(--gold);outline-offset:0;border-color:var(--gold)}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.form{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:10px;align-items:end}
.form label{display:flex;flex-direction:column;gap:4px;font-size:13px;color:var(--muted)}
.seg{display:inline-flex;border:1px solid var(--edge)}
.seg button{border:0;background:transparent;padding:6px 12px;font-weight:400;font-size:13px;font-family:inherit;cursor:pointer;color:var(--muted)}
.seg button.on{background:var(--ink);color:var(--surface);font-weight:500}
#login{background:transparent;border:0}
.login{max-width:400px;margin:12vh auto;text-align:center}
.login input{width:100%;margin:14px 0 10px}
.photos{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px}
.thumbs{display:flex;gap:6px;margin-bottom:8px}
.thumbs img{width:33%;aspect-ratio:1;object-fit:cover;border-radius:10px;background:var(--chip)}
.msg{color:var(--muted);padding:28px;text-align:center}
.err{color:var(--bad)}
label.set{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid var(--line)}
label.set input{width:120px;direction:ltr}
.bars{display:flex;align-items:flex-end;gap:3px;height:150px;padding-top:8px;direction:ltr}
.bars div{flex:1;background:var(--navy-3);border-radius:4px 4px 0 0;min-height:2px;position:relative}
.bars div.neg{background:var(--bad);opacity:.7}
.bars div:hover{background:var(--gold)}
.axis{display:flex;justify-content:space-between;color:var(--muted);font-size:12px;margin-top:6px;direction:ltr}
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
.alerts{display:flex;flex-direction:column;gap:8px;margin-bottom:16px}
.alert{display:flex;gap:10px;align-items:center;padding:10px 14px;font-size:14px;font-weight:400}
.alert b{font-weight:500}
.alert.red{background:var(--bad-soft);color:var(--bad)}
.alert.amber{background:var(--gold-soft);color:var(--gold-ink)}
.alert.info{background:var(--info-soft);color:var(--info)}
.alert .go{margin-inline-start:auto}
.secret{display:flex;gap:8px;align-items:center;background:var(--navy);color:var(--gold);border-radius:12px;padding:10px 14px;margin-top:12px}
.secret code{flex:1;word-break:break-all;direction:ltr;font-size:13px}
.print-head,.print-foot,#doc{display:none}
/* مستند الطباعة الرسمي (كشف الحساب والتقرير)، يظهر في الطباعة بس */
.doc{font:12px/1.55 Tajawal,system-ui,sans-serif;color:#1C2B3A}
[dir=ltr] .doc{font-family:Montserrat,Tajawal,sans-serif;font-size:11px}
.doc .d-head{display:flex;justify-content:space-between;align-items:flex-start;gap:20px;padding-bottom:14px;border-bottom:3px solid var(--navy);position:relative}
.doc .d-head:after{content:"";position:absolute;inset-inline-start:0;bottom:-7px;width:90px;height:3px;background:var(--gold)}
.doc .d-brand{display:flex;gap:12px;align-items:center}
.doc .d-brand b{display:block;font:800 26px Montserrat,sans-serif;color:var(--navy);letter-spacing:.5px;line-height:1}
.doc .d-brand b span{color:#C9971F}
.doc .d-brand small{display:block;color:var(--muted);font-size:11px;margin-top:4px}
.doc .d-title{text-align:end}
.doc .d-title h1{margin:0;font-size:24px;font-weight:800;color:var(--navy);letter-spacing:.3px}
.doc .d-title .en{font:600 11px Montserrat,sans-serif;color:var(--muted);letter-spacing:2px;text-transform:uppercase}
.doc .d-meta{display:grid;grid-template-columns:repeat(4,1fr);margin:18px 0 12px;border:1px solid var(--line);border-radius:10px;overflow:hidden}
.doc .d-meta div{padding:8px 12px;border-inline-end:1px solid var(--line)}
.doc .d-meta div:last-child{border:0}
.doc .d-meta span{display:block;color:var(--muted);font-size:10px}
.doc .d-meta b{font-size:12.5px;color:var(--navy);font-variant-numeric:tabular-nums}
.doc .d-sum{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:8px}
.doc .d-sum div{border:1px solid var(--line);border-radius:10px;padding:10px 14px}
.doc .d-sum span{display:block;color:var(--muted);font-size:11px}
.doc .d-sum b{font:700 19px Montserrat,sans-serif;color:var(--navy);direction:ltr;display:block;text-align:start}
[dir=rtl] .doc .d-sum b{text-align:right}
.doc .d-sum b small{font:500 10px Tajawal;color:var(--muted)}
.doc .d-sum .main{background:var(--navy);border-color:var(--navy)}
.doc .d-sum .main span{color:var(--on-navy)}.doc .d-sum .main b{color:var(--gold)}
.doc h2{font-size:13.5px;margin:12px 0 5px;color:var(--navy);display:flex;align-items:center;gap:8px}
.doc h2:before{content:"";width:4px;height:14px;background:var(--gold);border-radius:2px}
.doc table{width:100%;border-collapse:collapse}
.doc th{background:#EEF2F6;color:var(--navy);font-size:10.5px;font-weight:800;padding:6px 8px;text-align:start;border-bottom:2px solid var(--navy)}
.doc td{padding:5px 8px;border-bottom:1px solid var(--line);font-size:11.5px;vertical-align:top;background:#fff}
.doc td.num,.doc th.num{text-align:left;direction:ltr;font-variant-numeric:tabular-nums;white-space:nowrap}
[dir=ltr] .doc td.num,[dir=ltr] .doc th.num{text-align:right}
.doc td.i{color:var(--muted);width:24px}
.doc td small{display:block;color:var(--muted);font-size:10px}
.doc .d-sub td{background:#F8FAFB;font-weight:800;color:var(--navy);border-bottom:1px solid var(--navy)}
.doc .d-bottom{display:grid;grid-template-columns:1fr 280px;gap:24px;margin-top:12px;align-items:start}
.doc .d-notes{color:var(--muted);font-size:10.5px;border:1px dashed var(--line);border-radius:10px;padding:10px 12px}
.doc .d-notes b{color:var(--navy);display:block;margin-bottom:2px}
.doc .d-total{border:1px solid var(--line);border-radius:10px;overflow:hidden}
.doc .d-total div{display:flex;justify-content:space-between;padding:5px 14px;border-bottom:1px solid var(--line)}
.doc .d-total div b{direction:ltr;font-variant-numeric:tabular-nums}
.doc .d-total .net{background:var(--navy);color:#fff;border:0;font-weight:800;font-size:13px}
.doc .d-total .net b{color:var(--gold)}
.doc .d-sign{display:grid;grid-template-columns:1fr 1fr 100px;gap:22px;margin-top:16px;break-inside:avoid}
.doc .d-sign div{font-size:11px;color:var(--muted)}
.doc .d-sign div p{margin:22px 0 0;border-top:1px solid #9AA8B5;padding-top:4px}
.doc .d-sign .stamp{width:92px;height:92px;border:2px dashed var(--line);border-radius:50%!important;display:flex;align-items:center;justify-content:center;text-align:center;font-size:10px}
.doc .d-foot{position:fixed;bottom:0;left:0;right:0;display:flex;justify-content:space-between;border-top:1px solid var(--line);padding-top:5px;font-size:9px;color:var(--muted)}
.doc .pos{color:var(--good)}.doc .neg{color:var(--bad)}
/* صفحة المستخدمين */
.u-head .row{gap:8px}
.u-kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px}
.u-kpis button{border:1px solid var(--line);background:var(--surface);padding:12px 16px;text-align:start;font-family:inherit;color:var(--ink);cursor:pointer}
.u-kpis button:hover{border-color:var(--muted)}
.u-kpis button.on{border-color:var(--ink)}
.u-kpis .k{color:var(--muted);font-size:13px;display:block}
.u-kpis .v{font:400 24px var(--num);display:block;direction:ltr;text-align:start;unicode-bidi:plaintext}
.u-kpis .d{font-size:12px;color:var(--muted)}
.u-banner{display:flex;align-items:center;gap:14px;border:1px solid var(--line);padding:12px 16px;margin-top:14px}
.u-banner .ic{width:36px;height:36px;border-radius:50%!important;background:var(--gold-soft);color:var(--gold-ink);display:grid;place-items:center;flex:none}
.u-banner .ic svg,.u-ico{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round;flex:none}
.u-banner div{flex:1;min-width:0}
.u-banner b{display:block}
.u-banner span{color:var(--muted);font-size:13px}
.u-views{display:flex;gap:2px;margin-top:20px;border-bottom:1px solid var(--line);overflow-x:auto}
.u-views button{background:transparent;border:0;border-bottom:2px solid transparent;margin-bottom:-1px;padding:8px 12px 10px;font:inherit;font-size:14px;color:var(--muted);cursor:pointer;white-space:nowrap;display:flex;gap:6px;align-items:center}
.u-views button.on{color:var(--ink);font-weight:500;border-color:var(--ink)}
.u-views .c{font:400 12px var(--num);background:var(--chip);padding:0 7px;color:var(--muted)}
.u-tools{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:14px}
.u-search{display:flex;align-items:center;gap:8px;border:1px solid var(--edge);padding:0 12px;flex:1 1 240px;max-width:360px;color:var(--muted)}
.u-search input{border:0;outline:0;background:transparent;padding:7px 0;width:100%;min-width:0}
.u-chip{display:inline-flex;align-items:center;gap:6px;border:1px solid var(--edge);background:var(--surface);color:var(--ink);padding:5px 12px;font:inherit;font-size:13px;cursor:pointer}
.u-chip:hover{background:var(--hover)}
.u-chip.set{border-color:var(--ink);background:var(--chip);font-weight:500}
.u-chip svg{width:14px;height:14px}
.u-pop{position:relative;display:inline-block}
.u-menu{position:absolute;top:calc(100% + 4px);inset-inline-start:0;background:var(--surface);border:1px solid var(--line);box-shadow:0 8px 24px rgba(15,26,36,.12);padding:6px;z-index:30;min-width:180px;display:flex;flex-direction:column;gap:2px}
.u-menu.end{inset-inline-start:auto;inset-inline-end:0}
.u-menu button{background:transparent;border:0;padding:7px 10px;text-align:start;font:inherit;font-size:13px;color:var(--ink);cursor:pointer;display:flex;gap:8px;align-items:center;white-space:nowrap}
.u-menu button:hover{background:var(--hover)}
.u-menu button[aria-checked=true]{font-weight:500}
.u-menu button[aria-checked=true]::after{content:"✓";margin-inline-start:auto;color:var(--good)}
.u-menu .row{padding:6px 4px;flex-wrap:nowrap}
.u-menu input{width:80px}
.u-menu .danger{color:var(--bad)}
.u-menu button.act{background:var(--primary);color:var(--on-primary);padding:4px 12px}
.u-menu button.act:hover{background:var(--primary)}
.u-head button.act{display:inline-flex;align-items:center;gap:6px}
.u-tools .end{margin-inline-start:auto;display:flex;gap:6px}
.u-icobtn{border:1px solid var(--edge);background:var(--surface);width:34px;height:34px;display:grid;place-items:center;color:var(--muted);cursor:pointer}
.u-icobtn:hover{color:var(--ink);background:var(--hover)}
.u-bulk{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-top:12px;background:var(--chip);padding:8px 14px;font-size:13px}
.u-bulk .x{margin-inline-start:auto;background:transparent;border:0;color:var(--muted);cursor:pointer;font-size:16px}
.u-table{border:1px solid var(--line);margin-top:12px;overflow-x:auto}
.u-table table{min-width:920px}
.u-table th{padding:10px 12px}
.u-table td{padding:14px 12px;font-size:13px}
.u-table tbody tr{cursor:pointer}
.u-table tbody tr:hover{background:var(--hover)}
.u-table tbody tr.sel{background:var(--info-soft)}
.u-table input[type=checkbox]{width:16px;height:16px;accent-color:#0B2236;cursor:pointer}
.u-id{font:400 13px var(--num);direction:ltr;unicode-bidi:isolate}
.u-sub{display:block;color:var(--muted);font-size:12px}
.u-num{font-family:var(--num);font-variant-numeric:tabular-nums;direction:ltr;unicode-bidi:isolate}
.u-st{display:inline-flex;align-items:center;gap:6px;padding:1px 10px;font-size:12px;white-space:nowrap;background:var(--chip);color:var(--muted)}
.u-st::before{content:"";width:6px;height:6px;border-radius:50%!important;background:currentColor}
.u-st.active{background:var(--good-soft);color:var(--good)}
.u-st.soon,.u-st.empty{background:var(--warn-soft);color:var(--warn)}
.u-st.blocked{background:var(--bad-soft);color:var(--bad)}
.u-bar{display:block;width:72px;height:3px;background:var(--chip);margin-top:4px;margin-inline-start:auto}
.u-bar i{display:block;height:100%;background:var(--good)}
.u-bar i.low{background:var(--bad)}
.u-acts{display:flex;gap:2px;justify-content:flex-end;opacity:.5}
tr:hover .u-acts,tr:focus-within .u-acts{opacity:1}
.u-acts>.u-pop>button{background:transparent;border:0;padding:6px;color:var(--muted);cursor:pointer;display:grid;place-items:center}
.u-acts>.u-pop>button:hover{background:var(--chip);color:var(--ink)}
.u-foot{display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap;margin-top:14px;color:var(--muted);font-size:13px}
.scrim{position:fixed;inset:0;background:rgba(8,19,30,.35);z-index:40}
.drawer{position:fixed;top:0;bottom:0;inset-inline-end:0;width:min(460px,100vw);background:var(--surface);border-inline-start:1px solid var(--line);z-index:41;display:flex;flex-direction:column}
.drawer .dh{padding:18px 20px 0;display:flex;gap:12px;align-items:flex-start}
.drawer .dh h2{margin:0;font:500 15px var(--num);direction:ltr;unicode-bidi:isolate;word-break:break-all}
.drawer .dh .x{margin-inline-start:auto;background:transparent;border:0;padding:6px;color:var(--muted);cursor:pointer}
.drawer .avatar{width:42px;height:42px;background:var(--chip);display:grid;place-items:center;color:var(--muted);flex:none}
.dtabs{display:flex;gap:2px;padding:0 14px;border-bottom:1px solid var(--line);margin-top:14px;overflow-x:auto}
.dtabs button{background:transparent;border:0;border-bottom:2px solid transparent;margin-bottom:-1px;padding:8px 10px;font:inherit;font-size:14px;color:var(--muted);cursor:pointer;white-space:nowrap}
.dtabs button.on{color:var(--ink);font-weight:500;border-color:var(--ink)}
.dtabs .soon{font-size:10px;background:var(--chip);padding:0 5px;margin-inline-start:4px}
.dbody{padding:16px 20px;overflow-y:auto;flex:1;display:flex;flex-direction:column;gap:14px}
.facts{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.facts div{border:1px solid var(--line);padding:10px 12px}
.facts span{display:block;font-size:12px;color:var(--muted)}
.facts b{font:400 17px var(--num);display:block}
.sect{border:1px solid var(--line);padding:12px 14px}
.sect h4{margin:0 0 10px;font-size:14px;font-weight:500}
.tl{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:10px}
.tl li{display:flex;gap:10px;font-size:13px}
.tl li::before{content:"";width:7px;height:7px;border-radius:50%!important;background:var(--gold);margin-top:7px;flex:none}
.tl time{color:var(--muted);font-size:12px;display:block}
.soonbox{border:1px dashed var(--edge);padding:22px;text-align:center;color:var(--muted)}
.soonbox b{color:var(--ink);display:block;margin-bottom:4px}
@media (max-width:860px){
  .shell{grid-template-columns:1fr;padding:0;gap:0}
  aside{position:sticky;top:0;height:auto;padding:8px 12px;flex-direction:row;align-items:center;gap:10px;z-index:5;overflow-x:auto;border-width:0 0 1px}
  .brand{border:0;padding:0}
  nav .grp,.brand .theme{display:none}
  nav button.on::before{inset-inline-start:0;top:auto;bottom:0;width:100%;height:2px}
  main{border:0;padding:16px}
  .brand small,.side-foot .who{display:none}
  .side-foot{margin:0;flex-direction:row}
  nav{flex-direction:row}
  nav button{padding:8px 10px;white-space:nowrap}
  nav button span{display:none}
  nav button.on span{display:inline}
  .cols{grid-template-columns:1fr}
  .u-kpis{grid-template-columns:repeat(2,minmax(0,1fr))}
  .grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
  .kpi .v{font-size:21px}
  .brand b{white-space:nowrap}
  .pl small{font-size:9px}
}
@media print{
  @page{size:A4;margin:10mm 10mm 14mm}
  :root[data-theme=dark]{--bg:#fff;--surface:#fff;--ink:#0F1A24;--muted:#5B6B79;--line:#EAEEF2;--edge:#CFD9DE;--chip:#F3F5F7;--gold-soft:#FDF3DA;--gold-ink:#7A5300;--good:#17804F;--good-soft:#E3F4EA;--bad:#B3261E;--bad-soft:#FBE6E4;--info:#21507A;--info-soft:#E5EEF8;color-scheme:light}
  body{background:#fff;font-size:12px}
  main{border:0}
  .u-bulk,.u-views,.u-tools,.u-banner,.u-acts,.u-check,.drawer,.scrim{display:none!important}
  aside,.noprint,button,input,select,.alerts,.top{display:none!important}
  .shell{display:block;padding:0}
  main{padding:0 0 10mm;max-width:none}
  .card{box-shadow:none;break-inside:avoid;border-color:var(--line);border-radius:12px;padding:12px 14px}
  .card h3{color:var(--navy);border-bottom:2px solid var(--gold);padding-bottom:6px;margin-bottom:8px;font-size:14px}
  .cols{grid-template-columns:1fr 1fr;gap:10px;margin-top:10px}
  .grid{grid-template-columns:repeat(4,1fr);gap:10px}
  .kpi .v{font-size:20px}
  .kpi .k,.kpi .n{font-size:11px}
  th{background:var(--navy);color:#fff;font-size:11px;padding:7px 8px}
  td{font-size:11.5px;padding:7px 8px}
  tr:nth-child(even) td{background:#F6F8FA}
  tfoot td{background:var(--gold-soft)!important;color:var(--navy)}
  .pill{border:1px solid var(--line)}
  .note{font-size:11px}
  .print-head{display:flex;justify-content:space-between;align-items:center;gap:16px;background:var(--navy);color:#fff;border-radius:14px;padding:14px 20px;border-bottom:4px solid var(--gold);margin-bottom:14px}
  .ph-brand{display:flex;align-items:center;gap:12px}
  .ph-brand b{font:800 24px Montserrat,sans-serif;letter-spacing:.5px;color:#fff}
  .ph-brand b span{color:var(--gold)}
  .ph-brand small{display:block;color:var(--on-navy);font-size:11px;margin-top:2px}
  .ph-doc{text-align:end}
  #ph-title{font-size:18px;font-weight:800}
  #ph-sub{color:var(--gold);font-size:12px;font-weight:700}
  #ph-meta{color:var(--on-navy);font-size:10px;margin-top:2px}
  .print-foot{display:flex;justify-content:space-between;position:fixed;bottom:0;left:0;right:0;border-top:1px solid var(--line);padding-top:4px;font-size:9.5px;color:var(--muted);background:#fff}
  .print-foot b{font-family:Montserrat,sans-serif;color:var(--navy)}
  .print-foot b span{color:var(--gold-ink)}
  *{-webkit-print-color-adjust:exact;print-color-adjust:exact}
  body.has-doc .shell{display:none!important}
  body.has-doc #doc{display:block}
  body.has-doc main{padding:0}
}
</style>
</head>
<body>
<div class="shell" id="shell" hidden>
<aside>
  <div class="brand">
    <svg width="34" height="34" viewBox="0 0 34 34" aria-hidden="true"><rect width="34" height="34" fill="#0B2236"/><path d="M6 11V7h4M28 11V7h-4M6 23v4h4M28 23v4h-4" stroke="#F2C14E" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M9 17c3-4 8-5 12-2l4-3v10l-4-3c-4 3-9 2-12-2z" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>
    <div><b>FISH <span>ID</span></b><small id="brand-sub"></small></div>
    <button class="theme" id="theme"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/></svg></button>
  </div>
  <nav id="nav"></nav>
  <div class="side-foot"><div class="who" id="who"></div><button id="lang"></button><button id="out"></button></div>
</aside>
<main>
<header class="print-head"><div class="ph-brand"><svg width="46" height="46" viewBox="0 0 34 34" aria-hidden="true"><rect width="34" height="34" rx="9" fill="#122F48"/><path d="M6 11V7h4M28 11V7h-4M6 23v4h4M28 23v4h-4" stroke="#F2C14E" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M9 17c3-4 8-5 12-2l4-3v10l-4-3c-4 3-9 2-12-2z" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg><div><b>FISH <span>ID</span></b><small id="ph-tag"></small></div></div>
  <div class="ph-doc"><div id="ph-title"></div><div id="ph-sub"></div><div id="ph-meta"></div></div></header>
<div class="alerts" id="alerts"></div><div id="app"></div>
<footer class="print-foot"><b>FISH <span>ID</span></b><span id="pf-note"></span><span dir="ltr">hawat.id</span></footer>
</main>
</div>
<main id="login"></main>
<div class="scrim" id="scrim" hidden></div>
<div class="drawer" id="drawer" role="dialog" aria-modal="true" hidden></div>
<div id="doc" class="doc"></div>
<script>
const $ = (s, e = document) => e.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

// اللغة: تتبع المتصفح أول مرة وبعدين اللي يختاره المستخدم. الأرقام دايم 123 والتاريخ ميلادي.
let lang = 'ar';
try { lang = localStorage.getItem('fishid-lang') || (navigator.language.startsWith('ar') ? 'ar' : 'en'); } catch (e) {}
const T = (ar, en) => lang === 'en' ? en : ar;
const loc = () => lang === 'en' ? 'en-GB' : 'ar-SA-u-nu-latn-ca-gregory';
function applyLang() {
  document.documentElement.lang = lang;
  document.documentElement.dir = lang === 'en' ? 'ltr' : 'rtl';
  document.title = T('FISH ID: لوحة الإدارة', 'FISH ID: Admin');
}
applyLang();
// الوضع الليلي: اختيار يدوي من زر القمر، ويتحفظ في المتصفح.
function applyTheme(t) {
  if (t === 'dark') document.documentElement.dataset.theme = 'dark';
  else delete document.documentElement.dataset.theme;
}
try { applyTheme(localStorage.getItem('fishid-theme')); } catch (e) {}

const money = n => (Math.round((n || 0) * 100) / 100).toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2});
// رمز الريال السعودي الرسمي (من خط saudi_riyal، رخصة SIL OFL).
const RIYAL = '<svg class="sr" viewBox="0 0 1256 1256" role="img" aria-label="SAR"><path fill="currentColor" d="M750,1119 C730,1163,716,1211,711,1262 C711,1262,1136,1172,1136,1172 C1156,1127,1169,1079,1174,1028 C1174,1028,750,1119,750,1119Z M1136,901 C1136,901,1136,901,1136,901 C1156,857,1169,809,1174,758 C1174,758,843,828,843,828 C843,828,843,693,843,693 C843,693,1136,631,1136,631 C1156,587,1169,538,1174,488 C1174,488,843,558,843,558 C843,558,843,72,843,72 C793,100,748,138,711,183 C711,183,711,586,711,586 C711,586,579,614,579,614 C579,614,579,6,579,6 C528,34,483,72,447,117 C447,117,447,642,447,642 C447,642,151,705,151,705 C131,750,117,798,112,849 C112,849,447,777,447,777 C447,777,447,948,447,948 C447,948,88,1024,88,1024 C68,1068,55,1117,50,1167 C50,1167,425,1088,425,1088 C456,1081,482,1063,499,1038 C499,1038,568,936,568,936 C568,936,568,936,568,936 C575,926,579,913,579,899 C579,899,579,749,579,749 C579,749,711,721,711,721 C711,721,711,992,711,992 C711,992,1136,901,1136,901Z"/></svg>';
const sar = n => money(n) + ` <small>${RIYAL}</small>`;
const num = n => (n || 0).toLocaleString('en-US');
const when = s => s ? new Date(s).toLocaleString(loc(), {dateStyle: 'medium', timeStyle: 'short'}) : '';
const dayName = d => new Date(d + 'T00:00:00Z').toLocaleDateString(loc(), {weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC'});
const shortDay = d => new Date(d + 'T00:00:00Z').toLocaleDateString(loc(), {day: 'numeric', month: 'short', timeZone: 'UTC'});
const monthName = m => new Date(m + '-01T00:00:00Z').toLocaleDateString(loc(), {month: 'long', year: 'numeric', timeZone: 'UTC'});
const monthShort = m => new Date(m + '-01T00:00:00Z').toLocaleDateString(loc(), {month: 'short', timeZone: 'UTC'});
const today = () => new Date().toISOString().slice(0, 10);
const thisMonth = () => today().slice(0, 7);
const storageName = k => ({ice: T('على ثلج', 'on ice'), fridge: T('ثلاجة', 'fridge'), room: T('حرارة الغرفة', 'room temp'), hot: T('بالحر', 'hot'), frozen: T('مجمّد', 'frozen'), unknown: T('الحفظ غير معروف', 'storage unknown')})[k] || k;
const planName = k => ({free: T('مجاني', 'Free'), monthly: T('شهري', 'Monthly'), yearly: T('سنوي', 'Yearly'), shop: T('محل', 'Shop')})[k] || k;
const repeatName = k => ({once: T('مرة وحدة', 'Once'), monthly: T('كل شهر', 'Monthly'), yearly: T('كل سنة', 'Yearly')})[k] || k;
const roleName = k => ({owner: T('المالك', 'Owner'), admin: T('مدير', 'Admin'), accountant: T('محاسب', 'Accountant'), investor: T('مستثمر', 'Investor')})[k] || k;
// اسم المنتج من رقمه في المتجر (fishid_monthly، fishid_yearly...).
const productName = id => /shop/.test(id) ? T('باقة المحل', 'Shop plan') : /year|annual/.test(id) ? T('الاشتراك السنوي', 'Yearly subscription') : /month/.test(id) ? T('الاشتراك الشهري', 'Monthly subscription') : id;
const providers = () => ({
  expense: ['Anthropic (Claude)', 'Hostinger', 'Google (Play, Cloud)', 'Apple', 'RevenueCat', T('الدومين', 'Domain'), T('تسويق وإعلانات', 'Marketing'), T('رواتب ومستقلين', 'Salaries & freelancers'), T('رسوم بنكية', 'Bank fees'), T('رسوم حكومية', 'Government fees'), T('أخرى', 'Other')],
  income: [T('محلات (تحويل بنكي)', 'Shops (bank transfer)'), T('رعاية أو منحة', 'Sponsorship or grant'), 'Google Play', 'App Store', T('أخرى', 'Other')],
});
const icons = {
  home: '<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
  report: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  money: '<rect x="3" y="6" width="18" height="12" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M7 9v6M17 9v6"/>',
  alerts: '<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 21h4"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.5 3.4-5.5 6.5-5.5s5.7 2 6.5 5.5M16 4.5a3.5 3.5 0 0 1 0 7M18 14.5c1.9.6 3.1 2.6 3.5 5.5"/>',
  scans: '<path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M4 16v3a1 1 0 0 0 1 1h3M16 20h3a1 1 0 0 0 1-1v-3M7 12c2-3 6-3.5 9-1.5l2-1.5v6l-2-1.5c-3 2-7 1.5-9-1.5z"/>',
  contrib: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-8 8"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>',
  codes: '<rect x="3" y="8" width="18" height="12" rx="2"/><path d="M12 8v12M3 12h18M12 8c-2-4-6-4-6-1.5S10 8 12 8zm0 0c2-4 6-4 6-1.5S14 8 12 8z"/>',
  site: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.5 3.8 5.5 3.8 9s-1.3 6.5-3.8 9c-2.5-2.5-3.8-5.5-3.8-9S9.5 5.5 12 3z"/>',
  launch: '<path d="M4 6h16v12H4z"/><path d="M4 7l8 6 8-6"/>',
  staff: '<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4-6 8-6s7 2 8 6"/><path d="M17 3l1.5 1.5L21 2"/>',
};
const tabName = k => ({home: T('الرئيسية', 'Overview'), report: T('التقارير', 'Reports'), money: T('المحاسبة', 'Accounting'), alerts: T('التنبيهات', 'Alerts'),
  users: T('المستخدمين', 'Users'), scans: T('الفحوصات', 'Scans'), contrib: T('صور المساهمين', 'Contributions'), settings: T('الباقات والأسعار', 'Plans & prices'),
  codes: T('رموز الهدايا', 'Gift codes'), site: T('الموقع والزوار', 'Website & status'), launch: T('بلّغني بالإطلاق', 'Launch waitlist'), staff: T('الفريق', 'Team')})[k];
// التبويبات حسب الصلاحية (السيرفر يتأكد بعد).
const roleTabs = {
  owner: ['home', 'site', 'launch', 'report', 'money', 'alerts', 'users', 'scans', 'contrib', 'settings', 'codes', 'staff'],
  admin: ['home', 'site', 'launch', 'report', 'money', 'alerts', 'users', 'scans', 'contrib', 'settings', 'codes'],
  accountant: ['home', 'report', 'money', 'alerts'],
  investor: ['report'],
};
// مجموعات القائمة الجانبية. أي تبويب جديد ينضاف لمجموعته هنا.
const navGroups = () => [
  [T('نظرة عامة', 'Overview'), ['home', 'report', 'alerts']],
  [T('العملاء', 'Customers'), ['users', 'scans', 'contrib', 'launch']],
  [T('المال', 'Money'), ['money', 'settings', 'codes']],
  [T('الموقع والفريق', 'Site & team'), ['site', 'staff']],
];
let token = '';
try { token = sessionStorage.getItem('fishid-admin') || ''; } catch (e) {}
let names = {}, me = null, current = 'home', currentArgs = [];

async function api(path, opts = {}) {
  const res = await fetch('admin/' + path, {...opts, headers: {authorization: 'Bearer ' + token, 'content-type': 'application/json'}});
  if (res.status === 401) { logout(); throw new Error(T('الرمز غير صحيح', 'Wrong token')); }
  if (!res.ok) throw new Error((await res.json().catch(() => ({}))).message || T('خطأ ', 'Error ') + res.status);
  return (res.headers.get('content-type') || '').includes('json') ? res.json() : res.blob();
}
const post = (path, body) => api(path, {method: 'POST', body: JSON.stringify(body)});
const sp = id => names[id] ? `${esc(names[id])} <span class="mono">${esc(id)}</span>` : `<span class="mono">${esc(id || '')}</span>`;
const printBtn = () => `<button class="act ghost noprint" onclick="window.print()">${T('طباعة', 'Print')}</button>`;
// الصفحة اللي لها مستند رسمي (كشف الحساب، التقرير) تحط هنا دالة ترسمه وقت الطباعة.
let docBuilder = null;
const heading = (title, sub = '', extra = '') => `<div class="top"><div><h1>${title}</h1>${sub ? `<div class="sub">${sub}</div>` : ''}</div><div class="row">${extra}${printBtn()}</div></div>`;
const kpi = (k, v, note = '', cls = '') => `<div class="card kpi ${cls}"><div class="k">${k}</div><div class="v">${v}</div>${note ? `<div class="n">${note}</div>` : ''}</div>`;
const signed = n => `<span class="${n < 0 ? 'neg' : 'pos'}">${sar(n)}</span>`;
const can = tab => (roleTabs[me?.role] || []).includes(tab);

function langButton() {
  return T('English', 'عربي');
}
function toggleLang() {
  lang = lang === 'en' ? 'ar' : 'en';
  try { localStorage.setItem('fishid-lang', lang); } catch (e) {}
  applyLang();
  if (me) { buildNav(); show(current, ...currentArgs); } else logout();
}

function logout() {
  token = '';
  me = null;
  try { sessionStorage.removeItem('fishid-admin'); } catch (e) {}
  $('#shell').hidden = true;
  $('#login').hidden = false;
  $('#login').innerHTML = `<div class="card login">
    <svg width="56" height="56" viewBox="0 0 34 34" aria-hidden="true"><rect width="34" height="34" rx="9" fill="#0B2236"/><path d="M6 11V7h4M28 11V7h-4M6 23v4h4M28 23v4h-4" stroke="#F2C14E" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M9 17c3-4 8-5 12-2l4-3v10l-4-3c-4 3-9 2-12-2z" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>
    <h2 style="margin:10px 0 4px">${T('لوحة إدارة FISH ID', 'FISH ID Admin')}</h2>
    <div class="k">${T('الصق رمز الدخول اللي وصلك', 'Paste the access token you were given')}</div>
    <input id="tok" type="password" autocomplete="current-password" placeholder="${T('الرمز', 'Token')}">
    <button class="act gold" id="go" style="width:100%">${T('دخول', 'Sign in')}</button><div id="lerr" class="err" style="margin-top:8px"></div>
    <button class="act ghost sm" id="lang2" style="margin-top:14px">${langButton()}</button></div>`;
  const go = async () => {
    token = $('#tok').value.trim();
    try { await api('me'); try { sessionStorage.setItem('fishid-admin', token); } catch (e) {} start(); }
    catch (e) { $('#lerr').textContent = e.message; }
  };
  $('#go').onclick = go;
  $('#tok').onkeydown = e => { if (e.key === 'Enter') go(); };
  $('#lang2').onclick = toggleLang;
}

function buildNav() {
  const tabs = roleTabs[me.role];
  $('#nav').innerHTML = navGroups().map(([g, keys]) => {
    const mine = keys.filter(k => tabs.includes(k));
    return mine.length ? `<div class="grp">${g}</div>` + mine.map(k => `<button data-tab="${k}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${icons[k]}</svg><span>${tabName(k)}</span></button>`).join('') : '';
  }).join('');
  document.querySelectorAll('#nav button').forEach(b => b.onclick = () => show(b.dataset.tab));
  $('#brand-sub').textContent = T('لوحة الإدارة', 'Admin panel');
  $('#who').textContent = (me.name ? me.name + ' · ' : '') + roleName(me.role);
  $('#lang').textContent = langButton();
  $('#out').textContent = T('خروج', 'Sign out');
  $('#theme').title = $('#theme').ariaLabel = T('الوضع الليلي', 'Dark mode');
}

async function start() {
  me = await api('me');
  if (!roleTabs[me.role]) return logout();
  $('#login').hidden = true;
  $('#shell').hidden = false;
  buildNav();
  $('#lang').onclick = toggleLang;
  $('#out').onclick = logout;
  $('#theme').onclick = () => {
    const t = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    applyTheme(t);
    try { localStorage.setItem('fishid-theme', t); } catch (e) {}
  };
  names = await api('species').catch(() => ({}));
  const tab = location.hash.slice(1);
  show(can(tab) ? tab : roleTabs[me.role][0]);
}

async function show(tab, ...args) {
  if (!can(tab)) tab = roleTabs[me.role][0];
  current = tab;
  currentArgs = args;
  docBuilder = null;
  $('#drawer').hidden = $('#scrim').hidden = true;
  document.querySelectorAll('#nav button').forEach(b => b.classList.toggle('on', b.dataset.tab === tab));
  history.replaceState(null, '', '#' + tab);
  $('#app').innerHTML = `<div class="msg">${T('جاري التحميل…', 'Loading…')}</div>`;
  if (can('alerts')) loadAlerts();
  try { await views[tab](...args); } catch (e) { $('#app').innerHTML = `<div class="msg err">${esc(e.message)}</div>`; }
  fillPrint();
}

// ترويسة الطباعة: عنوان الصفحة وفترتها ووقت الطباعة ومن طبعها.
function fillPrint() {
  $('#ph-tag').textContent = T('إحدى مبادرات منظومة حوات', 'A HUWAT ecosystem initiative');
  $('#ph-title').textContent = $('#app .top h1')?.textContent || tabName(current);
  $('#ph-sub').textContent = $('#app .top .sub')?.textContent || '';
  $('#ph-meta').textContent = T('طُبع ', 'Printed ') + when(new Date().toISOString()) + (me ? ' · ' + (me.name || roleName(me.role)) : '');
  $('#pf-note').textContent = T('تقرير صادر من لوحة إدارة FISH ID، للاستخدام الداخلي', 'Generated by the FISH ID admin panel, for internal use');
}
window.addEventListener('beforeprint', () => {
  fillPrint();
  $('#doc').innerHTML = docBuilder ? docBuilder() : '';
  document.body.classList.toggle('has-doc', !!docBuilder);
});

const logoSvg = size => `<svg width="${size}" height="${size}" viewBox="0 0 34 34" aria-hidden="true"><rect width="34" height="34" rx="9" fill="#0B2236"/><path d="M6 11V7h4M28 11V7h-4M6 23v4h4M28 23v4h-4" stroke="#F2C14E" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M9 17c3-4 8-5 12-2l4-3v10l-4-3c-4 3-9 2-12-2z" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
const docSar = n => `${money(n)} <small>${RIYAL}</small>`;

// هيكل المستند: الترويسة، بيانات المستند، المحتوى، التوقيعات والتذييل.
function docShell({title, en, number, period, body}) {
  return `<div class="d-head">
      <div class="d-brand">${logoSvg(54)}<div><b>FISH <span>ID</span></b><small>${T('إحدى مبادرات منظومة حوات', 'A HUWAT ecosystem initiative')}</small><small dir="ltr">hawat.id</small></div></div>
      <div class="d-title"><h1>${title}</h1><div class="en">${en}</div></div></div>
    <div class="d-meta">
      <div><span>${T('رقم المستند', 'Document no.')}</span><b dir="ltr">${number}</b></div>
      <div><span>${T('الفترة', 'Period')}</span><b>${period}</b></div>
      <div><span>${T('تاريخ الإصدار', 'Issued')}</span><b>${new Date().toLocaleDateString(loc(), {day: 'numeric', month: 'long', year: 'numeric'})}</b></div>
      <div><span>${T('أعدّه', 'Prepared by')}</span><b>${esc(me?.name || roleName(me?.role))}</b></div>
    </div>
    ${body}
    <div class="d-sign">
      <div>${T('المحاسب', 'Accountant')}<p>${T('الاسم والتوقيع', 'Name and signature')}</p></div>
      <div>${T('الإدارة', 'Management')}<p>${T('الاسم والتوقيع', 'Name and signature')}</p></div>
      <div class="stamp">${T('الختم', 'Stamp')}</div>
    </div>
    <div class="d-foot"><span>FISH ID · ${T('إحدى مبادرات منظومة حوات', 'A HUWAT ecosystem initiative')}</span><span>${T('مستند صادر آليًا من لوحة إدارة FISH ID', 'Issued automatically by the FISH ID admin panel')}</span><span dir="ltr">hawat.id</span></div>`;
}

// كشف الحساب الشهري بشكل فاتورة.
function statementDoc(r) {
  const inc = r.income.map((i, n) => `<tr><td class="i">${n + 1}</td><td>${esc(i.auto ? productName(i.label) : i.label)}${i.note ? `<small>${esc(i.note)}</small>` : ''}</td><td>${esc(i.provider)}</td>
    <td class="num">${i.auto ? num(i.n) : '—'}</td><td class="num">${money(i.auto ? i.grossSar : i.sar)}</td><td class="num">${i.auto ? money(i.taxSar) : '—'}</td><td class="num">${i.auto ? money(i.feeSar) : '—'}</td><td class="num"><b>${money(i.sar)}</b></td></tr>`).join('')
    || `<tr><td colspan="8">${T('لا يوجد دخل مسجّل', 'No income recorded')}</td></tr>`;
  const exp = r.expenses.map((e, n) => `<tr><td class="i">${n + 1}</td><td>${esc(e.auto ? T(e.label, autoLabel(e)) : e.label)}${e.n ? `<small>${num(e.n)} ${T('فحص', 'scans')}</small>` : ''}${e.note ? `<small>${esc(e.note)}</small>` : ''}</td><td>${esc(e.provider)}</td>
    <td>${e.auto ? T('حسب الاستخدام', 'Usage based') : repeatName(e.repeat)}${e.original ? `<small dir="ltr">${esc(e.original)}</small>` : ''}</td><td class="num"><b>${money(e.sar)}</b></td></tr>`).join('')
    || `<tr><td colspan="5">${T('لا توجد مصاريف مسجّلة', 'No expenses recorded')}</td></tr>`;
  return docShell({
    title: T('كشف الحساب الشهري', 'Monthly statement'), en: T('Monthly Statement', 'Income & expenses'),
    number: 'FID-ST-' + r.month.replace('-', ''), period: monthName(r.month),
    body: `<div class="d-sum">
        <div><span>${T('الدخل الصافي', 'Net income')}</span><b>${docSar(r.incomeSar)}</b></div>
        <div><span>${T('المصاريف', 'Expenses')}</span><b>${docSar(r.expensesSar)}</b></div>
        <div class="main"><span>${T('صافي الربح', 'Net profit')}${r.margin != null ? ` · ${T('الهامش', 'margin')} ${num(r.margin)}%` : ''}</span><b>${docSar(r.netSar)}</b></div></div>
      <h2>${T('أولًا: الدخل', '1. Income')}</h2>
      <table><tr><th>#</th><th>${T('البند', 'Item')}</th><th>${T('المصدر', 'Source')}</th><th class="num">${T('العدد', 'Qty')}</th><th class="num">${T('الإجمالي', 'Gross')}</th><th class="num">${T('الضريبة', 'VAT')}</th><th class="num">${T('عمولة المتجر', 'Store fee')}</th><th class="num">${T('الصافي', 'Net')}</th></tr>
        ${inc}<tr class="d-sub"><td></td><td colspan="6">${T('إجمالي الدخل الصافي', 'Total net income')}</td><td class="num">${money(r.incomeSar)}</td></tr></table>
      <h2>${T('ثانيًا: المصاريف', '2. Expenses')}</h2>
      <table><tr><th>#</th><th>${T('البند', 'Item')}</th><th>${T('المزوّد', 'Provider')}</th><th>${T('التكرار', 'Repeats')}</th><th class="num">${T('المبلغ', 'Amount')}</th></tr>
        ${exp}<tr class="d-sub"><td></td><td colspan="3">${T('إجمالي المصاريف', 'Total expenses')}</td><td class="num">${money(r.expensesSar)}</td></tr></table>
      <div class="d-bottom">
        <div class="d-notes"><b>${T('ملاحظات', 'Notes')}</b>${T('جميع المبالغ بالريال السعودي. دخل المتجر بعد خصم ضريبة القيمة المضافة وعمولة Google Play. المصاريف بالدولار محوّلة بسعر الصرف المعتمد في اللوحة. تكلفة Claude محسوبة آليًا من كل فحص.', 'All amounts in Saudi riyals. Store income is after VAT and the Google Play fee. USD expenses are converted at the rate set in the panel. Claude cost is calculated automatically per scan.')}
          ${r.sandboxSales ? `<br>${T('مبيعات تجريبية غير محتسبة:', 'Test purchases not counted:')} ${num(r.sandboxSales)}` : ''}</div>
        <div class="d-total">
          <div><span>${T('إجمالي مبيعات المتجر', 'Store gross sales')}</span><b>${money(r.grossSar)}</b></div>
          <div><span>${T('الضريبة والعمولة', 'VAT and fees')}</span><b>−${money(r.storeTaxSar + r.storeFeeSar)}</b></div>
          <div><span>${T('الدخل الصافي', 'Net income')}</span><b>${money(r.incomeSar)}</b></div>
          <div><span>${T('المصاريف', 'Expenses')}</span><b>−${money(r.expensesSar)}</b></div>
          <div class="net"><span>${T('صافي الربح', 'Net profit')}</span><b>${money(r.netSar)} ${RIYAL}</b></div>
        </div></div>`,
  });
}

// ملخص الأداء للمستثمر.
function reportDoc(r, period, key) {
  const p = r.previous;
  const pct = (c, v, low = false) => {
    if (!v) return c ? T('جديد', 'new') : '—';
    const x = Math.round((c - v) / Math.abs(v) * 100);
    return `<span class="${(low ? x < 0 : x > 0) ? 'pos' : x ? 'neg' : ''}">${x > 0 ? '+' : ''}${num(x)}%</span>`;
  };
  const rows = [[T(`الدخل الصافي (${RIYAL})`, `Net income (${RIYAL})`), 'incomeSar', money], [T(`المصاريف (${RIYAL})`, `Expenses (${RIYAL})`), 'expensesSar', money, true], [T(`صافي الربح (${RIYAL})`, `Net profit (${RIYAL})`), 'netSar', money],
    [T(`مبيعات المتجر (${RIYAL})`, `Store gross (${RIYAL})`), 'grossSar', money], [T('اشتراكات جديدة', 'New subscriptions'), 'newSubs', num], [T('تجديدات', 'Renewals'), 'renewals', num],
    [T('مستخدمون جدد', 'New users'), 'newUsers', num], [T('مستخدمون نشطون', 'Active users'), 'activeUsers', num], [T('الفحوصات', 'Scans'), 'scans', num],
    [T(`تكلفة Claude (${RIYAL})`, `Claude cost (${RIYAL})`), 'claudeSar', money, true]];
  const paying = Object.values(r.payingNow).reduce((t, n) => t + n, 0);
  const title = {day: T('ملخص الأداء اليومي', 'Daily performance summary'), month: T('ملخص الأداء الشهري', 'Monthly performance summary'), year: T('ملخص الأداء السنوي', 'Annual performance summary')}[period];
  return docShell({
    title, en: T('Performance Summary', 'For investors and partners'), number: 'FID-RP-' + key.replace(/-/g, ''), period: periodLabel(period, key),
    body: `<div class="d-sum">
        <div><span>${T('المشتركون حاليًا', 'Paying subscribers')}</span><b>${num(paying)}</b></div>
        <div><span>${T('إجمالي المستخدمين', 'Total users')}</span><b>${num(r.users)}</b></div>
        <div class="main"><span>${T('صافي الربح', 'Net profit')}</span><b>${docSar(r.netSar)}</b></div></div>
      <h2>${T('المؤشرات الرئيسية', 'Key indicators')}</h2>
      <table><tr><th>#</th><th>${T('المؤشر', 'Indicator')}</th><th class="num">${esc(periodLabel(period, key))}</th><th class="num">${esc(periodLabel(period, r.previousKey))}</th><th class="num">${T('التغيّر', 'Change')}</th></tr>
        ${rows.map(([l, f, fmt, low], n) => `<tr><td class="i">${n + 1}</td><td>${l}</td><td class="num"><b>${fmt(r[f])}</b></td><td class="num">${fmt(p[f])}</td><td class="num">${pct(r[f], p[f], low)}</td></tr>`).join('')}</table>
      <div class="d-bottom">
        <div><h2 style="margin-top:0">${T('أكثر الأنواع فحصًا', 'Most scanned species')}</h2>
          <table><tr><th>#</th><th>${T('النوع', 'Species')}</th><th class="num">${T('الفحوصات', 'Scans')}</th></tr>
          ${r.topSpecies.slice(0, 5).map((t, n) => `<tr><td class="i">${n + 1}</td><td>${esc(names[t.id] || t.id)}</td><td class="num">${num(t.n)}</td></tr>`).join('') || `<tr><td colspan="3">—</td></tr>`}</table></div>
        <div class="d-total">
          <div><span>${T('المشتركون الشهريون', 'Monthly plans')}</span><b>${num(r.payingNow.monthly)}</b></div>
          <div><span>${T('المشتركون السنويون', 'Yearly plans')}</span><b>${num(r.payingNow.yearly)}</b></div>
          <div><span>${T('المحلات', 'Shops')}</span><b>${num(r.payingNow.shop)}</b></div>
          <div><span>${T('متوسط ثقة التعرّف', 'Average ID confidence')}</span><b>${r.avgConfidence != null ? num(Math.round(r.avgConfidence)) + '%' : '—'}</b></div>
          <div class="net"><span>${T('صافي الربح', 'Net profit')}</span><b>${money(r.netSar)} ${RIYAL}</b></div>
        </div></div>
      <div class="d-notes" style="margin-top:14px"><b>${T('ملاحظات', 'Notes')}</b>${T('المبالغ بالريال السعودي بعد ضريبة المتجر وعمولته. المقارنة مع الفترة السابقة المماثلة.', 'Amounts in SAR after store VAT and fees. Compared with the previous equal period.')} ${period === 'day' ? T('الملخص اليومي لا يوزّع المصاريف الشهرية على الأيام.', 'The daily summary does not spread monthly costs across days.') : ''}</div>`,
  });
}

// نص التنبيه بلغة اللوحة. السيرفر يرسل الرمز والأرقام بس.
function alertText(a) {
  const usd = n => '$' + money(n);
  switch (a.code) {
    case 'claude_credit': return T(`<b>رصيد Claude خلص والفحص واقف.</b> اشحن من console.anthropic.com ← Billing، ويرجع الفحص بنفسه.`, `<b>Claude credit ran out and scanning is down.</b> Top up at console.anthropic.com → Billing; scanning resumes by itself.`);
    case 'claude_account': return T(`<b>Claude رفض المفتاح.</b> الحساب موقوف أو المفتاح انلغى، راجع console.anthropic.com.`, `<b>Claude rejected the API key.</b> The account is suspended or the key was revoked; check console.anthropic.com.`);
    case 'balance_out': return T(`<b>رصيد Claude المتوقع خلص</b> (صرفنا ${usd(a.spentUsd)} من ${usd(a.usd)}). اشحن الحين وحدّث الرصيد هنا.`, `<b>Expected Claude balance is used up</b> (spent ${usd(a.spentUsd)} of ${usd(a.usd)}). Top up now and update the balance here.`);
    case 'balance_low': return T(`<b>رصيد Claude قرب يخلص:</b> باقي تقريبًا ${usd(a.leftUsd)}${a.daysLeft != null ? `، يكفي ${num(a.daysLeft)} يوم` : ''}.`, `<b>Claude balance is running low:</b> about ${usd(a.leftUsd)} left${a.daysLeft != null ? `, enough for ${num(a.daysLeft)} days` : ''}.`);
    case 'balance_unset': return T('سجّل رصيد Claude الحالي عشان ننبهك قبل ما يخلص.', 'Enter the current Claude balance so you get warned before it runs out.');
    case 'bill_due': return T(`<b>فاتورة قريبة:</b> ${esc(a.label)} (${esc(a.provider)}) بتاريخ ${shortDay(a.due)}، ${money(a.sar)} ${RIYAL}`, `<b>Bill due:</b> ${esc(a.label)} (${esc(a.provider)}) on ${shortDay(a.due)}, ${money(a.sar)} ${RIYAL}`);
    default: return esc(a.code);
  }
}
let alertCache = null;
async function loadAlerts() {
  try { alertCache = await api('alerts'); } catch (e) { return; }
  const list = alertCache.alerts.filter(a => current !== 'alerts' || a.level !== 'info');
  $('#alerts').innerHTML = current === 'alerts' ? '' : list.map(a => `<div class="alert ${a.level}"><span>${alertText(a)}</span>${current !== 'alerts' ? `<button class="act ghost sm go" data-go>${T('التفاصيل', 'Details')}</button>` : ''}</div>`).join('');
  $('#alerts').querySelectorAll('[data-go]').forEach(b => b.onclick = () => show('alerts'));
  const urgent = alertCache.alerts.filter(a => a.level !== 'info').length;
  const btn = $('#nav button[data-tab=alerts]');
  if (btn) { btn.querySelector('.badge')?.remove(); if (urgent) btn.insertAdjacentHTML('beforeend', `<b class="badge">${urgent}</b>`); }
}

function bars(series, field, label, fmt = num) {
  const vals = series.map(s => s[field] || 0);
  const max = Math.max(1e-9, ...vals.map(Math.abs));
  return `<div class="bars">${series.map((s, i) => `<div class="${vals[i] < 0 ? 'neg' : ''}" style="height:${Math.abs(vals[i]) / max * 100}%" title="${esc(label(s.key))}: ${fmt(vals[i])}"></div>`).join('')}</div>
    <div class="axis"><span>${esc(label(series[0].key))}</span><span>${esc(label(series[series.length - 1].key))}</span></div>`;
}

function dailyChart(daily) {
  return bars(daily.map(d => ({key: d.day, n: d.n})), 'n', d => d.slice(5));
}

function plChart(history, current) {
  const max = Math.max(1, ...history.flatMap(h => [h.incomeSar, h.expensesSar]));
  return `<div class="pl">${history.map(h => `<div class="m ${h.month === current ? 'on' : ''}" data-m="${h.month}" title="${monthName(h.month)}: ${T('دخل', 'income')} ${money(h.incomeSar)}، ${T('مصاريف', 'expenses')} ${money(h.expensesSar)}، ${T('صافي', 'net')} ${money(h.netSar)}">
      <div class="pair"><i class="in" style="height:${h.incomeSar / max * 100}%"></i><i class="out" style="height:${h.expensesSar / max * 100}%"></i></div>
      <small>${monthShort(h.month)}</small></div>`).join('')}</div>
    <div class="legend" style="margin-top:8px"><span><i style="background:var(--good)"></i>${T('الدخل الصافي', 'Net income')}</span><span><i style="background:var(--bad);opacity:.75"></i>${T('المصاريف', 'Expenses')}</span></div>`;
}

// التغيّر عن الفترة اللي قبل (بالنسبة)، الأخضر تحسّن. [lowerIsBetter] للمصاريف.
function delta(cur, prev, lowerIsBetter = false) {
  if (!prev) return cur ? `<span class="d pos">${T('جديد', 'new')}</span>` : '';
  const p = Math.round((cur - prev) / Math.abs(prev) * 100);
  if (!p) return `<span class="d">0%</span>`;
  const good = lowerIsBetter ? p < 0 : p > 0;
  return `<span class="d ${good ? 'pos' : 'neg'}">${p > 0 ? '▲ +' : '▼ '}${num(p)}%</span>`;
}

const periodLabel = (period, key) => period === 'day' ? dayName(key) : period === 'month' ? monthName(key) : key;

const views = {
  async home() {
    const s = await api('stats');
    const l = s.ledger;
    $('#app').innerHTML = heading(T('الرئيسية', 'Overview'), T('نظرة سريعة على ', 'Snapshot of ') + monthName(thisMonth())) + `
      <div class="grid">
        ${l ? kpi(T('صافي الربح هالشهر', 'Net profit this month'), signed(l.netSar), `${T('دخل', 'Income')} ${money(l.incomeSar)} · ${T('مصاريف', 'expenses')} ${money(l.expensesSar)}`, 'hero') : ''}
        ${kpi(T('المشتركين', 'Subscribers'), num(s.paying), `${planName('monthly')} ${num(s.plans.monthly)} · ${planName('yearly')} ${num(s.plans.yearly)} · ${T('محلات', 'shops')} ${num(s.plans.shop)}`)}
        ${kpi(T('المستخدمين', 'Users'), num(s.users), `${T('جدد اليوم', 'New today')} ${num(s.newToday)} · ${T('هالأسبوع', 'this week')} ${num(s.newWeek)}`)}
        ${kpi(T('خلصت مجانيتهم', 'Used up free scans'), num(s.outOfFree), T('ما اشتركوا للحين', 'not subscribed yet'))}
        ${kpi(T('فحوصات اليوم', 'Scans today'), num(s.scansToday), `${T('هالشهر', 'This month')} ${num(s.scansMonth)}`)}
        ${kpi(T('تكلفة الفحص', 'Cost per scan'), sar(s.costPerScanSar), `${T('متوسط', 'Average')} ${(s.avgSeconds || 0).toFixed(1)} ${T('ثانية', 's')}`)}
        ${kpi(T('الدخل الشهري المتكرر', 'Monthly recurring revenue'), sar(s.mrrSar), T('تقديري من المشتركين الحاليين', 'Estimated from current subscribers'))}
      </div>
      <div class="cols">
        <div class="card"><h3>${T('الفحوصات آخر 30 يوم', 'Scans, last 30 days')} <span class="k">${num(s.daily.reduce((t, d) => t + d.n, 0))}</span></h3>${dailyChart(s.daily)}</div>
        <div class="card"><h3>${T('أكثر الأنواع فحصًا هالشهر', 'Top species this month')}</h3>
          <table>${s.topSpecies.map(t => `<tr><td>${sp(t.id)}<div class="meter"><i style="width:${t.n / s.topSpecies[0].n * 100}%"></i></div></td><td class="num">${num(t.n)}</td></tr>`).join('') || `<tr><td class="msg">${T('ما فيه فحوصات للحين', 'No scans yet')}</td></tr>`}</table></div>
      </div>`;
  },

  // حالة الخادم وزيارات hawat.id ومن وين جوا وش ضغطوا (يعدّها الخادم من الصفحة نفسها).
  async site() {
    const r = await api('site');
    const st = r.status;
    const srcNames = {fb_ad: T('إعلان فيسبوك/إنستغرام', 'Facebook/Instagram ad'), facebook: T('فيسبوك', 'Facebook'), instagram: T('إنستغرام', 'Instagram'), google: 'Google', bing: 'Bing',
      tiktok: 'TikTok', snapchat: 'Snapchat', x: 'X', whatsapp: 'WhatsApp', telegram: 'Telegram', ksafish: T('الموسوعة', 'KSAFish'), direct: T('مباشر', 'Direct'), other: T('غيره', 'Other')};
    const clickNames = {download_button: T('زر حمّل التطبيق', 'Download button'), store: T('أزرار المتاجر', 'Store buttons'), play_testing: T('رابط تجربة أندرويد', 'Android testing link'),
      pricing_button: T('زر الأسعار', 'Pricing button'), facebook: T('أيقونة فيسبوك', 'Facebook icon'), instagram: T('أيقونة إنستغرام', 'Instagram icon'), x: T('أيقونة إكس', 'X icon'), notify_button: T('زر بلّغني', 'Notify-me button'), waitlist_signup: T('سجلوا في بلّغني', 'Waitlist signups'), ksafish: T('روابط الموسوعة', 'KSAFish links'), email: T('تواصل معنا', 'Contact us')};
    const dot = (ok, yes, no) => `<tr><td><span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:var(--${ok ? 'good' : 'bad'});margin-inline-end:8px"></span>${ok ? yes : no}</td></tr>`;
    const list = (m, names) => {
      const rows = Object.entries(m || {}).sort((a, b) => b[1] - a[1]);
      return `<table>${rows.map(([k, n]) => `<tr><td>${esc(names[k] || k)}<div class="meter"><i style="width:${n / rows[0][1] * 100}%"></i></div></td><td class="num">${num(n)}</td></tr>`).join('') || `<tr><td class="msg">${T('ما فيه شي للحين', 'Nothing yet')}</td></tr>`}</table>`;
    };
    const sum = m => Object.values(m || {}).reduce((a, b) => a + b, 0);
    $('#app').innerHTML = heading(T('الموقع والزوار', 'Website & status'), T('حالة الخادم، وزوار hawat.id ومن وين جوا ووش ضغطوا', 'Server status, and hawat.id visitors, where they came from and what they clicked')) + `
      <div class="cols">
        <div class="card"><h3>${T('الحالة الحين', 'Status now')}</h3><table>
          ${dot(st.server, T('الخادم والموقع شغالين', 'Server and website are up'), T('الخادم ما يرد', 'Server is down'))}
          ${dot(st.claude, T('فحص الأسماك شغال (مفتاح Claude موجود)', 'Fish scans are on (Claude key set)'), T('الفحوصات متوقفة: مفتاح Claude ناقص', 'Scans are off: Claude key missing'))}
          ${dot(st.telegram, T('إشعارات الجوال مربوطة', 'Phone notifications connected'), T('الإشعارات مو مربوطة: شغّل bash server/ntfy.sh', 'Notifications not connected: run bash server/ntfy.sh'))}
        </table></div>
        <div class="card"><h3>${T('آخر 7 أيام', 'Last 7 days')}</h3><div class="grid">
          ${kpi(T('زيارات', 'Visits'), num(r.week?.visits || 0), `${num(r.week?.unique || 0)} ${T('زائر', 'visitors')}`)}
          ${kpi(T('ضغطات', 'Clicks'), num(sum(r.week?.clicks)), `${T('اليوم', 'Today')} ${num(sum(r.today?.clicks))}`)}
        </div></div>
      </div>
      ${r.daily ? `<div class="grid" style="margin-top:14px">
        ${kpi(T('زيارات اليوم', 'Visits today'), num(r.today.visits), `${num(r.today.unique)} ${T('زائر مختلف', 'unique visitors')}`)}
        ${kpi(T('زيارات 30 يوم', 'Visits, 30 days'), num(r.month.visits), `${num(r.month.unique)} ${T('زائر', 'visitors')}`)}
        ${kpi(T('من الإعلان (30 يوم)', 'From the ad (30 days)'), num(r.month.src.fb_ad || 0), T('زيارات جت من إعلان فيسبوك/إنستغرام', 'Visits from the Facebook/Instagram ad'))}
        ${kpi(T('ضغطات 30 يوم', 'Clicks, 30 days'), num(sum(r.month.clicks)))}
      </div>
      <div class="card" style="margin-top:14px"><h3>${T('الزيارات آخر 30 يوم', 'Visits, last 30 days')}</h3>${bars(r.daily, 'visits', d => d.slice(5))}</div>
      <div class="cols" style="margin-top:14px">
        <div class="card"><h3>${T('من وين جوا (30 يوم)', 'Where they came from (30 days)')}</h3>${list(r.month.src, srcNames)}</div>
        <div class="card"><h3>${T('وش ضغطوا (30 يوم)', 'What they clicked (30 days)')}</h3>${list(r.month.clicks, clickNames)}</div>
      </div>` : ''}`;
  },

  // اللي سجلوا في hawat.id عشان نبلغهم وقت الإطلاق.
  async launch() {
    const r = await api('waitlist');
    const draw = r => {
      $('#app').innerHTML = heading(T('بلّغني بالإطلاق', 'Launch waitlist'), T('اللي سجلوا إيميلهم أو جوالهم في hawat.id، نرسل لهم رسالة «تم التدشين» وقت الإطلاق', 'People who left an email or phone on hawat.id, to get a launch message'),
        `<button class="act ghost noprint" id="wcsv">${T('تصدير Excel', 'Export to Excel')}</button>`) + `
        <div class="grid">
          ${kpi(T('المسجلين', 'Signed up'), num(r.count), `${T('إيميل', 'Email')} ${num(r.emails)} · ${T('جوال', 'Phone')} ${num(r.phones)}`, 'hero')}
          ${kpi(T('اليوم', 'Today'), num(r.today))}
          ${kpi(T('آخر 7 أيام', 'Last 7 days'), num(r.week))}
          ${kpi(T('يبغون يجربون قبل الناس', 'Early testers'), num(r.betaAndroid + r.betaIos), `${T('أندرويد', 'Android')} ${num(r.betaAndroid)} · ${T('آيفون', 'iPhone')} ${num(r.betaIos)}`)}
        </div>
        <div class="card" style="margin-top:14px"><table>
          <tr><th>${T('الإيميل أو الجوال', 'Email or phone')}</th><th>${T('تجربة مبكرة', 'Early test')}</th><th>${T('من وين', 'Source')}</th><th>${T('الوقت', 'When')}</th><th></th></tr>
          ${r.items.map(x => `<tr><td class="mono" dir="ltr">${esc(x.contact)}</td><td>${x.beta ? (x.os === 'ios' ? T('آيفون', 'iPhone') : T('أندرويد', 'Android')) : ''}</td><td>${esc(x.src || '')}</td><td>${when(x.at)}</td><td><button class="act ghost sm" data-wdel="${esc(x.id)}">${T('حذف', 'Delete')}</button></td></tr>`).join('') || `<tr><td class="msg" colspan="5">${T('ما فيه أحد للحين', 'Nobody yet')}</td></tr>`}
        </table></div>`;
      $('#wcsv').onclick = () => {
        const q = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
        const lines = [[T('الإيميل أو الجوال', 'Email or phone'), T('النوع', 'Type'), T('تجربة مبكرة', 'Early test'), T('الاسم', 'Name'), T('اللغة', 'Language'), T('من وين', 'Source'), T('الوقت', 'When')],
          ...r.items.map(x => [x.contact, x.kind, x.beta ? x.os : '', x.name, x.lang, x.src, x.at])];
        const a = document.createElement('a');
        a.href = URL.createObjectURL(new Blob(['﻿' + lines.map(l => l.map(q).join(',')).join('\r\n')], {type: 'text/csv;charset=utf-8'}));
        a.download = `fish-id-waitlist-${today()}.csv`;
        a.click();
      };
      document.querySelectorAll('[data-wdel]').forEach(b => b.onclick = async () => {
        if (!confirm(T('تحذف هذا التسجيل؟', 'Delete this signup?'))) return;
        draw(await post('waitlist', {delete: b.dataset.wdel}));
      });
    };
    draw(r);
  },

  // ملخص يوم أو شهر أو سنة، يصلح يُطبع ويُعطى للمستثمر.
  async report(period = 'month', key = '') {
    key ||= period === 'day' ? today() : period === 'month' ? thisMonth() : today().slice(0, 4);
    const r = await api(`report?period=${period}&key=${key}`);
    const p = r.previous;
    const prevName = {day: T('عن أمس', 'vs previous day'), month: T('عن الشهر اللي قبل', 'vs previous month'), year: T('عن السنة اللي قبل', 'vs previous year')}[period];
    const picker = period === 'day' ? `<input type="date" id="key" value="${key}" max="${today()}">`
      : period === 'month' ? `<input type="month" id="key" value="${key}" max="${thisMonth()}">`
      : `<input type="number" id="key" value="${key}" min="2025" max="${today().slice(0, 4)}" style="width:100px" dir="ltr">`;
    const label = period === 'year' ? monthShort : period === 'month' ? (k => k.slice(8)) : (k => k.slice(11) + ':00');
    $('#app').innerHTML = heading(T('ملخص ', 'Summary: ') + periodLabel(period, key), `${T('مقارنة', 'Compared')} ${prevName} (${periodLabel(period, r.previousKey)})`,
      `<div class="seg noprint" id="per">${['day', 'month', 'year'].map(x => `<button data-p="${x}" class="${x === period ? 'on' : ''}">${{day: T('يوم', 'Day'), month: T('شهر', 'Month'), year: T('سنة', 'Year')}[x]}</button>`).join('')}</div><span class="noprint">${picker}</span>`) + `
      <div class="grid">
        ${kpi(T('صافي الربح', 'Net profit'), signed(r.netSar), `${delta(r.netSar, p.netSar)} ${prevName}`, 'hero')}
        ${kpi(T('الدخل الصافي', 'Net income'), sar(r.incomeSar), `${delta(r.incomeSar, p.incomeSar)} · ${T('مبيعات المتجر', 'Store gross')} ${money(r.grossSar)}`)}
        ${kpi(T('المصاريف', 'Expenses'), sar(r.expensesSar), `${delta(r.expensesSar, p.expensesSar, true)} · Claude ${money(r.claudeSar)}`)}
        ${kpi(T('المشتركين الحين', 'Paying now'), num(Object.values(r.payingNow).reduce((t, n) => t + n, 0)), `${planName('monthly')} ${num(r.payingNow.monthly)} · ${planName('yearly')} ${num(r.payingNow.yearly)} · ${planName('shop')} ${num(r.payingNow.shop)}<br>${T('اشتراك جديد', 'New subs')} ${num(r.newSubs)} · ${T('تجديد', 'renewals')} ${num(r.renewals)}${r.refunds ? ` · ${T('استرجاع', 'refunds')} ${num(r.refunds)}` : ''}`)}
        ${kpi(T('المستخدمين', 'Users'), num(r.users), `${T('جدد', 'New')} ${num(r.newUsers)} ${delta(r.newUsers, p.newUsers)}`)}
        ${kpi(T('المستخدمين النشطين', 'Active users'), num(r.activeUsers), `${delta(r.activeUsers, p.activeUsers)} ${T('فحصوا مرة على الأقل', 'scanned at least once')}`)}
        ${kpi(T('الفحوصات', 'Scans'), num(r.scans), `${delta(r.scans, p.scans)} · ${T('متوسط', 'avg')} ${(r.avgSeconds || 0).toFixed(1)} ${T('ث', 's')}`)}
        ${kpi(T('متوسط ثقة التعرّف', 'Average ID confidence'), r.avgConfidence != null ? num(Math.round(r.avgConfidence)) + '%' : '—', T('من نتائج الفحص', 'from scan results'))}
      </div>
      <div class="cols">
        <div class="card"><h3>${T('الفحوصات', 'Scans')} <span class="k">${{day: T('بالساعة', 'by hour'), month: T('باليوم', 'by day'), year: T('بالشهر', 'by month')}[period]}</span></h3>${bars(r.series, 'scans', label)}</div>
        <div class="card"><h3>${T('المستخدمين الجدد', 'New users')}</h3>${bars(r.series, 'newUsers', label)}</div>
      </div>
      ${period === 'year' ? `<div class="card" style="margin-top:14px"><h3>${T('صافي الربح بالشهر', 'Net profit by month')} <span class="k">${RIYAL}</span></h3>${bars(r.series, 'netSar', label, money)}</div>` : ''}
      <div class="cols">
        <div class="card"><h3>${T('أكثر الأنواع فحصًا', 'Top species')}</h3>
          <table>${r.topSpecies.map(t => `<tr><td>${sp(t.id)}<div class="meter"><i style="width:${t.n / r.topSpecies[0].n * 100}%"></i></div></td><td class="num">${num(t.n)}</td></tr>`).join('') || `<tr><td class="msg">${T('ما فيه فحوصات بهالفترة', 'No scans in this period')}</td></tr>`}</table></div>
        <div class="card"><h3>${T('مقارنة بالفترة اللي قبل', 'Against the previous period')}</h3><table>
          <tr><th></th><th class="num">${esc(periodLabel(period, key))}</th><th class="num">${esc(periodLabel(period, r.previousKey))}</th></tr>
          ${[[T('الدخل الصافي', 'Net income'), 'incomeSar', money], [T('المصاريف', 'Expenses'), 'expensesSar', money], [T('صافي الربح', 'Net profit'), 'netSar', money],
             [T('مستخدمين جدد', 'New users'), 'newUsers', num], [T('نشطين', 'Active users'), 'activeUsers', num], [T('فحوصات', 'Scans'), 'scans', num], [T('اشتراكات جديدة', 'New subscriptions'), 'newSubs', num]]
            .map(([l, f, fmt]) => `<tr><td>${l}</td><td class="num"><b>${fmt(r[f])}</b></td><td class="num">${fmt(p[f])}</td></tr>`).join('')}
        </table></div>
      </div>
      <div class="note">${T('المبالغ بالريال بعد ضريبة المتجر وعمولته. ', 'Amounts in SAR after store VAT and commission. ')}${period === 'day' ? T('ملخص اليوم ما يوزّع المصاريف الشهرية على الأيام.', 'The daily summary does not spread monthly costs across days.') : ''} ${T('أُنشئ', 'Generated')} ${when(r.generated)}</div>`;
    docBuilder = () => reportDoc(r, period, key);
    $('#per').querySelectorAll('button').forEach(b => b.onclick = () => show('report', b.dataset.p));
    $('#key').onchange = e => e.target.value && show('report', period, e.target.value);
  },

  async money(month = thisMonth()) {
    const r = await api('ledger?month=' + month);
    $('#app').innerHTML = heading(T('المحاسبة', 'Accounting'), T('الدخل والمصاريف والصافي لكل شهر، بالريال السعودي', 'Monthly income, expenses and net, in Saudi riyals') + ' · ' + monthName(r.month),
      `<input type="month" id="mon" class="noprint" value="${r.month}"><button class="act ghost noprint" id="csv">${T('تصدير Excel', 'Export to Excel')}</button>`) + `
      <div class="grid">
        ${kpi(T('صافي الربح', 'Net profit'), signed(r.netSar), r.margin != null ? `${T('الهامش', 'Margin')} ${num(r.margin)}%` : monthName(r.month), 'hero')}
        ${kpi(T('الدخل الصافي', 'Net income'), sar(r.incomeSar), `${T('مبيعات المتجر', 'Store sales')} ${num(r.paidSales)}${r.sandboxSales ? ` · ${T('تجريبية', 'test')} ${num(r.sandboxSales)} (${T('ما تنحسب', 'not counted')})` : ''}`)}
        ${kpi(T('المصاريف', 'Expenses'), sar(r.expensesSar), `${num(r.expenses.length)} ${T('بند', 'items')}`)}
        ${kpi(T('ما يوصلك من المتجر', 'Paid out by the store'), sar(r.grossSar - r.storeTaxSar - r.storeFeeSar), `${T('من', 'of')} ${money(r.grossSar)}: ${T('ضريبة', 'VAT')} ${money(r.storeTaxSar)} · ${T('عمولة', 'fee')} ${money(r.storeFeeSar)}`)}
        ${kpi(T('تكلفة الفحص', 'Cost per scan'), sar(r.scans ? (r.expenses.find(e => e.auto && e.n)?.sar || 0) / r.scans : 0), `${num(r.scans)} ${T('فحص هالشهر', 'scans this month')}`)}
      </div>
      <div class="cols">
        <div class="card"><h3>${T('آخر 12 شهر', 'Last 12 months')} <span class="k noprint">${T('اضغط الشهر لعرضه', 'Click a month to open it')}</span></h3>${plChart(r.history, r.month)}</div>
        <div class="card"><h3>${T('المصاريف حسب المزوّد', 'Expenses by provider')}</h3>
          <table>${r.providers.map(p => `<tr><td>${esc(p.provider)}<div class="meter"><i style="width:${p.sar / r.providers[0].sar * 100}%"></i></div></td><td class="num">${money(p.sar)}</td></tr>`).join('') || `<tr><td class="msg">${T('ما فيه مصاريف هالشهر', 'No expenses this month')}</td></tr>`}</table></div>
      </div>
      <div class="card" style="margin-top:14px"><h3>${T('الدخل', 'Income')} · ${monthName(r.month)}</h3><div class="wrap"><table>
        <tr><th>${T('البند', 'Item')}</th><th>${T('المصدر', 'Source')}</th><th class="num">${T('العدد', 'Count')}</th><th class="num">${T('الإجمالي', 'Gross')}</th><th class="num">${T('الضريبة', 'VAT')}</th><th class="num">${T('عمولة المتجر', 'Store fee')}</th><th class="num">${T('الصافي', 'Net')}</th><th class="noprint"></th></tr>
        ${r.income.map(i => `<tr><td>${esc(i.auto ? productName(i.label) : i.label)} ${i.auto ? `<span class="pill auto">${T('تلقائي', 'auto')}</span>` : i.repeat !== 'once' ? `<span class="pill">${repeatName(i.repeat)}</span>` : ''}${i.note ? `<div class="k">${esc(i.note)}</div>` : ''}</td>
          <td>${esc(i.provider)}</td><td class="num">${i.auto ? num(i.n) + (i.refunds ? ` (−${num(i.refunds)})` : '') : ''}</td>
          <td class="num">${money(i.auto ? i.grossSar : i.sar)}</td><td class="num">${i.auto ? money(i.taxSar) : ''}</td><td class="num">${i.auto ? money(i.feeSar) : ''}</td>
          <td class="num"><b>${money(i.sar)}</b></td><td class="noprint">${rowActions(i)}</td></tr>`).join('') || `<tr><td colspan="8" class="msg">${T('ما فيه دخل مسجّل هالشهر', 'No income recorded this month')}</td></tr>`}
        <tfoot><tr><td colspan="6">${T('إجمالي الدخل الصافي', 'Total net income')}</td><td class="num">${money(r.incomeSar)}</td><td class="noprint"></td></tr></tfoot></table></div></div>
      <div class="card" style="margin-top:14px"><h3>${T('المصاريف', 'Expenses')} · ${monthName(r.month)}</h3><div class="wrap"><table>
        <tr><th>${T('البند', 'Item')}</th><th>${T('المزوّد', 'Provider')}</th><th>${T('التكرار', 'Repeats')}</th><th class="num">${T('المبلغ', 'Amount')}</th><th class="noprint"></th></tr>
        ${r.expenses.map(e => `<tr><td>${esc(e.auto ? T(e.label, autoLabel(e)) : e.label)} ${e.auto ? `<span class="pill auto">${T('تلقائي', 'auto')}</span>` : ''}${e.n ? `<div class="k">${num(e.n)} ${T('فحص', 'scans')}</div>` : ''}${e.note ? `<div class="k">${esc(e.note)}</div>` : ''}</td>
          <td>${esc(e.provider)}</td><td>${e.auto ? T('يُحسب من الاستخدام', 'Usage based') : repeatName(e.repeat)}${e.original ? `<div class="k mono">${esc(e.original)}</div>` : ''}</td>
          <td class="num"><b>${money(e.sar)}</b></td><td class="noprint">${rowActions(e)}</td></tr>`).join('') || `<tr><td colspan="5" class="msg">${T('ما فيه مصاريف مسجّلة هالشهر', 'No expenses recorded this month')}</td></tr>`}
        <tfoot><tr><td colspan="3">${T('إجمالي المصاريف', 'Total expenses')}</td><td class="num">${money(r.expensesSar)}</td><td class="noprint"></td></tr></tfoot></table></div></div>
      <div class="card noprint" style="margin-top:14px"><h3>${T('إضافة قيد', 'Add an entry')}</h3>
        <div class="form">
          <label>${T('النوع', 'Type')}<div class="seg" id="kind"><button data-k="expense" class="on">${T('مصروف', 'Expense')}</button><button data-k="income">${T('دخل', 'Income')}</button></div></label>
          <label>${T('المزوّد أو المصدر', 'Provider or source')}<input id="f-provider" list="provs"><datalist id="provs"></datalist></label>
          <label>${T('الوصف', 'Description')}<input id="f-label" placeholder="${T('مثل: اشتراك الخادم KVM 8', 'e.g. KVM 8 server plan')}"></label>
          <label>${T('المبلغ', 'Amount')}<input id="f-amount" type="number" min="0" step="0.01" dir="ltr"></label>
          <label>${T('العملة', 'Currency')}<select id="f-currency"><option value="SAR">${T('ريال', 'SAR')}</option><option value="USD">${T('دولار', 'USD')}</option></select></label>
          <label>${T('التاريخ', 'Date')}<input id="f-date" type="date" value="${r.month === thisMonth() ? today() : r.month + '-01'}"></label>
          <label>${T('التكرار', 'Repeats')}<select id="f-repeat">${['once', 'monthly', 'yearly'].map(x => `<option value="${x}">${repeatName(x)}</option>`).join('')}</select></label>
          <label>${T('ملاحظة', 'Note')}<input id="f-note" placeholder="${T('اختياري: رقم الفاتورة مثلًا', 'Optional, e.g. invoice number')}"></label>
          <div><button class="act gold" id="f-save" style="width:100%">${T('إضافة', 'Add')}</button></div>
        </div><div id="f-msg" class="err" style="margin-top:6px"></div>
        <div class="note">${T('الدخل من Google Play وتكلفة Claude تنحسب لحالها. أضف هنا الباقي: الخادم من Hostinger، الدومين، رسوم المطوّرين، التسويق، أي دخل من المحلات بالتحويل. المصروف المتكرر ينحسب كل شهر لين توقفه.',
          'Google Play income and Claude costs are recorded automatically. Add the rest here: the Hostinger server, domain, developer fees, marketing, shop bank transfers. A recurring expense counts every month until you stop it.')}</div>
      </div>`;
    $('#mon').onchange = e => e.target.value && show('money', e.target.value);
    $('#app').querySelectorAll('.pl .m').forEach(m => m.onclick = () => show('money', m.dataset.m));
    docBuilder = () => statementDoc(r);
    $('#csv').onclick = () => csv(r);
    let kind = 'expense';
    const fill = () => $('#provs').innerHTML = providers()[kind].map(p => `<option value="${esc(p)}">`).join('');
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
      else { b.dataset.sure = 1; b.textContent = T('متأكد؟ يحذف من كل الشهور', 'Sure? Removes it from every month'); }
    });
    $('#app').querySelectorAll('[data-stop]').forEach(b => b.onclick = async () => {
      const [y, m] = r.month.split('-').map(Number);
      const prev = new Date(Date.UTC(y, m - 2, 1)).toISOString().slice(0, 7);
      await post('ledger', {stop: b.dataset.stop, last: prev}); show('money', r.month);
    });
  },

  // رصيد Claude والفواتير الجاية، عشان ما يوقف التطبيق.
  async alerts() {
    const a = await api('alerts');
    alertCache = a;
    const b = a.balance;
    $('#app').innerHTML = heading(T('التنبيهات', 'Alerts'), T('رصيد Claude والفواتير الجاية، عشان ما يوقف التطبيق', 'Claude balance and upcoming bills, so the app never stops')) + `
      <div class="alerts">${a.alerts.map(x => `<div class="alert ${x.level}"><span>${alertText(x)}</span></div>`).join('') || `<div class="alert info" style="background:var(--good-soft);color:var(--good)">${T('كل شيء تمام، ما فيه تنبيهات.', 'All good, no alerts.')}</div>`}</div>
      <div class="grid">
        ${b ? kpi(T('رصيد Claude المتبقي (تقديري)', 'Claude balance left (est.)'), `<span class="${b.leftUsd <= 0 ? 'neg' : ''}">$${money(b.leftUsd)}</span>`, `${T('من', 'of')} $${money(b.usd)} ${T('سجلته', 'entered')} ${when(b.at)}`, 'hero') : ''}
        ${b ? kpi(T('الصرف اليومي', 'Daily spend'), '$' + money(b.perDayUsd), T('متوسط آخر 7 أيام', 'Average of the last 7 days')) : ''}
        ${b ? kpi(T('يكفي لـ', 'Lasts about'), b.daysLeft != null ? num(b.daysLeft) + ` <small>${T('يوم', 'days')}</small>` : '—', T('بنفس الاستخدام الحالي', 'at the current usage')) : ''}
      </div>
      <div class="cols">
        <div class="card"><h3>${T('الفواتير الجاية', 'Upcoming bills')}</h3><div class="wrap"><table>
          <tr><th>${T('التاريخ', 'Due')}</th><th>${T('البند', 'Item')}</th><th>${T('المزوّد', 'Provider')}</th><th class="num">${T('المبلغ', 'Amount')}</th></tr>
          ${a.upcoming.map(u => `<tr><td>${shortDay(u.due)}</td><td>${esc(u.label)} <span class="pill">${repeatName(u.repeat)}</span></td><td>${esc(u.provider)}</td><td class="num">${money(u.sar)}</td></tr>`).join('') || `<tr><td colspan="4" class="msg">${T('ما فيه مصاريف متكررة مسجّلة. أضفها من المحاسبة.', 'No recurring expenses yet. Add them under Accounting.')}</td></tr>`}
        </table></div></div>
        <div class="card noprint"><h3>${T('رصيد Claude', 'Claude balance')}</h3>
          <div class="k">${T('افتح console.anthropic.com ← Billing، وانسخ الرصيد هنا بعد كل شحن. نطرح منه تكلفة كل فحص ونحسب كم يوم باقي.', 'Open console.anthropic.com → Billing and enter the balance here after every top-up. Each scan’s cost is subtracted to estimate the days left.')}</div>
          <div class="row" style="margin-top:12px"><span dir="ltr">$</span><input id="bal" type="number" min="0" step="0.01" dir="ltr" style="width:140px" value="${b ? b.leftUsd : ''}"><button class="act gold" id="bal-save">${T('حفظ الرصيد', 'Save balance')}</button><span id="bal-msg" class="k"></span></div>
          <div class="note">${T('يطلع تنبيه لما يقل الرصيد عن 20% أو يكفي أقل من 7 أيام، ولما Claude يرفض الطلبات، وقبل كل فاتورة متكررة بأسبوع.', 'You get an alert when the balance falls under 20% or less than 7 days, when Claude refuses requests, and a week before every recurring bill.')}</div></div>
      </div>`;
    $('#bal-save').onclick = async () => {
      const v = parseFloat($('#bal').value);
      if (!(v >= 0)) return;
      await post('alerts', {balanceUsd: v});
      show('alerts');
    };
  },

  async users(st = {}) {
    // st: حالة الصفحة (العرض والبحث والفلاتر والصفحة)، تنحفظ مع التنقل عشان التحديث يرجع لنفس المكان.
    st = {view: 'all', q: '', plan: '', from: '', activity: '', page: 1, ...st};
    const qs = o => new URLSearchParams(Object.entries(o).filter(([, v]) => v !== '' && v != null)).toString();
    const r = await api('users?' + qs({view: st.view, q: st.q, plan: st.plan, from: st.from, activity: st.activity, page: st.page}));
    const again = (patch = {}) => show('users', {...st, ...patch});
    const sel = new Set();
    const ico = d => `<svg class="u-ico" viewBox="0 0 24 24">${d}</svg>`;
    const I = {
      gift: '<rect x="3" y="8" width="18" height="13"/><path d="M12 8v13M3 12h18M12 8c-2-4-6-4-6-1.5S10 8 12 8zm0 0c2-4 6-4 6-1.5S14 8 12 8z"/>',
      plan: '<path d="M4 7h13l-3-3M20 17H7l3 3"/>',
      block: '<circle cx="12" cy="12" r="9"/><path d="M6 6l12 12"/>',
      more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
      down: '<path d="M6 9l6 6 6-6"/>',
      plus: '<path d="M12 5v14M5 12h14"/>',
      search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
      clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
      refresh: '<path d="M20 12a8 8 0 1 1-2.3-5.6M20 4v4h-4"/>',
      export: '<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>',
      user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4-6 8-6s7 2 8 6"/>',
      x: '<path d="M6 6l12 12M18 6L6 18"/>',
    };
    const stName = k => ({active: T('نشط', 'Active'), soon: T('ينتهي قريب', 'Ending soon'), free: T('مجاني', 'Free'), empty: T('خلص رصيده', 'Out of scans'), blocked: T('موقوف', 'Blocked')})[k] || k;
    const fromName = k => ({store: T('المتجر', 'Store'), manual: T('يدوي من الأدمن', 'Set by admin'), code: T('رمز هدية', 'Gift code')})[k] || '';
    const ago = s => {
      if (!s) return T('ما فحص', 'Never');
      const h = (Date.now() - new Date(s)) / 36e5;
      return h < 1 ? T('قبل دقائق', 'Minutes ago') : h < 24 ? T(`قبل <span class="u-num">${Math.round(h)}</span> ساعة`, `<span class="u-num">${Math.round(h)}</span>h ago`) : T(`قبل <span class="u-num">${Math.round(h / 24)}</span> يوم`, `<span class="u-num">${Math.round(h / 24)}</span>d ago`);
    };
    const date = s => s ? `<span class="u-num">${s.slice(0, 10)}</span>` : '—';
    const viewsList = [['all', T('الكل', 'All')], ['paid', T('المشتركين', 'Subscribers')], ['free', T('المجاني', 'Free')], ['soon', T('ينتهي قريب', 'Ending soon')], ['blocked', T('الموقوفين', 'Blocked')]];
    const filters = {
      plan: [T('الباقة', 'Plan'), [['free', planName('free')], ['monthly', planName('monthly')], ['yearly', planName('yearly')], ['shop', planName('shop')]]],
      from: [T('المصدر', 'Source'), [['store', fromName('store')], ['manual', fromName('manual')], ['code', fromName('code')]]],
      activity: [T('آخر نشاط', 'Last activity'), [['24', T('آخر 24 ساعة', 'Last 24 hours')], ['168', T('آخر أسبوع', 'Last week')], ['none', T('ما فحص أبد', 'Never scanned')]]],
    };
    // قوائم الإجراءات (هدية، باقة، إيقاف) نفسها للسطر وللتحديد الجماعي.
    const giftMenu = () => `<div class="u-menu end" role="menu">${[5, 10, 25, 50].map(n => `<button data-gift="${n}">${T('أهدِ', 'Gift')} <span class="u-num">${n}</span> ${T('فحوصات', 'scans')}</button>`).join('')}
      <div class="row"><input type="number" min="1" max="1000" data-n placeholder="${T('عدد', 'Count')}" aria-label="${T('عدد الفحوصات', 'Scans')}"><button class="act sm" data-gift-n>${T('أهدِ', 'Gift')}</button></div></div>`;
    const planMenu = () => `<div class="u-menu end" role="menu">
      <button data-extend="31">${T('تمديد الباقة شهر', 'Extend by a month')}</button>
      <button data-plan="monthly:31">${planName('monthly')} · <span class="u-num">31</span> ${T('يوم', 'days')}</button>
      <button data-plan="yearly:366">${planName('yearly')} · <span class="u-num">366</span> ${T('يوم', 'days')}</button>
      <button data-plan="shop:31">${planName('shop')} · <span class="u-num">31</span> ${T('يوم', 'days')}</button>
      <button data-plan="free:0" class="danger">${T('رجّعه مجاني', 'Back to free')}</button></div>`;
    const blockMenu = blocked => `<div class="u-menu end" role="menu"><button data-block="${!blocked}" class="${blocked ? '' : 'danger'}">${blocked ? T('أكّد التفعيل', 'Confirm unblock') : T('أكّد الإيقاف', 'Confirm block')}</button></div>`;
    const menuBody = (b, blocked) => b === 'gift' ? giftMenu() : b === 'plan' ? planMenu() : blockMenu(blocked);
    const act = async (ids, body) => {
      if (ids.length === 1) await post('users/' + ids[0], body);
      else await post('users', {ids, ...body});
    };
    // يربط أزرار القائمة المفتوحة بالإجراء، وبعدها يحدّث الصفحة (أو الدرج).
    const wireMenu = (menu, ids, done) => {
      menu.onclick = e => e.stopPropagation();
      menu.querySelectorAll('[data-gift]').forEach(b => b.onclick = async () => { await act(ids, {grant: +b.dataset.gift}); done(); });
      menu.querySelector('[data-gift-n]')?.addEventListener('click', async () => { const n = parseInt(menu.querySelector('[data-n]').value, 10); if (n > 0) { await act(ids, {grant: n}); done(); } });
      menu.querySelectorAll('[data-extend]').forEach(b => b.onclick = async () => { await act(ids, {extend: +b.dataset.extend}); done(); });
      menu.querySelectorAll('[data-plan]').forEach(b => b.onclick = async () => { const [plan, days] = b.dataset.plan.split(':'); await act(ids, {plan, days: +days}); done(); });
      menu.querySelectorAll('[data-block]').forEach(b => b.onclick = async () => { await act(ids, {blocked: b.dataset.block === 'true'}); done(); });
    };
    const closeMenus = () => document.querySelectorAll('.u-menu').forEach(m => m.remove());
    const openMenu = (pop, html, ids, done) => {
      const had = pop.querySelector('.u-menu');
      closeMenus();
      if (had) return;
      pop.insertAdjacentHTML('beforeend', html);
      wireMenu(pop.querySelector('.u-menu'), ids, done);
    };
    document.onclick = closeMenus;

    const c = r.counts, pages = Math.max(1, Math.ceil(r.total / r.size));
    const kpis = [['all', T('كل الحسابات', 'All accounts'), c.all, `<span class="pos u-num">+${num(r.newWeek)}</span> ${T('هذا الأسبوع', 'this week')}`],
      ['paid', T('مشتركين نشطين', 'Active subscribers'), c.paid, T('شهري، سنوي، ومحلات', 'Monthly, yearly and shops')],
      ['soon', T('ينتهي خلال 7 أيام', 'Ending within 7 days'), c.soon, T('يحتاجون متابعة', 'Need a follow-up')],
      ['blocked', T('موقوفين', 'Blocked'), c.blocked, T('إساءة استخدام أو احتيال', 'Abuse or fraud')]];
    const hasFilter = st.q || st.plan || st.from || st.activity;
    $('#app').innerHTML = `<div class="top u-head"><div><h1>${T('المستخدمين', 'Users')}</h1><div class="sub">${T('كل حسابات التطبيق، باقاتهم، ورصيد فحوصاتهم', 'Every app account, its plan and scans left')}${hasFilter ? T(' (مع الفلتر)', ' (filtered)') : ''}</div></div>
      <div class="row noprint"><button class="act ghost" id="u-export">${ico(I.export)} ${T('تصدير Excel', 'Export to Excel')}</button>${printBtn()}</div></div>
      <div class="u-kpis">${kpis.map(([v, t, n, d]) => `<button data-v="${v}" class="${st.view === v ? 'on' : ''}"><span class="k">${t}</span><span class="v">${num(n)}</span><span class="d">${d}</span></button>`).join('')}</div>
      ${c.soon && st.view !== 'soon' ? `<div class="u-banner"><span class="ic">${ico(I.clock)}</span><div><b>${T(`<span class="u-num">${num(c.soon)}</span> اشتراكات تنتهي خلال <span class="u-num">7</span> أيام`, `<span class="u-num">${num(c.soon)}</span> subscriptions end within <span class="u-num">7</span> days`)}</b><span>${T('تقدر تهديهم فحوصات أو تمدد الباقة قبل ما تنتهي.', 'You can gift scans or extend the plan before it ends.')}</span></div><button class="act" data-v="soon">${T('اعرضهم', 'Show them')}</button></div>` : ''}
      <div class="u-views" role="tablist">${viewsList.map(([k, t]) => `<button role="tab" aria-selected="${st.view === k}" class="${st.view === k ? 'on' : ''}" data-v="${k}">${t}<span class="c">${num(c[k])}</span></button>`).join('')}</div>
      <div class="u-tools">
        <label class="u-search">${ico(I.search)}<input id="u-q" value="${esc(st.q)}" placeholder="${T('ابحث برقم الحساب', 'Search by account id')}" aria-label="${T('بحث', 'Search')}"></label>
        ${Object.entries(filters).map(([k, [label, opts]]) => {
          const v = st[k], name = v ? opts.find(o => o[0] === v)?.[1] : '';
          return `<span class="u-pop"><button class="u-chip ${v ? 'set' : ''}" data-f="${k}" aria-haspopup="true">${label}${v ? `: ${name}` : ''}${ico(I.down)}</button></span>`;
        }).join('')}
        ${hasFilter ? `<button class="u-chip" id="u-clear">${T('مسح الفلاتر', 'Clear filters')}</button>` : ''}
        <div class="end"><button class="u-icobtn" id="u-refresh" title="${T('تحديث', 'Refresh')}" aria-label="${T('تحديث', 'Refresh')}">${ico(I.refresh)}</button></div>
      </div>
      <div class="u-bulk" id="u-bulk" hidden><b><span class="u-num" id="u-seln">0</span> ${T('محدد', 'selected')}</b>
        <span class="u-pop"><button class="act ghost sm" data-bulk="gift">${T('إهداء فحوصات', 'Gift scans')}</button></span>
        <span class="u-pop"><button class="act ghost sm" data-bulk="plan">${T('تغيير الباقة', 'Change plan')}</button></span>
        <span class="u-pop"><button class="act ghost sm" data-bulk="block">${T('إيقاف', 'Block')}</button></span>
        <button class="x" id="u-unsel" aria-label="${T('إلغاء التحديد', 'Clear selection')}">✕</button></div>
      <div class="u-table"><table><thead><tr><th class="u-check" style="width:36px"><input type="checkbox" id="u-all" aria-label="${T('تحديد الكل', 'Select all')}"></th>
        <th>${T('الحساب', 'Account')}</th><th>${T('الباقة', 'Plan')}</th><th>${T('الحالة', 'Status')}</th><th>${T('المصدر', 'Source')}</th><th class="num">${T('الرصيد المتبقي', 'Scans left')}</th><th class="num">${T('الفحوصات', 'Scans')}</th><th>${T('آخر فحص', 'Last scan')}</th><th class="noprint"></th></tr></thead>
      <tbody>${r.items.map(u => {
        const pct = Math.max(0, Math.min(100, Math.round(u.remaining / Math.max(1, u.cap) * 100)));
        return `<tr data-id="${esc(u.id)}" tabindex="0">
        <td class="u-check"><input type="checkbox" data-c aria-label="${T('تحديد', 'Select')}"></td>
        <td><span class="u-id">${esc(u.id.slice(0, 14))}…</span><span class="u-sub">${T('انضم', 'Joined')} ${ago(u.created)}</span></td>
        <td><span class="pill ${u.active ? 'pay' : ''}">${planName(u.active ? u.plan : 'free')}</span>${u.active ? `<span class="u-sub">${T('لين', 'until')} ${date(u.until)}</span>` : ''}</td>
        <td><span class="u-st ${u.status}">${stName(u.status)}</span></td>
        <td>${u.from ? `<span class="pill ${u.from === 'store' ? 'auto' : ''}">${fromName(u.from)}</span>` : '<span class="u-sub">—</span>'}</td>
        <td class="num"><span class="u-num">${num(u.remaining)}</span>${u.bonus ? ` <span class="u-sub" style="display:inline">(${T('منها', 'incl.')} <span class="u-num">${num(u.bonus)}</span> ${T('هدية', 'gift')})</span>` : ''}<span class="u-bar"><i class="${pct < 20 ? 'low' : ''}" style="width:${pct}%"></i></span></td>
        <td class="num">${num(u.scans)}</td>
        <td>${ago(u.lastScan)}</td>
        <td class="noprint"><div class="u-acts">
          <span class="u-pop"><button data-m="gift" title="${T('إهداء فحوصات', 'Gift scans')}" aria-label="${T('إهداء فحوصات', 'Gift scans')}">${ico(I.gift)}</button></span>
          <span class="u-pop"><button data-m="plan" title="${T('تغيير الباقة', 'Change plan')}" aria-label="${T('تغيير الباقة', 'Change plan')}">${ico(I.plan)}</button></span>
          <span class="u-pop"><button data-m="block" title="${u.blocked ? T('تفعيل', 'Unblock') : T('إيقاف', 'Block')}" aria-label="${u.blocked ? T('تفعيل', 'Unblock') : T('إيقاف', 'Block')}">${ico(I.block)}</button></span>
          <span class="u-pop"><button data-open title="${T('التفاصيل', 'Details')}" aria-label="${T('التفاصيل', 'Details')}">${ico(I.more)}</button></span>
        </div></td></tr>`;
      }).join('') || `<tr><td colspan="9" class="msg">${T('ما فيه حسابات تطابق الفلتر', 'No accounts match these filters')}</td></tr>`}</tbody></table></div>
      <div class="u-foot"><span>${T('يعرض', 'Showing')} <span class="u-num">${num(r.items.length)}</span> ${T('من', 'of')} <span class="u-num">${num(r.total)}</span> ${T('حساب', 'accounts')}${pages > 1 ? ` · ${T('صفحة', 'page')} <span class="u-num">${r.page}/${pages}</span>` : ''}</span>
        <div class="row noprint"><button class="act ghost sm" id="u-prev" ${r.page <= 1 ? 'disabled' : ''}>${T('السابق', 'Previous')}</button><button class="act ghost sm" id="u-next" ${r.page >= pages ? 'disabled' : ''}>${T('التالي', 'Next')}</button></div></div>`;

    $('#app').querySelectorAll('[data-v]').forEach(b => b.onclick = () => again({view: b.dataset.v, page: 1}));
    const search = () => again({q: $('#u-q').value.trim(), page: 1});
    $('#u-q').onkeydown = e => { if (e.key === 'Enter') search(); };
    $('#u-q').onchange = search;
    $('#u-refresh').onclick = () => again();
    $('#u-clear')?.addEventListener('click', () => again({q: '', plan: '', from: '', activity: '', page: 1}));
    $('#u-prev').onclick = () => again({page: r.page - 1});
    $('#u-next').onclick = () => again({page: r.page + 1});
    $('#app').querySelectorAll('[data-f]').forEach(b => b.onclick = e => {
      e.stopPropagation();
      const k = b.dataset.f, pop = b.parentElement, had = pop.querySelector('.u-menu');
      closeMenus();
      if (had) return;
      pop.insertAdjacentHTML('beforeend', `<div class="u-menu" role="menu">${filters[k][1].map(([o, l]) => `<button role="menuitemradio" aria-checked="${st[k] === o}" data-o="${o}">${l}</button>`).join('')}${st[k] ? `<button data-o="">${T('مسح الفلتر', 'Clear filter')}</button>` : ''}</div>`);
      pop.querySelectorAll('[data-o]').forEach(o => o.onclick = () => again({[k]: o.dataset.o, page: 1}));
    });

    const syncSel = () => {
      $('#u-bulk').hidden = !sel.size;
      $('#u-seln').textContent = num(sel.size);
      $('#u-all').checked = r.items.length > 0 && sel.size === r.items.length;
      $('#app').querySelectorAll('tr[data-id]').forEach(tr => tr.classList.toggle('sel', sel.has(tr.dataset.id)));
    };
    $('#u-all').onchange = e => {
      $('#app').querySelectorAll('tr[data-id] [data-c]').forEach(c => { c.checked = e.target.checked; });
      r.items.forEach(u => e.target.checked ? sel.add(u.id) : sel.delete(u.id));
      syncSel();
    };
    $('#u-unsel').onclick = () => { sel.clear(); $('#app').querySelectorAll('[data-c]').forEach(c => { c.checked = false; }); syncSel(); };
    $('#app').querySelectorAll('[data-bulk]').forEach(b => b.onclick = e => { e.stopPropagation(); openMenu(b.parentElement, menuBody(b.dataset.bulk, false), [...sel], () => again()); });
    $('#app').querySelectorAll('tr[data-id]').forEach(tr => {
      const id = tr.dataset.id, u = r.items.find(x => x.id === id);
      tr.onclick = e => { if (!e.target.closest('[data-c],.u-acts')) userDrawer(id, again); };
      tr.onkeydown = e => { if (e.key === 'Enter' && e.target === tr) userDrawer(id, again); };
      tr.querySelector('[data-c]').onchange = e => { e.target.checked ? sel.add(id) : sel.delete(id); syncSel(); };
      tr.querySelectorAll('[data-m]').forEach(b => b.onclick = e => { e.stopPropagation(); openMenu(b.parentElement, menuBody(b.dataset.m, u.blocked), [id], () => again()); });
      tr.querySelector('[data-open]').onclick = e => { e.stopPropagation(); userDrawer(id, again); };
    });

    // التصدير: كل الحسابات اللي تطابق الفلتر الحالي (كل الصفحات) في ملف CSV يفتح في Excel.
    $('#u-export').onclick = async () => {
      const all = [];
      for (let p = 1; ; p++) {
        const x = await api('users?' + qs({view: st.view, q: st.q, plan: st.plan, from: st.from, activity: st.activity, page: p}));
        all.push(...x.items);
        if (p * x.size >= x.total) break;
      }
      const head = [T('الحساب', 'Account'), T('الباقة', 'Plan'), T('الحالة', 'Status'), T('المصدر', 'Source'), T('لين', 'Until'), T('الرصيد المتبقي', 'Scans left'), T('هدية', 'Gift'), T('الفحوصات', 'Scans'), T('آخر فحص', 'Last scan'), T('انضم', 'Joined')];
      const cell = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
      const rows = all.map(u => [u.id, planName(u.active ? u.plan : 'free'), stName(u.status), fromName(u.from), u.active ? (u.until || '').slice(0, 10) : '', u.remaining, u.bonus || 0, u.scans || 0, (u.lastScan || '').slice(0, 16).replace('T', ' '), (u.created || '').slice(0, 10)]);
      const blob = new Blob(['﻿' + [head, ...rows].map(x => x.map(cell).join(',')).join('\r\n')], {type: 'text/csv;charset=utf-8'});
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `fish-id-users-${today()}.csv`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    };

    // درج تفاصيل الحساب. كل تبويب جديد بالمستقبل ينضاف هنا: سطر في tabs ودالة في body.
    const userDrawer = async (id, refresh) => {
      const d = await api('users/' + encodeURIComponent(id));
      let tab = 'over';
      const tabs = [['over', T('نظرة عامة', 'Overview')], ['scans', T('الفحوصات', 'Scans')], ['pay', T('الاشتراك', 'Subscription')], ['log', T('السجل', 'History')], ['notes', T('ملاحظات', 'Notes'), true], ['devices', T('الأجهزة', 'Devices'), true]];
      const logText = l => [
        l.grant != null ? T(`أهدى <span class="u-num">${num(l.grant)}</span> فحوصات`, `Gifted <span class="u-num">${num(l.grant)}</span> scans`) : '',
        l.plan ? T(`غيّر الباقة إلى ${planName(l.plan)}`, `Set plan to ${planName(l.plan)}`) + (l.until && l.plan !== 'free' ? ` ${T('لين', 'until')} ${date(l.until)}` : '') : '',
        l.blocked != null ? (l.blocked ? T('أوقف الحساب', 'Blocked the account') : T('فعّل الحساب', 'Unblocked the account')) : '',
      ].filter(Boolean).join('، ');
      const sec = (title, body) => `<div class="sect"><h4>${title}</h4>${body}</div>`;
      const empty = (title, text) => `<div class="soonbox"><b>${title}</b>${text}</div>`;
      const body = {
        over: () => `<div class="facts">
            <div><span>${T('الرصيد المتبقي', 'Scans left')}</span><b>${num(d.remaining)}</b></div>
            <div><span>${T('مجموع الفحوصات', 'Total scans')}</span><b>${num(d.scans)}</b></div>
            <div><span>${T('انضم', 'Joined')}</span><b>${(d.created || '').slice(0, 10) || '—'}</b></div>
            <div><span>${d.active ? T('الباقة لين', 'Plan until') : T('آخر فحص', 'Last scan')}</span><b>${d.active ? (d.until || '').slice(0, 10) : (d.lastScan || '').slice(0, 10) || '—'}</b></div></div>
          ${sec(T('إجراءات سريعة', 'Quick actions'), `<div class="row">
            <span class="u-pop"><button class="act sm" data-m="gift">${T('إهداء فحوصات', 'Gift scans')}</button></span>
            <span class="u-pop"><button class="act ghost sm" data-m="plan">${T('الباقة والتمديد', 'Plan & extend')}</button></span>
            <span class="u-pop"><button class="act ghost sm" data-m="block" style="color:var(--bad)">${d.blocked ? T('تفعيل الحساب', 'Unblock') : T('إيقاف الحساب', 'Block')}</button></span></div>`)}
          ${sec(T('آخر النشاط', 'Recent activity'), `<ul class="tl">
            ${d.recent[0] ? `<li><div>${T('فحص', 'Scanned')} ${d.recent[0].species ? sp(d.recent[0].species) : T('بدون نوع', 'no species')}${d.recent[0].confidence != null ? ` · <span class="u-num">${d.recent[0].confidence}%</span>` : ''}<time>${when(d.recent[0].at)}</time></div></li>` : ''}
            ${d.log[0] ? `<li><div>${esc(d.log[0].by)}: ${logText(d.log[0])}<time>${when(d.log[0].at)}</time></div></li>` : ''}
            ${(d.codes || []).map(code => `<li><div>${T('استخدم رمز الهدية', 'Redeemed gift code')} <span class="u-id">${esc(code)}</span></div></li>`).join('')}
            <li><div>${T('أنشأ الحساب', 'Account created')}<time>${when(d.created)}</time></div></li></ul>`)}`,
        scans: () => d.recent.length ? sec(T('آخر الفحوصات (آخر 3 شهور)', 'Latest scans (last 3 months)'), `<ul class="tl">${d.recent.map(x => `<li><div>${x.species ? sp(x.species) : T('بدون نوع', 'No species')}${x.confidence != null ? ` · ${T('ثقة', 'confidence')} <span class="u-num">${x.confidence}%</span>` : ''} · <span class="u-num">${x.photos}</span> ${T('صور', 'photos')}<time>${when(x.at)}</time></div></li>`).join('')}</ul>`) : empty(T('ما فيه فحوصات', 'No scans'), T('هذا الحساب ما فحص شي في آخر 3 شهور.', 'This account has no scans in the last 3 months.')),
        pay: () => d.active ? sec(T('الاشتراك الحالي', 'Current subscription'), `<ul class="tl"><li><div>${planName(d.plan)} · ${fromName(d.from)}<time>${T('ينتهي', 'Ends')} ${when(d.until)}</time></div></li></ul>
            <div class="k" style="margin-top:10px">${d.from === 'store' ? T('الاشتراك من المتجر يتجدد تلقائيًا من RevenueCat، والمبالغ في المحاسبة.', 'Store subscriptions renew automatically through RevenueCat; amounts are under Accounting.') : T('هذه الباقة أعطاها الأدمن يدويًا وما تتجدد لحالها.', 'This plan was set by an admin and does not renew by itself.')}</div>`) : empty(T('ما عنده اشتراك', 'No subscription'), T('هذا الحساب على الباقة المجانية.', 'This account is on the free plan.')),
        log: () => d.log.length ? sec(T('تعديلات الأدمن', 'Admin changes'), `<ul class="tl">${d.log.map(l => `<li><div>${esc(l.by)}: ${logText(l)}<time>${when(l.at)}</time></div></li>`).join('')}</ul>`) : empty(T('ما فيه تعديلات', 'No changes yet'), T('أي هدية أو تغيير باقة أو إيقاف من اللوحة ينكتب هنا.', 'Gifts, plan changes and blocks made here are listed in this tab.')),
        notes: () => empty(T('ملاحظات الفريق', 'Team notes'), T('قريبًا: مكان تكتبون فيه ملاحظة عن الحساب، مثل محل تواصل معكم أو شكوى.', 'Coming soon: notes about the account, such as a shop that contacted you or a complaint.')),
        devices: () => empty(T('الأجهزة والنسخة', 'Devices & app version'), T('قريبًا: نوع الجوال ونسخة التطبيق لكل حساب، يساعد في حل المشاكل.', 'Coming soon: phone model and app version per account, to help with support.')),
      };
      const close = () => { $('#drawer').hidden = $('#scrim').hidden = true; document.removeEventListener('keydown', esc_); };
      const esc_ = e => { if (e.key === 'Escape') close(); };
      const paint = () => {
        $('#drawer').innerHTML = `<div class="dh"><span class="avatar">${ico(I.user)}</span><div><h2>${esc(d.id)}</h2><div class="row" style="margin-top:6px"><span class="pill ${d.active ? 'pay' : ''}">${planName(d.active ? d.plan : 'free')}</span><span class="u-st ${d.status}">${stName(d.status)}</span></div></div>
          <button class="x" id="d-close" aria-label="${T('إغلاق', 'Close')}">${ico(I.x)}</button></div>
          <div class="dtabs" role="tablist">${tabs.map(([k, t, soon]) => `<button role="tab" aria-selected="${tab === k}" class="${tab === k ? 'on' : ''}" data-t="${k}">${t}${soon ? `<span class="soon">${T('قريبًا', 'Soon')}</span>` : ''}</button>`).join('')}</div>
          <div class="dbody">${body[tab]()}</div>`;
        $('#d-close').onclick = close;
        $('#drawer').querySelectorAll('[data-t]').forEach(b => b.onclick = () => { tab = b.dataset.t; paint(); });
        $('#drawer').querySelectorAll('[data-m]').forEach(b => b.onclick = e => {
          e.stopPropagation();
          openMenu(b.parentElement, menuBody(b.dataset.m, d.blocked).replace('u-menu end', 'u-menu'), [d.id], async () => { close(); await refresh(); userDrawer(id, refresh); });
        });
      };
      paint();
      $('#drawer').hidden = $('#scrim').hidden = false;
      $('#scrim').onclick = close;
      document.addEventListener('keydown', esc_);
      $('#d-close').focus();
    };
  },

  async scans() {
    const list = await api('scans');
    $('#app').innerHTML = heading(T('الفحوصات', 'Scans'), `${T('آخر', 'Latest')} ${num(list.length)}`) + `
      <div class="card"><div class="wrap"><table><tr><th>${T('الوقت', 'Time')}</th><th>${T('النوع', 'Species')}</th><th class="num">${T('الثقة', 'Confidence')}</th><th class="num">${T('الصور', 'Photos')}</th><th class="num">${T('المدة', 'Time')}</th><th class="num">${T('التكلفة', 'Cost')}</th><th>${T('الحساب', 'Account')}</th></tr>
      ${list.map(s => `<tr><td>${when(s.at)}</td><td>${s.species ? sp(s.species) : `<span class="k">${T('بدون نوع', 'No species')}</span>`}</td>
        <td class="num">${s.confidence != null ? s.confidence + '%' : ''}</td><td class="num">${s.photos}</td><td class="num">${(s.ms / 1000).toFixed(1)} ${T('ث', 's')}</td>
        <td class="num">${money((s.usd || 0) * 3.75)}</td><td class="mono">${esc((s.user || T('قديم', 'legacy')).slice(0, 8))}</td></tr>`).join('') || `<tr><td colspan="7" class="msg">${T('ما فيه فحوصات للحين', 'No scans yet')}</td></tr>`}
      </table></div></div>`;
  },

  async contrib(status = 'new') {
    const list = await api('contrib?status=' + status);
    const st = {new: T('جديدة', 'New'), approved: T('مقبولة', 'Approved'), rejected: T('مرفوضة', 'Rejected')};
    $('#app').innerHTML = heading(T('صور المساهمين', 'Contributed photos'), `${num(list.length)} ${T('مساهمة', 'contributions')}`,
      `<div class="seg noprint">${Object.entries(st).map(([k, v]) => `<button data-st="${k}" class="${k === status ? 'on' : ''}">${v}</button>`).join('')}</div>`) + `
      <div class="photos">${list.map(c => `<div class="card" data-day="${esc(c.day)}" data-id="${esc(c.id)}">
        <div class="thumbs">${c.files.map(f => `<img alt="" data-src="contrib/${esc(c.day)}/${esc(c.id)}/${esc(f)}">`).join('')}</div>
        <div><b>${c.species ? sp(c.species) : T('بدون نوع', 'No species')}</b> ${c.species_confirmed ? `<span class="pill ok">${T('أكّده المستخدم', 'user confirmed')}</span>` : ''}</div>
        <div class="k">${c.days_since_catch >= 0 ? `${num(c.days_since_catch)} ${T('يوم من الصيد', 'days since catch')}` : T('الأيام غير معروفة', 'days unknown')} · ${esc(storageName(c.storage))} · ${when(c.at)}</div>
        <div class="k">${T('التطبيق توقع', 'App predicted')}: ${(c.predicted || []).map(sp).join(', ') || '—'}</div>
        <div class="row noprint" style="margin-top:10px"><button class="act sm" data-r="approved">${T('قبول', 'Approve')}</button><button class="act ghost sm" data-r="rejected">${T('رفض', 'Reject')}</button>
          <input data-fix placeholder="${T('تصحيح النوع (4 أرقام)', 'Fix species (4 digits)')}" inputmode="numeric" style="width:150px"></div></div>`).join('') || `<div class="card msg">${T('ما فيه مساهمات هنا', 'Nothing here')}</div>`}</div>`;
    $('#app').querySelectorAll('[data-st]').forEach(b => b.onclick = () => show('contrib', b.dataset.st));
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
      ['freeScans', T('الفحوصات المجانية لكل حساب (مرة وحدة)', 'Free scans per account (one time)')],
      ['monthlyCap', T('سقف الفحوصات بالشهر للشهري والسنوي', 'Monthly scan cap, monthly and yearly plans')],
      ['shopCap', T('سقف الفحوصات بالشهر للمحلات', 'Monthly scan cap, shops')],
      ['priceMonthly', T(`سعر الشهري (${RIYAL})`, `Monthly price (${RIYAL})`)],
      ['priceYearly', T(`سعر السنوي (${RIYAL})`, `Yearly price (${RIYAL})`)],
      ['priceShop', T(`سعر باقة المحل بالشهر (${RIYAL})`, `Shop plan per month (${RIYAL})`)],
      ['netShare', T('نسبة الصافي التقديرية بعد العمولة والضريبة (0.74 = 74%)', 'Estimated net share after fees and VAT (0.74 = 74%)')],
      ['usdToSar', T('سعر الدولار بالريال', 'USD to SAR rate')],
    ];
    $('#app').innerHTML = heading(T('الباقات والأسعار', 'Plans & prices'), T('السقف والأسعار المستخدمة في الحسبة', 'Caps and prices used in the calculations')) + `<div class="card" style="max-width:680px">
      ${rows.map(([k, l]) => `<label class="set"><span>${l}</span><input data-k="${k}" type="number" step="any" min="0" value="${esc(s[k])}"></label>`).join('')}
      <label class="set"><span>${T('إلزام رقم الحساب (التطبيقات القديمة توقف وتطلب التحديث)', 'Require an account id (old app versions stop and ask to update)')}</span><input data-b="requireAccount" type="checkbox" ${s.requireAccount ? 'checked' : ''} style="width:auto"></label>
      <div class="note">${T('أسعار المتجر نفسها تتغير من Google Play Console و App Store Connect. هنا السقف والحسبة بس.', 'Store prices themselves are changed in Google Play Console and App Store Connect. This page only sets caps and calculations.')}</div>
      <div class="row noprint" style="margin-top:14px"><button class="act gold" id="save">${T('حفظ', 'Save')}</button> <span id="saved" class="k"></span></div></div>`;
    $('#save').onclick = async () => {
      const body = {};
      $('#app').querySelectorAll('[data-k]').forEach(i => body[i.dataset.k] = parseFloat(i.value));
      $('#app').querySelectorAll('[data-b]').forEach(i => body[i.dataset.b] = i.checked);
      await post('settings', body);
      $('#saved').textContent = T('تم الحفظ', 'Saved');
    };
  },

  async codes() {
    const list = await api('codes');
    $('#app').innerHTML = heading(T('رموز الهدايا', 'Gift codes'), T('المستخدم يكتب الرمز في التطبيق (القائمة ← عندك رمز؟) وتنضاف له الفحوصات، مرة وحدة لكل حساب', 'Users enter the code in the app (menu → Have a code?) to get scans, once per account')) + `
      <div class="cols"><div class="card"><div class="wrap"><table><tr><th>${T('الرمز', 'Code')}</th><th class="num">${T('الفحوصات', 'Scans')}</th><th class="num">${T('المستخدم', 'Used')}</th><th class="noprint"></th></tr>
      ${list.map(c => `<tr><td class="mono">${esc(c.code)}</td><td class="num">${num(c.scans)}</td><td class="num">${num(c.used || 0)} / ${num(c.max)}</td><td class="noprint"><button class="act ghost sm" data-del="${esc(c.code)}">${T('حذف', 'Delete')}</button></td></tr>`).join('') || `<tr><td colspan="4" class="msg">${T('ما فيه رموز', 'No codes')}</td></tr>`}
      </table></div></div>
      <div class="card noprint"><h3>${T('رمز جديد', 'New code')}</h3>
      <label class="set"><span>${T('الرمز (حروف إنجليزية كبيرة وأرقام)', 'Code (capital letters and digits)')}</span><input id="c-code" dir="ltr"></label>
      <label class="set"><span>${T('كم فحص يعطي', 'Scans it gives')}</span><input id="c-scans" type="number" min="1" value="50"></label>
      <label class="set"><span>${T('كم حساب يقدر يستخدمه', 'How many accounts can use it')}</span><input id="c-max" type="number" min="1" value="20"></label>
      <div class="row" style="margin-top:12px"><button class="act gold" id="c-save">${T('حفظ الرمز', 'Save code')}</button> <span id="c-msg" class="err"></span></div>
      <div class="note">${T('رمز مراجعة Google Play لازم يكون هنا عشان فريق المراجعة يقدر يجرب التطبيق.', 'The Google Play review code must exist here so reviewers can test the app.')}</div></div></div>`;
    $('#c-save').onclick = async () => {
      try { await post('codes', {code: $('#c-code').value, scans: parseInt($('#c-scans').value), max: parseInt($('#c-max').value)}); show('codes'); }
      catch (e) { $('#c-msg').textContent = e.message; }
    };
    $('#app').querySelectorAll('[data-del]').forEach(b => b.onclick = async () => { await post('codes', {code: b.dataset.del, max: 0}); show('codes'); });
  },

  // مستخدمين اللوحة (للمالك بس). الرمز ينعرض مرة وحدة.
  async staff(added = null) {
    const list = await api('staff');
    const roleHelp = {admin: T('كل شيء إلا الفريق', 'Everything except the team'), accountant: T('الرئيسية والتقارير والمحاسبة والتنبيهات', 'Overview, reports, accounting and alerts'), investor: T('التقارير بس، قراءة فقط', 'Reports only, read only')};
    $('#app').innerHTML = heading(T('الفريق', 'Team'), T('أضف محاسب أو مستثمر أو مدير، وكل واحد يدخل برمزه الخاص', 'Add an accountant, investor or admin; each signs in with their own token')) + `
      ${added ? `<div class="card" style="margin-bottom:14px"><h3>${T('رمز', 'Token for')} ${esc(added.name)} (${roleName(added.role)})</h3>
        <div class="k">${T('انسخه الحين وأرسله له بشكل خاص. ما راح ينعرض مرة ثانية. يدخل من نفس الرابط:', 'Copy it now and send it privately. It will not be shown again. They sign in at the same address:')} <span class="mono">${esc(location.origin + location.pathname)}</span></div>
        <div class="secret"><code id="tok-new">${esc(added.token)}</code><button class="act gold sm" id="copy">${T('نسخ', 'Copy')}</button></div></div>` : ''}
      <div class="cols"><div class="card"><div class="wrap"><table><tr><th>${T('الاسم', 'Name')}</th><th>${T('الصلاحية', 'Role')}</th><th>${T('أُضيف', 'Added')}</th><th class="noprint"></th></tr>
      ${list.map(s => `<tr><td>${esc(s.name)}</td><td><span class="pill">${roleName(s.role)}</span><div class="k">${roleHelp[s.role] || ''}</div></td><td>${when(s.created)}</td><td class="noprint"><button class="act ghost sm" data-del="${esc(s.id)}">${T('حذف', 'Remove')}</button></td></tr>`).join('') || `<tr><td colspan="4" class="msg">${T('ما فيه أحد للحين', 'Nobody yet')}</td></tr>`}
      </table></div></div>
      <div class="card noprint"><h3>${T('إضافة شخص', 'Add someone')}</h3>
        <label class="set"><span>${T('الاسم', 'Name')}</span><input id="s-name" style="width:200px"></label>
        <label class="set"><span>${T('الصلاحية', 'Role')}</span><select id="s-role">${['accountant', 'investor', 'admin'].map(r => `<option value="${r}">${roleName(r)}</option>`).join('')}</select></label>
        <div class="k" id="s-help" style="margin-top:6px"></div>
        <div class="row" style="margin-top:12px"><button class="act gold" id="s-save">${T('إضافة وإنشاء رمز', 'Add and create token')}</button> <span id="s-msg" class="err"></span></div>
        <div class="note">${T('لو تسرب الرمز احذف الشخص وأضفه من جديد برمز جديد.', 'If a token leaks, remove the person and add them again for a new token.')}</div></div></div>`;
    const help = () => $('#s-help').textContent = roleHelp[$('#s-role').value];
    help();
    $('#s-role').onchange = help;
    if (added) $('#copy').onclick = async () => { try { await navigator.clipboard.writeText(added.token); $('#copy').textContent = T('تم النسخ', 'Copied'); } catch (e) {} };
    $('#s-save').onclick = async () => {
      try { show('staff', await post('staff', {add: {name: $('#s-name').value, role: $('#s-role').value}})); }
      catch (e) { $('#s-msg').textContent = e.message; }
    };
    $('#app').querySelectorAll('[data-del]').forEach(b => b.onclick = async () => {
      if (b.dataset.sure) { await post('staff', {delete: b.dataset.del}); show('staff'); }
      else { b.dataset.sure = 1; b.textContent = T('متأكد؟', 'Sure?'); }
    });
  },
};

// أسماء البنود التلقائية من السيرفر (عربية) بالإنجليزي.
function autoLabel(e) {
  if (/Claude/.test(e.provider)) return 'App scans';
  if (/RevenueCat/.test(e.provider)) return '1% fee on store revenue';
  return e.label;
}

function rowActions(x) {
  if (x.auto) return '';
  const recurring = x.repeat && x.repeat !== 'once';
  return `<div class="row">${recurring ? `<button class="act ghost sm" data-stop="${esc(x.id)}" title="${T('يبقى في الشهور اللي قبل', 'Stays in earlier months')}">${T('إيقاف من هالشهر', 'Stop from this month')}</button>` : ''}<button class="act ghost sm" data-del="${esc(x.id)}">${T('حذف', 'Delete')}</button></div>`;
}

// ملف CSV يفتح في Excel (مع BOM عشان العربي).
function csv(r) {
  const q = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const lines = [[T('النوع', 'Type'), T('البند', 'Item'), T('المزوّد', 'Provider'), T('التكرار', 'Repeats'), T('الإجمالي', 'Gross'), T('الضريبة', 'VAT'), T('عمولة المتجر', 'Store fee'), T('الصافي (ريال)', 'Net (SAR)')]];
  r.income.forEach(i => lines.push([T('دخل', 'Income'), i.auto ? productName(i.label) : i.label, i.provider, i.auto ? T('تلقائي', 'auto') : repeatName(i.repeat), i.auto ? i.grossSar : i.sar, i.taxSar ?? '', i.feeSar ?? '', i.sar]));
  r.expenses.forEach(e => lines.push([T('مصروف', 'Expense'), e.auto ? T(e.label, autoLabel(e)) : e.label, e.provider, e.auto ? T('تلقائي', 'auto') : repeatName(e.repeat), e.sar, '', '', -e.sar]));
  lines.push([], ['', T('الدخل الصافي', 'Net income'), '', '', '', '', '', r.incomeSar], ['', T('المصاريف', 'Expenses'), '', '', '', '', '', -r.expensesSar], ['', T('صافي الربح', 'Net profit'), '', '', '', '', '', r.netSar]);
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
