# FISH ID

صوّر السمكة، ويقول لك التطبيق نوعها من موسوعة [KSAFish](https://ksafish.com/ar) ومدى طزاجتها وكل المعلومات المنشورة عنها.
إحدى مبادرات منظومة حوات.

## كيف يشتغل

1. المستخدم يصوّر السمكة أو يختار صورة (`image_picker`). الصورة تتصغّر إلى 1600 بكسل قبل الإرسال.
2. التطبيق يرسلها لخادم FISH ID الصغير (مجلد `server/`) على `https://hawat.id/api/`، على نفس سيرفر KSAFish. الخادم يسأل Claude ويرجّع JSON فيه حتى 3 أنواع محتملة بنسبة ثقة، وتقدير الطزاجة من العين والخياشيم والجلد.
3. بيانات الأنواع (447 نوعًا، والأسماء المحلية، والمعلومات) مضمّنة في التطبيق في `assets/data/ksafish.json`، فتصفّح الموسوعة والبحث يشتغلان بدون إنترنت.

مفتاح Claude موجود في الخادم فقط (`ANTHROPIC_API_KEY` في `server/.env`)، والتطبيق ما يعرفه.
صور الموسوعة لا تُضمَّن في التطبيق، وزر «صفحة النوع» يفتحها في موقع KSAFish.

## تقييم الطزاجة (QIM)

نستخدم طريقة مؤشر الجودة (Quality Index Method) بالعلامات اللي تبان في الصورة فقط: لمعة الجلد، مخاط الجلد، صفاء العين، شكل العين، لون الخياشيم، مخاط الخياشيم، البطن، الدم وتغيّر اللون.
النموذج يعطي نقاط عيب لكل علامة (أو -1 إذا ما بانت)، والخادم (`server/lib/qim.dart`) يحسب منها الدرجة من 100 والمستوى وتقريب درجة الاتحاد الأوروبي (Extra / A / B / غير صالحة).
الرائحة والصلابة ما تنقاس من صورة، فالتطبيق ينبّه المستخدم يفحصها بيده. ويقدر المستخدم يضيف حتى صورتين قريبتين (العين والخياشيم) لنفس السمكة.
المصادر (ملخصة بالعربي والإنجليزي في قسم «العلم» بصفحة hawat.id):
- Huss (1995), Quality and quality changes in fresh fish, FAO Fisheries Technical Paper 348.
- Hyldig & Green-Petersen (2004), Quality Index Method: an objective tool for determination of sensory quality.
- Martinsdóttir et al. (2001), QIM Eurofish reference manual.
- Council Regulation (EC) No 2406/96 (فئات الطزاجة Extra / A / B).
- Codex CXG 31-1999، المعتمدة خليجيًا GSO CAC/GL 31:2021.

الخطوة الجاية: معايرة النقاط والأيام بصور السوق المعروف عمرها (أداة التجميع).

## قياس الدقة

`bash server/eval.sh species` و `bash server/eval.sh fresh` على السيرفر. البروتوكول والمقارنة العلمية في [docs/benchmark.md](docs/benchmark.md).

## حاسبة المدة المتبقية

في شاشة النتيجة: المستخدم يختار وين انحفظت السمكة وكم مدة، ونحسب الباقي بنموذج FAO و DTU للأسماك الاستوائية، ln(RRS) = 0.12·T (`lib/data/shelf_life.dart`). فوق 30 °م ساعتين أو أكثر يطلع تحذير قاطع. ولعائلات الهيستامين (التونة والكنعد والسردين والحمام وغيرها) يطلع تحذير إضافي.

## مساهمات المستخدمين

بطاقة «ساهم بصورتك» في شاشة النتيجة: المستخدم يؤكد النوع وكم يوم من الصيد وطريقة الحفظ، ويوافق صراحةً، فتنحفظ الصور عبر `POST fishId/contribute` في `/opt/fish-id/data/contrib/YYYY-MM-DD/ID/` (الصور + meta.json). ما نحفظ أي بيانات شخصية، ونحذف EXIF (فيه الموقع) من JPEG و PNG قبل الحفظ (`server/lib/contrib.dart`). هذي أساس مجموعة بيانات أسماك الخليج والبحر الأحمر ومعايرة الطزاجة.

## التشغيل

```sh
flutter pub get
flutter run                                   # يتصل بـ https://hawat.id/api/
flutter run --dart-define=API_URL=http://localhost:8080/   # خادم محلي
flutter run --dart-define=API_URL=DEMO        # وضع التجربة: نتيجة مثال بدون خادم
flutter test
```

## الخادم (server/)

صفحة الهبوط في `landing/` تنعرض على `https://hawat.id/`.

خادم Dart صغير في Docker، يسمع على `127.0.0.1:18490`، و nginx يوصّل له من `https://hawat.id/api/`.

التركيب أول مرة على سيرفر KSAFish:

```sh
git clone https://github.com/<المالك>/fish-id.git /opt/fish-id
sudo bash /opt/fish-id/server/install.sh   # يطلب مفتاح Claude ويضبط nginx وشهادة HTTPS
```

التحديث: `cd /opt/fish-id && git pull && sudo bash server/install.sh`.
الإعدادات في `server/.env` (انظر `server/.env.example`). فحص الحالة: `curl https://hawat.id/api/health`.

## تحديث بيانات الموسوعة

استبدل `assets/data/ksafish.json` بتصدير جديد بنفس الشكل: `species` (id, sci, fam, famAr, red, gulf, en, code, url) و`facts` (لكل معرّف: [العنوان، القيمة، الوحدة، النطاق]).
الخادم يقرأ نفس الملف وقت البناء، فبعد التحديث شغّل `sudo bash server/install.sh` على السيرفر.

## الخطوات القادمة

- نموذج داخل الجوال (بدون إنترنت) مدرّب على صور الأسواق اللي تُجمع الحين بأداة التجميع.
