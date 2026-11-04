# حوات ميل

تطبيق ويب (PWA) على https://hawat.id/mail/ يجمع كل إيميلات حوات (حسابات Google Workspace/Gmail) في مكان واحد، مع أيقونة على الجوال والكمبيوتر وإشعارات للرسائل الجديدة.

- الدخول: رمز من 6 أرقام يوصل على بوت تلقرام حق تنبيهات FISH ID، والجهاز يبقى داخل سنة.
- كل حساب يتربط بكلمة مرور تطبيقات من Google (myaccount.google.com/apppasswords) ويحتاج التحقق بخطوتين. الحسابات محفوظة في `/opt/fish-id/data/mail/config.json` على السيرفر فقط (صلاحية المالك).
- يراقب الوارد لحظيًا (IMAP IDLE) ويرسل Web Push. الإرسال عن طريق smtp.gmail.com، ويقدر يرسل من العناوين الإضافية (مثل info@hawat.id) إذا كانت مضافة في Gmail «إرسال بريد باسم».
- التركيب أو التحديث على السيرفر: `cd /opt/fish-id && git pull && bash mail/install.sh`
