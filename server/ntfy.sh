#!/usr/bin/env bash
# يربط تنبيهات FISH ID بإشعارات الجوال عن طريق ntfy.sh، بدون رقم جوال وبدون حساب.
# الاستخدام: cd /opt/fish-id && bash server/ntfy.sh
# يسوي اسم موضوع عشوائي (هو كلمة السر)، ويحفظه في server/.env، ويعيد تشغيل الخادم، ويطبع رابط الاشتراك.
set -euo pipefail
cd "$(dirname "$0")"
umask 077
touch .env
TOPIC=$(grep -oP '^FISHID_NTFY_TOPIC=\K.+' .env || true)
if [[ -z $TOPIC ]]; then
  TOPIC="fishid-$(head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  printf 'FISHID_NTFY_TOPIC=%s\n' "$TOPIC" >> .env
fi
docker compose up -d --force-recreate
sleep 3
curl -fsS -H 'Title: FISH ID' -H 'Tags: fish' -d '✅ تجربة: الإشعارات وصلت لجوالك' "https://ntfy.sh/$TOPIC" >/dev/null && echo 'انرسل إشعار تجربة.'
echo
echo '1) افتح هذا الرابط في جوالك (Safari في الآيفون، Chrome في الأندرويد):'
echo "   https://ntfy.sh/$TOPIC"
echo '2) شارك ← «إضافة إلى الشاشة الرئيسية»، وافتح الأيقونة، واسمح بالإشعارات.'
echo '   أو نزّل تطبيق ntfy واضغط + واكتب اسم الموضوع:'
echo "   $TOPIC"
echo 'لا تنشر الرابط: أي أحد عنده الرابط يشوف الإشعارات.'
