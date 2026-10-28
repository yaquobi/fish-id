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

# 3. nginx: موقع جديد للدومين إذا ما له إعداد. إذا له إعداد، نطبع السطور اللي تنضاف له.
SITE=/etc/nginx/sites-available/fish-id
if grep -rqs "server_name[^;]*\b$DOMAIN\b" /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ && [[ ! -f $SITE ]]; then
  echo "للدومين $DOMAIN إعداد nginx موجود. أضف داخل server { } الخاص به:"
  echo '  location /api/ { proxy_pass http://127.0.0.1:$PORT/; client_max_body_size 10m; proxy_read_timeout 120s; proxy_set_header Host $host; }'
  echo 'ثم: nginx -t && systemctl reload nginx'
  exit 0
fi
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
  location / { return 200 'FISH ID'; add_header Content-Type text/plain; }
}
NGINX
ln -sf $SITE /etc/nginx/sites-enabled/fish-id
nginx -t && systemctl reload nginx

# 4. شهادة HTTPS.
if ! command -v certbot >/dev/null; then apt-get update -qq && apt-get install -y -qq certbot python3-certbot-nginx; fi
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect || \
  echo "تعذّرت الشهادة. تأكد إن الدومين $DOMAIN موجّه لهذا السيرفر ثم شغّل السكربت مرة ثانية."
curl -fsS "https://$DOMAIN/api/health" && echo && echo 'تم ✅'
