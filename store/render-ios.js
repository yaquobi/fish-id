// صور App Store بمقاس آيفون 6.9 إنش (1290×2796) في store/ios/<اللغة>/shot-N.jpg، من لقطات tool/shots/store_ios/<اللغة>/.
// node store/render-ios.js   (شغّله من جذر المشروع بعد اختبار اللقطات بـ IOS=true لكل لغة)
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
// [اسم اللقطة، أي صورة، أي عنصر يبدأ عنده القص (null = من فوق)، العنوان، الوصف]
const shots = {
  ar: [
    ['1', '1-home', null, 'صوّر السمكة <b>واعرف كل شيء عنها</b>', 'نوعها وطزاجتها ومعلوماتها في ثواني'],
    ['2', '2-result', null, 'كم هي <b>طازجة</b>؟', 'تقييم علمي (QIM) للعين والخياشيم والجلد من 100'],
    ['3', '2-result', 1, 'يعرف النوع <b>باسمه المحلي</b>', 'أسماء البحر الأحمر والخليج من موسوعة KSAFish'],
    ['4', '2-result', 2, 'كم <b>باقي لها</b>؟', 'حاسبة صلاحية حسب الحفظ والحرارة'],
    ['5', '6-browse', null, 'موسوعة <b>447 نوعًا</b>', 'تصفحها بدون إنترنت'],
  ],
  en: [
    ['1', '1-home', null, 'Snap a fish, <b>know everything</b>', 'Species, freshness and facts in seconds'],
    ['2', '2-result', null, 'How <b>fresh</b> is it?', 'A scientific QIM score out of 100 for eyes, gills and skin'],
    ['3', '2-result', 1, 'Knows the <b>local name</b>', 'Red Sea and Gulf names from the KSAFish encyclopedia'],
    ['4', '2-result', 2, 'How <b>long will it last</b>?', 'Shelf-life calculator by storage and temperature'],
    ['5', '6-browse', null, '<b>447 species</b> encyclopedia', 'Browse it offline'],
  ],
};

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1290, height: 2796 } });
  for (const [lang, list] of Object.entries(shots)) {
    const out = path.join(root, 'store', 'ios', lang);
    fs.mkdirSync(out, { recursive: true });
    for (const [n, src, card, h, s] of list) {
      await page.goto('file://' + path.join(root, 'store', 'frame-ios.html'));
      const img = 'data:image/png;base64,' + fs.readFileSync(path.join(root, 'tool', 'shots', 'store_ios', lang, src + '.png')).toString('base64');
      await page.evaluate(
        async ({ lang, img, card, h, s }) => {
          document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
          document.getElementById('h').innerHTML = h;
          document.getElementById('s').textContent = s;
          const i = document.getElementById('i');
          i.src = img;
          await i.decode();
          if (card !== null) {
            // نقص من بداية البطاقة رقم card (البطاقات بيضاء على خلفية رمادية)، مع هامش فوقها.
            const c = document.createElement('canvas');
            c.width = i.naturalWidth;
            c.height = i.naturalHeight;
            const x = c.getContext('2d');
            x.drawImage(i, 0, 0);
            const d = x.getImageData(60, 0, 1, c.height).data;
            const tops = [];
            for (let y = 1; y < c.height; y++) {
              const w = (k) => d[k * 4] > 250 && d[k * 4 + 1] > 250 && d[k * 4 + 2] > 250;
              if (w(y) && !w(y - 1)) tops.push(y);
            }
            const top = tops[card] - 42;
            i.style.marginTop = (-top * i.clientWidth) / i.naturalWidth + 'px';
          }
          await document.fonts.ready;
        },
        { lang, img, card, h, s },
      );
      await page.screenshot({ path: path.join(out, `shot-${n}.jpg`), type: 'jpeg', quality: 92 });
      console.log(lang, n);
    }
  }
  await browser.close();
})();
