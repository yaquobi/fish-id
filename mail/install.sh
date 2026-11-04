#!/usr/bin/env bash
# تركيب أو تحديث حوات ميل (https://hawat.id/mail/). الاستخدام من /opt/fish-id:  bash mail/install.sh
set -euo pipefail
cd "$(dirname "$0")"
PORT=${MAIL_HOST_PORT:-18495}
export MAIL_HOST_PORT=$PORT

# رمز الدخول يوصل على نفس بوت تلقرام حق تنبيهات FISH ID. ننسخ سطرين بس (بدون مفتاح Claude).
umask 077
grep -E '^FISHID_TELEGRAM_(TOKEN|CHAT)=' ../server/.env > .env || { echo 'تلقرام غير مربوط: شغّل bash server/telegram.sh أول'; exit 1; }
mkdir -p ../data/mail && chown 1000:1000 ../data/mail && chmod 700 ../data/mail

docker compose up -d --build
for _ in $(seq 1 20); do curl -fsS http://127.0.0.1:$PORT/health >/dev/null 2>&1 && break; sleep 1; done
curl -fsS http://127.0.0.1:$PORT/health; echo

# nginx: نضيف /mail/ لإعداد hawat.id (قبل سطر الصفحة الرئيسية) مرة وحدة.
SITE=/etc/nginx/sites-available/fish-id
if [[ -f $SITE ]] && ! grep -q 'location /mail/' $SITE; then
  cp $SITE /root/fish-id.nginx.bak
  sed -i "/^  location \/ {/i\\  location = /mail { return 301 /mail/; }\\n  location /mail/ { proxy_pass http://127.0.0.1:$PORT/; client_max_body_size 30m; proxy_read_timeout 120s; proxy_set_header Host \$host; }" $SITE
  nginx -t && systemctl reload nginx || { cp /root/fish-id.nginx.bak $SITE; echo 'رجعنا إعداد nginx القديم'; exit 1; }
fi
curl -fsS -o /dev/null -w "حوات ميل: %{http_code}\n" https://hawat.id/mail/ && echo 'تم ✅  افتح https://hawat.id/mail/ من جوالك'
