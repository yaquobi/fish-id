# FISH ID

صوّر السمكة، ويقول لك التطبيق نوعها من موسوعة [KSAFish](https://ksafish.com/ar) ومدى طزاجتها وكل المعلومات المنشورة عنها.
إحدى مبادرات منظومة حوات.

## كيف يشتغل

1. المستخدم يصوّر السمكة أو يختار صورة (`image_picker`). الصورة تتصغّر إلى 1600 بكسل قبل الإرسال.
2. التطبيق يرسلها لخادم FISH ID الصغير (مجلد `server/`) على `https://hawat.id/api/`، على نفس سيرفر KSAFish. الخادم يسأل Claude ويرجّع JSON فيه حتى 3 أنواع محتملة بنسبة ثقة، وتقدير الطزاجة من العين والخياشيم والجلد.
3. بيانات الأنواع (447 نوعًا، والأسماء المحلية، والمعلومات) مضمّنة في التطبيق في `assets/data/ksafish.json`، فتصفّح الموسوعة والبحث يشتغلان بدون إنترنت.

مفتاح Claude موجود في الخادم فقط (`ANTHROPIC_API_KEY` في `server/.env`)، والتطبيق ما يعرفه.
صور الموسوعة لا تُضمَّن في التطبيق، وزر «صفحة النوع» يفتحها في موقع KSAFish.

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
