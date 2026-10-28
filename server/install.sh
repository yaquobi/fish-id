#!/usr/bin/env bash
# تركيب أو تحديث خادم FISH ID على سيرفر KSAFish (nginx على السيرفر نفسه).
# الاستخدام: sudo bash server/install.sh   (من داخل /opt/fish-id)
set -euo pipefail
DOMAIN=${DOMAIN:-hawat.id}
PORT=${FISHID_HOST_PORT:-18490}
export FISHID_HOST_PORT=$PORT
cd "$(dirname "$0")"

# 1. المفتاح: يُطلب مرة وحدة ويُحفظ في .env بصلاحية للمالك فقط.
if ! grep -q '^ANTHROPIC_API_KEY=sk-' .env 2>/dev/null; then
  read -rsp 'الصق مفتاح Claude: ' KEY; echo
  umask 077
  printf 'ANTHROPIC_API_KEY=%s\n' "$KEY" > .env
  unset KEY
fi

# 2. الحاوية.
docker compose up -d --build
for _ in $(seq 1 20); do curl -fsS http://127.0.0.1:$PORT/health >/dev/null 2>&1 && break; sleep 1; done
curl -fsS http://127.0.0.1:$PORT/health; echo

# 3. nginx: الـ API على /api/ وصفحة الهبوط (مجلد landing) على /.
# إذا للدومين إعداد ثاني غير ملفنا، نطبع السطور اللي تنضاف له بدل ما نلمسه.
SITE=/etc/nginx/sites-available/fish-id
LANDING=$(cd .. && pwd)/landing
ROOT_LOC="  location / { root $LANDING; try_files \$uri \$uri/ /index.html; }"
if grep -rqs "server_name[^;]*\b$DOMAIN\b" /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ && [[ ! -f $SITE ]]; then
  echo "للدومين $DOMAIN إعداد nginx موجود. أضف داخل server { } الخاص به:"
  echo "  location /api/ { proxy_pass http://127.0.0.1:$PORT/; client_max_body_size 10m; proxy_read_timeout 120s; proxy_set_header Host \$host; }"
  echo "$ROOT_LOC"
  echo 'ثم: nginx -t && systemctl reload nginx'
  exit 0
fi
if [[ -f $SITE ]]; then
  # الملف موجود (و certbot أضاف له HTTPS): نغيّر سطر الصفحة الرئيسية بس.
  sed -i "s#^  location / {.*}\$#$ROOT_LOC#" $SITE
else
  cat > $SITE <<NGINX
server {
  listen 80;
  listen [::]:80;
  server_name $DOMAIN www.$DOMAIN;
  location /api/ {
    proxy_pass http://127.0.0.1:$PORT/;
    client_max_body_size 10m;
    proxy_read_timeout 120s;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
$ROOT_LOC
}
NGINX
fi
ln -sf $SITE /etc/nginx/sites-enabled/fish-id
nginx -t && systemctl reload nginx

# 4. شهادة HTTPS (مرة وحدة، و certbot يجددها بنفسه).
if [[ ! -d /etc/letsencrypt/live/$DOMAIN ]]; then
  command -v certbot >/dev/null || { apt-get update -qq && apt-get install -y -qq certbot python3-certbot-nginx; }
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect || \
    echo "تعذّرت الشهادة. تأكد إن الدومين $DOMAIN موجّه لهذا السيرفر ثم شغّل السكربت مرة ثانية."
fi
curl -fsS "https://$DOMAIN/api/health" && echo
curl -fsS -o /dev/null -w "الصفحة الرئيسية: %{http_code}\n" "https://$DOMAIN/" && echo 'تم ✅'
